import Foundation

/// Scorekeeping engines for the SpriteKit arcade & sports games. Like
/// Pinball and Breakout, the action lives in the scene; these track score,
/// attempts, and outcomes so results flow through banners, stats,
/// leaderboards, and saved games like everything else.

// MARK: - Centipede

struct CentipedeGame: GameEngine {
    static let kind = GameKind.centipede
    static let livesPerGame = 3

    var score = 0
    var livesLost = 0
    var level = 1

    var currentPlayer: Int { 0 }
    var isOver: Bool { livesLost >= Self.livesPerGame }
    var livesLeft: Int { Self.livesPerGame - livesLost }

    func legalMoves() -> [Move] { isOver ? [] : [.arcade(.lifeLost)] }

    func isLegal(_ move: Move) -> Bool {
        if case .arcade = move { return !isOver }
        return false
    }

    mutating func apply(_ move: Move) throws {
        guard case .arcade(let event) = move else { throw GameError.illegalMove }
        switch event {
        case .score(let points) where points > 0: score += points
        case .lifeLost: livesLost += 1
        case .levelUp: level += 1; score += 300
        default: throw GameError.illegalMove
        }
    }

    var statusText: String {
        "Score \(score) · Wave \(level) · " + String(repeating: "●", count: livesLeft)
    }

    var resultText: String? {
        isOver ? "Game over — \(score) points · wave \(level)" : nil
    }
}

// MARK: - Field Goal (football)

struct FootballGame: GameEngine {
    static let kind = GameKind.football
    static let kicksPerGame = 10

    var score = 0
    var kicksTaken = 0
    var made = 0

    var currentPlayer: Int { 0 }
    var isOver: Bool { kicksTaken >= Self.kicksPerGame }
    var kicksLeft: Int { Self.kicksPerGame - kicksTaken }

    func legalMoves() -> [Move] { isOver ? [] : [.arcade(.attempt)] }

    func isLegal(_ move: Move) -> Bool {
        if case .arcade = move { return !isOver }
        return false
    }

    mutating func apply(_ move: Move) throws {
        guard case .arcade(let event) = move else { throw GameError.illegalMove }
        switch event {
        case .score(let points) where points > 0:
            score += points
            made += 1
        case .attempt:
            kicksTaken += 1
        default:
            throw GameError.illegalMove
        }
    }

    var statusText: String {
        "Score \(score) · Made \(made) · Kick \(min(kicksTaken + 1, Self.kicksPerGame)) of \(Self.kicksPerGame)"
    }

    var resultText: String? {
        isOver ? "Final — \(made) of \(Self.kicksPerGame) kicks good · \(score) points" : nil
    }
}

// MARK: - Home Run Derby (baseball)

struct BaseballGame: GameEngine {
    static let kind = GameKind.baseball
    static let pitchesPerGame = 10

    var score = 0
    var pitchesSeen = 0
    var homers = 0

    var currentPlayer: Int { 0 }
    var isOver: Bool { pitchesSeen >= Self.pitchesPerGame }
    var pitchesLeft: Int { Self.pitchesPerGame - pitchesSeen }

    func legalMoves() -> [Move] { isOver ? [] : [.arcade(.attempt)] }

    func isLegal(_ move: Move) -> Bool {
        if case .arcade = move { return !isOver }
        return false
    }

    mutating func apply(_ move: Move) throws {
        guard case .arcade(let event) = move else { throw GameError.illegalMove }
        switch event {
        case .score(let points) where points > 0:
            score += points
            homers += 1
        case .attempt:
            pitchesSeen += 1
        default:
            throw GameError.illegalMove
        }
    }

    var statusText: String {
        "\(homers) homers · \(score) ft total · Pitch \(min(pitchesSeen + 1, Self.pitchesPerGame)) of \(Self.pitchesPerGame)"
    }

    var resultText: String? {
        isOver ? "Final — \(homers) home runs · \(score) feet of dingers" : nil
    }
}

// MARK: - Penalty Shootout (soccer)

struct SoccerGame: GameEngine {
    static let kind = GameKind.soccer
    static let roundsPerSide = 5

    var yourGoals = 0
    var botGoals = 0
    var yourShots = 0
    var botShots = 0

    var currentPlayer: Int { 0 }
    /// Phase 1: you shoot 5. Phase 2: you keep goal for 5.
    var shootingPhase: Bool { yourShots < Self.roundsPerSide }
    var isOver: Bool { yourShots >= Self.roundsPerSide && botShots >= Self.roundsPerSide }
    var won: Bool { isOver && yourGoals > botGoals }

    func legalMoves() -> [Move] { isOver ? [] : [.arcade(.attempt)] }

    func isLegal(_ move: Move) -> Bool {
        if case .arcade = move { return !isOver }
        return false
    }

    mutating func apply(_ move: Move) throws {
        guard case .arcade(let event) = move else { throw GameError.illegalMove }
        switch event {
        case .score(let goals) where goals > 0: yourGoals += 1
        case .opponentScore: botGoals += 1
        case .attempt:
            if shootingPhase { yourShots += 1 } else { botShots += 1 }
        default:
            throw GameError.illegalMove
        }
    }

    var statusText: String {
        let phase = shootingPhase
            ? "You shoot · kick \(yourShots + 1) of \(Self.roundsPerSide)"
            : "You're in goal · save \(min(botShots + 1, Self.roundsPerSide)) of \(Self.roundsPerSide)"
        return "You \(yourGoals) – \(botGoals) Bots · \(phase)"
    }

    var resultText: String? {
        guard isOver else { return nil }
        if yourGoals > botGoals { return "You win the shootout \(yourGoals)–\(botGoals)!" }
        if yourGoals < botGoals { return "Bots take it \(botGoals)–\(yourGoals)" }
        return "Level at \(yourGoals)–\(botGoals) — honors shared"
    }
}

// MARK: - Air Hockey

struct HockeyGame: GameEngine {
    static let kind = GameKind.hockey
    static let goalsToWin = 7

    var yourGoals = 0
    var botGoals = 0

    var currentPlayer: Int { 0 }
    var isOver: Bool { yourGoals >= Self.goalsToWin || botGoals >= Self.goalsToWin }
    var won: Bool { yourGoals >= Self.goalsToWin }

    func legalMoves() -> [Move] { isOver ? [] : [.arcade(.opponentScore(1))] }

    func isLegal(_ move: Move) -> Bool {
        if case .arcade = move { return !isOver }
        return false
    }

    mutating func apply(_ move: Move) throws {
        guard case .arcade(let event) = move else { throw GameError.illegalMove }
        switch event {
        case .score(let goals) where goals > 0: yourGoals += 1
        case .opponentScore: botGoals += 1
        default: throw GameError.illegalMove
        }
    }

    var statusText: String {
        "You \(yourGoals) – \(botGoals) Bot · first to \(Self.goalsToWin)"
    }

    var resultText: String? {
        guard isOver else { return nil }
        return won ? "You win \(yourGoals)–\(botGoals)!" : "The bot wins \(botGoals)–\(yourGoals)"
    }
}
