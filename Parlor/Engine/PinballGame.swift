import Foundation

/// Pinball bookkeeping. The physics lives in the SpriteKit table (Views);
/// the engine only tracks score and balls so results, "play again", and
/// high-score recording flow through the same machinery as every other game.
struct PinballGame: GameEngine {
    static let kind = GameKind.pinball

    static let ballsPerGame = 3

    var score = 0
    var ballsPlayed = 0
    var bestBallScore = 0
    var ballStartScore = 0
    /// Whether any single ball broke the 100k jackpot threshold.
    var jackpotBalls = 0
    static let jackpotThreshold = 100_000
    /// Largest single scoring event (a big bonus/combo hit).
    var biggestHit = 0
    /// Lowest single-ball score (for consistency check).
    var worstBallScore = Int.max
    /// Highest score multiplier reached during this game.
    var highestMultiplierReached = 1

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
            if points > biggestHit { biggestHit = points }
        case .ballDrained:
            let ballScore = score - ballStartScore
            if ballScore > bestBallScore { bestBallScore = ballScore }
            if ballScore < worstBallScore { worstBallScore = ballScore }
            if ballScore >= Self.jackpotThreshold { jackpotBalls += 1 }
            ballStartScore = score
            ballsPlayed += 1
        case .multiplier(let m):
            if m > highestMultiplierReached { highestMultiplierReached = m }
        }
    }

    var currentBallScore: Int { score - ballStartScore }

    var statusText: String {
        let ball = min(ballsPlayed + 1, Self.ballsPerGame)
        var text = "Score \(score) · Ball \(ball) of \(Self.ballsPerGame)"
        if currentBallScore > 0 { text += " · this ball \(currentBallScore)" }
        if currentBallScore >= Self.jackpotThreshold { text += " 💰 JACKPOT!" }
        return text
    }

    var resultText: String? {
        guard isOver else { return nil }
        var text = "Game over — \(score) points"
        if bestBallScore > 0 { text += " · best ball: \(bestBallScore)" }
        let avgBall = score / max(Self.ballsPerGame, 1)
        text += " · avg \(avgBall)/ball"
        if jackpotBalls == Self.ballsPerGame { text += " · 👑 ALL jackpot balls!" }
        else if jackpotBalls > 0 { text += " · 💰 \(jackpotBalls) jackpot ball\(jackpotBalls == 1 ? "" : "s")" }
        if biggestHit >= 5000 { text += " · 🎯 big hit \(biggestHit)" }
        if highestMultiplierReached > 1 { text += " · peak ×\(highestMultiplierReached) multiplier" }
        if bestBallScore > 0 && worstBallScore != Int.max && worstBallScore >= bestBallScore * 2 / 3 {
            text += " · 📊 consistent"
        }
        return text
    }
}
