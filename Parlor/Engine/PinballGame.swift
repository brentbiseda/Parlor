import Foundation

/// Pinball bookkeeping. The physics lives in the SpriteKit table (Views);
/// the engine only tracks score and balls so results, "play again", and
/// high-score recording flow through the same machinery as every other game.
struct PinballGame: GameEngine {
    static let kind = GameKind.pinball

    static let ballsPerGame = 3

    var score = 0
    var ballsPlayed = 0

    var currentPlayer: Int { 0 }
    var isOver: Bool { ballsPlayed >= Self.ballsPerGame }
    var ballsLeft: Int { Self.ballsPerGame - ballsPlayed }

    func legalMoves() -> [Move] {
        isOver ? [] : [.pinball(.ballDrained)]
    }

    /// The table reports score and drain events freely while the game runs.
    func isLegal(_ move: Move) -> Bool {
        if case .pinball = move { return !isOver }
        return false
    }

    mutating func apply(_ move: Move) throws {
        guard case .pinball(let event) = move else { throw GameError.illegalMove }
        switch event {
        case .score(let points):
            guard points > 0 else { throw GameError.illegalMove }
            score += points
        case .ballDrained:
            ballsPlayed += 1
        }
    }

    var statusText: String {
        "Score \(score) · Ball \(min(ballsPlayed + 1, Self.ballsPerGame)) of \(Self.ballsPerGame)"
    }

    var resultText: String? {
        isOver ? "Game over — \(score) points" : nil
    }
}
