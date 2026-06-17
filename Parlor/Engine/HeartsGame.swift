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

    var passDirection: PassDirection { PassDirection.allCases[passDirectionIndex % 4] }

    init() {
        startRound()
    }

    mutating func startRound() {
        let (dealt, _) = TrickTaking.deal(deck: Card.standardDeck(), players: 4, count: 13)
        hands = dealt
        passSelections = Array(repeating: nil, count: 4)
        trick = []
        tricksPlayed = 0
        heartsBroken = false
        queenPlayed = false
        roundPoints = [0, 0, 0, 0]
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
            let highCard = trick.max(by: { TrickTaking.plainValue($0.card) < TrickTaking.plainValue($1.card) })?.card
            let cardLabel = highCard.map { "\($0.rank.label)\($0.suit.symbol)" } ?? ""
            let pts = trickPoints > 0 ? " +\(trickPoints)♥" : ""
            lastTrickSummary = "Seat \(winner + 1) wins\(pts) — \(cardLabel)"
            // Track aggression: was this trick won by the seat that led it?
            if winner == trickLeader { trickLeadWins[winner] += 1 }
            totalTricksWon[winner] += 1
            trick = []
            trickLeader = winner
            tricksPlayed += 1
            if tricksPlayed == 13 { finishRound() }
        }
    }

    mutating func finishRound() {
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
        }
        if scores.contains(where: { $0 >= Self.gameEndThreshold }) {
            phase = .gameOver
        } else {
            passDirectionIndex += 1
            startRound()
        }
    }

    var statusText: String {
        switch phase {
        case .passing:
            let waiting = (0..<4).filter { passSelections[$0] == nil }.count
            let seat0PassPts = passSelections[0].map { $0.reduce(0) { $0 + points(for: $1) } }.map { $0 > 0 ? " · \($0)♥ in your pass" : "" } ?? ""
            return "Round \(roundNumber): pass \(passDirection.label) · \(waiting) selecting\(seat0PassPts)"
        case .playing:
            let scoreStr = scores.map { "\($0)" }.joined(separator: "/")
            var extras: [String] = []
            if heartsBroken { extras.append("♥ broken") }
            if queenPlayed && tricksPlayed < 13 { extras.append("Q♠ played") }
            // Warn if someone is collecting all hearts so far (potential moon shot).
            if tricksPlayed >= 3 {
                for seat in 0..<4 {
                    let pts = roundPoints[seat]
                    let hasAllHearts = pts >= tricksPlayed && !queenPlayed
                    if pts > 0 && pts == tricksPlayed && hasAllHearts {
                        extras.append("🌙 Seat \(seat + 1) may shoot!")
                        break
                    }
                }
            }
            // Warn anyone nearing the game-ending threshold.
            if let maxScore = scores.max(), maxScore >= Self.gameEndThreshold - 20 {
                if let danger = (0..<4).first(where: { scores[$0] == maxScore }) {
                    extras.append("⚠️ Seat \(danger + 1) at \(maxScore)")
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
