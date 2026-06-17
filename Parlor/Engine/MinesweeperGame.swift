import Foundation

/// Classic Minesweeper with three difficulty presets. The first reveal is
/// always safe (mines are placed after it), zero-cells flood-fill open, and
/// the game is won when every safe cell is revealed.
///
/// Difficulties:
///   Easy   9×11  14 mines   (~14 %)
///   Medium 12×16 40 mines   (~21 %)
///   Hard   16×22 99 mines   (~28 %)
///
/// Chording: tap a satisfied number (flagged neighbors == count) to pop all
/// unflagged neighbors at once. A wrong flag still triggers a loss.
struct MinesweeperGame: GameEngine {
    static let kind = GameKind.minesweeper

    // MARK: - Difficulty

    enum Difficulty: Int, Codable, CaseIterable, Hashable {
        case easy, medium, hard

        var label: String { ["Easy", "Medium", "Hard"][rawValue] }
        var width: Int  { [9,  12, 16][rawValue] }
        var height: Int { [11, 16, 22][rawValue] }
        var mines: Int  { [14, 40, 99][rawValue] }
        var safeCells: Int { width * height - mines }
    }

    // MARK: - State

    var difficulty: Difficulty = .easy
    var mines: Set<Int> = []
    var revealed: Set<Int> = []
    var flagged: Set<Int> = []
    var questioned: Set<Int> = []  // cells marked with ? (uncertain)
    var minesPlaced = false
    var lost = false
    var moveCount = 0
    var startTime: Date? = nil
    var endTime: Date? = nil
    /// True if the player placed at least one flag during this game.
    var usedFlags = false
    /// Consecutive successful chord expansions (no wrong flag triggered).
    var chordStreak = 0
    var bestChordStreak = 0
    /// Largest number of cells opened by a single reveal/flood (skill flair).
    var biggestCascade = 0
    /// Whether the first click was safe (always true in normal play — ensures stat accuracy).
    var safeFirstClick = true
    /// Flags placed adjacent to other flags (pattern recognition indicator).
    var patternFlags = 0
    /// Number of cells opened on the very first click cascade.
    var firstClearCascade: Int = 0
    /// Whether we've recorded the first cascade yet.
    private var firstClickDone: Bool = false

    var currentPlayer: Int { 0 }
    var won: Bool {
        minesPlaced && !lost && revealed.count == difficulty.safeCells
    }
    var isOver: Bool { lost || won }

    var elapsedSeconds: Int {
        guard let start = startTime else { return 0 }
        return Int((endTime ?? Date()).timeIntervalSince(start))
    }

    init(difficulty: Difficulty = .easy) {
        self.difficulty = difficulty
    }

    // MARK: - Grid helpers

    func index(_ x: Int, _ y: Int) -> Int { y * difficulty.width + x }

    func neighbors(_ idx: Int) -> [Int] {
        let (x, y) = (idx % difficulty.width, idx / difficulty.width)
        var result: [Int] = []
        for dy in -1...1 {
            for dx in -1...1 where dx != 0 || dy != 0 {
                let (nx, ny) = (x + dx, y + dy)
                if (0..<difficulty.width).contains(nx), (0..<difficulty.height).contains(ny) {
                    result.append(index(nx, ny))
                }
            }
        }
        return result
    }

    func adjacentMines(_ idx: Int) -> Int {
        neighbors(idx).filter { mines.contains($0) }.count
    }

    var flagsLeft: Int { difficulty.mines - flagged.count }
    var flagCount: Int { flagged.count }
    var totalCells: Int { difficulty.width * difficulty.height }
    var efficiency: Int {
        guard won, difficulty.safeCells > 0 else { return 0 }
        return min(100, revealed.count * 100 / difficulty.safeCells)
    }

    /// mm:ss formatted elapsed time.
    var timerString: String {
        let s = elapsedSeconds
        return s >= 60 ? "\(s / 60):\(String(format: "%02d", s % 60))" : "\(s)s"
    }

    // MARK: - Moves

    func legalMoves() -> [Move] {
        guard !isOver else { return [] }
        return (0..<(difficulty.width * difficulty.height))
            .filter { !revealed.contains($0) && !flagged.contains($0) }
            .map { .minesweeper(.reveal(x: $0 % difficulty.width, y: $0 / difficulty.width)) }
    }

    func isLegal(_ move: Move) -> Bool {
        if case .minesweeper = move { return !isOver }
        return false
    }

    mutating func apply(_ move: Move) throws {
        guard case .minesweeper(let m) = move else { throw GameError.illegalMove }
        switch m {
        case .reveal(let x, let y):
            guard (0..<difficulty.width).contains(x),
                  (0..<difficulty.height).contains(y) else { throw GameError.illegalMove }
            let idx = index(x, y)
            guard !flagged.contains(idx) else { throw GameError.illegalMove }
            if revealed.contains(idx) {
                try chord(at: idx)
                return
            }
            if !minesPlaced {
                placeMines(avoiding: idx)
                startTime = Date()
            }
            moveCount += 1
            if mines.contains(idx) {
                lost = true
                revealed.insert(idx)
                endTime = Date()
                return
            }
            let before = revealed.count
            floodReveal(from: idx)
            let cascadeSize = revealed.count - before
            biggestCascade = max(biggestCascade, cascadeSize)
            if !firstClickDone {
                firstClearCascade = cascadeSize
                firstClickDone = true
            }
            if won { endTime = Date() }
        case .flag(let x, let y):
            guard (0..<difficulty.width).contains(x),
                  (0..<difficulty.height).contains(y) else { throw GameError.illegalMove }
            let idx = index(x, y)
            guard !revealed.contains(idx) else { throw GameError.illegalMove }
            if flagged.contains(idx) {
                // Cycle: flag → ? → clear
                flagged.remove(idx)
                questioned.insert(idx)
            } else if questioned.contains(idx) {
                questioned.remove(idx)
            } else {
                // Clear → flag
                let adjacentToFlag = neighbors(idx).contains { flagged.contains($0) }
                if adjacentToFlag { patternFlags += 1 }
                flagged.insert(idx)
                usedFlags = true
            }
        }
    }

    private mutating func chord(at idx: Int) throws {
        let count = adjacentMines(idx)
        let nbrs = neighbors(idx)
        let flaggedCount = nbrs.filter { flagged.contains($0) }.count
        let hidden = nbrs.filter { !flagged.contains($0) && !revealed.contains($0) }
        guard count > 0, flaggedCount == count, !hidden.isEmpty else {
            throw GameError.illegalMove
        }
        moveCount += 1
        for n in hidden {
            if mines.contains(n) {
                lost = true
                chordStreak = 0
                revealed.insert(n)
                endTime = Date()
                return
            }
            floodReveal(from: n)
        }
        chordStreak += 1
        if chordStreak > bestChordStreak { bestChordStreak = chordStreak }
        if won { endTime = Date() }
    }

    private mutating func placeMines(avoiding idx: Int) {
        minesPlaced = true
        let forbidden = Set([idx] + neighbors(idx))
        let total = difficulty.width * difficulty.height
        let candidates = (0..<total).filter { !forbidden.contains($0) }
        mines = Set(candidates.shuffled().prefix(difficulty.mines))
    }

    private mutating func floodReveal(from start: Int) {
        var frontier = [start]
        while let idx = frontier.popLast() {
            guard !revealed.contains(idx), !mines.contains(idx) else { continue }
            revealed.insert(idx)
            flagged.remove(idx)
            questioned.remove(idx)
            if adjacentMines(idx) == 0 {
                frontier.append(contentsOf: neighbors(idx).filter { !revealed.contains($0) })
            }
        }
    }

    // MARK: - Status

    var statusText: String {
        if isOver { return resultText ?? "" }
        guard minesPlaced else {
            return "\(difficulty.label) · \(difficulty.mines) 💣 · tap to start"
        }
        let pct = Int(Double(revealed.count) / Double(difficulty.safeCells) * 100)
        let reveals = revealed.count
        let efficiency = moveCount > 0 ? " · \(String(format: "%.1f", Double(reveals) / Double(moveCount)))/click" : ""
        let remaining = difficulty.safeCells - revealed.count
        var tail = ""
        if remaining <= 10 && remaining > 0 { tail = " · 🏁 \(remaining) cell\(remaining == 1 ? "" : "s") to go!" }
        else if chordStreak >= 2 { tail = " · ⚡ chord ×\(chordStreak)" }
        return "\(flagsLeft)/\(difficulty.mines) 💣 · \(pct)% clear\(efficiency) · \(timerString)\(tail)"
    }

    var resultText: String? {
        if won {
            var text = "✓ \(difficulty.label) cleared in \(timerString) · \(moveCount) moves"
            if moveCount > 0 {
                let ratio = Double(difficulty.safeCells) / Double(moveCount)
                if ratio >= 3.0 {
                    let ratioStr = String(format: "%.1f", ratio)
                    text += " · ⚡ \(ratioStr) cells/click"
                }
            }
            if !usedFlags { text += " · 🎯 No flags!" }
            else if flagged.allSatisfy({ mines.contains($0) }) && !flagged.isEmpty {
                text += " · 🎯 Perfect flagging!"
            }
            if bestChordStreak >= 3 { text += " · ⚡ \(bestChordStreak)× chord" }
            if biggestCascade >= 20 { text += " · 💥 \(biggestCascade)-cell open" }
            if firstClearCascade > 3 { text += " · 🎲 first click opened \(firstClearCascade) cells" }
            text += " · Efficiency: \(efficiency)%"
            return text
        }
        if lost {
            let pct = Int(Double(revealed.count - 1) / Double(difficulty.safeCells) * 100)
            var text = "💥 \(difficulty.label) · survived \(elapsedSeconds)s · \(revealed.count - 1) safe (\(pct)%)"
            if pct >= 90 { text += " · 😫 so close!" }
            return text
        }
        return nil
    }
}
