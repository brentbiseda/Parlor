import Foundation

/// Capsules (Dr. Mario-style): a bottle seeded with viruses, two-color pills
/// falling under the Blocks controls. Four or more same-color cells in a row
/// or column clear; orphaned pill halves fall and chains cascade. Clear every
/// virus to win the level and advance; top out and the game ends.
///
/// Scoring: 25 pts × cells-cleared × chain-depth + 100 × viruses × chain-depth.
/// Level clear bonus: 1000 × level. Chain multiplier escalates with consecutive
/// cascade reactions, rewarding setups.
struct CapsulesGame: GameEngine {
    static let kind = GameKind.capsules
    static let width = 8
    static let height = 16
    /// Viruses added per level; capped at maxViruses.
    static let virusesPerLevel = 4
    static let baseViruses = 4
    static let maxViruses = 40

    // MARK: - Data types

    /// Cell contents: 3 colors × (virus | pill half). Pill halves remember
    /// their partner direction so breaking a pill orphans the other half.
    struct Cell: Codable, Hashable {
        var color: Int          // 0 red, 1 yellow, 2 blue
        var isVirus: Bool
        /// Offset to the attached half (dx, dy), zero when orphaned/single.
        var linkDX: Int = 0
        var linkDY: Int = 0
    }

    struct Pill: Codable, Hashable {
        var colors: [Int]       // [first, second]
        /// Position of the first half; second half sits at +dx/+dy.
        var x: Int
        var y: Int
        /// 0: horizontal (second right), 1: vertical (second above),
        /// 2: horizontal flipped (colors swapped), 3: vertical flipped.
        var rotation: Int

        var cells: [(x: Int, y: Int, color: Int)] {
            let second: (Int, Int)
            switch rotation & 3 {
            case 0, 2: second = (x + 1, y)
            default:   second = (x, y - 1)
            }
            let flipped = (rotation & 3) >= 2
            return [(x, y, colors[flipped ? 1 : 0]),
                    (second.0, second.1, colors[flipped ? 0 : 1])]
        }
    }

    // MARK: - State

    var board: [Cell?] = Array(repeating: nil, count: width * height)
    var current: Pill?
    var nextColors: [Int]
    var score = 0
    var level = 1
    var virusesLeft = 0
    var virusesAtLevelStart = 0
    var pillsUsed = 0
    var pillsAtLevelStart = 0
    var over = false
    var cleared = false
    /// Total levels completed across this session (for stats display).
    var levelsCleared = 0
    /// Deepest chain reaction achieved this session.
    var maxChain = 0
    /// Cumulative virus count cleared across all levels this session.
    var totalVirusesCleared = 0
    /// Fewest pills used to clear any single level this session (0 = unset).
    var bestPillCount = 0
    /// Chain length resolved on the most recent pill placement (for live feedback).
    var lastChain = 0
    /// Levels cleared using fewer pills than there were viruses.
    var efficientClears = 0
    /// Most viruses ever cleared in one chain reaction.
    var mostVirusesInChain = 0
    /// Levels cleared in under 20 pills (speed clears).
    var speedClears = 0
    /// Highest virus count faced at the start of any level this session.
    var hardestLevelViruses = 0
    /// Total chain reactions (each cascade step counts) across session.
    var totalChains: Int = 0
    /// Largest single virus cluster cleared in one step.
    var biggestVirusClear: Int = 0
    /// Pills used at the start of the current level (to compute level duration).
    var levelStartPills: Int = 0
    /// Fewest pills used to clear any single level (best speed measure). 0 = unset.
    var bestLevelClearPills: Int = 0

    init(level: Int = 1) {
        self.level = level
        nextColors = [Int.random(in: 0..<3), Int.random(in: 0..<3)]
        levelStartPills = 0
        seedViruses()
        spawn()
    }

    var currentPlayer: Int { 0 }
    var isOver: Bool { over || cleared }

    func cell(_ x: Int, _ y: Int) -> Cell? {
        guard (0..<Self.width).contains(x), (0..<Self.height).contains(y) else { return nil }
        return board[y * Self.width + x]
    }

    private mutating func setCell(_ x: Int, _ y: Int, _ value: Cell?) {
        guard (0..<Self.width).contains(x), (0..<Self.height).contains(y) else { return }
        board[y * Self.width + x] = value
    }

    // MARK: - Setup

    private mutating func seedViruses() {
        let count = min(Self.baseViruses + level * Self.virusesPerLevel, Self.maxViruses)
        // Top 6 rows are always clear so new pills have room to fall in.
        let openRange = Self.width * 6 ..< Self.width * Self.height
        let open = Array(openRange).shuffled()
        board = Array(repeating: nil, count: Self.width * Self.height)
        for i in 0..<count {
            board[open[i]] = Cell(color: i % 3, isVirus: true)
        }
        virusesLeft = count
        virusesAtLevelStart = count
        hardestLevelViruses = max(hardestLevelViruses, count)
    }

    private func fits(_ pill: Pill) -> Bool {
        for (x, y, _) in pill.cells {
            guard (0..<Self.width).contains(x), y < Self.height else { return false }
            if y >= 0, cell(x, y) != nil { return false }
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

    // MARK: - Moves

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
                if fits(kicked) { current = kicked; return }
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

    // MARK: - Locking & resolution

    private mutating func lock(_ pill: Pill) {
        let cells = pill.cells
        guard cells.allSatisfy({ $0.y >= 0 }) else {
            over = true; current = nil; return
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
            levelsCleared += 1
            let used = pillsUsed - pillsAtLevelStart
            if bestPillCount == 0 || used < bestPillCount { bestPillCount = used }
            let levelPills = pillsUsed - levelStartPills
            if levelPills > 0 {
                bestLevelClearPills = bestLevelClearPills == 0 ? levelPills : min(bestLevelClearPills, levelPills)
            }
            if used > 0 && used < 20 { speedClears += 1 }
            // Efficiency bonus: clearing with fewer pills than viruses is sharp play.
            if used > 0 && used < virusesAtLevelStart {
                efficientClears += 1
                score += (virusesAtLevelStart - used) * 200 * level
            }
        } else if !over {
            spawn()
        }
    }

    /// Advance to the next level, carrying the score forward.
    /// Called externally (e.g., from the view after the clear animation).
    mutating func advanceLevel() {
        guard cleared else { return }
        level += 1
        cleared = false
        over = false
        current = nil
        pillsAtLevelStart = pillsUsed
        levelStartPills = pillsUsed
        nextColors = [Int.random(in: 0..<3), Int.random(in: 0..<3)]
        seedViruses()
        spawn()
    }

    /// Clear 4-in-a-row runs, let orphaned halves fall, repeat for chains.
    private mutating func resolveMatches() {
        var chain = 0
        var virusesThisResolve = 0
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
                if let c = board[index], !c.isVirus, (c.linkDX != 0 || c.linkDY != 0) {
                    let px = index % Self.width + c.linkDX
                    let py = index / Self.width + c.linkDY
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
            totalVirusesCleared += virusesCleared
            virusesThisResolve += virusesCleared
            totalChains += 1
            if virusesCleared > biggestVirusClear { biggestVirusClear = virusesCleared }
            // Chain multiplier: each cascade level escalates the value.
            let multiplier = chain
            score += toClear.count * 25 * multiplier + virusesCleared * 100 * multiplier
            settle()
        }
        if chain > maxChain { maxChain = chain }
        if virusesThisResolve > mostVirusesInChain { mostVirusesInChain = virusesThisResolve }
        lastChain = chain
    }

    /// Indices belonging to any same-color run of 4+.
    /// Uses a sentinel color (nil) at position `inner` to flush the trailing run.
    private func runIndices(horizontal: Bool) -> Set<Int> {
        var result = Set<Int>()
        let outer = horizontal ? Self.height : Self.width
        let inner = horizontal ? Self.width : Self.height
        for o in 0..<outer {
            var runStart = 0
            var runColor: Int? = nil
            // Iterate one past the end (i == inner gives nil) to flush final run.
            for i in 0...inner {
                let color: Int? = i < inner ? cell(horizontal ? i : o, horizontal ? o : i)?.color : nil
                if color != runColor {
                    if runColor != nil, i - runStart >= 4 {
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

    /// Gravity for loose pill halves (viruses never fall; horizontal pairs fall
    /// only when both columns below are open).
    private mutating func settle() {
        var moved = true
        while moved {
            moved = false
            for y in stride(from: Self.height - 2, through: 0, by: -1) {
                for x in 0..<Self.width {
                    guard let c = cell(x, y), !c.isVirus else { continue }
                    if c.linkDX == 1 {
                        // Left half of a horizontal pill — move both or neither.
                        guard let right = cell(x + 1, y),
                              cell(x, y + 1) == nil, cell(x + 1, y + 1) == nil else { continue }
                        setCell(x, y + 1, c); setCell(x + 1, y + 1, right)
                        setCell(x, y, nil);   setCell(x + 1, y, nil)
                        moved = true
                    } else if c.linkDX == -1 {
                        continue   // handled with its left half above
                    } else if c.linkDY == -1 {
                        // Bottom half of a vertical pill — pull top half down too.
                        guard cell(x, y + 1) == nil, let top = cell(x, y - 1) else { continue }
                        setCell(x, y + 1, c); setCell(x, y, top); setCell(x, y - 1, nil)
                        moved = true
                    } else if c.linkDY == 0 {
                        // Orphaned single half.
                        if cell(x, y + 1) == nil {
                            setCell(x, y + 1, c); setCell(x, y, nil)
                            moved = true
                        }
                    }
                    // linkDY == 1 means this is the top half — handled when we reach the bottom half
                }
            }
        }
    }

    // MARK: - Ghost

    /// Where the current pill would land (for drop preview).
    func ghostPill() -> Pill? {
        guard var pill = current else { return nil }
        while fits(pill) { pill.y += 1 }
        pill.y -= 1
        return pill
    }

    // MARK: - Status

    var statusText: String {
        let virusWord = virusesLeft == 1 ? "virus" : "viruses"
        let virusesCleared = virusesAtLevelStart - virusesLeft
        // Show per-color virus counts: R=red, Y=yellow, B=blue.
        let colorNames = ["R", "Y", "B"]
        let colorCounts = (0..<3).map { color in
            let n = board.compactMap { $0 }.filter { $0.isVirus && $0.color == color }.count
            return n > 0 ? "\(colorNames[color]):\(n)" : nil
        }.compactMap { $0 }.joined(separator: " ")
        let colorStr = colorCounts.isEmpty ? "" : " [\(colorCounts)]"
        var tail = ""
        if virusesLeft == 1 { tail = " · 🎯 last virus!" }
        if lastChain >= 2 { tail += " · ⛓️ ×\(lastChain) chain!" }
        return "Level \(level) · \(virusesLeft) \(virusWord)\(colorStr) (\(virusesCleared)/\(virusesAtLevelStart) cleared) · Score \(score)\(tail)"
    }

    var resultText: String? {
        if cleared { return "Level \(level) clear! \(score) pts · \(totalVirusesCleared) viruses total — advancing…" }
        if over {
            var parts = ["Game over — \(score) pts"]
            if levelsCleared > 0 { parts.append("\(levelsCleared) level\(levelsCleared == 1 ? "" : "s")") }
            if maxChain >= 4 { parts.append("🏆 Chain Master ×\(maxChain)!") }
            else if maxChain > 1 { parts.append("best chain ×\(maxChain)") }
            if bestPillCount > 0 { parts.append("fastest clear: \(bestPillCount) pills 🏆") }
            if efficientClears > 0 { parts.append("⚡ \(efficientClears) efficient clear\(efficientClears == 1 ? "" : "s")") }
            if speedClears > 0 { parts.append("🏎️ \(speedClears) speed clear\(speedClears == 1 ? "" : "s")") }
            if mostVirusesInChain >= 3 { parts.append("💥 \(mostVirusesInChain) viruses in one chain") }
            if hardestLevelViruses >= 20 { parts.append("☠️ faced \(hardestLevelViruses) viruses") }
            if totalVirusesCleared > 0 && pillsUsed > 0 {
                let ratio = String(format: "%.1f", Double(pillsUsed) / Double(totalVirusesCleared))
                parts.append("\(ratio) pills/virus")
            }
            if totalChains > 0 { parts.append("\(totalChains) chain reaction\(totalChains == 1 ? "" : "s")") }
            if biggestVirusClear >= 3 { parts.append("🦠 biggest clear: \(biggestVirusClear)") }
            if bestLevelClearPills > 0 { parts.append("⚡ fastest level: \(bestLevelClearPills) pills") }
            return parts.joined(separator: " · ")
        }
        return nil
    }
}
