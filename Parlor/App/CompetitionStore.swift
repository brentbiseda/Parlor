import Foundation
import Combine

/// Owns every league and tournament, persisted as JSON in Application
/// Support. Also simulates bot-only tables synchronously (the engines are
/// pure and fast) so a league full of bots can play out instantly.
@MainActor
final class CompetitionStore: ObservableObject {
    @Published private(set) var leagues: [League] = [] {
        didSet { save(leagues, to: "leagues.json") }
    }
    @Published private(set) var tournaments: [Tournament] = [] {
        didSet { save(tournaments, to: "tournaments.json") }
    }

    /// Reports simulated results (participants as (name, isBot) in seat
    /// order, plus the seat ranking) so ratings update for bot matches too.
    var onSimulatedResult: ((GameKind, [(name: String, isBot: Bool)], [[Int]]) -> Void)?

    init() {
        leagues = load("leagues.json") ?? []
        tournaments = load("tournaments.json") ?? []
    }

    // MARK: - Leagues

    func add(_ league: League) { leagues.insert(league, at: 0) }

    func deleteLeague(id: UUID) { leagues.removeAll { $0.id == id } }

    func league(id: UUID) -> League? { leagues.first { $0.id == id } }

    func record(leagueID: UUID, matchID: UUID, outcome: MatchOutcome) {
        guard let index = leagues.firstIndex(where: { $0.id == leagueID }) else { return }
        leagues[index].record(matchID: matchID, outcome: outcome)
    }

    /// Play out a bot-only league match instantly.
    func simulateLeagueMatch(leagueID: UUID, matchID: UUID) {
        guard let league = league(id: leagueID),
              let match = league.matches.first(where: { $0.id == matchID }),
              let outcome = Self.simulateOutcome(kind: league.gameKind, options: league.options,
                                                 entrantIDs: match.entrantIDs) else { return }
        record(leagueID: leagueID, matchID: matchID, outcome: outcome)
        reportSimulated(kind: league.gameKind, entrants: match.entrantIDs.compactMap { league.entrant($0) },
                        seatIDs: match.entrantIDs, outcome: outcome)
    }

    // MARK: - Tournaments

    func add(_ tournament: Tournament) { tournaments.insert(tournament, at: 0) }

    func deleteTournament(id: UUID) { tournaments.removeAll { $0.id == id } }

    func tournament(id: UUID) -> Tournament? { tournaments.first { $0.id == id } }

    /// Returns false when the result was a draw a knockout can't accept.
    @discardableResult
    func record(tournamentID: UUID, matchID: UUID, outcome: MatchOutcome) -> Bool {
        guard let index = tournaments.firstIndex(where: { $0.id == tournamentID }) else { return true }
        return tournaments[index].record(matchID: matchID, outcome: outcome)
    }

    /// Play out a bot-only knockout match instantly, replaying draws.
    func simulateTournamentMatch(tournamentID: UUID, matchID: UUID) {
        guard let tournament = tournament(id: tournamentID),
              let match = tournament.matches.first(where: { $0.id == matchID }) else { return }
        for _ in 0..<20 {
            guard let outcome = Self.simulateOutcome(kind: tournament.gameKind, options: tournament.options,
                                                     entrantIDs: match.entrantIDs) else { return }
            if record(tournamentID: tournamentID, matchID: matchID, outcome: outcome) {
                reportSimulated(kind: tournament.gameKind,
                                entrants: match.entrantIDs.compactMap { tournament.entrant($0) },
                                seatIDs: match.entrantIDs, outcome: outcome)
                return
            }
        }
    }

    private func reportSimulated(kind: GameKind, entrants: [Entrant], seatIDs: [UUID], outcome: MatchOutcome) {
        guard entrants.count == seatIDs.count else { return }
        let seatRanking = outcome.rankedGroups.map { $0.compactMap { id in seatIDs.firstIndex(of: id) } }
        onSimulatedResult?(kind, entrants.map { ($0.name, $0.isBot) }, seatRanking)
    }

    // MARK: - Bot simulation

    static func simulateOutcome(kind: GameKind, options: GameOptions,
                                entrantIDs: [UUID], maxMoves: Int = 30000) -> MatchOutcome? {
        var game = AnyGame.make(kind: kind, options: options)
        var moves = 0
        while !game.isOver, moves < maxMoves,
              let move = Bot.chooseMove(for: game, difficulty: options.botDifficulty) {
            guard (try? game.applyValidated(move)) != nil else { return nil }
            moves += 1
        }
        let ranking = game.ranking()
        guard !ranking.isEmpty else { return nil }
        return MatchOutcome(rankedGroups: ranking.map { $0.map { entrantIDs[$0] } },
                            summary: game.resultText ?? "Game over")
    }

    private func load<T: Decodable>(_ file: String) -> T? { Persistence.load(file) }
    private func save<T: Encodable>(_ value: T, to file: String) { Persistence.save(value, to: file) }
}
