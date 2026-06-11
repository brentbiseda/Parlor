import Foundation
import SwiftUI
import GroupActivities

@MainActor
final class AppModel: ObservableObject {
    @Published var session: GameSession?
    @Published var playerName: String {
        didSet { UserDefaults.standard.set(playerName, forKey: "parlor.name") }
    }
    @Published var showJoinSheet = false
    @Published var toast: String?

    private var sharePlayTask: Task<Void, Never>?

    init() {
        playerName = UserDefaults.standard.string(forKey: "parlor.name") ?? "Player"
        listenForSharePlay()
        // Dev hook: PARLOR_AUTOSTART=<gameKind> jumps straight to a local game.
        if let kind = ProcessInfo.processInfo.environment["PARLOR_AUTOSTART"].flatMap(GameKind.init(rawValue:)) {
            startLocal(kind: kind, options: GameOptions(), humanCount: 1)
        }
    }

    var displayName: String {
        playerName.trimmingCharacters(in: .whitespaces).isEmpty ? "Player" : playerName
    }

    // MARK: - Starting tables

    func startLocal(kind: GameKind, options: GameOptions, humanCount: Int) {
        session = GameSession(localGame: kind, options: options, humanCount: humanCount, myName: displayName)
    }

    func hostNearby(kind: GameKind, options: GameOptions) {
        let transport = MultipeerTransport(hostingGame: kind, hostName: displayName)
        session = GameSession(hosting: kind, options: options, transport: transport, myName: displayName)
    }

    func joinNearby(table: DiscoveredTable, browser: MultipeerTransport) {
        browser.join(table)
        session = GameSession(joining: browser, expectedKind: table.gameKind, myName: displayName)
        showJoinSheet = false
    }

    /// Replay the same local game with the same seats.
    func playAgain() {
        guard let old = session, old.role == .local else { return }
        let humans = old.localHumanSeats.count
        startLocal(kind: old.lobby.gameKind, options: old.lobby.options, humanCount: humans)
    }

    func endSession() {
        session?.leave()
        session = nil
    }

    // MARK: - SharePlay

    func startSharePlay(kind: GameKind, options: GameOptions) {
        let activity = ParlorActivity(gameKind: kind, options: options,
                                      hostPlayerID: Identity.playerID, hostName: displayName)
        Task {
            do {
                _ = try await activity.activate()
                // The sessions() listener below builds the GameSession.
            } catch {
                toast = "Couldn't start SharePlay. Join a FaceTime call with your friends first, then try again."
            }
        }
    }

    private func listenForSharePlay() {
        sharePlayTask = Task { [weak self] in
            for await groupSession in ParlorActivity.sessions() {
                guard let self else { return }
                let transport = SharePlayTransport(session: groupSession)
                let activity = groupSession.activity
                if transport.isHost {
                    self.session = GameSession(hosting: activity.gameKind, options: activity.options,
                                               transport: transport, myName: self.displayName)
                } else {
                    self.session = GameSession(joining: transport, expectedKind: activity.gameKind,
                                               myName: self.displayName)
                }
            }
        }
    }

    // MARK: - Links

    /// parlor://join opens the nearby-table browser.
    func handle(url: URL) {
        if url.scheme == "parlor" {
            if session == nil { showJoinSheet = true }
        }
    }
}
