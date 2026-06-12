import Foundation

/// Capsules (Dr. Mario-style): a bottle seeded with viruses, two-color pills
/// falling under the Blocks controls. Four or more same-color cells in a row
/// or column clear; orphaned pill halves fall and chains cascade. Clear every
/// virus to win the level; top out and the game ends.
struct CapsulesGame: GameEngine {
    static let kind = GameKind.capsules
    static let width = 8
    static let height = 16

    /// Cell contents: 3 colors × (virus | pill half). Pill halves remember
    /// their partner direction so breaking a pill orphans the other half.
    struct Cell: Codable, Hashable {
        var color: Int          // 0 red, 1 yellow, 2 blue
        var isVirus: Bool
        /// Offset to the attached half (dx, dy), zero when single.
        var linkDX: Int = 0
        var linkDY: Int = 0
    }

    struct Pill: Codable, Hashable {
        var colors: [Int]       // [first, second]
        /// Position of the first half; second half sits at +dx/+dy.
        var x: Int
        var y: Int
        /// 0: horizontal (second right), 1: vertical (second above),
        /// 2: horizontal flipped, 3: vertical flipped.
        var rotation: Int

        var cells: [(x: Int, y: Int, color: Int)] {
            let second: (Int, Int)
            switch rotation & 3 {
            case 0: second = (x + 1, y)
            case 1: second = (x, y - 1)
            case 2: second = (x + 1, y)
            default: second = (x, y - 1)
            }
            let flipped = (rotation & 3) >= 2
            return [(x, y, colors[flipped ? 1 : 0]),
                    (second.0, second.1, colors[flipped ? 0 : 1])]
        }
    }

    var board: [Cell?] = Array(repeating: nil, count: width * height)
    var current: Pill?
    var nextColors: [Int]
    var score = 0
    var level = 1
    var virusesLeft = 0
    var pillsUsed = 0
    var over = false
    var cleared = false

    init(level: Int = 1) {
        self.level = level
        nextColors = [Int.random(in: 0..<3), Int.random(in: 0..<3)]
        seedViruses()
        spawn()
    }

    var currentPlayer: Int { 0 }
    var isOver: Bool { over || cleared }

    func cell(_ x: Int, _ y: Int) -> Cell? { board[y * Self.width + x] }

    private mutating func setCell(_ x: Int, _ y: Int, _ value: Cell?) {
        board[y * Self.width + x] = value
    }

    private mutating func seedViruses() {
        let count = min(4 + level * 4, 40)
        var open = Array(0..<(Self.width * (Self.height - 6))).shuffled()
        for i in 0..<count {
            let slot = open[i] + Self.width * 6   // keep the top rows clear
            board[slot] = Cell(color: i % 3, isVirus: true)
        }
        virusesLeft = count
    }

    private func fits(_ pill: Pill) -> Bool {
        for (x, y, _) in pill.cells {
            guard (0..<Self.width).contains(x), y < Self.height else { return false }
            if y >= 0 && cell(x, y) != nil { return false }
        }
        return true
    }

    private mutating func spawn() {
        let pill = Pill(colors: nextColors, x: Self.width / 2 - 1, y: 0, rotation: 0)
        nextColors = [Int.random(in: 0..<3), Int.random(in: 0..<3)]
        if fits(pill) {
            current = pill
        } else {
            over = true
            current = nil
        }
    }

    func legalMoves() -> [Move] {
        isOver ? [] : [.capsules(.tick)]
    }

    func isLegal(_ move: Move) -> Bool {
        if case .capsules = move { return !isOver }
        return false
    }

    mutating func apply(_ move: Move) throws {
        guard case .capsules(let m) = move, var pill = current else {
            if case .capsules = move, isOver { throw GameError.gameOver }
            throw GameError.illegalMove
        }
        switch m {
        case .left:
            pill.x -= 1
            if fits(pill) { current = pill }
        case .right:
            pill.x += 1
            if fits(pill) { current = pill }
        case .rotate:
            pill.rotation += 1
            for kick in [0, -1, 1] {
                var kicked = pill
                kicked.x += kick
                if fits(kicked) {
                    current = kicked
                    return
                }
            }
        case .softDrop, .tick:
            pill.y += 1
            if fits(pill) {
                current = pill
            } else {
                pill.y -= 1
                lock(pill)
            }
        case .hardDrop:
            while fits(pill) { pill.y += 1 }
            pill.y -= 1
            lock(pill)
        }
    }

    private mutating func lock(_ pill: Pill) {
        let cells = pill.cells
        guard cells.allSatisfy({ $0.y >= 0 }) else {
            over = true
            current = nil
            return
        }
        let (a, b) = (cells[0], cells[1])
        setCell(a.x, a.y, Cell(color: a.color, isVirus: false, linkDX: b.x - a.x, linkDY: b.y - a.y))
        setCell(b.x, b.y, Cell(color: b.color, isVirus: false, linkDX: a.x - b.x, linkDY: a.y - b.y))
        pillsUsed += 1
        current = nil
        resolveMatches()
        if virusesLeft == 0 {
            cleared = true
            score += 1000 * level
        } else if !over {
            spawn()
        }
    }

    /// Clear 4-in-a-row runs, let orphaned halves fall, repeat for chains.
    private mutating func resolveMatches() {
        var chain = 0
        while true {
            var toClear = Set<Int>()
            toClear.formUnion(runIndices(horizontal: true))
            toClear.formUnion(runIndices(horizontal: false))
            guard !toClear.isEmpty else { break }
            chain += 1
            var virusesCleared = 0
            for index in toClear {
                if board[index]?.isVirus == true { virusesCleared += 1 }
                // Detach the partner of any cleared pill half.
                if let cell = board[index], !cell.isVirus, cell.linkDX != 0 || cell.linkDY != 0 {
                    let px = index % Self.width + cell.linkDX
                    let py = index / Self.width + cell.linkDY
                    if (0..<Self.width).contains(px), (0..<Self.height).contains(py),
                       var partner = board[py * Self.width + px] {
                        partner.linkDX = 0
                        partner.linkDY = 0
                        board[py * Self.width + px] = partner
                    }
                }
                board[index] = nil
            }
            virusesLeft -= virusesCleared
            score += toClear.count * 25 * chain + virusesCleared * 100 * chain
            settle()
        }
    }

    /// Indices belonging to any same-color run of 4+.
    private func runIndices(horizontal: Bool) -> Set<Int> {
        var result = Set<Int>()
        let outer = horizontal ? Self.height : Self.width
        let inner = horizontal ? Self.width : Self.height
        for o in 0..<outer {
            var runStart = 0
            var runColor: Int? = nil
            for i in 0...inner {
                let (x, y) = horizontal ? (i, o) : (o, i)
                let color = i < inner ? cell(x, y)?.color : nil
                if color != runColor {
                    if let runColor, runColor >= 0, i - runStart >= 4 {
                        for j in runStart..<i {
                            let (jx, jy) = horizontal ? (j, o) : (o, j)
                            result.insert(jy * Self.width + jx)
                        }
                    }
                    runStart = i
                    runColor = color
                }
            }
        }
        return result
    }

    /// Gravity for loose pill halves (viruses never fall; linked horizontal
    /// pairs fall only when both columns are open).
    private mutating func settle() {
        var moved = true
        while moved {
            moved = false
            for y in stride(from: Self.height - 2, through: 0, by: -1) {
                for x in 0..<Self.width {
                    guard let c = cell(x, y), !c.isVirus else { continue }
                    if c.linkDX == 1 {
                        // Left half of a horizontal pill: move both or neither.
                        guard let right = cell(x + 1, y), cell(x, y + 1) == nil,
                              x + 1 < Self.width, cell(x + 1, y + 1) == nil else { continue }
                        setCell(x, y + 1, c)
                        setCell(x + 1, y + 1, right)
                        setCell(x, y, nil)
                        setCell(x + 1, y, nil)
                        moved = true
                    } else if c.linkDX == -1 {
                        continue   // handled with its left half
                    } else if c.linkDY != 0 {
                        // Vertical pill: bottom half drives the fall.
                        if c.linkDY == -1 {   // partner above
                            guard cell(x, y + 1) == nil, y >= 1, let top = cell(x, y - 1) else { continue }
                            setCell(x, y + 1, c)
                            setCell(x, y, top)
                            setCell(x, y - 1, nil)
                            moved = true
                        }
                    } else {
                        if cell(x, y + 1) == nil {
                            setCell(x, y + 1, c)
                            setCell(x, y, nil)
                            moved = true
                        }
                    }
                }
            }
        }
    }

    /// Where the current pill would land.
    func ghostPill() -> Pill? {
        guard var pill = current else { return nil }
        while fits(pill) { pill.y += 1 }
        pill.y -= 1
        return pill
    }

    var statusText: String {
        "Score \(score) · \(virusesLeft) viruses left · Level \(level)"
    }

    var resultText: String? {
        if cleared { return "Bottle cleared! \(score) points" }
        if over { return "The bottle overflowed — \(score) points" }
        return nil
    }
}
