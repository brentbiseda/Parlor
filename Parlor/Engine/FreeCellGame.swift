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
    var foundations: [[Card]] = Array(repeating: [], count: 4)
    var moveCount = 0
    /// Tracks whether the game has been proven unsolvable (no legal moves).
    var deadlocked = false
    /// Times all 4 free cells were occupied simultaneously (pressure indicator).
    var fullFreeCellMoments = 0
    /// Longest run of consecutive moves that sent a card to a foundation.
    var foundationRun = 0
    var bestFoundationRun = 0
    /// Times the player used undo.
    var undoCount = 0
    /// Moves made by auto-finish assist.
    var autoFinishMoves = 0

    init() {
        var deck = Card.standardDeck().shuffled()
        cascades = (0..<8).map { col in
            let n = col < 4 ? 7 : 6
            defer { deck.removeFirst(n) }
            return Array(deck.prefix(n))
        }
    }

    var currentPlayer: Int { 0 }
    var isOver: Bool { foundations.allSatisfy { $0.count == 13 } || deadlocked }

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

    func isRun(_ cards: ArraySlice<Card>) -> Bool {
        guard !cards.isEmpty else { return false }
        for (a, b) in zip(cards, cards.dropFirst()) {
            guard a.suit.isRed != b.suit.isRed, a.rank.rawValue == b.rank.rawValue + 1 else { return false }
        }
        return true
    }

    var emptyCellCount: Int { freeCells.filter { $0 == nil }.count }
    var emptyCascadeCount: Int { cascades.filter(\.isEmpty).count }

    func maxRunLength(toEmptyCascade: Bool) -> Int {
        let empties = emptyCascadeCount - (toEmptyCascade ? 1 : 0)
        return (1 + emptyCellCount) * (1 << max(0, empties))
    }

    /// True when every remaining card is already in order and can cascade
    /// to foundations without needing free cells (safe auto-finish).
    var autoFinishAvailable: Bool {
        guard !isOver else { return false }
        let done = foundations.map { $0.count }
        // Each cascade must be a clean descending run and all cards above
        // the minimum already-placed rank can be pushed straight up.
        let minDone = done.min() ?? 0
        for cascade in cascades {
            for (i, card) in cascade.enumerated() {
                if i > 0 {
                    let below = cascade[i - 1]
                    if !(card.suit.isRed != below.suit.isRed
                         && card.rank.rawValue == below.rank.rawValue - 1) { return false }
                }
                // The card must be safely auto-playable: its rank ≤ minDone+2
                // (standard safe-to-auto rule avoids releasing needed blockers).
                if card.rank.rawValue > minDone + 2 { return false }
            }
        }
        return freeCells.compactMap { $0 }.allSatisfy { $0.rank.rawValue <= minDone + 2 }
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
                        // Skip moving an entire cascade to an empty column (no gain).
                        let movesWholePile = count == ups.count && cascades[dest].isEmpty
                        if !movesWholePile {
                            moves.append(.freecell(.cascadeToCascade(from: col, count: count, to: dest)))
                        }
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
        switch m {
        case .cascadeToFoundation, .freeToFoundation:
            foundationRun += 1
            bestFoundationRun = max(bestFoundationRun, foundationRun)
        default:
            foundationRun = 0
        }
        if freeCells.allSatisfy({ $0 != nil }) { fullFreeCellMoments += 1 }
        if legalMoves().isEmpty && !isOver { deadlocked = true }
    }

    var foundationCount: Int { foundations.reduce(0) { $0 + $1.count } }

    var statusText: String {
        if deadlocked { return "No moves — deal was unwinnable after \(moveCount) moves" }
        let done = foundationCount
        let freeFilled = freeCells.compactMap { $0 }.count
        let pct = done * 100 / 52
        let suitProgress = Suit.allCases.map { suit in
            let count = foundations[foundationIndex(for: suit)].count
            return "\(suit.symbol)\(count)"
        }.joined(separator: " ")
        var text = "Found. \(done)/52 (\(pct)%) [\(suitProgress)] · free \(freeFilled)/4 · \(moveCount) moves"
        if freeFilled == 4 { text += " ⚠️ cells full" }
        else if emptyCascadeCount > 0 { text += " · \(emptyCascadeCount) empty col\(emptyCascadeCount == 1 ? "" : "s")" }
        if autoFinishAvailable { text += " · ✨ auto-finish ready" }
        return text
    }

    var resultText: String? {
        if deadlocked { return "Stuck — no legal moves after \(moveCount) moves" }
        guard isOver else { return nil }
        var text = "Solved in \(moveCount) moves!"
        // Lower bound: every card needs at least one move onto a foundation.
        let estimate = 52
        if moveCount > estimate {
            let eff = Int(Double(estimate) / Double(moveCount) * 100)
            text += " · \(eff)% efficient (\(moveCount)/\(estimate) min)"
        } else {
            text += " · 💯 perfect efficiency!"
        }
        if fullFreeCellMoments == 0 { text += " · 🆓 Cells never full!" }
        else if fullFreeCellMoments <= 2 { text += " · \(fullFreeCellMoments)× all cells used" }
        if moveCount <= 60 { text += " · 🏅 Speedrun!" }
        else if moveCount <= 90 { text += " · efficient solve" }
        if bestFoundationRun >= 5 { text += " · 🔥 \(bestFoundationRun)-card run" }
        if undoCount == 0 { text += " · 🏆 no undos!" }
        else { text += " · used \(undoCount) undo\(undoCount == 1 ? "" : "s")" }
        if autoFinishMoves > 0 { text += " · ✨ auto-finished \(autoFinishMoves) moves" }
        return text
    }
}
