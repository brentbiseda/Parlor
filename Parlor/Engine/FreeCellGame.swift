import Foundation

/// FreeCell solitaire. All 52 cards dealt face up into 8 cascades; 4 free
/// cells hold one card each. Foundations build up by suit from ace; cascades
/// build down alternating color. Multi-card moves are allowed up to the
/// classic supermove limit: (1 + empty cells) × 2^(empty cascades), halved
/// when moving onto an empty cascade.
struct FreeCellGame: GameEngine {
    static let kind = GameKind.freecell

    var cascades: [[Card]] = []
    var freeCells: [Card?] = [nil, nil, nil, nil]
    /// Foundations indexed by Suit.allCases order.
    var foundations: [[Card]] = Array(repeating: [], count: 4)
    var moveCount = 0

    init() {
        var deck = Card.standardDeck().shuffled()
        cascades = (0..<8).map { col in
            let n = col < 4 ? 7 : 6
            defer { deck.removeFirst(n) }
            return Array(deck.prefix(n))
        }
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

    func canPlace(_ card: Card, onCascade col: Int) -> Bool {
        guard let top = cascades[col].last else { return true }
        return card.suit.isRed != top.suit.isRed && card.rank.rawValue == top.rank.rawValue - 1
    }

    /// Whether the top `count` cards of a cascade form a movable run
    /// (descending, alternating colors).
    func isRun(_ cards: ArraySlice<Card>) -> Bool {
        guard !cards.isEmpty else { return false }
        for (a, b) in zip(cards, cards.dropFirst()) {
            guard a.suit.isRed != b.suit.isRed, a.rank.rawValue == b.rank.rawValue + 1 else { return false }
        }
        return true
    }

    var emptyCellCount: Int { freeCells.filter { $0 == nil }.count }
    var emptyCascadeCount: Int { cascades.filter(\.isEmpty).count }

    /// Largest run movable to `destination` (nil = a non-empty cascade).
    func maxRunLength(toEmptyCascade: Bool) -> Int {
        let empties = emptyCascadeCount - (toEmptyCascade ? 1 : 0)
        return (1 + emptyCellCount) * (1 << max(0, empties))
    }

    func legalMoves() -> [Move] {
        var moves: [Move] = []
        for col in cascades.indices {
            guard let top = cascades[col].last else { continue }
            if canPlaceOnFoundation(top) { moves.append(.freecell(.cascadeToFoundation(col: col))) }
            if let cell = freeCells.firstIndex(where: { $0 == nil }) {
                moves.append(.freecell(.cascadeToFree(col: col, cell: cell)))
            }
            for dest in cascades.indices where dest != col {
                let limit = maxRunLength(toEmptyCascade: cascades[dest].isEmpty)
                let ups = cascades[col]
                var count = 1
                while count <= min(limit, ups.count) {
                    let run = ups.suffix(count)
                    if isRun(run), let head = run.first, canPlace(head, onCascade: dest) {
                        moves.append(.freecell(.cascadeToCascade(from: col, count: count, to: dest)))
                    }
                    if !isRun(run) { break }
                    count += 1
                }
            }
        }
        for (cell, card) in freeCells.enumerated() {
            guard let card else { continue }
            if canPlaceOnFoundation(card) { moves.append(.freecell(.freeToFoundation(cell: cell))) }
            for dest in cascades.indices where canPlace(card, onCascade: dest) {
                moves.append(.freecell(.freeToCascade(cell: cell, to: dest)))
            }
        }
        return moves
    }

    /// Like Klondike, moves are validated structurally in `apply`.
    func isLegal(_ move: Move) -> Bool {
        if case .freecell = move { return true }
        return false
    }

    mutating func apply(_ move: Move) throws {
        guard case .freecell(let m) = move else { throw GameError.illegalMove }
        switch m {
        case .cascadeToFree(let col, let cell):
            guard cascades.indices.contains(col), freeCells.indices.contains(cell),
                  freeCells[cell] == nil, let top = cascades[col].last else { throw GameError.illegalMove }
            cascades[col].removeLast()
            freeCells[cell] = top
        case .cascadeToFoundation(let col):
            guard cascades.indices.contains(col), let top = cascades[col].last,
                  canPlaceOnFoundation(top) else { throw GameError.illegalMove }
            cascades[col].removeLast()
            foundations[foundationIndex(for: top.suit)].append(top)
        case .cascadeToCascade(let from, let count, let to):
            guard from != to, cascades.indices.contains(from), cascades.indices.contains(to),
                  count >= 1, count <= cascades[from].count else { throw GameError.illegalMove }
            let run = cascades[from].suffix(count)
            guard isRun(run), let head = run.first, canPlace(head, onCascade: to),
                  count <= maxRunLength(toEmptyCascade: cascades[to].isEmpty) else { throw GameError.illegalMove }
            cascades[from].removeLast(count)
            cascades[to].append(contentsOf: run)
        case .freeToFoundation(let cell):
            guard freeCells.indices.contains(cell), let card = freeCells[cell],
                  canPlaceOnFoundation(card) else { throw GameError.illegalMove }
            freeCells[cell] = nil
            foundations[foundationIndex(for: card.suit)].append(card)
        case .freeToCascade(let cell, let to):
            guard freeCells.indices.contains(cell), let card = freeCells[cell],
                  cascades.indices.contains(to), canPlace(card, onCascade: to) else { throw GameError.illegalMove }
            freeCells[cell] = nil
            cascades[to].append(card)
        }
        moveCount += 1
    }

    var statusText: String {
        let done = foundations.reduce(0) { $0 + $1.count }
        return "Foundations \(done)/52 · \(moveCount) moves"
    }

    var resultText: String? {
        isOver ? "Solved in \(moveCount) moves!" : nil
    }
}
