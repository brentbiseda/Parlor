import Foundation

/// One space on the Star Party board. The live star marker is tracked
/// separately (`starSpace`) and floats independently of these base types.
enum MPSpace: String, Codable, Hashable, CaseIterable {
    case start      // home base — small lap payout
    case blue       // +3 coins
    case red        // −3 coins
    case lucky      // +5 coins
    case item       // small coin gift
    case bowser     // −5 coins
    case event      // random swing

    var coinDelta: Int {
        switch self {
        case .start: return 2
        case .blue: return 3
        case .red: return -3
        case .lucky: return 5
        case .item: return 0      // handled with a random gift
        case .bowser: return -5
        case .event: return 0     // handled with a random swing
        }
    }
}

/// Interactive minigame kinds that play at the end of each round.
enum MinigameKind: String, Codable, Hashable, CaseIterable {
    // Original 4
    case tapFrenzy       // tap as fast as possible (4 seconds)
    case starSprint      // tap the star before it moves (6 rounds)
    case coinDash        // catch falling coins (10 coins, 5 seconds)
    case quickDraw       // react when the signal fires (5 rounds)
    // 10 new
    case memoryMatch     // flip pairs of cards, find all matches
    case colorBlast      // tap only the target color, ignore others
    case balanceAct      // keep the bar centered by tapping left/right
    case numberCrunch    // tap numbers in ascending order
    case bombDefuse      // cut the right wire before time runs out (5 rounds)
    case starMap         // reproduce a star constellation pattern
    case rhythmTap       // tap on the beat for 8 beats
    case priceIsRight    // guess the coin value (higher/lower)
    case treasureHunt    // find the hidden star in a 4×4 grid (3 guesses)
    case spinWheel       // stop the spinning wheel on the gold slice

    var displayName: String {
        switch self {
        case .tapFrenzy:    return "Tap Frenzy"
        case .starSprint:   return "Star Sprint"
        case .coinDash:     return "Coin Dash"
        case .quickDraw:    return "Quick Draw"
        case .memoryMatch:  return "Memory Match"
        case .colorBlast:   return "Color Blast"
        case .balanceAct:   return "Balance Act"
        case .numberCrunch: return "Number Crunch"
        case .bombDefuse:   return "Bomb Defuse!"
        case .starMap:      return "Star Map"
        case .rhythmTap:    return "Rhythm Tap"
        case .priceIsRight: return "Price Is Right"
        case .treasureHunt: return "Treasure Hunt"
        case .spinWheel:    return "Spin the Wheel"
        }
    }

    var icon: String {
        switch self {
        case .tapFrenzy:    return "hand.tap.fill"
        case .starSprint:   return "star.fill"
        case .coinDash:     return "circle.fill"
        case .quickDraw:    return "bolt.fill"
        case .memoryMatch:  return "rectangle.on.rectangle.angled.fill"
        case .colorBlast:   return "paintpalette.fill"
        case .balanceAct:   return "scale.3d"
        case .numberCrunch: return "number.circle.fill"
        case .bombDefuse:   return "exclamationmark.triangle.fill"
        case .starMap:      return "sparkles"
        case .rhythmTap:    return "music.note"
        case .priceIsRight: return "dollarsign.circle.fill"
        case .treasureHunt: return "map.fill"
        case .spinWheel:    return "arrow.clockwise.circle.fill"
        }
    }

    var instructions: String {
        switch self {
        case .tapFrenzy:    return "Tap as fast as you can!"
        case .starSprint:   return "Tap the star before it moves!"
        case .coinDash:     return "Catch the falling coins!"
        case .quickDraw:    return "Tap the instant it turns green!"
        case .memoryMatch:  return "Flip pairs and find all matches!"
        case .colorBlast:   return "Tap only the matching color!"
        case .balanceAct:   return "Keep the needle centered!"
        case .numberCrunch: return "Tap 1 → 2 → 3 in order!"
        case .bombDefuse:   return "Cut the correct wire to defuse!"
        case .starMap:      return "Tap the stars in the shown pattern!"
        case .rhythmTap:    return "Tap in time with the beat!"
        case .priceIsRight: return "Guess: higher or lower each round?"
        case .treasureHunt: return "Find the hidden star — 3 guesses!"
        case .spinWheel:    return "Tap to stop on the gold slice!"
        }
    }

    var accentColor: String {
        switch self {
        case .tapFrenzy:    return "red"
        case .starSprint:   return "yellow"
        case .coinDash:     return "gold"
        case .quickDraw:    return "green"
        case .memoryMatch:  return "purple"
        case .colorBlast:   return "orange"
        case .balanceAct:   return "teal"
        case .numberCrunch: return "blue"
        case .bombDefuse:   return "red"
        case .starMap:      return "indigo"
        case .rhythmTap:    return "pink"
        case .priceIsRight: return "green"
        case .treasureHunt: return "orange"
        case .spinWheel:    return "yellow"
        }
    }
}

/// **Star Party** — a light 4-player dice-and-board party game in the spirit of
/// the console classics. Each turn the active player hits a dice block (1–10),
/// hops that many spaces around a looping board, banks/loses coins from the
/// space they pass or land on, and buys a Star whenever they reach the Star
/// space holding enough coins. After every full round of four turns, an
/// interactive minigame lets the human player compete for a coin bonus.
/// Most Stars after `totalRounds` rounds wins; coins break ties.
struct MarioPartyGame: GameEngine {
    static let kind = GameKind.marioParty
    static let seatCount = 4
    static let startCoins = 10
    static let starCost = 20
    static let totalRounds = 10
    static let minigamePayout = 12
    static let minigameRunnerUpPayout = 5
    static let lapBonus = 3          // extra coins for completing a full lap

    /// Fixed board layout, walked clockwise from `start` at index 0.
    static let board: [MPSpace] = [
        .start, .blue, .blue, .red, .blue, .item, .blue, .lucky,
        .blue, .red, .event, .blue, .blue, .bowser, .blue, .item,
        .red, .blue, .lucky, .blue, .event, .blue, .red, .blue,
    ]

    var positions: [Int]
    var coins: [Int]
    var stars: [Int]
    var starSpace: Int
    var current: Int
    var round: Int
    var turnsThisRound: Int

    /// Non-nil when the engine is waiting for the interactive minigame result.
    var minigamePhase: MinigameKind?

    // Last-move presentation (read by the view for dice + token animation).
    var lastRoll: Int?
    var lastMover: Int?
    var lastFrom: Int?
    var lastEvent: String?
    var lastMinigame: String?
    var lastStarBuyer: Int?

    // Lap tracking (for lap bonus)
    var lapsCompleted: [Int]

    // Stats
    var totalRolls: Int
    var bestRoll: Int
    var starsSold: Int
    var minigamesPlayed: Int
    var minigameWins: [Int]
    var minigameRunnerUpWins: [Int]
    var totalMinigameScore: Int   // cumulative interactive score for resultText

    /// RNG state, captured in the struct so results survive coding round-trips.
    var seed: UInt64

    init() {
        positions = Array(repeating: 0, count: Self.seatCount)
        coins = Array(repeating: Self.startCoins, count: Self.seatCount)
        stars = Array(repeating: 0, count: Self.seatCount)
        starSpace = 12
        current = 0
        round = 1
        turnsThisRound = 0
        lapsCompleted = Array(repeating: 0, count: Self.seatCount)
        totalRolls = 0
        bestRoll = 0
        starsSold = 0
        minigamesPlayed = 0
        minigameWins = Array(repeating: 0, count: Self.seatCount)
        minigameRunnerUpWins = Array(repeating: 0, count: Self.seatCount)
        totalMinigameScore = 0
        seed = UInt64.random(in: UInt64.min...UInt64.max)
    }

    // MARK: - GameEngine

    /// During minigame phase seat 0 is the "actor" so the view's actionableSeat fires.
    var currentPlayer: Int { minigamePhase != nil ? 0 : current }
    var isOver: Bool { round > Self.totalRounds }
    var displayRound: Int { min(round, Self.totalRounds) }

    func legalMoves() -> [Move] {
        if isOver { return [] }
        if minigamePhase != nil { return [.marioParty(.playMinigame(playerScore: 50))] }
        return [.marioParty(.roll)]
    }

    func isLegal(_ move: Move) -> Bool {
        switch move {
        case .marioParty(.roll):                return minigamePhase == nil && !isOver
        case .marioParty(.playMinigame):        return minigamePhase != nil && !isOver
        default:                                return false
        }
    }

    var statusText: String {
        if isOver { return resultText ?? "Final results" }
        if minigamePhase != nil {
            return "Round \(displayRound)/\(Self.totalRounds) · 🎮 Minigame!"
        }
        var parts = ["Round \(displayRound)/\(Self.totalRounds)"]
        if turnsThisRound == 0, let mg = lastMinigame {
            parts.append("🎮 \(mg)")
        } else if let e = lastEvent {
            parts.append(e)
        }
        return parts.joined(separator: " · ")
    }

    var resultText: String? {
        guard isOver else { return nil }
        let order = standings().flatMap { $0 }
        guard let winner = order.first else { return "Game over" }
        var parts = ["⭐ \(stars[winner]) star\(stars[winner] == 1 ? "" : "s") · 🪙 \(coins[winner])"]
        parts.append("stars " + (0..<Self.seatCount).map { "P\($0 + 1):\(stars[$0])" }.joined(separator: " "))
        if bestRoll > 0 { parts.append("🎲 best roll \(bestRoll)") }
        if starsSold > 0 { parts.append("⭐ \(starsSold) stars sold") }
        parts.append("🎮 \(minigamesPlayed) minigames")
        if let mvp = minigameWins.indices.max(by: { minigameWins[$0] < minigameWins[$1] }),
           minigameWins[mvp] > 0 {
            parts.append("🏅 P\(mvp + 1) won \(minigameWins[mvp]) MG")
        }
        if totalMinigameScore > 0 { parts.append("🎯 MG score \(totalMinigameScore)") }
        let topLaps = lapsCompleted.max() ?? 0
        if topLaps > 0 { parts.append("🏃 \(topLaps) lap\(topLaps == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    /// Seats grouped by finishing rank (most stars, then most coins), best first.
    private func standings() -> [[Int]] {
        let order = (0..<Self.seatCount).sorted { a, b in
            if stars[a] != stars[b] { return stars[a] > stars[b] }
            return coins[a] > coins[b]
        }
        var groups: [[Int]] = []
        for seat in order {
            if let last = groups.last, let rep = last.first,
               stars[rep] == stars[seat], coins[rep] == coins[seat] {
                groups[groups.count - 1].append(seat)
            } else {
                groups.append([seat])
            }
        }
        return groups
    }

    func ranking() -> [[Int]] {
        isOver ? standings() : []
    }

    // MARK: - Apply

    mutating func apply(_ move: Move) throws {
        switch move {
        case .marioParty(.roll):
            try applyRoll()
        case .marioParty(.playMinigame(let playerScore)):
            try applyMinigameResult(playerScore: playerScore)
        default:
            throw GameError.illegalMove
        }
    }

    private mutating func applyRoll() throws {
        guard minigamePhase == nil, !isOver else { throw GameError.illegalMove }

        var gen = SplitMix64(seed: seed)
        defer { seed = gen.state }

        let seat = current
        lastMinigame = nil
        lastStarBuyer = nil

        // 1. Roll the dice block and hop forward, buying a star on the way past.
        let roll = Int.random(in: 1...10, using: &gen)
        totalRolls += 1
        bestRoll = max(bestRoll, roll)
        lastRoll = roll
        lastMover = seat
        lastFrom = positions[seat]

        var pos = positions[seat]
        var boughtStar = false
        for step in 0..<roll {
            let nextPos = (pos + 1) % Self.board.count
            // Lap detection: passing index 0 (start)
            if nextPos == 0 && (pos + 1) >= Self.board.count {
                lapsCompleted[seat] += 1
                coins[seat] += Self.lapBonus
            }
            pos = nextPos
            if pos == starSpace, !boughtStar, coins[seat] >= Self.starCost {
                coins[seat] -= Self.starCost
                stars[seat] += 1
                starsSold += 1
                boughtStar = true
                lastStarBuyer = seat
                relocateStar(using: &gen)
            }
            _ = step
        }
        coins[seat] = max(0, coins[seat])
        positions[seat] = pos

        // 2. Resolve the space the player landed on.
        let landed = Self.board[pos]
        var note = resolveLanding(landed, seat: seat, using: &gen)
        if boughtStar { note = "⭐ bought a Star! " + note }
        lastEvent = "🎲\(roll) — " + note

        // 3. Hand off to the next player; after all 4 roll, open minigame phase.
        current = (current + 1) % Self.seatCount
        turnsThisRound += 1
        if turnsThisRound == Self.seatCount {
            turnsThisRound = 0
            // Pick a random interactive minigame; the view will show it.
            let kinds = MinigameKind.allCases
            let idx = Int.random(in: 0..<kinds.count, using: &gen)
            minigamePhase = kinds[idx]
            // Advance the seed so bots' scores later use fresh randomness.
            seed = gen.state
        }
    }

    private mutating func applyMinigameResult(playerScore: Int) throws {
        guard let kind = minigamePhase, !isOver else { throw GameError.illegalMove }

        var gen = SplitMix64(seed: seed)
        defer { seed = gen.state }

        // Human (seat 0) uses the interactive result; bots get random scores.
        var scores = (0..<Self.seatCount).map { _ in Int.random(in: 20...95, using: &gen) }
        let clamped = max(0, min(100, playerScore))
        scores[0] = clamped
        totalMinigameScore += clamped

        let top = scores.max() ?? 0
        let second = scores.filter { $0 < top }.max() ?? -1
        let winners = (0..<Self.seatCount).filter { scores[$0] == top }
        let runnerUps = second >= 0 ? (0..<Self.seatCount).filter { scores[$0] == second } : []
        for w in winners {
            coins[w] += Self.minigamePayout
            minigameWins[w] += 1
        }
        for r in runnerUps where !winners.contains(r) {
            coins[r] += Self.minigameRunnerUpPayout
            minigameRunnerUpWins[r] += 1
        }
        // Coin floor: nobody goes below 0
        for i in coins.indices { coins[i] = max(0, coins[i]) }
        minigamesPlayed += 1
        let who = winners.map { "P\($0 + 1)" }.joined(separator: " & ")
        let runnerStr = runnerUps.isEmpty ? "" : " · \(runnerUps.map{"P\($0+1)"}.joined(separator:"&")) +\(Self.minigameRunnerUpPayout)"
        lastMinigame = "\(kind.displayName) — \(who) +\(Self.minigamePayout)🪙\(runnerStr)"
        minigamePhase = nil
        round += 1
    }

    private mutating func relocateStar(using gen: inout SplitMix64) {
        let candidates = (1..<Self.board.count).filter { $0 != starSpace }
        if let next = candidates.randomElement(using: &gen) { starSpace = next }
    }

    private mutating func resolveLanding(_ space: MPSpace, seat: Int,
                                         using gen: inout SplitMix64) -> String {
        switch space {
        case .blue:
            coins[seat] += 3
            return "+3 coins"
        case .start:
            coins[seat] += 2
            return "home base +2"
        case .red:
            let loss = min(coins[seat], 3)
            coins[seat] -= loss
            return "−\(loss) coins"
        case .lucky:
            coins[seat] += 5
            return "Lucky! +5 coins"
        case .item:
            let gift = [3, 4, 5].randomElement(using: &gen) ?? 3
            coins[seat] += gift
            return "Item! +\(gift) coins"
        case .bowser:
            let loss = min(coins[seat], 5)
            coins[seat] -= loss
            return loss > 0 ? "Bowser! −\(loss) coins" : "Bowser! (no coins to take)"
        case .event:
            return resolveEvent(seat: seat, using: &gen)
        }
    }

    private mutating func resolveEvent(seat: Int, using gen: inout SplitMix64) -> String {
        switch Int.random(in: 0..<3, using: &gen) {
        case 0:
            let g = Int.random(in: 4...8, using: &gen)
            coins[seat] += g
            return "Event: struck \(g) coins"
        case 1:
            let drop = min(coins[seat], Int.random(in: 3...6, using: &gen))
            coins[seat] -= drop
            return drop > 0 ? "Event: lost \(drop) coins" : "Event: nothing to lose"
        default:
            let leader = (0..<Self.seatCount).max(by: { coins[$0] < coins[$1] }) ?? seat
            if leader == seat {
                coins[seat] += 4
                return "Event: leader's bonus +4"
            }
            let steal = min(coins[leader], 5)
            coins[leader] -= steal
            coins[seat] += steal
            return "Event: swiped \(steal) from P\(leader + 1)"
        }
    }
}
