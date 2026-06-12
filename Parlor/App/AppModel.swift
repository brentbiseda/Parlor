import Foundation
import SwiftUI
import GroupActivities

@MainActor
final class AppModel: ObservableObject {
    @Published var session: GameSession?
    @Published var showJoinSheet = false
    @Published var toast: String?
    @Published var activeMatch: ActiveMatch?
    /// Most recently played games, newest first, for the home quick-launch row.
    @Published private(set) var recentKinds: [GameKind] = []

    let competitions = CompetitionStore()
    let stats = StatsStore()
    let profiles = ProfileStore()
    let leaderboards = LeaderboardStore()
    let savedGames = SavedGamesStore()

    private var sharePlayTask: Task<Void, Never>?

    init() {
        recentKinds = (UserDefaults.standard.stringArray(forKey: "parlor.recents") ?? [])
            .compactMap(GameKind.init(rawValue:))
        listenForSharePlay()
        // Simulated (bot-only) league & tournament matches still move ratings.
        competitions.onSimulatedResult = { [weak self] kind, participants, seatRanking in
            self?.profiles.recordResult(kind: kind, participants: participants, seatRanking: seatRanking)
        }
        // Dev hook: PARLOR_AUTOSTART=<gameKind> jumps straight to a local
        // game, honoring the persisted solo settings.
        if let kind = ProcessInfo.processInfo.environment["PARLOR_AUTOSTART"].flatMap(GameKind.init(rawValue:)) {
            let defaults = UserDefaults.standard
            let options = GameOptions(
                klondikeDrawThree: defaults.bool(forKey: "parlor.klondike.draw3"),
                klondikeMaxPasses: defaults.integer(forKey: "parlor.klondike.passes"),
                pinballLayout: defaults.string(forKey: "parlor.pinball.layout") ?? "classic")
            startLocal(kind: kind, options: options, humanCount: 1)
        }
    }

    var displayName: String {
        let name = profiles.active.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Player" : name
    }

    // MARK: - Starting tables

    func startLocal(kind: GameKind, options: GameOptions, humanCount: Int) {
        activeMatch = nil
        noteRecent(kind)
        session = GameSession(localGame: kind, options: options, humanCount: humanCount, myName: displayName)
    }

    func hostNearby(kind: GameKind, options: GameOptions) {
        activeMatch = nil
        noteRecent(kind)
        let transport = MultipeerTransport(hostingGame: kind, hostName: displayName)
        session = GameSession(hosting: kind, options: options, transport: transport, myName: displayName)
    }

    private func noteRecent(_ kind: GameKind) {
        recentKinds.removeAll { $0 == kind }
        recentKinds.insert(kind, at: 0)
        recentKinds = Array(recentKinds.prefix(8))
        UserDefaults.standard.set(recentKinds.map(\.rawValue), forKey: "parlor.recents")
    }

    func joinNearby(table: DiscoveredTable, browser: MultipeerTransport) {
        activeMatch = nil
        browser.join(table)
        session = GameSession(joining: browser, expectedKind: table.gameKind, myName: displayName)
        showJoinSheet = false
    }

    /// Replay the same local game with the same seats.
    func playAgain() {
        guard let old = session, old.role == .local else { return }
        recordIfFinished(old)
        savedGames.remove(id: old.sessionID)
        session = GameSession(matchGame: old.lobby.gameKind, options: old.lobby.options,
                              players: old.lobby.players, myName: displayName)
    }

    /// Leaving a table finishes it or suspends it. Finished games are
    /// recorded; unfinished local games park in Saved Games (async play).
    func endSession() {
        if let session {
            if session.game?.isOver == true {
                recordIfFinished(session)
                savedGames.remove(id: session.sessionID)
            } else if shouldSuspend(session), let snapshot = session.snapshot(match: activeMatch) {
                savedGames.upsert(snapshot)
            }
            session.leave()
        }
        session = nil
        activeMatch = nil
    }

    /// Multiplayer tables always suspend; an untouched solo deal isn't worth keeping.
    private func shouldSuspend(_ session: GameSession) -> Bool {
        guard session.role == .local, let game = session.game, !game.isOver else { return false }
        if !game.kind.isSolo { return true }
        return soloProgress(game)
    }

    private func soloProgress(_ game: AnyGame) -> Bool {
        switch game.engine {
        case let g as KlondikeGame: return g.moveCount > 0
        case let g as FreeCellGame: return g.moveCount > 0
        case let g as MahjongGame: return g.remainingCount < 144
        case let g as PinballGame: return g.ballsPlayed > 0 || g.score > 0
        case let g as BreakoutGame: return g.livesLost > 0 || g.score > 0
        case let g as TetrisGame: return g.piecesPlaced > 0
        case let g as CapsulesGame: return g.pillsUsed > 0
        case let g as MinesweeperGame: return g.minesPlaced
        case let g as MuncherGame: return g.score > 0 || g.lives < 3
        case let g as HopperGame: return g.score > 0 || g.lives < 3
        case let g as CentipedeGame: return g.score > 0 || g.livesLost > 0
        case let g as SnakeGame: return g.score > 0 || g.lives < 3
        case let g as FootballGame: return g.kicksTaken > 0
        case let g as BaseballGame: return g.pitchesSeen > 0
        case let g as SoccerGame: return g.yourShots > 0
        case let g as HockeyGame: return g.yourGoals > 0 || g.botGoals > 0
        default: return false
        }
    }

    // MARK: - Asynchronous play

    func resume(_ saved: SavedGame) {
        activeMatch = saved.match
        session = GameSession(resuming: saved, myName: displayName)
    }

    /// Deleting a suspended solo game counts it as played-but-lost so
    /// solitaire win rates stay honest.
    func discardSavedGame(_ saved: SavedGame) {
        if saved.kind.isSolo {
            stats.recordGame(kind: saved.kind, won: false,
                             score: (saved.game.engine as? PinballGame)?.score)
        }
        savedGames.remove(id: saved.id)
    }

    /// Called when the app heads to the background: park the live table so
    /// nothing is lost if the system kills the app.
    func saveSnapshotForBackground() {
        guard let session, shouldSuspend(session),
              let snapshot = session.snapshot(match: activeMatch) else { return }
        savedGames.upsert(snapshot)
    }

    // MARK: - League & tournament matches

    func playLeagueMatch(league: League, match: CompetitionMatch) {
        let entrants = match.entrantIDs.compactMap { league.entrant($0) }
        guard entrants.count == match.entrantIDs.count else { return }
        start(match: match, kind: league.gameKind, options: league.options, entrants: entrants,
              competition: .league(league.id))
    }

    func playTournamentMatch(tournament: Tournament, match: CompetitionMatch) {
        let entrants = match.entrantIDs.compactMap { tournament.entrant($0) }
        guard entrants.count == match.entrantIDs.count else { return }
        start(match: match, kind: tournament.gameKind, options: tournament.options, entrants: entrants,
              competition: .tournament(tournament.id))
    }

    private func start(match: CompetitionMatch, kind: GameKind, options: GameOptions,
                       entrants: [Entrant], competition: ActiveMatch.Competition) {
        let players = entrants.map { PlayerInfo(id: $0.id.uuidString, name: $0.name, isBot: $0.isBot) }
        activeMatch = ActiveMatch(competition: competition, matchID: match.id,
                                  entrantIDsBySeat: match.entrantIDs)
        session = GameSession(matchGame: kind, options: options, players: players, myName: displayName)
    }

    /// Write a finished game into personal stats, leaderboards, Elo ratings,
    /// and — when the table belongs to a league or tournament — its standings.
    private func recordIfFinished(_ session: GameSession) {
        guard session.role == .local, !session.resultRecorded,
              let game = session.game, game.isOver else { return }
        session.resultRecorded = true
        let ranking = game.ranking()

        // Personal stats only make sense when one human sat at this table.
        if session.localHumanSeats.count == 1, let seat = session.localHumanSeats.first {
            var won = ranking.first?.contains(seat) ?? false
            var score: Int? = nil
            switch game.engine {
            case let g as PinballGame: won = false; score = g.score
            case let g as BreakoutGame: won = false; score = g.score
            case let g as TetrisGame: won = false; score = g.score
            case let g as KlondikeGame: score = g.moveCount
            case let g as FreeCellGame: score = g.moveCount
            case let g as CapsulesGame: won = g.cleared; score = g.score
            case let g as MinesweeperGame: won = g.won
            case let g as MuncherGame: won = false; score = g.score
            case let g as HopperGame: won = false; score = g.score
            case let g as CentipedeGame: won = false; score = g.score
            case let g as SnakeGame: won = false; score = g.score
            case let g as FootballGame: won = false; score = g.score
            case let g as BaseballGame: won = false; score = g.score
            case let g as SoccerGame: won = g.won
            case let g as HockeyGame: won = g.won
            default: break
            }
            stats.recordGame(kind: game.kind, won: won, score: score)
            recordLeaderboard(game: game, won: won, playerName: session.playerName(seat: seat))
        }

        // Elo ratings for every named participant of a competitive table.
        if game.kind.isCompetitive, !ranking.isEmpty {
            let participants = session.lobby.players.map { (name: $0.name, isBot: $0.isBot) }
            if participants.count == game.playerCount {
                profiles.recordResult(kind: game.kind, participants: participants, seatRanking: ranking)
            }
        }

        guard let match = activeMatch, !ranking.isEmpty else { return }
        let groups = ranking.map { $0.compactMap { match.entrantIDsBySeat[safe: $0] } }
        let outcome = MatchOutcome(rankedGroups: groups, summary: game.resultText ?? "Game over")
        switch match.competition {
        case .league(let id):
            competitions.record(leagueID: id, matchID: match.matchID, outcome: outcome)
        case .tournament(let id):
            if !competitions.record(tournamentID: id, matchID: match.matchID, outcome: outcome) {
                toast = "That knockout match was drawn — play it again to decide who advances."
            }
        }
    }

    /// Record tables: arcade scores always; solve quality only on wins.
    private func recordLeaderboard(game: AnyGame, won: Bool, playerName: String) {
        switch game.engine {
        case let g as PinballGame where g.score > 0:
            let position = leaderboards.position(of: g.score, kind: .pinball)
            leaderboards.record(kind: .pinball, playerName: playerName, value: g.score, detail: "3-ball game")
            if position == 1 { toast = "New pinball record — \(g.score) points!" }
        case let g as BreakoutGame where g.score > 0:
            leaderboards.record(kind: .breakout, playerName: playerName, value: g.score,
                                detail: "level \(g.level)")
        case let g as TetrisGame where g.score > 0:
            leaderboards.record(kind: .tetris, playerName: playerName, value: g.score,
                                detail: "\(g.lines) lines")
        case let g as KlondikeGame where won:
            leaderboards.record(kind: .solitaire, playerName: playerName, value: g.moveCount,
                                detail: g.drawThree ? "draw 3" : "draw 1")
        case let g as FreeCellGame where won:
            leaderboards.record(kind: .freecell, playerName: playerName, value: g.moveCount, detail: "solved")
        case let g as MahjongGame where won:
            leaderboards.record(kind: .mahjong, playerName: playerName, value: g.shufflesUsed, detail: "cleared")
        case let g as CapsulesGame where g.score > 0:
            leaderboards.record(kind: .capsules, playerName: playerName, value: g.score,
                                detail: g.cleared ? "bottle cleared" : "level \(g.level)")
        case let g as MuncherGame where g.score > 0:
            leaderboards.record(kind: .muncher, playerName: playerName, value: g.score,
                                detail: "level \(g.level)")
        case let g as HopperGame where g.score > 0:
            leaderboards.record(kind: .hopper, playerName: playerName, value: g.score,
                                detail: "level \(g.level)")
        case let g as CentipedeGame where g.score > 0:
            leaderboards.record(kind: .centipede, playerName: playerName, value: g.score,
                                detail: "wave \(g.level)")
        case let g as SnakeGame where g.score > 0:
            leaderboards.record(kind: .snake, playerName: playerName, value: g.score,
                                detail: "\(g.body.count) segments")
        case let g as FootballGame where g.score > 0:
            leaderboards.record(kind: .football, playerName: playerName, value: g.score,
                                detail: "\(g.made) of \(FootballGame.kicksPerGame)")
        case let g as BaseballGame where g.score > 0:
            leaderboards.record(kind: .baseball, playerName: playerName, value: g.score,
                                detail: "\(g.homers) homers")
        default:
            break
        }
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
