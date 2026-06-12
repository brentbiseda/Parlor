import Foundation

/// Crazy Eights for four players with a standard deck: match the discard's
/// suit or rank, eights are wild and nominate a suit, draw one when stuck
/// (play it or keep it), pass when the stock is gone. First out wins; the
/// rest rank by points left in hand (8 = 50, faces = 10, ace = 1).
struct EightsGame: GameEngine {
    static let kind = GameKind.eights

    var hands: [[Card]] = Array(repeating: [], count: 4)
    var stock: [Card] = []
    var discard: [Card] = []
    /// Suit in force (overridden by an eight's nomination).
    var activeSuit: Suit = .clubs
    var currentPlayer = 0
    var drewThisTurn = false
    var winner: Int? = nil
    var consecutivePasses = 0
    var endedByBlock = false

    init() {
        var deck = Card.standardDeck().shuffled()
        for seat in 0..<4 {
            hands[seat] = Array(deck.prefix(5)).displaySorted()
            deck.removeFirst(5)
        }
        // Start on a non-eight so the opener isn't a wild.
        while deck.first?.rank == .eight { deck.append(deck.removeFirst()) }
        let start = deck.removeFirst()
        discard = [start]
        activeSuit = start.suit
        stock = deck
    }

    var isOver: Bool { winner != nil || endedByBlock }
    var topCard: Card? { discard.last }

    func canPlay(_ card: Card) -> Bool {
        if card.rank == .eight { return true }
        return card.suit == activeSuit || card.rank == topCard?.rank
    }

    func legalCards(for seat: Int) -> [Card] {
        hands[seat].filter { canPlay($0) }
    }

    func legalMoves() -> [Move] {
        guard !isOver else { return [] }
        var moves: [Move] = []
        for card in legalCards(for: currentPlayer) {
            if card.rank == .eight {
                for suit in Suit.allCases {
                    moves.append(.eights(.play(card, nominated: suit)))
                }
            } else {
                moves.append(.eights(.play(card, nominated: nil)))
            }
        }
        if drewThisTurn || stock.isEmpty {
            moves.append(.eights(.pass))
        } else {
            moves.append(.eights(.draw))
        }
        return moves
    }

    mutating func apply(_ move: Move) throws {
        guard case .eights(let m) = move else { throw GameError.illegalMove }
        switch m {
        case .play(let card, let nominated):
            guard let index = hands[currentPlayer].firstIndex(of: card),
                  canPlay(card) else { throw GameError.illegalMove }
            if card.rank == .eight && nominated == nil { throw GameError.illegalMove }
            hands[currentPlayer].remove(at: index)
            discard.append(card)
            activeSuit = card.rank == .eight ? (nominated ?? card.suit) : card.suit
            consecutivePasses = 0
            drewThisTurn = false
            if hands[currentPlayer].isEmpty {
                winner = currentPlayer
                return
            }
            currentPlayer = (currentPlayer + 1) % 4
        case .draw:
            guard !drewThisTurn, !stock.isEmpty else { throw GameError.illegalMove }
            let card = stock.removeLast()
            hands[currentPlayer].append(card)
            hands[currentPlayer] = hands[currentPlayer].displaySorted()
            consecutivePasses = 0
            if canPlay(card) {
                drewThisTurn = true   // may play or keep it
            } else {
                currentPlayer = (currentPlayer + 1) % 4
            }
        case .pass:
            guard drewThisTurn || stock.isEmpty else { throw GameError.illegalMove }
            drewThisTurn = false
            consecutivePasses += 1
            if consecutivePasses >= 4 {
                endedByBlock = true   // nobody can move — lightest hand wins
                return
            }
            currentPlayer = (currentPlayer + 1) % 4
        }
    }

    func handPoints(_ seat: Int) -> Int {
        hands[seat].reduce(0) { total, card in
            switch card.rank {
            case .eight: return total + 50
            case .king, .queen, .jack: return total + 10
            case .ace: return total + 1
            case .ten: return total + 10
            default: return total + card.rank.rawValue
            }
        }
    }

    func ranking() -> [[Int]] {
        guard isOver else { return [] }
        if let winner {
            let losers = (0..<4).filter { $0 != winner }
            let grouped = Dictionary(grouping: losers, by: handPoints)
            return [[winner]] + grouped.keys.sorted().map { grouped[$0]!.sorted() }
        }
        // Blocked: everyone ranks by hand points.
        let grouped = Dictionary(grouping: 0..<4, by: handPoints)
        return grouped.keys.sorted().map { grouped[$0]!.sorted() }
    }

    func redacted(for seat: Int) -> EightsGame {
        var copy = self
        let blank = Card(suit: .clubs, rank: .two)
        for other in 0..<4 where other != seat {
            copy.hands[other] = Array(repeating: blank, count: hands[other].count)
        }
        copy.stock = Array(repeating: blank, count: stock.count)
        return copy
    }

    var statusText: String {
        if isOver { return resultText ?? "Game over" }
        var text = "\(activeSuit.symbol) in play · stock \(stock.count)"
        if let smallest = hands.map(\.count).min(), smallest == 1 { text += " · last card!" }
        return text
    }

    var resultText: String? {
        if let winner { return "Seat \(winner + 1) goes out" }
        if endedByBlock {
            let best = (0..<4).min { handPoints($0) < handPoints($1) } ?? 0
            return "Blocked — Seat \(best + 1) wins with the lightest hand"
        }
        return nil
    }
}
