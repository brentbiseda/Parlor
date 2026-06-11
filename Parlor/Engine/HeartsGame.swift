import Foundation

/// Standard 4-player Hearts. Pass 3 cards (left, right, across, hold rotation),
/// 2♣ leads, hearts must be broken, Q♠ = 13 points, shooting the moon gives
/// the other three players 26. Game ends when someone reaches 100; low score wins.
struct HeartsGame: GameEngine {
    static let kind = GameKind.hearts

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
            // The UI builds the 3-card selection; expose one canonical option for bots.
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
            // No points on the first trick unless the hand forces it.
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

    /// Hearts passing has no fixed order; UI bypasses the canonical legalMoves
    /// check, so override legality for pass selections.
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

        if trick.count == 4 {
            let led = trick[0].card.suit
            let winner = TrickTaking.winner(plays: trick, ledSuit: led, suitOf: { $0.suit }, value: TrickTaking.plainValue)
            let trickPoints = trick.reduce(0) { $0 + points(for: $1.card) }
            roundPoints[winner] += trickPoints
            lastTrickSummary = "Trick to seat \(winner + 1)" + (trickPoints > 0 ? " (+\(trickPoints))" : "")
            trick = []
            trickLeader = winner
            tricksPlayed += 1
            if tricksPlayed == 13 { finishRound() }
        }
    }

    mutating func finishRound() {
        if let shooter = roundPoints.firstIndex(of: 26) {
            for seat in 0..<4 where seat != shooter { scores[seat] += 26 }
            lastTrickSummary = "Seat \(shooter + 1) shot the moon!"
        } else {
            for seat in 0..<4 { scores[seat] += roundPoints[seat] }
        }
        if scores.contains(where: { $0 >= 100 }) {
            phase = .gameOver
        } else {
            passDirectionIndex += 1
            startRound()
        }
    }

    var statusText: String {
        switch phase {
        case .passing:
            return "Round \(roundNumber): pass 3 cards \(passDirection.label)"
        case .playing:
            return "Round \(roundNumber) · trick \(tricksPlayed + 1) of 13" + (heartsBroken ? " · hearts broken" : "")
        case .gameOver:
            return resultText ?? "Game over"
        }
    }

    var resultText: String? {
        guard isOver else { return nil }
        let best = scores.min()!
        let winners = (0..<4).filter { scores[$0] == best }.map { "Seat \($0 + 1)" }
        return "\(winners.joined(separator: " & ")) win\(winners.count == 1 ? "s" : "") with \(best) points"
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
