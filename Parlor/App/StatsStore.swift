import Foundation
import Combine

/// Lifetime record for one game, shown on the home screen.
struct GameStats: Codable {
    var played = 0
    var wins = 0
    /// Pinball: best score. Klondike/FreeCell: fewest moves in a solve.
    var bestScore: Int? = nil

    var summary: String? {
        guard played > 0 else { return nil }
        return "\(played) played · \(wins) won"
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
        if won { record.wins += 1 }
        if let score {
            switch kind {
            case .pinball, .breakout, .tetris:   // higher is better
                if score > (record.bestScore ?? Int.min) { record.bestScore = score }
            case .solitaire, .freecell:           // fewer moves is better, only counts when solved
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
        case .pinball, .breakout, .tetris: return "Best \(best)"
        case .solitaire, .freecell: return "Best solve \(best) moves"
        default: return nil
        }
    }
}
