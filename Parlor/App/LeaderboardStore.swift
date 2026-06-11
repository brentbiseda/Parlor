import Foundation
import Combine

/// Local record tables: pinball high scores, fastest solitaire solves, …
/// Top 20 per game, persisted as JSON.
@MainActor
final class LeaderboardStore: ObservableObject {
    @Published private(set) var boards: [String: [ScoreEntry]] = [:] {
        didSet { Persistence.save(boards, to: "leaderboards.json") }
    }

    init() {
        boards = Persistence.load("leaderboards.json") ?? [:]
    }

    func entries(for kind: GameKind) -> [ScoreEntry] {
        boards[kind.rawValue] ?? []
    }

    func record(kind: GameKind, playerName: String, value: Int, detail: String) {
        guard kind.leaderboardTitle != nil else { return }
        var entries = boards[kind.rawValue] ?? []
        entries.append(ScoreEntry(playerName: playerName, value: value, detail: detail))
        entries.sort {
            kind.leaderboardAscending ? $0.value < $1.value : $0.value > $1.value
        }
        boards[kind.rawValue] = Array(entries.prefix(20))
    }

    /// 1-based position the value would land at, for "new record!" flair.
    func position(of value: Int, kind: GameKind) -> Int {
        let better = entries(for: kind).filter {
            kind.leaderboardAscending ? $0.value < value : $0.value > value
        }
        return better.count + 1
    }
}
