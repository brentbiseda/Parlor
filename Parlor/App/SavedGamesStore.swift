import Foundation
import Combine

/// Suspended tables for asynchronous play. Saves are keyed by session id,
/// so re-saving the same table updates its entry instead of duplicating it.
@MainActor
final class SavedGamesStore: ObservableObject {
    @Published private(set) var games: [SavedGame] = [] {
        didSet { Persistence.save(games, to: "saved-games.json") }
    }

    private let limit = 20

    init() {
        games = Persistence.load("saved-games.json") ?? []
    }

    func upsert(_ saved: SavedGame) {
        games.removeAll { $0.id == saved.id }
        games.insert(saved, at: 0)
        if games.count > limit { games.removeLast(games.count - limit) }
    }

    func remove(id: UUID) {
        games.removeAll { $0.id == id }
    }

    func game(id: UUID) -> SavedGame? { games.first { $0.id == id } }
}
