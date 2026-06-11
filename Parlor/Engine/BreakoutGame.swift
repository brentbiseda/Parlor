import Foundation

/// Breakout bookkeeping. The paddle-and-bricks physics lives in the
/// SpriteKit scene (Views); the engine tracks score, lives, and level so
/// results, "play again", stats, and leaderboards flow through the same
/// machinery as every other game.
struct BreakoutGame: GameEngine {
    static let kind = GameKind.breakout

    static let livesPerGame = 3

    var score = 0
    var livesLost = 0
    var level = 1

    var currentPlayer: Int { 0 }
    var isOver: Bool { livesLost >= Self.livesPerGame }
    var livesLeft: Int { Self.livesPerGame - livesLost }

    func legalMoves() -> [Move] {
        isOver ? [] : [.breakout(.ballLost)]
    }

    func isLegal(_ move: Move) -> Bool {
        if case .breakout = move { return !isOver }
        return false
    }

    mutating func apply(_ move: Move) throws {
        guard case .breakout(let event) = move else { throw GameError.illegalMove }
        switch event {
        case .score(let points):
            guard points > 0 else { throw GameError.illegalMove }
            score += points
        case .ballLost:
            livesLost += 1
        case .levelCleared:
            score += 500
            level += 1
        }
    }

    var statusText: String {
        "Score \(score) · Level \(level) · " + String(repeating: "●", count: livesLeft)
    }

    var resultText: String? {
        isOver ? "Game over — \(score) points · level \(level)" : nil
    }
}
