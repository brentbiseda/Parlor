import Foundation

struct TrickPlay: Codable, Hashable {
    var seat: Int
    var card: Card
}

enum TrickTaking {
    /// Deal `count` cards to each of `players` seats from a shuffled copy of `deck`.
    /// Returns (hands, remainder).
    static func deal(deck: [Card], players: Int, count: Int) -> ([[Card]], [Card]) {
        var shuffled = deck.shuffled()
        var hands: [[Card]] = Array(repeating: [], count: players)
        for seat in 0..<players {
            hands[seat] = Array(shuffled.prefix(count)).displaySorted()
            shuffled.removeFirst(count)
        }
        return (hands, shuffled)
    }

    /// Cards in `hand` playable when `ledSuit` was led, treating `suitOf` as the
    /// effective suit (handles the Euchre left bower). Must follow suit if able.
    static func followLegal(hand: [Card], ledSuit: Suit?, suitOf: (Card) -> Suit) -> [Card] {
        guard let led = ledSuit else { return hand }
        let following = hand.filter { suitOf($0) == led }
        return following.isEmpty ? hand : following
    }

    /// Winner of a completed trick. `value` must rank trump cards above all
    /// led-suit cards (e.g. add a large constant for trump).
    static func winner(plays: [TrickPlay], ledSuit: Suit, suitOf: (Card) -> Suit, value: (Card) -> Int) -> Int {
        var best = plays[0]
        for play in plays.dropFirst() {
            let bestRelevant = suitOf(best.card) == ledSuit || value(best.card) >= 1000
            let thisRelevant = suitOf(play.card) == ledSuit || value(play.card) >= 1000
            if thisRelevant && (!bestRelevant || value(play.card) > value(best.card)) {
                best = play
            }
        }
        return best.seat
    }

    /// Standard no-trump value: rank only.
    static func plainValue(_ card: Card) -> Int { card.rank.rawValue }

    /// Value with a trump suit: trump cards get +1000 so they beat led-suit cards.
    static func trumpValue(_ card: Card, trump: Suit?) -> Int {
        card.rank.rawValue + (card.suit == trump ? 1000 : 0)
    }

    /// Returns a dictionary of card count per suit, using `suitOf` for effective suit
    /// (handles Euchre left bower). Useful for bidding and bot decision-making.
    static func suitCounts(hand: [Card], suitOf: (Card) -> Suit = { $0.suit }) -> [Suit: Int] {
        hand.reduce(into: [:]) { counts, card in counts[suitOf(card), default: 0] += 1 }
    }

    /// High-Card Points for a hand (standard bridge valuation):
    /// Ace=4, King=3, Queen=2, Jack=1. Used by bridge bidding bot.
    static func highCardPoints(hand: [Card]) -> Int {
        hand.reduce(0) { pts, card in
            switch card.rank {
            case .ace:   return pts + 4
            case .king:  return pts + 3
            case .queen: return pts + 2
            case .jack:  return pts + 1
            default:     return pts
            }
        }
    }

    /// Safe lead from `hand` when opening a trick in a trump game.
    /// Prefers leading low from a long side suit over leading trump, and
    /// avoids leading away from tenaces (K-Q without the ace).
    static func safeLead(from hand: [Card], trump: Suit?, suitOf: (Card) -> Suit = { $0.suit }) -> Card? {
        guard !hand.isEmpty else { return nil }
        let nonTrump = hand.filter { suitOf($0) != trump }
        let pool = nonTrump.isEmpty ? hand : nonTrump
        // Avoid leading the top of a K-Q tenace (may give away the trick cheaply).
        let notTenace = pool.filter { card in
            let suit = suitOf(card)
            let inSuit = hand.filter { suitOf($0) == suit }.map(\.rank)
            if card.rank == .king && inSuit.contains(.queen) && !inSuit.contains(.ace) { return false }
            return true
        }
        let lead = notTenace.isEmpty ? pool : notTenace
        // Lead the fourth-from-highest in the longest non-trump suit.
        let bySuit = Dictionary(grouping: lead) { suitOf($0) }
        if let longest = bySuit.max(by: { $0.value.count < $1.value.count }) {
            let sorted = longest.value.sorted { $0.rank.rawValue > $1.rank.rawValue }
            return sorted.count >= 4 ? sorted[3] : sorted.last
        }
        return lead.min { $0.rank.rawValue < $1.rank.rawValue }
    }

    /// Estimated trick count for a suit in a hand, accounting for length and honors.
    /// Returns (quick tricks, potential tricks). Quick tricks = guaranteed winners.
    static func trickEstimate(hand: [Card], suit: Suit) -> (quick: Int, potential: Int) {
        let suitCards = hand.filter { $0.suit == suit }
            .sorted { $0.rank.rawValue > $1.rank.rawValue }
        guard !suitCards.isEmpty else { return (0, 0) }
        var quick = 0
        // Count A, then A-K, then A-K-Q sequences.
        if suitCards[0].rank == .ace {
            quick += 1
            if suitCards.count > 1, suitCards[1].rank == .king {
                quick += 1
                if suitCards.count > 2, suitCards[2].rank == .queen { quick += 1 }
            }
        } else if suitCards[0].rank == .king && suitCards.count > 1 && suitCards[1].rank == .queen {
            quick += 1  // K-Q = 1 quick trick
        }
        // Length tricks: cards beyond 4 in a suit.
        let potential = quick + max(0, suitCards.count - 4)
        return (quick, potential)
    }
}
