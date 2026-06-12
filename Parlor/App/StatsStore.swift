import Foundation
import Combine

/// Lifetime record for one game, shown on the home screen. Decoding is
/// tolerant of missing keys so older saved stats survive new fields.
struct GameStats: Codable {
    var played = 0
    var wins = 0
    /// Pinball: best score. Klondike/FreeCell: fewest moves in a solve.
    var bestScore: Int? = nil
    var streak = 0
    var bestStreak = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        played = try c.decodeIfPresent(Int.self, forKey: .played) ?? 0
        wins = try c.decodeIfPresent(Int.self, forKey: .wins) ?? 0
        bestScore = try c.decodeIfPresent(Int.self, forKey: .bestScore)
        streak = try c.decodeIfPresent(Int.self, forKey: .streak) ?? 0
        bestStreak = try c.decodeIfPresent(Int.self, forKey: .bestStreak) ?? 0
    }

    var summary: String? {
        guard played > 0 else { return nil }
        var text = "\(played) played · \(wins) won"
        if streak >= 2 { text += " · 🔥\(streak)" }
        return text
    }
}

@MainActor
final class StatsStore: ObservableObject {
    @Published private(set) var stats: [String: GameStats] = [:] {
        didSet {
            if let data = try? JSONEncoder().encode(stats) {
                UserDefaults.standard.set(data, forKey: Self.key)
            }
        }
    }

    private static let key = "parlor.stats"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([String: GameStats].self, from: data) {
            stats = decoded
        }
    }

    func stats(for kind: GameKind) -> GameStats {
        stats[kind.rawValue] ?? GameStats()
    }

    /// Record one finished (or abandoned solo) session for the local player.
    func recordGame(kind: GameKind, won: Bool, score: Int? = nil) {
        var record = stats(for: kind)
        record.played += 1
        if won {
            record.wins += 1
            record.streak += 1
            record.bestStreak = max(record.bestStreak, record.streak)
        } else {
            record.streak = 0
        }
        if let score {
            switch kind {
            case .pinball, .breakout, .tetris, .capsules, .muncher, .hopper,
                 .centipede, .snake, .football, .baseball:   // higher is better
                if score > (record.bestScore ?? Int.min) { record.bestScore = score }
            case .solitaire, .freecell:               // fewer moves is better, when solved
                if won, score < (record.bestScore ?? Int.max) { record.bestScore = score }
            default:
                break
            }
        }
        stats[kind.rawValue] = record
    }

    func bestLine(for kind: GameKind) -> String? {
        guard let best = stats(for: kind).bestScore else { return nil }
        switch kind {
        case .pinball, .breakout, .tetris, .capsules, .muncher, .hopper,
             .centipede, .snake, .football:
            return "Best \(best)"
        case .baseball: return "Best \(best) ft"
        case .solitaire, .freecell: return "Best solve \(best) moves"
        default: return nil
        }
    }
}
