import Foundation

/// Falling blocks on a 10×20 well. The view drives gravity by submitting
/// `.tetris(.tick)` on a timer that speeds up with the level; everything
/// else (collision, rotation kicks, line clears, scoring, 7-bag) lives here.
struct TetrisGame: GameEngine {
    static let kind = GameKind.tetris
    static let width = 10
    static let height = 20

    enum PieceKind: Int, Codable, CaseIterable {
        case i, o, t, s, z, j, l

        /// Cell offsets at rotation 0, in a box of `boxSize` (y grows down).
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
        /// 1-based color index stored in the board (0 = empty).
        var colorIndex: Int { rawValue + 1 }
    }

    struct Piece: Codable, Hashable {
        var kind: PieceKind
        var rotation: Int   // 0–3 clockwise quarter turns
        var x: Int          // box origin column
        var y: Int          // box origin row

        func cells() -> [(x: Int, y: Int)] {
            let size = kind.boxSize
            return kind.baseCells.map { cell in
                var (cx, cy) = cell
                for _ in 0..<(rotation & 3) {
                    (cx, cy) = (size - 1 - cy, cx)   // clockwise in the box
                }
                return (x + cx, y + cy)
            }
        }
    }

    /// Row-major, row 0 at the top; 0 empty, otherwise a piece color index.
    var board = [Int](repeating: 0, count: width * height)
    var current: Piece?
    var nextKind: PieceKind
    var bag: [PieceKind]
    var score = 0
    var lines = 0
    var piecesPlaced = 0
    var over = false

    var level: Int { lines / 10 + 1 }

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

    private mutating func lock(_ piece: Piece) {
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
        guard cleared > 0 else { return }
        let empty = [Int](repeating: 0, count: Self.width)
        board = Array(repeating: empty, count: cleared).flatMap { $0 } + kept.flatMap { $0 }
        score += [0, 100, 300, 500, 800][cleared] * level
        lines += cleared
    }

    func legalMoves() -> [Move] {
        over ? [] : [.tetris(.tick)]
    }

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
        case .right:
            piece.x += 1
            if fits(piece) { current = piece }
        case .rotate:
            piece.rotation += 1
            // Simple wall kicks: try in place, then a step left/right (two for I).
            for kick in [0, -1, 1, -2, 2] {
                var kicked = piece
                kicked.x += kick
                if fits(kicked) {
                    current = kicked
                    return
                }
            }
        case .softDrop, .tick:
            piece.y += 1
            if fits(piece) {
                current = piece
                if m == .softDrop { score += 1 }
            } else {
                piece.y -= 1
                lock(piece)
            }
        case .hardDrop:
            var dropped = piece
            while fits(dropped) { dropped.y += 1 }
            dropped.y -= 1
            score += 2 * (dropped.y - piece.y)
            lock(dropped)
        }
    }

    /// Where the current piece would land — drawn as a ghost outline.
    func ghostPiece() -> Piece? {
        guard var piece = current else { return nil }
        while fits(piece) { piece.y += 1 }
        piece.y -= 1
        return piece
    }

    var statusText: String {
        "Score \(score) · Lines \(lines) · Level \(level)"
    }

    var resultText: String? {
        over ? "Game over — \(score) points · \(lines) lines" : nil
    }
}
