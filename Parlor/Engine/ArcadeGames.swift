import Foundation

/// Scorekeeping engines for the SpriteKit arcade & sports games. Like
/// Pinball and Breakout, the action lives in the scene; these track score,
/// attempts, and outcomes so results flow through banners, stats,
/// leaderboards, and saved games like everything else.

// MARK: - Centipede

struct CentipedeGame: GameEngine {
    static let kind = GameKind.centipede
    static let livesPerGame = 3
    /// Bonus per mushroom destroyed (score bonus for clearing mushroom fields).
    static let mushroomBonus = 5

    var score = 0
    var livesLost = 0
    var level = 1
    /// Mushrooms destroyed this game (not just shot — full-level clears too).
    var mushroomsDestroyed = 0
    /// Centipede segments shot this game.
    var segmentsShot = 0
    /// Best score per life (peak single-life score).
    var bestLifeScore = 0
    private var lifeStartScore = 0
    /// Highest wave reached this game (used for milestone callouts).
    var deepestWave = 1

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
        case .score(let points) where points > 0:
            score += points
            // Heuristic: segment kills are 100 pts; mushroom hits are 5 pts.
            if points % 100 == 0 { segmentsShot += points / 100 }
            else { mushroomsDestroyed += points / Self.mushroomBonus }
        case .lifeLost:
            let lifeScore = score - lifeStartScore
            if lifeScore > bestLifeScore { bestLifeScore = lifeScore }
            lifeStartScore = score
            livesLost += 1
        case .levelUp: level += 1; score += 300; deepestWave = max(deepestWave, level)
        default: throw GameError.illegalMove
        }
    }

    private var speedLabel: String {
        switch level {
        case 1...3: return ""
        case 4...6: return " ⚡"
        case 7...9: return " ⚡⚡"
        default:    return " ⚡⚡⚡ Hyper!"
        }
    }

    var statusText: String {
        let lifeScore = score - lifeStartScore
        let paceStr = lifeScore > bestLifeScore && bestLifeScore > 0 ? " · ⭐ best life pace!" : ""
        return "Score \(score) · Wave \(level)\(speedLabel) · " + String(repeating: "●", count: livesLeft) + paceStr
    }

    var resultText: String? {
        guard isOver else { return nil }
        var parts = ["Game over — \(score) pts", "wave \(level)"]
        if segmentsShot > 0 { parts.append("\(segmentsShot) segments") }
        if mushroomsDestroyed > 0 { parts.append("\(mushroomsDestroyed) mushrooms") }
        if bestLifeScore > 0 { parts.append("best life \(bestLifeScore) pts") }
        if score / max(livesLost, 1) >= 2000 { parts.append("🎯 \(score / max(livesLost, 1)) pts/life") }
        if deepestWave >= 10 { parts.append("⚡⚡⚡ reached Hyper wave \(deepestWave)!") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Field Goal (football)

struct FootballGame: GameEngine {
    static let kind = GameKind.football
    static let kicksPerGame = 10

    var score = 0
    var kicksTaken = 0
    var made = 0
    /// Per-kick result: true = made, false = missed. Populated on each attempt.
    var kickResults: [Bool] = []
    /// Current consecutive made kicks (reset on a miss).
    var currentStreak = 0
    /// Best consecutive made kicks this game.
    var bestStreak = 0
    /// Points value of the longest single kick scored.
    var longestKick = 0
    /// Worst run of consecutive missed kicks this game.
    var worstMissStreak = 0
    private var currentMissStreak = 0
    /// Whether the most recent score event has been recorded for this attempt.
    private var pendingMade = false

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
            pendingMade = true
            currentStreak += 1
            currentMissStreak = 0
            if currentStreak > bestStreak { bestStreak = currentStreak }
            if points > longestKick { longestKick = points }
        case .attempt:
            kickResults.append(pendingMade)
            pendingMade = false
            kicksTaken += 1
            if kicksTaken > made {
                currentStreak = 0
                currentMissStreak += 1
                if currentMissStreak > worstMissStreak { worstMissStreak = currentMissStreak }
            }
        default:
            throw GameError.illegalMove
        }
    }

    var statusText: String {
        var text = "Score \(score) · Made \(made) · Kick \(min(kicksTaken + 1, Self.kicksPerGame))/\(Self.kicksPerGame)"
        if currentStreak >= 3 { text += " · 🔥\(currentStreak) in a row!" }
        else if currentStreak > 1 { text += " · 🔥\(currentStreak)" }
        if made == kicksTaken && kicksTaken > 0 && kicksLeft > 0 { text += " · 🎯 still perfect" }
        if kicksLeft == 1 { text += " · ⚡ final kick" }
        return text
    }

    var resultText: String? {
        guard isOver else { return nil }
        let pct = made * 100 / Self.kicksPerGame
        var parts = ["Final — \(made)/\(Self.kicksPerGame) good (\(pct)%) · \(score) pts"]
        if bestStreak > 1 { parts.append("🔥 best streak \(bestStreak)") }
        if longestKick > 0 { parts.append("longest \(longestKick) pts") }
        if worstMissStreak >= 3 { parts.append("😬 \(worstMissStreak) misses in a row") }
        if made == Self.kicksPerGame { parts.append("🎯 Perfect!") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Home Run Derby (baseball)

struct BaseballGame: GameEngine {
    static let kind = GameKind.baseball
    static let pitchesPerGame = 10

    var score = 0
    var pitchesSeen = 0
    var homers = 0
    /// Distance in feet of the longest home run this session.
    var longestHomer = 0
    /// Consecutive pitches with a home run.
    var currentHomerStreak = 0
    var bestHomerStreak = 0

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
            currentHomerStreak += 1
            if currentHomerStreak > bestHomerStreak { bestHomerStreak = currentHomerStreak }
            if points > longestHomer { longestHomer = points }
        case .attempt:
            pitchesSeen += 1
            if pitchesSeen > homers { currentHomerStreak = 0 }
        default:
            throw GameError.illegalMove
        }
    }

    var statusText: String {
        var text = "\(homers) HR · \(score) ft · Pitch \(min(pitchesSeen + 1, Self.pitchesPerGame))/\(Self.pitchesPerGame)"
        if longestHomer > 0 { text += " · longest \(longestHomer) ft" }
        if currentHomerStreak >= 2 { text += " · 🔥\(currentHomerStreak)" }
        if pitchesLeft == 1 { text += " · ⚡ last pitch" }
        return text
    }

    var resultText: String? {
        guard isOver else { return nil }
        let swingAndMisses = pitchesSeen - homers
        var parts = ["Final — \(homers) home run\(homers == 1 ? "" : "s") · \(score) ft total"]
        if pitchesSeen > 0 {
            let avg = String(format: ".%03d", homers * 1000 / pitchesSeen)
            parts.append("avg \(avg)")
        }
        if homers > 0 { parts.append("avg \(score / homers) ft/HR") }
        if longestHomer > 0 { parts.append("longest \(longestHomer) ft") }
        if bestHomerStreak >= 3 { parts.append("🔥 \(bestHomerStreak)-homer streak") }
        if swingAndMisses > 0 { parts.append("\(swingAndMisses) out\(swingAndMisses == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Penalty Shootout (soccer)

/// Tracks a 5-kick penalty shootout. Phase 1: player takes 5 kicks;
/// phase 2: player keeps goal against 5 bot attempts. The match ends
/// early if one side can no longer be caught.
struct SoccerGame: GameEngine {
    static let kind = GameKind.soccer
    static let roundsPerSide = 5

    enum Phase: Codable, Hashable {
        case shooting   // player kicks
        case keeping    // player is goalkeeper
        case done
    }

    var yourGoals = 0
    var botGoals = 0
    var yourShots = 0
    var botShots = 0
    var saves = 0       // shots blocked while keeping
    var phase: Phase = .shooting
    /// Largest goal deficit the player faced (for comeback detection).
    var maxDeficit = 0
    /// Consecutive shooting attempts without scoring.
    var currentDrought = 0
    var longestDrought = 0

    var currentPlayer: Int { 0 }
    var isOver: Bool { phase == .done }
    var won: Bool { isOver && yourGoals > botGoals }

    func legalMoves() -> [Move] { isOver ? [] : [.arcade(.attempt)] }

    func isLegal(_ move: Move) -> Bool {
        if case .arcade = move { return !isOver }
        return false
    }

    mutating func apply(_ move: Move) throws {
        guard case .arcade(let event) = move, !isOver else { throw GameError.illegalMove }
        switch event {
        case .score(let goals) where goals > 0 && phase == .shooting:
            yourGoals += 1
            currentDrought = 0
        case .opponentScore where phase == .keeping:
            botGoals += 1
            if botGoals - yourGoals > maxDeficit { maxDeficit = botGoals - yourGoals }
        case .attempt:
            switch phase {
            case .shooting:
                yourShots += 1
                if yourShots > yourGoals { currentDrought += 1; longestDrought = max(longestDrought, currentDrought) }
                if yourShots >= Self.roundsPerSide { phase = .keeping }
            case .keeping:
                // Count a save if bot shot but didn't score.
                if botShots < botGoals + saves { saves += 1 }
                botShots += 1
                if botShots >= Self.roundsPerSide { phase = .done }
                else if isDecided { phase = .done }
            case .done: break
            }
        default:
            throw GameError.illegalMove
        }
        if phase == .keeping && botShots == 0 && isDecided { phase = .done }
    }

    private var isDecided: Bool {
        let remaining = Self.roundsPerSide - botShots
        return yourGoals > botGoals + remaining || botGoals > yourGoals + (Self.roundsPerSide - yourShots)
    }

    var goldenBoot: Bool { yourGoals == Self.roundsPerSide }
    var cleanSheet: Bool { phase == .done && botGoals == 0 }

    var shotAccuracy: String {
        guard yourShots > 0 else { return "0/0 (0%)" }
        let pct = yourGoals * 100 / yourShots
        return "\(yourGoals)/\(yourShots) (\(pct)%)"
    }

    private var decisionNote: String {
        guard phase != .done else { return "" }
        if isDecided { return " — DECIDED" }
        switch phase {
        case .keeping:
            let remaining = Self.roundsPerSide - botShots
            if yourGoals < botGoals { return " — must save \(botGoals - yourGoals + 1)" }
            if yourGoals > botGoals + remaining { return " — SAFE" }
            if yourGoals == botGoals && remaining == 1 { return " — 🥅 do-or-die save!" }
        case .shooting:
            let remaining = Self.roundsPerSide - yourShots
            if yourGoals == botGoals && remaining == 1 { return " — ⚡ clutch kick!" }
        default: break
        }
        return ""
    }

    var statusText: String {
        switch phase {
        case .shooting:
            return "You \(yourGoals) – \(botGoals) Bot · Kick \(yourShots + 1)/\(Self.roundsPerSide)\(decisionNote)"
        case .keeping:
            return "You \(yourGoals) – \(botGoals) Bot · Save \(min(botShots + 1, Self.roundsPerSide))/\(Self.roundsPerSide)\(saves > 0 ? " · \(saves) saved" : "")\(decisionNote)"
        case .done:
            return resultText ?? "Shootout complete"
        }
    }

    var resultText: String? {
        guard isOver else { return nil }
        var extras: [String] = []
        if goldenBoot { extras.append("⚽ Golden Boot") }
        if cleanSheet { extras.append("🧤 Clean Sheet") }
        if won && maxDeficit >= 2 { extras.append("🔄 came back from –\(maxDeficit)") }
        if abs(yourGoals - botGoals) == 1 && (yourShots + botShots) >= 8 { extras.append("⚡ down to the wire") }
        if saves > 0 && botShots > 0 {
            let savePct = saves * 100 / botShots
            extras.append("🧤 \(savePct)% saves (\(saves)/\(botShots))")
        }
        extras.append("Shot accuracy: \(shotAccuracy)")
        if longestDrought > 2 { extras.append("⏳ max \(longestDrought)-shot drought") }
        let base: String
        if yourGoals > botGoals { base = "You win \(yourGoals)–\(botGoals)" }
        else if yourGoals < botGoals { base = "Bot wins \(botGoals)–\(yourGoals)" }
        else { base = "Draw \(yourGoals)–\(botGoals)" }
        return ([base] + extras).joined(separator: " · ")
    }
}

// MARK: - Air Hockey

struct HockeyGame: GameEngine {
    static let kind = GameKind.hockey
    static let goalsToWin = 7

    var yourGoals = 0
    var botGoals = 0
    /// Maximum lead the player trailed behind before winning (comeback metric).
    var maxDeficit = 0
    /// Goals scored in each period (3 periods, index by period 0-2).
    var yourPeriodGoals: [Int] = [0, 0, 0]
    var botPeriodGoals: [Int] = [0, 0, 0]

    private var currentPeriod: Int {
        let total = yourGoals + botGoals
        if total < 3 { return 0 }
        if total < 6 { return 1 }
        return 2
    }

    var currentPlayer: Int { 0 }
    var isOver: Bool { yourGoals >= Self.goalsToWin || botGoals >= Self.goalsToWin }
    var won: Bool { yourGoals >= Self.goalsToWin }
    var shutout: Bool { won && botGoals == 0 }

    func legalMoves() -> [Move] { isOver ? [] : [.arcade(.opponentScore(1))] }

    func isLegal(_ move: Move) -> Bool {
        if case .arcade = move { return !isOver }
        return false
    }

    mutating func apply(_ move: Move) throws {
        guard case .arcade(let event) = move, !isOver else { throw GameError.illegalMove }
        switch event {
        case .score(let goals) where goals > 0:
            let p = currentPeriod
            yourGoals = min(yourGoals + 1, Self.goalsToWin)
            if p < yourPeriodGoals.count { yourPeriodGoals[p] += 1 }
        case .opponentScore:
            let p = currentPeriod
            botGoals = min(botGoals + 1, Self.goalsToWin)
            if p < botPeriodGoals.count { botPeriodGoals[p] += 1 }
            let deficit = botGoals - yourGoals
            if deficit > maxDeficit { maxDeficit = deficit }
        default: throw GameError.illegalMove
        }
    }

    var statusText: String {
        let lead = yourGoals - botGoals
        let leadStr = lead > 0 ? " ↑\(lead)" : (lead < 0 ? " ↓\(-lead)" : " tied")
        let toWin = Self.goalsToWin - max(yourGoals, botGoals)
        let toWinStr = toWin <= 2 && toWin > 0 ? " · \(toWin) to win" : ""
        let closeGame = abs(lead) <= 1 && (yourGoals + botGoals) >= 8 ? " · 🔥 close!" : ""
        let comeback = maxDeficit >= 2 && lead >= 0 ? " · 🔄 comeback!" : ""
        return "You \(yourGoals) – \(botGoals) Bot\(leadStr) · first to \(Self.goalsToWin)\(toWinStr)\(closeGame)\(comeback)"
    }

    var resultText: String? {
        guard isOver else { return nil }
        let totalGoals = yourGoals + botGoals
        let margin = abs(yourGoals - botGoals)
        let flavor = margin >= 5 ? " · 💪 blowout" : (margin == 1 ? " · 😰 nailbiter" : "")
        let periods = (0..<3).map { "P\($0+1): \(yourPeriodGoals[$0])-\(botPeriodGoals[$0])" }.joined(separator: " · ")
        if won {
            var extras = shutout ? " · 🥅 Shutout!" : ""
            if maxDeficit > 0 { extras += " · 🔄 came back from –\(maxDeficit)" }
            extras += " · \(totalGoals) total goals\(flavor)"
            extras += " · \(periods)"
            return "You win \(yourGoals)–\(botGoals)\(extras)"
        }
        return "Bot wins \(botGoals)–\(yourGoals) · \(totalGoals) total goals\(flavor) · \(periods)"
    }
}
