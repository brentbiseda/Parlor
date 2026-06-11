import Foundation

/// Links an active session to the league/tournament match it came from so
/// the result lands back in the standings when the table closes. Persisted
/// inside SavedGame so a suspended match still counts when finished later.
struct ActiveMatch: Codable, Hashable {
    enum Competition: Codable, Hashable {
        case league(UUID)
        case tournament(UUID)
    }
    var competition: Competition
    var matchID: UUID
    /// Entrant for each seat, in seat order.
    var entrantIDsBySeat: [UUID]
}

/// A suspended local table — asynchronous play. The whole engine state is
/// Codable, so games park on disk and resume whenever, even mid-league.
struct SavedGame: Codable, Identifiable {
    var id: UUID                    // the session's id, so saves upsert
    var kind: GameKind
    var options: GameOptions
    var players: [PlayerInfo]
    var game: AnyGame
    var match: ActiveMatch?
    var savedAt = Date()

    var playersLine: String {
        let humans = players.filter { !$0.isBot }
        if kind.isSolo { return humans.first?.name ?? "Solo" }
        if humans.count == players.count { return players.map(\.name).joined(separator: ", ") }
        let bots = players.count - humans.count
        return humans.map(\.name).joined(separator: ", ") + " + \(bots) bot\(bots == 1 ? "" : "s")"
    }
}
