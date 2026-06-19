import Foundation

/// Breakout bookkeeping. The paddle-and-bricks physics lives in the SpriteKit
/// scene (Views); the engine tracks score, lives, level, and all stats so
/// results flow through the same machinery as every other game.
struct BreakoutGame: GameEngine {
    static let kind = GameKind.breakout
    static let livesPerGame = 3

    var score = 0
    var livesLost = 0
    var level = 1
    var bricksHit = 0
    var currentStreak = 0
    var bestStreak = 0
    var levelsCleared = 0
    var ballsLostThisLevel = 0
    var perfectLevels = 0
    var wallBounces = 0
    // Power-up stats
    var powerUpsCaught = 0
    var extraLivesGained = 0
    var shieldHits = 0
    // Brick progress (reported by scene)
    var bricksRemaining = 0
    var totalBricks = 0

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
            bricksHit += 1
            currentStreak += 1
            if currentStreak > bestStreak { bestStreak = currentStreak }
        case .ballLost:
            livesLost += 1
            ballsLostThisLevel += 1
            currentStreak = 0
        case .levelCleared:
            score += 500
            levelsCleared += 1
            if ballsLostThisLevel == 0 { perfectLevels += 1; score += 250 }
            ballsLostThisLevel = 0
            level += 1
            currentStreak = 0
        case .wallBounce:
            wallBounces += 1
        case .powerUp(let kind):
            powerUpsCaught += 1
            switch kind {
            case .extraLife:
                if livesLost > 0 { livesLost -= 1 }
                extraLivesGained += 1
            default:
                break
            }
        case .shieldHit:
            shieldHits += 1
        case .brickCount(let remaining, let total):
            bricksRemaining = remaining
            if total > 0 { totalBricks = total }
        }
    }

    private var speedLabel: String {
        switch level {
        case 1...2: return ""
        case 3...4: return " ⚡"
        case 5...6: return " ⚡⚡"
        default: return " ⚡⚡⚡"
        }
    }

    var statusText: String {
        var text = "Score \(score) · Lv\(level)\(speedLabel) · \(bricksHit) hit · " + String(repeating: "●", count: livesLeft)
        if currentStreak > 4 { text += " · 🔥\(currentStreak)" }
        if totalBricks > 0 {
            let pct = (totalBricks - bricksRemaining) * 100 / totalBricks
            text += " · \(bricksRemaining) left (\(pct)%)"
        }
        return text
    }

    var resultText: String? {
        guard isOver else { return nil }
        var parts = ["Game over — \(score) pts · level \(level)"]
        if bricksHit > 0 { parts.append("\(bricksHit) bricks") }
        if bestStreak > 4 { parts.append("best streak \(bestStreak) 🔥") }
        if perfectLevels > 0 { parts.append("⭐ \(perfectLevels) perfect level\(perfectLevels == 1 ? "" : "s")") }
        if livesLost > 0 { parts.append("\(bricksHit / max(livesLost, 1)) bricks/life") }
        if levelsCleared > 0 && perfectLevels == levelsCleared { parts.append("🏆 flawless run!") }
        if wallBounces > 0 { parts.append("\(wallBounces) wall bounce\(wallBounces == 1 ? "" : "s")") }
        if powerUpsCaught > 0 { parts.append("⚡ \(powerUpsCaught) power-up\(powerUpsCaught == 1 ? "" : "s")") }
        if extraLivesGained > 0 { parts.append("❤️ +\(extraLivesGained) extra life") }
        if shieldHits > 0 { parts.append("🛡 \(shieldHits) save\(shieldHits == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }
}
