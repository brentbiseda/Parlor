import Foundation

/// Standard 4-player Hearts. Pass 3 cards (left, right, across, hold rotation),
/// 2♣ leads, hearts must be broken, Q♠ = 13 points, shooting the moon gives
/// the other three players 26. Game ends when someone reaches 100; low score wins.
struct HeartsGame: GameEngine {
    static let kind = GameKind.hearts
    static let gameEndThreshold = 100

    enum PassDirection: Int, Codable, CaseIterable {
        case left = 1, right = 3, across = 2, hold = 0

        var label: String {
            switch self {
            case .left: return "left"
            case .right: return "right"
            case .across: return "across"
            case .hold: return "no passing"
            }
        }
    }

    enum Phase: Codable, Hashable {
        case passing
        case playing
        case gameOver
    }

    var hands: [[Card]] = Array(repeating: [], count: 4)
    var phase: Phase = .passing
    var passDirectionIndex = 0      // cycles left, right, across, hold
    var passSelections: [[Card]?] = Array(repeating: nil, count: 4)
    var trick: [TrickPlay] = []
    var trickLeader = 0
    var tricksPlayed = 0
    var heartsBroken = false
    var roundPoints = [0, 0, 0, 0]
    var scores = [0, 0, 0, 0]
    var roundNumber = 0
    var lastTrickSummary: String? = nil
    /// Per-round deltas for the current game, newest first.
    var roundHistory: [[Int]] = []
    /// Q♠ holder in the current trick (shown in statusText before trick ends).
    var queenPlayed = false
    /// Lifetime moon shots per seat this game.
    var moonShots = [0, 0, 0, 0]
    /// Count of rounds where a seat took zero points (clean sheet).
    var cleanRounds = [0, 0, 0, 0]
    /// Worst single-round point total taken by any seat (with seat label).
    var worstRound = 0
    var worstRoundSeat = 0
    /// Times each player was hit by Q♠ (13 pts from the queen of spades).
    var queenSpadeHits = [0, 0, 0, 0]
    /// How many times each seat won a trick they led (aggression stat).
    var trickLeadWins: [Int] = [0, 0, 0, 0]
    /// Total tricks won by each seat across all rounds.
    var totalTricksWon: [Int] = [0, 0, 0, 0]
    /// J♦ earned bonus (−10 pts). Only active when jackDiamondBonus is true.
    var jackDiamondWinner = -1
    /// Whether the Jack of Diamonds (-10 pts) variant is active.
    var jackDiamondBonus = false
    /// Lowest non-zero single-round score earned by any player (best defensive round).
    var lowestPositiveRoundScore: Int = Int.max
    var lowestPositiveRoundSeat: Int = 0
    /// Hearts taken per seat in the current round (for per-suit breakdown).
    var roundHeartsTaken = [0, 0, 0, 0]
    /// Total heart cards taken per seat across the whole game.
    var totalHeartsTaken = [0, 0, 0, 0]
    /// Cards received from passing this round (indexed by seat); empty until passes complete.
    var receivedCards: [[Card]] = Array(repeating: [], count: 4)
    /// Tricks won by each seat in the current round (reset each round).
    var tricksWonThisRound: [Int] = [0, 0, 0, 0]
    /// Cumulative tricks won per seat across all completed rounds (not including the in-progress round).
    var cumulativeTricksWon: [Int] = [0, 0, 0, 0]

    var passDirection: PassDirection { PassDirection.allCases[passDirectionIndex % 4] }

    /// Top dangerous cards in seat 0's hand — shown during pass phase to help the player decide.
    var handStrengthLabel: String {
        let hand = hands[0]
        let dangerous = hand.filter { points(for: $0) > 0 || ($0.suit == .spades && $0.rank.rawValue >= 11) }
        let sorted = dangerous.sorted { TrickTaking.plainValue($0) > TrickTaking.plainValue($1) }
        let top = sorted.prefix(3).map { "\($0.rank.label)\($0.suit.symbol)" }
        return top.isEmpty ? "" : top.joined(separator: " ")
    }

    /// Trick-dominance label for resultText: who won the most tricks overall.
    var trickDominanceLabel: String {
        guard let mostTricks = cumulativeTricksWon.max(), mostTricks > 0 else { return "" }
        let leaders = (0..<4).filter { cumulativeTricksWon[$0] == mostTricks }
        if leaders.count == 1 {
            return "S\(leaders[0] + 1) dominated with \(mostTricks) tricks"
        }
        return leaders.map { "S\($0 + 1)" }.joined(separator: " & ") + " tied at \(mostTricks) tricks"
    }

    /// True if any seat has collected all hearts (and possibly Q♠) without others scoring yet this round.
    var isShootingMoon: Bool {
        guard phase == .playing, tricksPlayed >= 3 else { return false }
        return (0..<4).contains { seat in
            let totalHeartsOut = roundHeartsTaken.reduce(0, +)
            return roundHeartsTaken[seat] == totalHeartsOut && totalHeartsOut >= 8
        }
    }

    /// The seat currently shooting (or -1 if none).
    var moonShooterSeat: Int {
        guard isShootingMoon else { return -1 }
        let totalHeartsOut = roundHeartsTaken.reduce(0, +)
        return (0..<4).first { roundHeartsTaken[$0] == totalHeartsOut && totalHeartsOut > 0 } ?? -1
    }

    init() {
        startRound()
    }

    mutating func startRound() {
        let (dealt, _) = TrickTaking.deal(deck: Card.standardDeck(), players: 4, count: 13)
        hands = dealt
        passSelections = Array(repeating: nil, count: 4)
        receivedCards = Array(repeating: [], count: 4)
        trick = []
        tricksPlayed = 0
        heartsBroken = false
        queenPlayed = false
        roundPoints = [0, 0, 0, 0]
        roundHeartsTaken = [0, 0, 0, 0]
        tricksWonThisRound = [0, 0, 0, 0]
        jackDiamondWinner = -1
        roundNumber += 1
        if passDirection == .hold {
            beginPlay()
        } else {
            phase = .passing
        }
    }

    mutating func beginPlay() {
        phase = .playing
        trickLeader = seatHoldingTwoOfClubs()
    }

    func seatHoldingTwoOfClubs() -> Int {
        for seat in 0..<4 where hands[seat].contains(Card(suit: .clubs, rank: .two)) { return seat }
        return 0
    }

    var currentPlayer: Int {
        switch phase {
        case .passing:
            return passSelections.firstIndex(where: { $0 == nil }) ?? 0
        case .playing:
            return (trickLeader + trick.count) % 4
        case .gameOver:
            return 0
        }
    }

    var isOver: Bool { phase == .gameOver }

    var isFirstTrick: Bool { tricksPlayed == 0 }

    func legalMoves() -> [Move] {
        switch phase {
        case .gameOver:
            return []
        case .passing:
            let hand = hands[currentPlayer]
            let pick = Array(hand.shuffled().prefix(3))
            return pick.count == 3 ? [.passCards(pick.displaySorted())] : []
        case .playing:
            return legalCards().map { .playCard($0) }
        }
    }

    func legalCards() -> [Card] {
        let seat = currentPlayer
        let hand = hands[seat]
        let twoClubs = Card(suit: .clubs, rank: .two)

        if trick.isEmpty {
            if isFirstTrick { return hand.contains(twoClubs) ? [twoClubs] : hand }
            if !heartsBroken {
                let nonHearts = hand.filter { $0.suit != .hearts }
                if !nonHearts.isEmpty { return nonHearts }
            }
            return hand
        }

        let led = trick[0].card.suit
        let following = hand.ofSuit(led)
        if !following.isEmpty { return following }
        if isFirstTrick {
            let safe = hand.filter { points(for: $0) == 0 }
            if !safe.isEmpty { return safe }
        }
        return hand
    }

    func points(for card: Card) -> Int {
        if card.suit == .hearts { return 1 }
        if card == Card(suit: .spades, rank: .queen) { return 13 }
        return 0
    }

    mutating func apply(_ move: Move) throws {
        switch (phase, move) {
        case (.passing, .passCards(let cards)):
            let seat = currentPlayer
            guard cards.count == 3, Set(cards).count == 3,
                  cards.allSatisfy({ hands[seat].contains($0) }) else { throw GameError.illegalMove }
            passSelections[seat] = cards
            if passSelections.allSatisfy({ $0 != nil }) {
                exchangePasses()
            }
        case (.playing, .playCard(let card)):
            guard legalCards().contains(card) else { throw GameError.illegalMove }
            play(card)
        default:
            throw GameError.illegalMove
        }
    }

    func isLegal(_ move: Move) -> Bool {
        if case .passCards(let cards) = move, phase == .passing {
            let seat = currentPlayer
            return cards.count == 3 && Set(cards).count == 3 && cards.allSatisfy { hands[seat].contains($0) }
        }
        return legalMoves().contains(move)
    }

    mutating func exchangePasses() {
        let offset = passDirection.rawValue
        var incoming: [[Card]] = Array(repeating: [], count: 4)
        for seat in 0..<4 {
            let cards = passSelections[seat]!
            hands[seat].removeAll { cards.contains($0) }
            incoming[(seat + offset) % 4] = cards
        }
        for seat in 0..<4 {
            hands[seat] = (hands[seat] + incoming[seat]).displaySorted()
            receivedCards[seat] = incoming[seat].displaySorted()
        }
        beginPlay()
    }

    mutating func play(_ card: Card) {
        let seat = currentPlayer
        hands[seat].removeAll { $0 == card }
        trick.append(TrickPlay(seat: seat, card: card))
        if card.suit == .hearts { heartsBroken = true }
        if card == Card(suit: .spades, rank: .queen) { queenPlayed = true }

        if trick.count == 4 {
            let led = trick[0].card.suit
            let winner = TrickTaking.winner(plays: trick, ledSuit: led, suitOf: { $0.suit }, value: TrickTaking.plainValue)
            let trickPoints = trick.reduce(0) { $0 + points(for: $1.card) }
            roundPoints[winner] += trickPoints
            // Track Q♠ hits per seat
            let queenInTrick = trick.contains { $0.card == Card(suit: .spades, rank: .queen) }
            if queenInTrick { queenSpadeHits[winner] += 1 }
            // Track hearts taken per seat
            let heartsTaken = trick.filter { $0.card.suit == .hearts }.count
            roundHeartsTaken[winner] += heartsTaken
            totalHeartsTaken[winner] += heartsTaken
            // Track J♦ winner in variant mode
            let jackDiamonds = Card(suit: .diamonds, rank: .jack)
            if jackDiamondBonus && trick.contains(where: { $0.card == jackDiamonds }) {
                jackDiamondWinner = winner
            }
            let highCard = trick.max(by: { TrickTaking.plainValue($0.card) < TrickTaking.plainValue($1.card) })?.card
            let cardLabel = highCard.map { "\($0.rank.label)\($0.suit.symbol)" } ?? ""
            let pts = trickPoints > 0 ? " +\(trickPoints)♥" : ""
            lastTrickSummary = "Seat \(winner + 1) wins\(pts) — \(cardLabel)"
            // Track aggression: was this trick won by the seat that led it?
            if winner == trickLeader { trickLeadWins[winner] += 1 }
            totalTricksWon[winner] += 1
            tricksWonThisRound[winner] += 1
            trick = []
            trickLeader = winner
            tricksPlayed += 1
            if tricksPlayed == 13 { finishRound() }
        }
    }

    mutating func finishRound() {
        // Accumulate per-round trick counts before resetting.
        for seat in 0..<4 { cumulativeTricksWon[seat] += tricksWonThisRound[seat] }
        var delta = [0, 0, 0, 0]
        if let shooter = roundPoints.firstIndex(of: 26) {
            // Shoot the moon: all others +26
            for seat in 0..<4 where seat != shooter { delta[seat] = 26 }
            moonShots[shooter] += 1
            lastTrickSummary = "🌙 Seat \(shooter + 1) shot the moon! +26 to others"
        } else {
            delta = roundPoints
        }
        roundHistory.insert(delta, at: 0)
        for seat in 0..<4 {
            scores[seat] += delta[seat]
            if delta[seat] == 0 { cleanRounds[seat] += 1 }
            if delta[seat] > worstRound { worstRound = delta[seat]; worstRoundSeat = seat }
            if delta[seat] > 0 && delta[seat] < lowestPositiveRoundScore {
                lowestPositiveRoundScore = delta[seat]
                lowestPositiveRoundSeat = seat
            }
        }
        if scores.contains(where: { $0 >= Self.gameEndThreshold }) {
            phase = .gameOver
        } else {
            passDirectionIndex += 1
            startRound()
        }
    }

    /// Compact summary of what seat 0 selected to pass.
    var seat0PassSummary: String {
        guard let cards = passSelections[0], !cards.isEmpty else { return "" }
        let pts = cards.reduce(0) { $0 + points(for: $1) }
        let cardStrs = cards.map { "\($0.rank.label)\($0.suit.symbol)" }.joined(separator: " ")
        return pts > 0 ? " · passing \(cardStrs) (\(pts)♥)" : " · passing \(cardStrs)"
    }

    var statusText: String {
        switch phase {
        case .passing:
            let waiting = (0..<4).filter { passSelections[$0] == nil }.count
            let dirSymbol: String
            switch passDirection {
            case .left: dirSymbol = "←"
            case .right: dirSymbol = "→"
            case .across: dirSymbol = "↕"
            case .hold: dirSymbol = "⟳"
            }
            let strengthHint = handStrengthLabel.isEmpty ? "" : " · danger: \(handStrengthLabel)"
            return "R\(roundNumber) · Pass \(dirSymbol) \(passDirection.label) · \(waiting) selecting\(seat0PassSummary)\(strengthHint)"
        case .playing:
            let scoreStr = scores.map { "\($0)" }.joined(separator: "/")
            var extras: [String] = []
            if heartsBroken { extras.append("♥ broken") }
            if queenPlayed && tricksPlayed < 13 { extras.append("Q♠ out") }
            // Moon-shoot detection: someone has taken ALL hearts and Q♠ so far
            if tricksPlayed >= 2 {
                for seat in 0..<4 {
                    let heartsSoFar = roundHeartsTaken[seat]
                    let totalHeartsPlayed = roundHeartsTaken.reduce(0, +)
                    let hasAll = heartsSoFar == totalHeartsPlayed && heartsSoFar > 0
                    let shooterQueenPlayed = !queenPlayed || roundPoints[seat] >= 13
                    if hasAll && tricksPlayed >= 3 {
                        if shooterQueenPlayed && roundPoints[seat] >= 8 {
                            extras.append("🌙🚨 S\(seat + 1) SHOOTING!")
                        } else {
                            extras.append("🌙 S\(seat + 1) may shoot")
                        }
                        break
                    }
                }
            }
            // Warn anyone nearing the game-ending threshold.
            if let maxScore = scores.max(), maxScore >= Self.gameEndThreshold - 15 {
                if let danger = (0..<4).first(where: { scores[$0] == maxScore }) {
                    extras.append("⚠️ S\(danger + 1) at \(maxScore)!")
                }
            }
            let extraStr = extras.isEmpty ? "" : " · " + extras.joined(separator: " · ")
            return "R\(roundNumber) · trick \(tricksPlayed + 1)/13\(extraStr) · \(scoreStr)"
        case .gameOver:
            return resultText ?? "Game over"
        }
    }

    var resultText: String? {
        guard isOver else { return nil }
        let best = scores.min()!
        let winners = (0..<4).filter { scores[$0] == best }.map { "Seat \($0 + 1)" }
        let scoreDetail = scores.map { "\($0)" }.joined(separator: "/")
        var text = "\(winners.joined(separator: " & ")) win with \(best) pts [\(scoreDetail)] in \(roundNumber) round\(roundNumber == 1 ? "" : "s")"
        if best == 0 { text += " · 🛡️ Perfect game!" }
        if worstRound >= 20 { text += " · 💥 S\(worstRoundSeat + 1) worst round \(worstRound)" }
        if let cleanLeader = (0..<4).max(by: { cleanRounds[$0] < cleanRounds[$1] }), cleanRounds[cleanLeader] >= 2 {
            text += " · 🧹 S\(cleanLeader + 1) \(cleanRounds[cleanLeader]) clean rounds"
        }
        let sorted = scores.sorted()
        let margin = sorted[1] - sorted[0]
        if winners.count == 1 && margin <= 5 { text += " · 😅 squeaker (won by \(margin))" }
        let totalMoons = moonShots.reduce(0, +)
        if totalMoons > 0 {
            let moonDetails = (0..<4).compactMap { moonShots[$0] > 0 ? "S\($0 + 1)×\(moonShots[$0])" : nil }
            text += " · 🌙 \(moonDetails.joined(separator: " "))"
        }
        // Show if any player was hit by Q♠ multiple times
        if let mostHit = queenSpadeHits.indices.max(by: { queenSpadeHits[$0] < queenSpadeHits[$1] }),
           queenSpadeHits[mostHit] >= 2 {
            text += " · ♛ S\(mostHit + 1) took Q♠ \(queenSpadeHits[mostHit])×"
        }
        // Aggressive leader stat
        if let leader = trickLeadWins.indices.max(by: { trickLeadWins[$0] < trickLeadWins[$1] }),
           trickLeadWins[leader] >= 5 {
            text += " · 🎯 S\(leader + 1) led and won \(trickLeadWins[leader]) tricks"
        }
        // Winner's total tricks won
        if let best = scores.min(), let winSeat = (0..<4).first(where: { scores[$0] == best }) {
            let ttw = totalTricksWon[winSeat]
            if ttw > 0 { text += " · S\(winSeat + 1) won \(ttw) tricks total" }
        }
        // Heart distribution per seat (♥ taken)
        let heartStr = (0..<4).map { "S\($0 + 1):\(totalHeartsTaken[$0])♥" }.joined(separator: " ")
        text += " · \(heartStr)"
        // Best defensive round
        if lowestPositiveRoundScore < Int.max && lowestPositiveRoundScore <= 3 {
            text += " · 🛡️ S\(lowestPositiveRoundSeat + 1) min round: \(lowestPositiveRoundScore)pts"
        }
        // Trick dominance across the whole game
        let domLabel = trickDominanceLabel
        if !domLabel.isEmpty { text += " · 🃏 \(domLabel)" }
        // Per-seat trick tally
        let trickTally = (0..<4).map { "S\($0 + 1):\(cumulativeTricksWon[$0])" }.joined(separator: " ")
        text += " · tricks: \(trickTally)"
        return text
    }

    func ranking() -> [[Int]] {
        guard isOver else { return [] }
        let byScore = Dictionary(grouping: 0..<4) { scores[$0] }
        return byScore.keys.sorted().map { byScore[$0]!.sorted() }
    }

    func redacted(for seat: Int) -> HeartsGame {
        var copy = self
        for other in 0..<4 where other != seat {
            copy.hands[other] = []
            if copy.passSelections[other] != nil { copy.passSelections[other] = [] }
        }
        return copy
    }
}
