import Foundation

/// Klondike solitaire. Draw one or three, unlimited stock passes.
/// Foundations build up by suit from ace; tableau builds down alternating color.
struct KlondikeGame: GameEngine {
    static let kind = GameKind.solitaire

    struct TableauPile: Codable, Hashable {
        var faceDown: [Card] = []
        var faceUp: [Card] = []
    }

    var tableau: [TableauPile] = []
    var stock: [Card] = []
    var waste: [Card] = []
    /// Foundations indexed by Suit.allCases order.
    var foundations: [[Card]] = Array(repeating: [], count: 4)
    var drawThree: Bool
    /// Times allowed through the stock; 0 = unlimited.
    var maxPasses: Int = 0
    /// Completed trips through the stock (the deal itself is pass 1).
    var passesUsed: Int = 1
    var moveCount = 0

    init(drawThree: Bool = false, maxPasses: Int = 0) {
        self.drawThree = drawThree
        self.maxPasses = maxPasses
        var deck = Card.standardDeck().shuffled()
        tableau = (0..<7).map { col in
            var pile = TableauPile()
            pile.faceDown = Array(deck.prefix(col))
            deck.removeFirst(col)
            pile.faceUp = [deck.removeFirst()]
            return pile
        }
        stock = deck
    }

    var currentPlayer: Int { 0 }
    var isOver: Bool { foundations.allSatisfy { $0.count == 13 } }

    func foundationIndex(for suit: Suit) -> Int {
        Suit.allCases.firstIndex(of: suit)!
    }

    func canPlaceOnFoundation(_ card: Card) -> Bool {
        let pile = foundations[foundationIndex(for: card.suit)]
        if let top = pile.last { return card.rank.rawValue == top.rank.rawValue + 1 }
        return card.rank == .ace
    }

    func canPlaceOnTableau(_ card: Card, column: Int) -> Bool {
        if let top = tableau[column].faceUp.last {
            return card.suit.isRed != top.suit.isRed && card.rank.rawValue == top.rank.rawValue - 1
        }
        return tableau[column].faceDown.isEmpty && card.rank == .king
    }

    /// Whether the stock may be flipped back over for another pass.
    var canResetStock: Bool {
        stock.isEmpty && !waste.isEmpty && (maxPasses == 0 || passesUsed < maxPasses)
    }

    func legalMoves() -> [Move] {
        var moves: [Move] = []
        if !stock.isEmpty {
            moves.append(.klondike(.draw))
        } else if canResetStock {
            moves.append(.klondike(.resetStock))
        }
        if let top = waste.last {
            if canPlaceOnFoundation(top) { moves.append(.klondike(.wasteToFoundation)) }
            for col in 0..<7 where canPlaceOnTableau(top, column: col) {
                moves.append(.klondike(.wasteToTableau(col)))
            }
        }
        for col in 0..<7 {
            let ups = tableau[col].faceUp
            if let top = ups.last, canPlaceOnFoundation(top) {
                moves.append(.klondike(.tableauToFoundation(col)))
            }
            for index in ups.indices {
                for dest in 0..<7 where dest != col && canPlaceOnTableau(ups[index], column: dest) {
                    moves.append(.klondike(.tableauToTableau(from: col, index: index, to: dest)))
                }
            }
        }
        for f in 0..<4 {
            if let top = foundations[f].last {
                for col in 0..<7 where canPlaceOnTableau(top, column: col) {
                    moves.append(.klondike(.foundationToTableau(foundation: f, to: col)))
                }
            }
        }
        return moves
    }

    mutating func apply(_ move: Move) throws {
        guard case .klondike(let m) = move else { throw GameError.illegalMove }
        switch m {
        case .draw:
            guard !stock.isEmpty else { throw GameError.illegalMove }
            let n = drawThree ? min(3, stock.count) : 1
            for _ in 0..<n { waste.append(stock.removeLast()) }
        case .resetStock:
            guard canResetStock else { throw GameError.illegalMove }
            stock = waste.reversed()
            waste = []
            passesUsed += 1
        case .wasteToFoundation:
            guard let top = waste.last, canPlaceOnFoundation(top) else { throw GameError.illegalMove }
            waste.removeLast()
            foundations[foundationIndex(for: top.suit)].append(top)
        case .wasteToTableau(let col):
            guard let top = waste.last, canPlaceOnTableau(top, column: col) else { throw GameError.illegalMove }
            waste.removeLast()
            tableau[col].faceUp.append(top)
        case .tableauToFoundation(let col):
            guard let top = tableau[col].faceUp.last, canPlaceOnFoundation(top) else { throw GameError.illegalMove }
            tableau[col].faceUp.removeLast()
            foundations[foundationIndex(for: top.suit)].append(top)
            flipIfNeeded(col)
        case .tableauToTableau(let from, let index, let to):
            guard from != to, tableau[from].faceUp.indices.contains(index),
                  canPlaceOnTableau(tableau[from].faceUp[index], column: to) else { throw GameError.illegalMove }
            let run = Array(tableau[from].faceUp[index...])
            tableau[from].faceUp.removeSubrange(index...)
            tableau[to].faceUp.append(contentsOf: run)
            flipIfNeeded(from)
        case .foundationToTableau(let f, let to):
            guard let top = foundations[f].last, canPlaceOnTableau(top, column: to) else { throw GameError.illegalMove }
            foundations[f].removeLast()
            tableau[to].faceUp.append(top)
        }
        moveCount += 1
    }

    /// Klondike moves are validated structurally in `apply`, not by enumeration.
    func isLegal(_ move: Move) -> Bool {
        if case .klondike = move { return true }
        return false
    }

    mutating func flipIfNeeded(_ col: Int) {
        if tableau[col].faceUp.isEmpty, let card = tableau[col].faceDown.popLast() {
            tableau[col].faceUp = [card]
        }
    }

    var statusText: String {
        let done = foundations.reduce(0) { $0 + $1.count }
        var text = "Foundations \(done)/52 · \(moveCount) moves"
        if maxPasses > 0 { text += " · pass \(min(passesUsed, maxPasses))/\(maxPasses)" }
        return text
    }

    var resultText: String? {
        isOver ? "Solved in \(moveCount) moves!" : nil
    }
}
