import Foundation

// MARK: - Shared pieces

/// A participant in a league or tournament. Humans play pass-and-play on
/// this device; bots are simulated (instantly when no human is at the table).
struct Entrant: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var isBot: Bool
}

/// Outcome of one table: entrant ids grouped by finishing rank, best group
/// first, tied entrants sharing a group (mirrors `GameEngine.ranking()`).
struct MatchOutcome: Codable, Hashable {
    var rankedGroups: [[UUID]]
    var summary: String
}

struct CompetitionMatch: Codable, Identifiable, Hashable {
    var id = UUID()
    var round: Int
    /// Entrants in seat order. Partnership games pair seats 0&2 vs 1&3.
    var entrantIDs: [UUID]
    var outcome: MatchOutcome?

    var isPlayed: Bool { outcome != nil }

    /// The first `count` entrants by rank, or nil if a tie spans the cutoff
    /// (knockout matches must then be replayed).
    func advancing(count: Int) -> [UUID]? {
        guard let outcome else { return nil }
        var result: [UUID] = []
        for group in outcome.rankedGroups {
            if result.count == count { break }
            guard result.count + group.count <= count else { return nil }
            result += group
        }
        return result.count == count ? result : nil
    }
}

// MARK: - League

/// A persistent league: a fixed roster plays a generated schedule and earns
/// placement points. 2-player games use a round robin; 4-player games seat
/// rotating tables of four.
struct League: Codable, Identifiable {
    var id = UUID()
    var name: String
    var gameKind: GameKind
    var options = GameOptions()
    var entrants: [Entrant]
    var matches: [CompetitionMatch] = []
    var createdAt = Date()

    struct Standing: Identifiable {
        var entrant: Entrant
        var played = 0
        var wins = 0
        var draws = 0
        var losses = 0
        var points = 0.0
        var id: UUID { entrant.id }
    }

    init(name: String, gameKind: GameKind, options: GameOptions = GameOptions(),
         entrants: [Entrant], rounds: Int) {
        self.name = name
        self.gameKind = gameKind
        self.options = options
        self.entrants = entrants
        self.matches = League.makeSchedule(entrants: entrants, gameKind: gameKind, rounds: rounds)
    }

    var roundCount: Int { (matches.map(\.round).max() ?? -1) + 1 }
    var playedCount: Int { matches.filter(\.isPlayed).count }
    var isComplete: Bool { !matches.isEmpty && matches.allSatisfy(\.isPlayed) }

    func entrant(_ id: UUID) -> Entrant? { entrants.first { $0.id == id } }

    func matches(inRound round: Int) -> [CompetitionMatch] {
        matches.filter { $0.round == round }
    }

    /// Placement points: with P seats, finishing position i (0-based) is worth
    /// P-1-i; tied entrants split the positions they cover evenly.
    /// (4-player: 3/2/1/0 · 2-player: 1/0 · a 2-player draw pays ½ each.)
    func standings() -> [Standing] {
        var table = Dictionary(uniqueKeysWithValues: entrants.map { ($0.id, Standing(entrant: $0)) })
        for match in matches {
            guard let outcome = match.outcome else { continue }
            let seats = match.entrantIDs.count
            var position = 0
            for (groupIndex, group) in outcome.rankedGroups.enumerated() {
                let covered = (position..<(position + group.count))
                let share = covered.reduce(0.0) { $0 + Double(seats - 1 - $1) } / Double(group.count)
                for id in group {
                    table[id]?.played += 1
                    table[id]?.points += share
                    if outcome.rankedGroups.count == 1 {
                        table[id]?.draws += 1
                    } else if groupIndex == 0 {
                        table[id]?.wins += 1
                    } else {
                        table[id]?.losses += 1
                    }
                }
                position += group.count
            }
        }
        return table.values.sorted {
            if $0.points != $1.points { return $0.points > $1.points }
            if $0.wins != $1.wins { return $0.wins > $1.wins }
            return $0.entrant.name < $1.entrant.name
        }
    }

    mutating func record(matchID: UUID, outcome: MatchOutcome) {
        guard let index = matches.firstIndex(where: { $0.id == matchID }) else { return }
        matches[index].outcome = outcome
    }

    // MARK: Scheduling

    static func makeSchedule(entrants: [Entrant], gameKind: GameKind, rounds: Int) -> [CompetitionMatch] {
        gameKind.playerCount == 2
            ? roundRobin(entrants: entrants, doubled: rounds > 1)
            : rotatingTables(entrants: entrants, rounds: rounds)
    }

    /// Circle-method round robin. Odd rosters get a bye each round.
    /// `doubled` repeats the schedule with seats (colors) swapped.
    static func roundRobin(entrants: [Entrant], doubled: Bool) -> [CompetitionMatch] {
        var ids: [UUID?] = entrants.map(\.id)
        if ids.count % 2 == 1 { ids.append(nil) }
        let n = ids.count
        guard n >= 2 else { return [] }
        var matches: [CompetitionMatch] = []
        var round = 0
        for cycle in 0..<(doubled ? 2 : 1) {
            for _ in 0..<(n - 1) {
                for i in 0..<(n / 2) {
                    guard let a = ids[i], let b = ids[n - 1 - i] else { continue }
                    // Alternate who sits first so colors/leads vary; the
                    // second cycle flips every pairing.
                    let flip = (round + i + cycle).isMultiple(of: 2)
                    matches.append(CompetitionMatch(round: round, entrantIDs: flip ? [a, b] : [b, a]))
                }
                // Rotate all but the first entry.
                let last = ids.removeLast()
                ids.insert(last, at: 1)
                round += 1
            }
        }
        return matches
    }

    /// 4-player games: each round re-seats the roster into tables of four by
    /// rotating everyone but the first player, so opponents (and partners in
    /// partnership games) vary from round to round.
    static func rotatingTables(entrants: [Entrant], rounds: Int) -> [CompetitionMatch] {
        let ids = entrants.map(\.id)
        guard ids.count >= 4, ids.count % 4 == 0 else { return [] }
        var matches: [CompetitionMatch] = []
        var rotating = Array(ids.dropFirst())
        for round in 0..<rounds {
            let order = [ids[0]] + rotating
            for table in stride(from: 0, to: order.count, by: 4) {
                matches.append(CompetitionMatch(round: round,
                                                entrantIDs: Array(order[table..<(table + 4)])))
            }
            rotating.append(rotating.removeFirst())
        }
        return matches
    }
}

// MARK: - Tournament

/// Single-elimination knockout. 2-player games advance the winner of each
/// match; 4-player games seat tables of four and advance the top two
/// (the winning pair, in partnership games) until one table remains.
struct Tournament: Codable, Identifiable {
    var id = UUID()
    var name: String
    var gameKind: GameKind
    var options = GameOptions()
    var entrants: [Entrant]
    var matches: [CompetitionMatch] = []
    var createdAt = Date()

    init(name: String, gameKind: GameKind, options: GameOptions = GameOptions(), entrants: [Entrant]) {
        self.name = name
        self.gameKind = gameKind
        self.options = options
        self.entrants = entrants.shuffled()   // random draw
        let seats = gameKind.playerCount
        for table in stride(from: 0, to: self.entrants.count, by: seats) {
            matches.append(CompetitionMatch(round: 0,
                                            entrantIDs: self.entrants[table..<(table + seats)].map(\.id)))
        }
    }

    /// Entrant counts that produce a clean bracket: tableSize × a power of two.
    static func validSizes(for kind: GameKind) -> [Int] {
        kind.playerCount == 2 ? [4, 8, 16] : [4, 8, 16]
    }

    var tableSize: Int { gameKind.playerCount }
    var advancePerTable: Int { tableSize == 2 ? 1 : 2 }
    var roundCount: Int { (matches.map(\.round).max() ?? -1) + 1 }
    var currentRound: Int { roundCount - 1 }

    func entrant(_ id: UUID) -> Entrant? { entrants.first { $0.id == id } }
    func matches(inRound round: Int) -> [CompetitionMatch] { matches.filter { $0.round == round } }

    func roundTitle(_ round: Int) -> String {
        let tables = matches(inRound: round).count
        if tables == 1 { return "Final" }
        if tables == 2 { return tableSize == 2 ? "Semifinals" : "Semifinal tables" }
        return "Round \(round + 1)"
    }

    /// The winners once the final table is decided. Partnership games crown
    /// the winning pair; otherwise the single top finisher.
    var championIDs: [UUID]? {
        guard let final = matches(inRound: currentRound).first,
              matches(inRound: currentRound).count == 1,
              let top = final.outcome?.rankedGroups.first else { return nil }
        if gameKind.isPartnership { return top.count == 2 ? top : nil }
        return top.count == 1 ? top : nil
    }

    var isComplete: Bool { championIDs != nil }

    /// Record an outcome. Knockouts can't tolerate ties across the cutoff
    /// (or a drawn head-to-head), so those clear the result and ask for a
    /// replay. Returns false when a replay is needed.
    @discardableResult
    mutating func record(matchID: UUID, outcome: MatchOutcome) -> Bool {
        guard let index = matches.firstIndex(where: { $0.id == matchID }),
              matches[index].outcome == nil else { return true }   // knockout results are final
        matches[index].outcome = outcome
        if matches[index].advancing(count: advancePerTable) == nil {
            matches[index].outcome = nil
            return false
        }
        buildNextRoundIfReady()
        return true
    }

    /// When every table of the current round is decided and more than one
    /// table played, pair tables to build the next round. Two tables feed
    /// each new table: winners (or winning pairs) are split across seats so
    /// partnership pairs stay partners — seats [A1, B1, A2, B2].
    mutating func buildNextRoundIfReady() {
        let round = currentRound
        let current = matches(inRound: round)
        guard current.count > 1 else { return }
        let advancers = current.map { $0.advancing(count: advancePerTable) }
        guard !advancers.contains(where: { $0 == nil }) else { return }
        let lists = advancers.compactMap { $0 }
        for i in stride(from: 0, to: lists.count, by: 2) {
            let a = lists[i], b = lists[i + 1]
            let seats = tableSize == 2 ? [a[0], b[0]] : [a[0], b[0], a[1], b[1]]
            matches.append(CompetitionMatch(round: round + 1, entrantIDs: seats))
        }
    }
}
