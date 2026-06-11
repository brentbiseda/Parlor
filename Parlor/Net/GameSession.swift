import Foundation
import Combine

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// One table of one game. The host (or the single device in local play) owns
/// the authoritative engine: clients propose moves, the host validates,
/// applies, and pushes per-seat redacted state back out.
@MainActor
final class GameSession: ObservableObject {
    enum Role { case local, host, client }

    let role: Role
    let transport: (any GameTransport)?
    let myID = Identity.playerID
    let myName: String

    @Published var lobby: LobbyState
    @Published var game: AnyGame?
    @Published var mySeat: Int? = nil
    /// Seats played by humans on THIS device (all of them in pass-and-play).
    @Published var localHumanSeats: Set<Int> = []
    /// Hotseat curtain: the seat whose hidden cards are currently shown.
    @Published var revealedSeat: Int? = nil
    @Published var toast: String? = nil
    @Published var ended = false

    private var botGeneration = 0

    // MARK: - Construction

    /// Solo or pass-and-play: every human seat lives on this device.
    init(localGame kind: GameKind, options: GameOptions, humanCount: Int, myName: String) {
        role = .local
        transport = nil
        self.myName = myName
        let humans = max(1, min(humanCount, kind.playerCount))
        var players: [PlayerInfo] = (0..<humans).map {
            PlayerInfo(id: $0 == 0 ? Identity.playerID : "local-\($0)",
                       name: humans == 1 ? myName : "Player \($0 + 1)")
        }
        while players.count < kind.playerCount {
            players.append(PlayerInfo(id: "bot-\(players.count)", name: "Bot \(players.count + 1)", isBot: true))
        }
        lobby = LobbyState(gameKind: kind, options: options, hostID: Identity.playerID, players: players)
        localHumanSeats = Set(0..<humans)
        if humans == 1 { revealedSeat = 0 }
        game = AnyGame.make(kind: kind, options: options)
        scheduleBotIfNeeded()
    }

    /// Host a networked table. The game starts when the host calls `startHostedGame`.
    init(hosting kind: GameKind, options: GameOptions, transport: any GameTransport, myName: String) {
        role = .host
        self.transport = transport
        self.myName = myName
        lobby = LobbyState(gameKind: kind, options: options, hostID: Identity.playerID,
                           players: [PlayerInfo(id: Identity.playerID, name: myName)])
        wireTransport()
    }

    /// Join a networked table.
    init(joining transport: any GameTransport, expectedKind: GameKind?, myName: String) {
        role = .client
        self.transport = transport
        self.myName = myName
        lobby = LobbyState(gameKind: expectedKind ?? .hearts, hostID: "")
        wireTransport()
        sendHelloIfNeeded()
    }

    private func wireTransport() {
        transport?.onReceive = { [weak self] envelope, sender in
            self?.receive(envelope, from: sender)
        }
        transport?.onPeersChanged = { [weak self] in
            self?.peersChanged()
        }
    }

    // MARK: - Lobby

    var seatsFilled: Int { lobby.players.count }
    var seatsTotal: Int { lobby.gameKind.playerCount }

    func playerName(seat: Int) -> String {
        lobby.players[safe: seat]?.name ?? "Seat \(seat + 1)"
    }

    private func sendHelloIfNeeded() {
        guard role == .client,
              !lobby.players.contains(where: { $0.id == myID }) else { return }
        transport?.broadcast(.hello(PlayerInfo(id: myID, name: myName)))
    }

    /// Host: fill remaining seats with bots and deal.
    func startHostedGame() {
        guard role == .host, game == nil else { return }
        while lobby.players.count < seatsTotal {
            lobby.players.append(PlayerInfo(id: "bot-\(lobby.players.count)",
                                            name: "Bot \(lobby.players.count + 1)", isBot: true))
        }
        mySeat = 0
        localHumanSeats = [0]
        revealedSeat = 0
        let fresh = AnyGame.make(kind: lobby.gameKind, options: lobby.options)
        game = fresh
        transport?.broadcast(.lobby(lobby))
        for (seat, player) in lobby.players.enumerated() where !player.isBot && player.id != myID {
            transport?.send(.start(game: fresh.redacted(for: seat), seat: seat), to: [player.id])
        }
        scheduleBotIfNeeded()
    }

    // MARK: - Message handling

    private func receive(_ envelope: Envelope, from sender: String) {
        switch (role, envelope) {
        case (.host, .hello(let info)):
            guard game == nil else { return }
            guard !lobby.players.contains(where: { $0.id == info.id }) else {
                transport?.broadcast(.lobby(lobby))
                return
            }
            guard lobby.players.count < seatsTotal else { return }
            lobby.players.append(info)
            transport?.broadcast(.lobby(lobby))
        case (.host, .propose(let move, let seat)):
            handleProposal(move, seat: seat, from: sender)
        case (.client, .lobby(let state)):
            lobby = state
        case (.client, .start(let game, let seat)), (.client, .state(let game, let seat)):
            self.game = game
            mySeat = seat
            localHumanSeats = [seat]
            revealedSeat = seat
        case (.client, .rejected(let reason)):
            toast = reason
        case (.client, .ended):
            toast = "The host closed the table."
            ended = true
        default:
            break
        }
    }

    private func handleProposal(_ move: Move, seat: Int, from sender: String) {
        guard let g = game, !g.isOver, seat == g.currentPlayer else {
            transport?.send(.rejected(reason: "It isn't your turn."), to: [sender])
            return
        }
        let controllingSeat = g.controller(of: seat)
        guard lobby.players[safe: controllingSeat]?.id == sender else {
            transport?.send(.rejected(reason: "That isn't your seat."), to: [sender])
            return
        }
        do {
            try applyAndSync(move)
        } catch {
            transport?.send(.rejected(reason: error.localizedDescription), to: [sender])
        }
    }

    private func peersChanged() {
        sendHelloIfNeeded()
        guard let transport else { return }
        switch role {
        case .host:
            let connected = Set(transport.connectedPeerIDs + [myID])
            if game == nil {
                let before = lobby.players.count
                lobby.players.removeAll { !$0.isBot && !connected.contains($0.id) }
                if lobby.players.count != before {
                    transport.broadcast(.lobby(lobby))
                }
            } else {
                // Keep the game alive: a departed human seat becomes a bot.
                var changed = false
                for idx in lobby.players.indices {
                    let p = lobby.players[idx]
                    if !p.isBot && !connected.contains(p.id) {
                        lobby.players[idx].isBot = true
                        lobby.players[idx].name = "\(p.name) (bot)"
                        changed = true
                    }
                }
                if changed {
                    transport.broadcast(.lobby(lobby))
                    scheduleBotIfNeeded()
                }
            }
        case .client:
            if game != nil, transport.connectedPeerIDs.isEmpty {
                toast = "Connection lost."
                ended = true
            }
        case .local:
            break
        }
    }

    // MARK: - Moves

    /// Seat whose cards/pieces the local user may currently act with, if any.
    var actionableSeat: Int? {
        guard let g = game, !g.isOver else { return nil }
        let controllingSeat = g.controller(of: g.currentPlayer)
        guard localHumanSeats.contains(controllingSeat) else { return nil }
        if needsHandoff { return nil }
        return g.currentPlayer
    }

    var needsHandoff: Bool {
        guard role == .local, localHumanSeats.count > 1,
              let g = game, !g.isOver, g.kind.hasHiddenInfo else { return false }
        let seat = g.controller(of: g.currentPlayer)
        return localHumanSeats.contains(seat) && revealedSeat != seat
    }

    func revealForHandoff() {
        guard let g = game else { return }
        revealedSeat = g.controller(of: g.currentPlayer)
    }

    /// Seat from whose point of view the table is drawn.
    var perspectiveSeat: Int {
        if let mySeat { return mySeat }
        if localHumanSeats.count == 1, let only = localHumanSeats.first { return only }
        return revealedSeat ?? 0
    }

    func submit(_ move: Move) {
        guard let g = game, !g.isOver else { return }
        if role == .client {
            transport?.send(.propose(move: move, seat: g.currentPlayer), to: nil)
            return
        }
        guard localHumanSeats.contains(g.controller(of: g.currentPlayer)) else {
            toast = "It isn't your turn."
            return
        }
        do {
            try applyAndSync(move)
        } catch {
            toast = error.localizedDescription
        }
    }

    private func applyAndSync(_ move: Move) throws {
        guard var g = game else { return }
        try g.applyValidated(move)
        game = g
        pushState()
        scheduleBotIfNeeded()
    }

    private func pushState() {
        guard role == .host, let g = game else { return }
        for (seat, player) in lobby.players.enumerated() where !player.isBot && player.id != myID {
            transport?.send(.state(game: g.redacted(for: seat), seat: seat), to: [player.id])
        }
    }

    // MARK: - Bots

    private func scheduleBotIfNeeded() {
        guard role != .client, let g = game, !g.isOver else { return }
        let seat = g.controller(of: g.currentPlayer)
        guard lobby.players[safe: seat]?.isBot == true else { return }
        botGeneration += 1
        let generation = botGeneration
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let self, generation == self.botGeneration,
                  let g = self.game, !g.isOver,
                  self.lobby.players[safe: g.controller(of: g.currentPlayer)]?.isBot == true,
                  let move = Bot.chooseMove(for: g) else { return }
            try? self.applyAndSync(move)
        }
    }

    // MARK: - Teardown

    func leave() {
        if role == .host {
            transport?.broadcast(.ended)
        }
        transport?.stop()
        ended = true
    }
}
