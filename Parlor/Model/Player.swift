import Foundation

/// One seat at a table, locally or across the wire.
struct PlayerInfo: Codable, Hashable, Identifiable {
    var id: String          // stable per-install UUID (humans) or "bot-N"
    var name: String
    var isBot = false
}

/// A local identity: human profiles are user-managed; bot profiles are
/// created automatically the first time a bot name shows up in a result,
/// so the rankings table can trash-talk back.
struct PlayerProfile: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var symbol: String = "person.fill"
    var colorIndex: Int = 0
    var isBot = false
    var createdAt = Date()
    /// GameKind rawValue → rating. Only games actually played appear.
    var ratings: [String: Rating] = [:]

    func rating(for kind: GameKind) -> Rating {
        ratings[kind.rawValue] ?? Rating()
    }

    var ratedGameCount: Int { ratings.values.reduce(0) { $0 + $1.played } }

    static let symbols = ["person.fill", "suit.spade.fill", "suit.heart.fill", "crown.fill",
                          "star.fill", "bolt.fill", "flame.fill", "moon.stars.fill",
                          "leaf.fill", "pawprint.fill", "music.note", "bird.fill",
                          "diamond.fill", "theatermasks.fill", "sailboat.fill", "cup.and.saucer.fill"]
}

/// Per-game competitive record for one profile.
struct Rating: Codable, Hashable {
    var elo = Elo.initial
    var played = 0
    var wins = 0
    var draws = 0
    var losses = 0

    var record: String { "\(wins)–\(draws)–\(losses)" }
}

/// Pairwise multiplayer Elo. Every pair of players in a finished game is
/// scored 1 / ½ / 0 by finishing-group order; K is split across opponents so
/// a 4-player table moves ratings about as fast as a head-to-head game.
enum Elo {
    static let initial = 1200.0
    static let k = 24.0

    /// Rating changes for `ratings` given `ranking` (groups of indices into
    /// `ratings`, best first, ties share a group). Zero-sum.
    static func deltas(ranking: [[Int]], ratings: [Double], k: Double = Elo.k) -> [Double] {
        let n = ratings.count
        var deltas = [Double](repeating: 0, count: n)
        guard n > 1 else { return deltas }
        var rankOf = [Int: Int]()
        for (rank, group) in ranking.enumerated() {
            for player in group { rankOf[player] = rank }
        }
        let players = ranking.flatMap { $0 }
        let kEff = k / Double(max(players.count - 1, 1))
        for (i, a) in players.enumerated() {
            for b in players[(i + 1)...] {
                guard let ra = rankOf[a], let rb = rankOf[b] else { continue }
                let score: Double = ra == rb ? 0.5 : (ra < rb ? 1 : 0)
                let expected = 1 / (1 + pow(10, (ratings[b] - ratings[a]) / 400))
                deltas[a] += kEff * (score - expected)
                deltas[b] += kEff * ((1 - score) - (1 - expected))
            }
        }
        return deltas
    }
}

// MARK: - Leaderboards

/// One record-table entry (high score, fastest solve, …).
struct ScoreEntry: Codable, Hashable, Identifiable {
    var id = UUID()
    var playerName: String
    var value: Int
    var detail: String
    var date = Date()
}

extension GameKind {
    /// Games with a numeric record table, and what it measures.
    var leaderboardTitle: String? {
        switch self {
        case .pinball, .breakout, .tetris, .capsules, .muncher, .hopper, .centipede, .snake:
            return "High scores"
        case .football: return "Best kicking days"
        case .baseball: return "Longest derby days"
        case .solitaire, .freecell: return "Fastest solves"
        case .mahjong: return "Cleared boards"
        default: return nil
        }
    }

    /// Whether smaller leaderboard values are better.
    var leaderboardAscending: Bool {
        switch self {
        case .solitaire, .freecell, .mahjong: return true
        default: return false
        }
    }

    func leaderboardLabel(for value: Int) -> String {
        switch self {
        case .pinball, .breakout, .tetris, .capsules, .muncher, .hopper, .centipede, .snake, .football:
            return "\(value) pts"
        case .baseball: return "\(value) ft"
        case .solitaire, .freecell: return "\(value) moves"
        case .mahjong: return value == 0 ? "no shuffles" : "\(value) shuffle\(value == 1 ? "" : "s")"
        default: return "\(value)"
        }
    }
}
