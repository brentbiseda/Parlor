import Foundation

/// Classic minesweeper on a 9×11 board with 14 mines. The first reveal is
/// always safe (mines are placed after it), zero cells flood-fill open, and
/// the game is won when every safe cell is revealed.
struct MinesweeperGame: GameEngine {
    static let kind = GameKind.minesweeper
    static let width = 9
    static let height = 11
    static let mineCount = 14

    var mines: Set<Int> = []
    var revealed: Set<Int> = []
    var flagged: Set<Int> = []
    var minesPlaced = false
    var lost = false
    var moveCount = 0

    var currentPlayer: Int { 0 }
    var won: Bool {
        minesPlaced && !lost && revealed.count == Self.width * Self.height - Self.mineCount
    }
    var isOver: Bool { lost || won }

    static func index(_ x: Int, _ y: Int) -> Int { y * width + x }

    static func neighbors(_ index: Int) -> [Int] {
        let (x, y) = (index % width, index / width)
        var result: [Int] = []
        for dy in -1...1 {
            for dx in -1...1 where dx != 0 || dy != 0 {
                let (nx, ny) = (x + dx, y + dy)
                if (0..<width).contains(nx), (0..<height).contains(ny) {
                    result.append(Self.index(nx, ny))
                }
            }
        }
        return result
    }

    func adjacentMines(_ index: Int) -> Int {
        Self.neighbors(index).filter { mines.contains($0) }.count
    }

    var flagsLeft: Int { Self.mineCount - flagged.count }

    func legalMoves() -> [Move] {
        guard !isOver else { return [] }
        return (0..<(Self.width * Self.height))
            .filter { !revealed.contains($0) && !flagged.contains($0) }
            .map { .minesweeper(.reveal(x: $0 % Self.width, y: $0 / Self.width)) }
    }

    func isLegal(_ move: Move) -> Bool {
        if case .minesweeper = move { return !isOver }
        return false
    }

    mutating func apply(_ move: Move) throws {
        guard case .minesweeper(let m) = move else { throw GameError.illegalMove }
        switch m {
        case .reveal(let x, let y):
            guard (0..<Self.width).contains(x), (0..<Self.height).contains(y) else {
                throw GameError.illegalMove
            }
            let index = Self.index(x, y)
            guard !flagged.contains(index) else { throw GameError.illegalMove }
            if revealed.contains(index) {
                try chord(at: index)
                return
            }
            if !minesPlaced { placeMines(avoiding: index) }
            moveCount += 1
            if mines.contains(index) {
                lost = true
                revealed.insert(index)
                return
            }
            floodReveal(from: index)
        case .flag(let x, let y):
            guard (0..<Self.width).contains(x), (0..<Self.height).contains(y) else {
                throw GameError.illegalMove
            }
            let index = Self.index(x, y)
            guard !revealed.contains(index) else { throw GameError.illegalMove }
            if flagged.contains(index) {
                flagged.remove(index)
            } else {
                flagged.insert(index)
            }
        }
    }

    /// Chording: re-tap a satisfied number (flags == its count) to pop all
    /// of its unflagged neighbors at once. Wrong flags still lose the game.
    private mutating func chord(at index: Int) throws {
        let count = adjacentMines(index)
        let neighbors = Self.neighbors(index)
        let flaggedCount = neighbors.filter { flagged.contains($0) }.count
        let hidden = neighbors.filter { !flagged.contains($0) && !revealed.contains($0) }
        guard count > 0, flaggedCount == count, !hidden.isEmpty else {
            throw GameError.illegalMove
        }
        moveCount += 1
        for n in hidden {
            if mines.contains(n) {
                lost = true
                revealed.insert(n)
                return
            }
            floodReveal(from: n)
        }
    }

    /// First click and its whole neighborhood stay clear so games open up.
    private mutating func placeMines(avoiding index: Int) {
        minesPlaced = true
        let forbidden = Set([index] + Self.neighbors(index))
        let candidates = (0..<(Self.width * Self.height)).filter { !forbidden.contains($0) }
        mines = Set(candidates.shuffled().prefix(Self.mineCount))
    }

    private mutating func floodReveal(from start: Int) {
        var frontier = [start]
        while let index = frontier.popLast() {
            guard !revealed.contains(index), !mines.contains(index) else { continue }
            revealed.insert(index)
            flagged.remove(index)
            if adjacentMines(index) == 0 {
                frontier.append(contentsOf: Self.neighbors(index).filter { !revealed.contains($0) })
            }
        }
    }

    var statusText: String {
        if isOver { return resultText ?? "" }
        return "\(flagsLeft) mines unflagged · \(revealed.count)/\(Self.width * Self.height - Self.mineCount) clear"
    }

    var resultText: String? {
        if won { return "Field cleared in \(moveCount) reveals!" }
        if lost { return "Boom — that was a mine" }
        return nil
    }
}
