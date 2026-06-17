import Foundation

/// Falling blocks on a 10×20 well. The view drives gravity by submitting
/// `.tetris(.tick)` on a timer that speeds up with the level; everything
/// else (collision, rotation kicks, line clears, scoring, 7-bag) lives here.
///
/// Scoring:
///   Single 100×level, Double 300×level, Triple 500×level, Tetris 800×level
///   Back-to-back Tetris: 1200×level
///   Combo bonus: 50×combo×level added per consecutive clear
///   Soft drop: 1 pt per row   Hard drop: 2 pts per row
struct TetrisGame: GameEngine {
    static let kind = GameKind.tetris
    static let width = 10
    static let height = 20
    static let lineClearScore = [0, 100, 300, 500, 800]
    static let softDropScore = 1
    static let hardDropScore = 2
    static let backToBackBonus = 400   // added on top of 800 for consecutive Tetrises
    static let comboBase = 50          // × combo count × level

    enum PieceKind: Int, Codable, CaseIterable {
        case i, o, t, s, z, j, l

        var baseCells: [(x: Int, y: Int)] {
            switch self {
            case .i: return [(0, 1), (1, 1), (2, 1), (3, 1)]
            case .o: return [(0, 0), (1, 0), (0, 1), (1, 1)]
            case .t: return [(1, 0), (0, 1), (1, 1), (2, 1)]
            case .s: return [(1, 0), (2, 0), (0, 1), (1, 1)]
            case .z: return [(0, 0), (1, 0), (1, 1), (2, 1)]
            case .j: return [(0, 0), (0, 1), (1, 1), (2, 1)]
            case .l: return [(2, 0), (0, 1), (1, 1), (2, 1)]
            }
        }

        var boxSize: Int { self == .i ? 4 : (self == .o ? 2 : 3) }
        var colorIndex: Int { rawValue + 1 }
    }

    struct Piece: Codable, Hashable {
        var kind: PieceKind
        var rotation: Int
        var x: Int
        var y: Int

        func cells() -> [(x: Int, y: Int)] {
            let size = kind.boxSize
            return kind.baseCells.map { cell in
                var (cx, cy) = cell
                for _ in 0..<(rotation & 3) {
                    (cx, cy) = (size - 1 - cy, cx)
                }
                return (x + cx, y + cy)
            }
        }
    }

    var board = [Int](repeating: 0, count: width * height)
    var current: Piece?
    var nextKind: PieceKind
    var bag: [PieceKind]
    var score = 0
    var lines = 0
    var piecesPlaced = 0
    var over = false
    var combo = 0                  // consecutive line-clearing drops
    var maxCombo = 0               // peak combo reached this game
    var lastClear = 0              // lines cleared on the last drop
    var backToBack = false         // previous clear was a Tetris
    var lastClearLabel: String? = nil  // "TETRIS", "TRIPLE", etc. for UI
    var lastWasRotation = false    // for T-spin detection
    var pendingTSpin = false       // set in lock(), consumed by clearLines()
    var tSpinCount = 0             // lifetime T-spins this game
    var tetrisCount = 0           // lifetime 4-line clears this game
    var perfectClears = 0         // times the board was emptied by a clear
    var bestDropScore = 0         // highest points earned on a single line clear
    var singleCount = 0           // 1-line clears
    var doubleCount = 0           // 2-line clears
    var tripleCount = 0           // 3-line clears
    var maxLevel: Int = 1         // highest level reached this game
    var survivalTicks: Int = 0    // total ticks survived (game length indicator)

    var level: Int { lines / 10 + 1 }

    /// Qualitative gravity speed for the current level (drives status + UI bar).
    var speedLabel: String {
        switch level {
        case 1...3: return "slow"
        case 4...6: return "medium"
        case 7...9: return "fast"
        case 10...12: return "very fast"
        default: return "blazing"
        }
    }

    /// Height of the tallest column (0 = empty well, 20 = full).
    var stackHeight: Int {
        for row in 0..<Self.height {
            let cells = board[(row * Self.width)..<((row + 1) * Self.width)]
            if cells.contains(where: { $0 != 0 }) { return Self.height - row }
        }
        return 0
    }

    init() {
        bag = PieceKind.allCases.shuffled()
        nextKind = bag.removeFirst()
        spawn()
    }

    var currentPlayer: Int { 0 }
    var isOver: Bool { over }

    func cell(_ x: Int, _ y: Int) -> Int { board[y * Self.width + x] }

    private func fits(_ piece: Piece) -> Bool {
        for (x, y) in piece.cells() {
            guard (0..<Self.width).contains(x), y < Self.height else { return false }
            if y >= 0 && cell(x, y) != 0 { return false }
        }
        return true
    }

    private mutating func spawn() {
        var piece = Piece(kind: nextKind, rotation: 0, x: (Self.width - nextKind.boxSize) / 2, y: -1)
        if bag.isEmpty { bag = PieceKind.allCases.shuffled() }
        nextKind = bag.removeFirst()
        if !fits(piece) {
            piece.y -= 1
            if !fits(piece) {
                over = true
                current = nil
                return
            }
        }
        current = piece
    }

    private func isTSpin(_ piece: Piece) -> Bool {
        guard piece.kind == .t, lastWasRotation else { return false }
        let corners = [(0, 0), (2, 0), (0, 2), (2, 2)]
        let occupied = corners.filter { dx, dy in
            let (cx, cy) = (piece.x + dx, piece.y + dy)
            if cx < 0 || cx >= Self.width || cy >= Self.height { return true }
            return cy >= 0 && cell(cx, cy) != 0
        }.count
        return occupied >= 3
    }

    private mutating func lock(_ piece: Piece) {
        pendingTSpin = isTSpin(piece)
        if pendingTSpin { tSpinCount += 1 }
        for (x, y) in piece.cells() where y >= 0 {
            board[y * Self.width + x] = piece.kind.colorIndex
        }
        if piece.cells().contains(where: { $0.y < 0 }) { over = true }
        clearLines()
        piecesPlaced += 1
        current = nil
        if !over { spawn() }
    }

    private mutating func clearLines() {
        var kept: [[Int]] = []
        var cleared = 0
        for row in 0..<Self.height {
            let cells = Array(board[(row * Self.width)..<((row + 1) * Self.width)])
            if cells.allSatisfy({ $0 != 0 }) {
                cleared += 1
            } else {
                kept.append(cells)
            }
        }
        lastClear = cleared
        guard cleared > 0 else {
            combo = 0
            lastClearLabel = nil
            return
        }

        let empty = [Int](repeating: 0, count: Self.width)
        board = Array(repeating: empty, count: cleared).flatMap { $0 } + kept.flatMap { $0 }

        // Base score; T-spins double the line value.
        var pts = Self.lineClearScore[cleared] * level
        let isTetris = cleared == 4
        if isTetris { tetrisCount += 1 }
        switch cleared {
        case 1: singleCount += 1
        case 2: doubleCount += 1
        case 3: tripleCount += 1
        default: break
        }
        if pendingTSpin && cleared > 0 {
            pts += Self.lineClearScore[cleared] * level   // T-spin doubles the score
            let labels = ["", "T-SPIN SINGLE", "T-SPIN DOUBLE", "T-SPIN TRIPLE"]
            lastClearLabel = cleared <= 3 ? labels[cleared] : "T-SPIN"
            backToBack = false
        } else if isTetris && backToBack {
            pts += Self.backToBackBonus * level
            lastClearLabel = "TETRIS B2B"
        } else {
            lastClearLabel = ["", "SINGLE", "DOUBLE", "TRIPLE", "TETRIS"][cleared]
        }
        if !pendingTSpin { backToBack = isTetris }
        pendingTSpin = false

        // Combo bonus.
        combo += 1
        if combo > maxCombo { maxCombo = combo }
        if combo > 1 { pts += Self.comboBase * (combo - 1) * level }

        // Perfect clear: board completely empty after this clear — big bonus.
        if board.allSatisfy({ $0 == 0 }) {
            perfectClears += 1
            pts += 1000 * level
            lastClearLabel = "PERFECT CLEAR"
        }

        if pts > bestDropScore { bestDropScore = pts }
        score += pts
        lines += cleared
    }

    func legalMoves() -> [Move] { over ? [] : [.tetris(.tick)] }

    func isLegal(_ move: Move) -> Bool {
        if case .tetris = move { return !over }
        return false
    }

    mutating func apply(_ move: Move) throws {
        guard case .tetris(let m) = move, var piece = current else {
            if case .tetris = move, over { throw GameError.gameOver }
            throw GameError.illegalMove
        }
        switch m {
        case .left:
            piece.x -= 1
            if fits(piece) { current = piece }
            lastWasRotation = false
        case .right:
            piece.x += 1
            if fits(piece) { current = piece }
            lastWasRotation = false
        case .rotate:
            piece.rotation += 1
            for kick in [0, -1, 1, -2, 2] {
                var kicked = piece
                kicked.x += kick
                if fits(kicked) { current = kicked; lastWasRotation = true; return }
            }
        case .softDrop, .tick:
            piece.y += 1
            if fits(piece) {
                current = piece
                if m == .softDrop { score += Self.softDropScore }
            } else {
                piece.y -= 1
                lock(piece)
            }
            survivalTicks += 1
            if level > maxLevel { maxLevel = level }
            lastWasRotation = false
        case .hardDrop:
            var dropped = piece
            while fits(dropped) { dropped.y += 1 }
            dropped.y -= 1
            score += Self.hardDropScore * max(0, dropped.y - piece.y)
            lock(dropped)
            lastWasRotation = false
        }
    }

    func ghostPiece() -> Piece? {
        guard var piece = current else { return nil }
        while fits(piece) { piece.y += 1 }
        piece.y -= 1
        return piece
    }

    var statusText: String {
        let nextLevel = level * 10
        let toNext = nextLevel - lines
        let urgency = toNext <= 2 ? " 🔜" : ""
        var text = "Score \(score) · L\(level) · \(lines) lines (+\(toNext)→L\(level + 1)\(urgency))"
        if combo > 1 { text += " · combo ×\(combo)" }
        if backToBack { text += " · B2B" }
        if level >= 4 { text += " · \(speedLabel)" }
        if stackHeight >= 16 { text += " · ⚠️ DANGER" }
        return text
    }

    var resultText: String? {
        guard over else { return nil }
        var text = "Game over — \(score) pts · \(lines) lines · L\(level)"
        if tSpinCount > 0 { text += " · 🌀 \(tSpinCount) T-spin\(tSpinCount == 1 ? "" : "s")" }
        if tetrisCount > 0 { text += " · 🟦 \(tetrisCount) Tetris\(tetrisCount == 1 ? "" : "es")" }
        if perfectClears > 0 { text += " · 💎 \(perfectClears) perfect clear\(perfectClears == 1 ? "" : "s")" }
        if maxCombo >= 3 { text += " · 🔥 \(maxCombo)× combo" }
        if bestDropScore >= 1200 { text += " · 💥 best drop \(bestDropScore)" }
        // Line-type breakdown
        var clearTypes: [String] = []
        if singleCount > 0 { clearTypes.append("1s×\(singleCount)") }
        if doubleCount > 0 { clearTypes.append("2s×\(doubleCount)") }
        if tripleCount > 0 { clearTypes.append("3s×\(tripleCount)") }
        if tetrisCount > 0 { clearTypes.append("T×\(tetrisCount)") }
        if !clearTypes.isEmpty { text += " · Lines: \(clearTypes.joined(separator: " "))" }
        if piecesPlaced > 0 && lines > 0 {
            let ppl = String(format: "%.1f", Double(piecesPlaced) / Double(lines))
            text += " · \(ppl) pieces/line"
        }
        if maxLevel > 1 { text += " · reached level \(maxLevel)" }
        if survivalTicks > 200 { text += " · survived \(survivalTicks) ticks" }
        return text
    }
}
