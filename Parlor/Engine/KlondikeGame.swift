import Foundation

/// Klondike solitaire. Draw one or three, limited or unlimited stock passes.
/// Foundations build up by suit from ace; tableau builds down alternating color.
/// Undo is supported for up to 50 moves; each move snapshots the mutable state.
struct KlondikeGame: GameEngine {
    static let kind = GameKind.solitaire
    static let maxUndoDepth = 50

    struct TableauPile: Codable, Hashable {
        var faceDown: [Card] = []
        var faceUp: [Card] = []
    }

    // MARK: - Undo snapshot

    private struct Snapshot: Codable {
        var tableau: [TableauPile]
        var stock: [Card]
        var waste: [Card]
        var foundations: [[Card]]
        var passesUsed: Int
        var moveCount: Int
        var foundationStreak: Int
        var bestFoundationStreak: Int
        var stockResets: Int
    }

    // MARK: - State

    var tableau: [TableauPile] = []
    var stock: [Card] = []
    var waste: [Card] = []
    /// Foundations indexed by Suit.allCases order.
    var foundations: [[Card]] = Array(repeating: [], count: 4)
    var drawThree: Bool
    /// Times allowed through the stock; 0 = unlimited.
    var maxPasses: Int = 0
    /// Completed trips through the stock (initial deal counts as pass 1).
    var passesUsed: Int = 1
    var moveCount = 0
    /// Consecutive moves that sent a card straight to a foundation (resets on any other move).
    var foundationStreak = 0
    var bestFoundationStreak = 0
    /// Times the waste was recycled into the stock (0 = clean solve).
    var stockResets = 0
    /// Times the player used undo.
    var undoCount = 0
    /// Moves that placed a card directly onto a foundation (waste-to-foundation or tableau-to-foundation).
    var autoPlayCount: Int = 0
    /// Computed alias for stockResets (how many times the waste was recycled into the stock).
    var stockCycles: Int { stockResets }

    private var history: [Snapshot] = []

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
    var canUndo: Bool { !history.isEmpty }

    func foundationIndex(for suit: Suit) -> Int {
        Suit.allCases.firstIndex(of: suit)!
    }

    func canPlaceOnFoundation(_ card: Card) -> Bool {
        let pile = foundations[foundationIndex(for: card.suit)]
        if let top = pile.last {
            // Ace (rawValue 14) is the foundation starter; the only special transition is Ace→2.
            if top.rank == .ace { return card.rank == .two }
            return card.rank.rawValue == top.rank.rawValue + 1
        }
        return card.rank == .ace
    }

    func canPlaceOnTableau(_ card: Card, column: Int) -> Bool {
        if let top = tableau[column].faceUp.last {
            return card.suit.isRed != top.suit.isRed && card.rank.rawValue == top.rank.rawValue - 1
        }
        return tableau[column].faceDown.isEmpty && card.rank == .king
    }

    var canResetStock: Bool {
        stock.isEmpty && !waste.isEmpty && (maxPasses == 0 || passesUsed < maxPasses)
    }

    // MARK: - Moves

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
                    // Skip futile moves: relocating a full king-run from one
                    // empty-backed column to another empty column gains nothing.
                    if index == 0, tableau[col].faceDown.isEmpty, tableau[dest].faceUp.isEmpty { continue }
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
        saveSnapshot()
        switch m {
        case .draw:
            guard !stock.isEmpty else { rollback(); throw GameError.illegalMove }
            let n = drawThree ? min(3, stock.count) : 1
            for _ in 0..<n { waste.append(stock.removeLast()) }
        case .resetStock:
            guard canResetStock else { rollback(); throw GameError.illegalMove }
            stock = waste.reversed()
            waste = []
            passesUsed += 1
            stockResets += 1
        case .wasteToFoundation:
            guard let top = waste.last, canPlaceOnFoundation(top) else { rollback(); throw GameError.illegalMove }
            waste.removeLast()
            foundations[foundationIndex(for: top.suit)].append(top)
        case .wasteToTableau(let col):
            guard let top = waste.last, canPlaceOnTableau(top, column: col) else { rollback(); throw GameError.illegalMove }
            waste.removeLast()
            tableau[col].faceUp.append(top)
        case .tableauToFoundation(let col):
            guard let top = tableau[col].faceUp.last, canPlaceOnFoundation(top) else { rollback(); throw GameError.illegalMove }
            tableau[col].faceUp.removeLast()
            foundations[foundationIndex(for: top.suit)].append(top)
            flipIfNeeded(col)
        case .tableauToTableau(let from, let index, let to):
            guard from != to, tableau[from].faceUp.indices.contains(index),
                  canPlaceOnTableau(tableau[from].faceUp[index], column: to) else { rollback(); throw GameError.illegalMove }
            let run = Array(tableau[from].faceUp[index...])
            tableau[from].faceUp.removeSubrange(index...)
            tableau[to].faceUp.append(contentsOf: run)
            flipIfNeeded(from)
        case .foundationToTableau(let f, let to):
            guard let top = foundations[f].last, canPlaceOnTableau(top, column: to) else { rollback(); throw GameError.illegalMove }
            foundations[f].removeLast()
            tableau[to].faceUp.append(top)
        }
        moveCount += 1
        switch m {
        case .wasteToFoundation, .tableauToFoundation:
            foundationStreak += 1
            bestFoundationStreak = max(bestFoundationStreak, foundationStreak)
            autoPlayCount += 1
        default:
            foundationStreak = 0
        }
    }

    /// Revert the last move (does nothing if history is empty).
    mutating func undo() {
        guard let snap = history.popLast() else { return }
        tableau = snap.tableau
        stock = snap.stock
        waste = snap.waste
        foundations = snap.foundations
        passesUsed = snap.passesUsed
        moveCount = snap.moveCount
        foundationStreak = snap.foundationStreak
        bestFoundationStreak = snap.bestFoundationStreak
        stockResets = snap.stockResets
        undoCount += 1
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

    // MARK: - Private

    private mutating func saveSnapshot() {
        if history.count >= Self.maxUndoDepth { history.removeFirst() }
        history.append(Snapshot(tableau: tableau, stock: stock, waste: waste,
                                foundations: foundations,
                                passesUsed: passesUsed, moveCount: moveCount,
                                foundationStreak: foundationStreak, bestFoundationStreak: bestFoundationStreak,
                                stockResets: stockResets))
    }

    private mutating func rollback() {
        guard let snap = history.popLast() else { return }
        tableau = snap.tableau; stock = snap.stock; waste = snap.waste
        foundations = snap.foundations; passesUsed = snap.passesUsed; moveCount = snap.moveCount
        foundationStreak = snap.foundationStreak; bestFoundationStreak = snap.bestFoundationStreak
        stockResets = snap.stockResets
    }

    // MARK: - Status

    /// Cards placed on foundations (0–52).
    var foundationProgress: Int { foundations.reduce(0) { $0 + $1.count } }
    /// 0.0–1.0 fraction of cards placed on foundations.
    var foundationProgressFraction: Double { Double(foundationProgress) / 52.0 }
    /// Number of cards currently placeable on a foundation (waste top + tableau tops).
    var autoFoundationCount: Int {
        var count = 0
        if let top = waste.last, canPlaceOnFoundation(top) { count += 1 }
        for col in 0..<tableau.count {
            if let top = tableau[col].faceUp.last, canPlaceOnFoundation(top) { count += 1 }
        }
        return count
    }

    var statusText: String {
        let done = foundationProgress
        let faceDownCount = tableau.reduce(0) { $0 + $1.faceDown.count }
        let faceDownStr = faceDownCount > 0 ? " · \(faceDownCount) face-down" : ""
        let pct = done > 0 ? " (\(Int(foundationProgressFraction * 100))%)" : ""
        var text = "Found. \(done)/52\(pct)\(faceDownStr) · \(moveCount) moves"
        if stockResets > 0 {
            let passLabel = maxPasses > 0 ? "Pass \(passesUsed)/\(maxPasses)" : "Pass \(passesUsed)"
            text += " · \(passLabel) · ↺\(stockCycles)"
        } else {
            text += maxPasses > 0 ? " · pass \(passesUsed)/\(maxPasses)" : ""
        }
        if maxPasses > 0 && passesUsed >= maxPasses && !stock.isEmpty {
            text += " ⚠️ last pass"
        }
        let ready = autoFoundationCount
        if ready > 0 { text += " · ✨\(ready) ready" }
        if done >= 48 { text += " · 🏁 almost there!" }
        if foundationStreak >= 3 { text += " · 🔥 streak \(foundationStreak)" }
        if stockResets == 0 && passesUsed == 1 && done >= 13 { text += " · ✨ clean so far" }
        // Live efficiency: useful when player is tracking their move count.
        if moveCount >= 20 && done > 0 {
            let eff = Int(Double(done) / Double(moveCount) * 100)
            if eff >= 70 { text += " · ⚡ \(eff)% eff" }
        }
        // No productive moves and the stock can't help: warn the player.
        if legalMoves().allSatisfy({ if case .klondike(.draw) = $0 { return true }; if case .klondike(.resetStock) = $0 { return true }; return false }),
           stock.isEmpty && !canResetStock, faceDownCount > 0 {
            text += " · 🚫 no moves left"
        }
        return text
    }

    var resultText: String? {
        guard isOver else { return nil }
        var text = "Solved in \(moveCount) moves!"
        if stockResets == 0 { text += " · ✨ Clean solve — no recycle!" }
        else { text += " · ↺\(stockCycles) recycle\(stockCycles == 1 ? "" : "s")" }
        if autoPlayCount > 0 { text += " · ✨\(autoPlayCount) auto" }
        if bestFoundationStreak >= 3 { text += " · 🔥 \(bestFoundationStreak)-card foundation streak" }
        if moveCount > 52 {
            let efficiency = Int(Double(52) / Double(moveCount) * 100)
            text += " · \(efficiency)% efficient"
        } else if moveCount > 0 {
            text += " · perfect efficiency!"
        }
        if undoCount == 0 { text += " · 🏆 no undos!" }
        else if undoCount > 0 { text += " · used \(undoCount) undo\(undoCount == 1 ? "" : "s")" }
        return text
    }
}
