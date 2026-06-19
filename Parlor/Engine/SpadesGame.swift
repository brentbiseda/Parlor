import Foundation

/// 4-player partnership Spades (seats 0&2 vs 1&3). Bids 0–13; 0 = nil bid.
/// Spades are always trump and can't be led until broken.
///
/// Scoring per round:
///   - Made contract:   10 × bid + bags earned this round
///   - Set (undertrick): −10 × bid
///   - Nil made:        +100  Nil set: −100
///   - Bag overflow:    −100 when a team accumulates 10 bags (bags reset to remainder)
///
/// Game ends when a team reaches ≥ 500 points or drops to ≤ −200.
struct SpadesGame: GameEngine {
    static let kind = GameKind.spades
    static let targetScore = 500
    static let bustedScore = -200
    static let bagPenaltyThreshold = 10
    static let bagPenalty = 100
    static let nilBonus = 100

    enum Phase: Codable, Hashable {
        case bidding
        case playing
        case gameOver
    }

    var hands: [[Card]] = Array(repeating: [], count: 4)
    var phase: Phase = .bidding
    var dealer = 0
    var bids: [Int?] = Array(repeating: nil, count: 4)
    var tricksWon = [0, 0, 0, 0]
    var trick: [TrickPlay] = []
    var trickLeader = 0
    var tricksPlayed = 0
    var spadesBroken = false
    var teamScores = [0, 0]
    var teamBags = [0, 0]
    var roundNumber = 0
    var lastTrickSummary: String? = nil
    /// Summary of the round just scored (shown until next round starts).
    var lastRoundSummary: String? = nil
    /// Consecutive successful nil bids per seat (resets on a miss or non-nil bid).
    var nilStreaks = [0, 0, 0, 0]
    /// Count of "Boston" rounds (team wins all 13 tricks) per team.
    var bostonCount = [0, 0]
    /// Largest single-round point swing recorded this game (abs value, with seat label).
    var biggestSwing = 0
    var biggestSwingTeam = 0
    /// Successful nil bids per team across the game.
    var nilsMade = [0, 0]
    /// Nil bids that failed (busted) per team.
    var nilsBusted = [0, 0]
    /// Cumulative bags accumulated per seat across the game (individual, never reset).
    var seatBags = [0, 0, 0, 0]
    /// Count of "nil slams" — a nil made while partner sweeps the rest (≥12 tricks).
    var nilSlams = [0, 0]
    /// Rounds where a team made exactly its contract with zero bags.
    var perfectBids = [0, 0]
    /// Track when either team reaches 7+ bags — penalty risk warning.
    var sandbagsWarned: Bool = false
    /// True when any team is 7+ bags (within 3 of the 10-bag penalty).
    var sandbagsWarning: Bool { teamBags[0] % 10 >= 7 || teamBags[1] % 10 >= 7 }

    /// Warning level string based on bag count (empty when safe, ⚠️ at 7+, 🚨 at 9+).
    var sandbagsWarningLevel: String {
        let max0 = teamBags[0] % 10; let max1 = teamBags[1] % 10
        let worst = Swift.max(max0, max1)
        if worst >= 9 { return "🚨" }
        if worst >= 7 { return "⚠️" }
        return ""
    }
    /// Tricks won per round per team (inner array = rounds, outer = teams).
    var teamTricksWonPerRound: [[Int]] = [[], []]
    /// Nil bids attempted (indexed by seat 0-3, maps to nil bid count).
    var nilBidsAttempted: Int = 0
    /// Nil bids successfully made (tricks taken == 0 while bidding nil).
    var nilBidsMade: Int = 0
    /// Per-round overtricks (bags) accumulated by each team; outer = team, inner = rounds.
    var overtricksPerRound: [[Int]] = [[], []]

    init() { startRound() }

    mutating func startRound() {
        let (dealt, _) = TrickTaking.deal(deck: Card.standardDeck(), players: 4, count: 13)
        hands = dealt
        bids = Array(repeating: nil, count: 4)
        tricksWon = [0, 0, 0, 0]
        trick = []
        tricksPlayed = 0
        spadesBroken = false
        roundNumber += 1
        trickLeader = (dealer + 1) % 4
        phase = .bidding
    }

    var currentPlayer: Int {
        switch phase {
        case .bidding:
            for offset in 1...4 {
                let seat = (dealer + offset) % 4
                if bids[seat] == nil { return seat }
            }
            return 0
        case .playing:  return (trickLeader + trick.count) % 4
        case .gameOver: return 0
        }
    }

    var isOver: Bool { phase == .gameOver }

    func isNilBid(_ seat: Int) -> Bool { bids[seat] == 0 }

    /// Team contract for team 0 or 1 (sum of non-nil bids).
    func teamContract(_ team: Int) -> Int {
        let seats = [team, team + 2]
        return seats.compactMap { bids[$0] }.filter { $0 > 0 }.reduce(0, +)
    }

    func legalMoves() -> [Move] {
        switch phase {
        case .gameOver: return []
        case .bidding:  return (0...13).map { .bid($0) }
        case .playing:  return legalCards().map { .playCard($0) }
        }
    }

    func legalCards() -> [Card] {
        let hand = hands[currentPlayer]
        if trick.isEmpty {
            if !spadesBroken {
                let nonSpades = hand.filter { $0.suit != .spades }
                if !nonSpades.isEmpty { return nonSpades }
            }
            return hand
        }
        return TrickTaking.followLegal(hand: hand, ledSuit: trick[0].card.suit, suitOf: { $0.suit })
    }

    mutating func apply(_ move: Move) throws {
        switch (phase, move) {
        case (.bidding, .bid(let n)):
            guard (0...13).contains(n) else { throw GameError.illegalMove }
            bids[currentPlayer] = n
            if bids.allSatisfy({ $0 != nil }) {
                phase = .playing
                trickLeader = (dealer + 1) % 4
            }
        case (.playing, .playCard(let card)):
            guard legalCards().contains(card) else { throw GameError.illegalMove }
            play(card)
        default:
            throw GameError.illegalMove
        }
    }

    mutating func play(_ card: Card) {
        let seat = currentPlayer
        hands[seat].removeAll { $0 == card }
        trick.append(TrickPlay(seat: seat, card: card))
        if card.suit == .spades { spadesBroken = true }

        if trick.count == 4 {
            let led = trick[0].card.suit
            let winner = TrickTaking.winner(plays: trick, ledSuit: led,
                                            suitOf: { $0.suit },
                                            value: { TrickTaking.trumpValue($0, trump: .spades) })
            tricksWon[winner] += 1
            let highCard = trick.max(by: { TrickTaking.trumpValue($0.card, trump: .spades)
                                        < TrickTaking.trumpValue($1.card, trump: .spades) })?.card
            let highLabel = highCard.map { "\($0.rank.label)\($0.suit.symbol)" } ?? ""
            lastTrickSummary = "Seat \(winner + 1) wins — \(highLabel)"
            trick = []
            trickLeader = winner
            tricksPlayed += 1
            if tricksPlayed == 13 { finishRound() }
        }
    }

    mutating func finishRound() {
        var summaryParts: [String] = []
        for team in 0...1 {
            let seats = [team, team + 2]
            var roundScore = 0
            var teamContract = 0
            let teamTricks = tricksWon[seats[0]] + tricksWon[seats[1]]

            for seat in seats {
                let bid = bids[seat] ?? 0
                if bid == 0 {
                    let made = tricksWon[seat] == 0
                    roundScore += made ? Self.nilBonus : -Self.nilBonus
                    if made { nilsMade[team] += 1 } else { nilsBusted[team] += 1 }
                    let partner = (seat + 2) % 4
                    var slamNote = ""
                    if made && tricksWon[partner] >= 12 { nilSlams[team] += 1; slamNote = " 💎slam" }
                    nilStreaks[seat] = made ? nilStreaks[seat] + 1 : 0
                    let streakNote = made && nilStreaks[seat] >= 2 ? " (streak \(nilStreaks[seat]))" : ""
                    summaryParts.append("S\(seat + 1) nil \(made ? "✓+100" : "✗−100")\(streakNote)\(slamNote)")
                } else {
                    nilStreaks[seat] = 0
                    teamContract += bid
                }
            }

            if teamContract > 0 {
                if teamTricks >= teamContract {
                    let bags = teamTricks - teamContract
                    roundScore += teamContract * 10 + bags
                    teamBags[team] += bags
                    for s in seats where bids[s] != nil && bids[s]! > 0 {
                        seatBags[s] += max(0, tricksWon[s] - bids[s]!)
                    }
                    var bagNote = bags > 0 ? " +\(bags)bag" : ""
                    if teamBags[team] >= Self.bagPenaltyThreshold {
                        teamBags[team] -= Self.bagPenaltyThreshold
                        roundScore -= Self.bagPenalty
                        bagNote += " overflow−100"
                    }
                    if bags == 0 { perfectBids[team] += 1; bagNote += " 🎯exact" }
                    if teamTricks == 13 { bagNote += " 🏆 Boston!"; bostonCount[team] += 1 }
                    summaryParts.append("T\(team + 1) made \(teamTricks)/\(teamContract)\(bagNote)")
                } else {
                    roundScore -= teamContract * 10
                    summaryParts.append("T\(team + 1) set \(teamTricks)/\(teamContract)−\(teamContract * 10)")
                }
            }
            teamScores[team] += roundScore
            if abs(roundScore) > biggestSwing {
                biggestSwing = abs(roundScore)
                biggestSwingTeam = team
            }
        }
        let scoreStr = "T1 \(teamScores[0]) vs T2 \(teamScores[1])"
        lastRoundSummary = (summaryParts + [scoreStr]).joined(separator: " · ")

        // Track aggregate nil bid stats
        for seat in 0..<4 {
            if let bid = bids[seat], bid == 0 {
                nilBidsAttempted += 1
                if tricksWon[seat] == 0 { nilBidsMade += 1 }
            }
        }
        // Record per-round overtricks per team
        for team in 0...1 {
            let seats = [team, team + 2]
            let teamContract = seats.compactMap { bids[$0] }.filter { $0 > 0 }.reduce(0, +)
            let teamTricks = tricksWon[seats[0]] + tricksWon[seats[1]]
            let bags = teamContract > 0 && teamTricks > teamContract ? teamTricks - teamContract : 0
            overtricksPerRound[team].append(bags)
        }

        // Record tricks won this round per team
        for team in 0...1 {
            let seats = [team, team + 2]
            let teamTricks = tricksWon[seats[0]] + tricksWon[seats[1]]
            teamTricksWonPerRound[team].append(teamTricks)
        }
        // Set sandbag warning if either team hits 7+ bags
        if teamBags[0] >= 7 || teamBags[1] >= 7 { sandbagsWarned = true }

        let gameEndCondition = teamScores.contains { $0 >= Self.targetScore }
                            || teamScores.contains { $0 <= Self.bustedScore }
        if gameEndCondition {
            phase = .gameOver
        } else {
            dealer = (dealer + 1) % 4
            startRound()
        }
    }

    func teamLabel(_ team: Int) -> String { team == 0 ? "N/S" : "E/W" }

    var statusText: String {
        switch phase {
        case .bidding:
            let made = bids.compactMap { $0 }.count
            let bidStr = (0..<4).map { bids[$0].map { $0 == 0 ? "nil" : "\($0)" } ?? "?" }.joined(separator: "/")
            return "R\(roundNumber) bidding (\(made)/4): \(bidStr)"
        case .playing:
            let bidStr = (0..<4).map { bids[$0].map { $0 == 0 ? "nil" : "\($0)" } ?? "–" }.joined(separator: "/")
            let t0 = tricksWon[0] + tricksWon[2]; let t1 = tricksWon[1] + tricksWon[3]
            let c0 = teamContract(0); let c1 = teamContract(1)
            let trickBar = "\(teamLabel(0)) \(t0)/\(c0) · \(teamLabel(1)) \(t1)/\(c1)"
            let lead: String
            if teamScores[0] == teamScores[1] { lead = "tied" }
            else { let l = teamScores[0] > teamScores[1] ? 0 : 1; lead = "\(teamLabel(l)) +\(abs(teamScores[0] - teamScores[1]))" }
            let scoreBar = "\(teamLabel(0)) \(teamScores[0]) · \(teamLabel(1)) \(teamScores[1]) (\(lead))"
            let bag0Warn = teamBags[0] % 10 >= 8 ? "⚠️" : ""
            let bag1Warn = teamBags[1] % 10 >= 8 ? "⚠️" : ""
            let seatBagDetail = (0..<4).compactMap { s -> String? in
                let b = seatBags[s]; return b >= 2 ? "S\(s+1):\(b)bg" : nil
            }.joined(separator: " ")
            let bagExtra = seatBagDetail.isEmpty ? "" : " [\(seatBagDetail)]"
            let warnLevel = sandbagsWarningLevel
            let bag0Critical = teamBags[0] >= 7 ? "\(warnLevel) BAGS:\(teamBags[0]) · " : ""
            let bag1Critical = teamBags[1] >= 7 ? "\(warnLevel) BAGS:\(teamBags[1]) · " : ""
            let criticalWarn = bag0Critical + bag1Critical
            let bagBar = "\(criticalWarn)bags \(teamBags[0])\(bag0Warn)/\(teamBags[1])\(bag1Warn)\(bagExtra)"
            let nilWarn = (0..<4).compactMap { seat -> String? in
                guard bids[seat] == 0 && tricksWon[seat] > 0 else { return nil }
                return "S\(seat + 1) nil busted!"
            }.first.map { " · 💀 \($0)" } ?? ""
            // Show "N to game" for the leading team when close to winning.
            let toGame: String
            let maxScore = teamScores.max() ?? 0
            if maxScore >= 400 {
                let leading = teamScores[0] >= teamScores[1] ? 0 : 1
                let needed = Self.targetScore - teamScores[leading]
                toGame = " · \(teamLabel(leading)) needs \(needed)"
            } else { toGame = "" }
            return "R\(roundNumber) bids \(bidStr) · \(trickBar) · \(scoreBar)\(toGame) · \(bagBar)\(nilWarn)"
        case .gameOver:
            return resultText ?? "Game over"
        }
    }

    var resultText: String? {
        guard isOver else { return nil }
        let winner = teamScores[0] > teamScores[1] ? 0 : (teamScores[1] > teamScores[0] ? 1 : -1)
        if winner == -1 { return "Draw — \(teamScores[0]) each" }
        let margin = abs(teamScores[winner] - teamScores[1 - winner])
        var text = "\(teamLabel(winner)) win \(teamScores[winner])–\(teamScores[1 - winner]) in \(roundNumber) round\(roundNumber == 1 ? "" : "s")"
        if margin <= 30 { text += " (squeaker!)" }
        let totalBostons = bostonCount[0] + bostonCount[1]
        if totalBostons > 0 {
            let detail = (0...1).compactMap { bostonCount[$0] > 0 ? "\(teamLabel($0))×\(bostonCount[$0])" : nil }
            text += " · 🏆 Boston \(detail.joined(separator: " "))"
        }
        // Nil bid summary: "3 nil made (N/S×2 E/W×1) · 1 busted"
        let totalNils = nilsMade[0] + nilsMade[1]
        let totalBusted = nilsBusted[0] + nilsBusted[1]
        if totalNils > 0 || totalBusted > 0 {
            let nilDetail = (0...1).compactMap { nilsMade[$0] > 0 ? "\(teamLabel($0))×\(nilsMade[$0])" : nil }.joined(separator: " ")
            var nilStr = totalNils > 0 ? "🎯 \(totalNils) nil (\(nilDetail))" : ""
            if totalBusted > 0 { nilStr += (nilStr.isEmpty ? "" : " · ") + "💀 \(totalBusted) busted" }
            text += " · \(nilStr)"
        }
        if biggestSwing >= 100 { text += " · ⚡ \(teamLabel(biggestSwingTeam)) \(biggestSwing)pt swing" }
        let totalSlams = nilSlams[0] + nilSlams[1]
        if totalSlams > 0 { text += " · 💎 \(totalSlams) nil slam\(totalSlams == 1 ? "" : "s")" }
        let totalPerfect = perfectBids[0] + perfectBids[1]
        if totalPerfect >= 2 { text += " · 🎯 \(totalPerfect) exact bids" }
        // Bag summary: highlight the worst offender
        let maxSeatBags = seatBags.max() ?? 0
        if let baggiest = seatBags.indices.max(by: { seatBags[$0] < seatBags[$1] }), maxSeatBags >= 4 {
            text += " · 🛍️ S\(baggiest + 1) \(seatBags[baggiest]) bags"
        }
        if sandbagsWarned { text += " · ⚠️ Bag penalties hit!" }
        // Average tricks per round per team (only when ≥ 3 rounds played)
        let winnerRounds = teamTricksWonPerRound[winner]
        if winnerRounds.count >= 3 {
            let avg = Double(winnerRounds.reduce(0, +)) / Double(winnerRounds.count)
            text += " · \(teamLabel(winner)) avg \(String(format: "%.1f", avg)) tricks/rd"
        }
        // Aggregate nil bid accuracy
        if nilBidsAttempted > 0 {
            text += " · 🤫 Nil: \(nilBidsMade)/\(nilBidsAttempted)"
        }
        // Worst bag round (peak overtricks in a single round, per team)
        for team in 0...1 {
            if let worstBagRound = overtricksPerRound[team].max(), worstBagRound >= 3 {
                text += " · 🛍️ \(teamLabel(team)) worst bag round: +\(worstBagRound)"
            }
        }
        return text
    }

    func ranking() -> [[Int]] {
        guard isOver else { return [] }
        if teamScores[0] == teamScores[1] { return [[0, 1, 2, 3]] }
        let winner = teamScores[0] >= teamScores[1] ? 0 : 1
        return [[winner, winner + 2], [1 - winner, 3 - winner]]
    }

    func redacted(for seat: Int) -> SpadesGame {
        var copy = self
        for other in 0..<4 where other != seat { copy.hands[other] = [] }
        return copy
    }
}
