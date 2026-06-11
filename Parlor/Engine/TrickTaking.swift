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
}
