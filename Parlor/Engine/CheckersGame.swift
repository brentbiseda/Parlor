import Foundation

/// American checkers (English draughts): captures are forced, multi-jumps
/// continue with the same piece, kings move both directions (no flying kings),
/// crowning ends a jump sequence. Seat 0 is red and moves up the board.
struct CheckersGame: GameEngine {
    static let kind = GameKind.checkers

    struct Piece: Codable, Hashable {
        var color: Int      // 0 = red (moves +y), 1 = black (moves -y)
        var king = false
    }

    var board: [Piece?] = Array(repeating: nil, count: 64)
    var currentPlayer = 0
    var mustContinueFrom: Point? = nil   // mid multi-jump
    var resigned: Int? = nil
    var movesWithoutCapture = 0
    var lastMove: BoardMove? = nil

    init() {
        for y in 0..<3 {
            for x in 0..<8 where (x + y) % 2 == 1 {
                self[Point(x: x, y: y)] = Piece(color: 0)
            }
        }
        for y in 5..<8 {
            for x in 0..<8 where (x + y) % 2 == 1 {
                self[Point(x: x, y: y)] = Piece(color: 1)
            }
        }
    }

    subscript(_ p: Point) -> Piece? {
        get { board[p.y * 8 + p.x] }
        set { board[p.y * 8 + p.x] = newValue }
    }

    func onBoard(_ p: Point) -> Bool { (0..<8).contains(p.x) && (0..<8).contains(p.y) }

    func directions(for piece: Piece) -> [(Int, Int)] {
        if piece.king { return [(1, 1), (-1, 1), (1, -1), (-1, -1)] }
        let dy = piece.color == 0 ? 1 : -1
        return [(1, dy), (-1, dy)]
    }

    func jumps(from: Point) -> [BoardMove] {
        guard let piece = self[from] else { return [] }
        var result: [BoardMove] = []
        for (dx, dy) in directions(for: piece) {
            let over = Point(x: from.x + dx, y: from.y + dy)
            let to = Point(x: from.x + 2 * dx, y: from.y + 2 * dy)
            if onBoard(to), self[to] == nil, let mid = onBoard(over) ? self[over] : nil, mid.color != piece.color {
                result.append(BoardMove(from: from, to: to))
            }
        }
        return result
    }

    func steps(from: Point) -> [BoardMove] {
        guard let piece = self[from] else { return [] }
        var result: [BoardMove] = []
        for (dx, dy) in directions(for: piece) {
            let to = Point(x: from.x + dx, y: from.y + dy)
            if onBoard(to), self[to] == nil {
                result.append(BoardMove(from: from, to: to))
            }
        }
        return result
    }

    func legalBoardMoves(for color: Int) -> [BoardMove] {
        if let origin = mustContinueFrom {
            return jumps(from: origin)
        }
        var allJumps: [BoardMove] = []
        var allSteps: [BoardMove] = []
        for i in 0..<64 where board[i]?.color == color {
            let p = Point(x: i % 8, y: i / 8)
            allJumps += jumps(from: p)
            allSteps += steps(from: p)
        }
        return allJumps.isEmpty ? allSteps : allJumps
    }

    var isOver: Bool {
        resigned != nil || legalBoardMoves(for: currentPlayer).isEmpty || movesWithoutCapture >= 80
    }

    func legalMoves() -> [Move] {
        guard resigned == nil else { return [] }
        let moves = legalBoardMoves(for: currentPlayer).map { Move.board($0) }
        return moves.isEmpty ? [] : moves + [.resign]
    }

    mutating func apply(_ move: Move) throws {
        switch move {
        case .resign:
            resigned = currentPlayer
        case .board(let m):
            guard legalBoardMoves(for: currentPlayer).contains(m), var piece = self[m.from] else {
                throw GameError.illegalMove
            }
            let isJump = abs(m.to.x - m.from.x) == 2
            if isJump {
                let over = Point(x: (m.from.x + m.to.x) / 2, y: (m.from.y + m.to.y) / 2)
                self[over] = nil
                movesWithoutCapture = 0
            } else {
                movesWithoutCapture += 1
            }

            let crowningRank = piece.color == 0 ? 7 : 0
            let crowned = !piece.king && m.to.y == crowningRank
            if crowned { piece.king = true }
            self[m.from] = nil
            self[m.to] = piece
            lastMove = m

            // Multi-jump continues with the same piece unless it was just crowned.
            if isJump && !crowned && !jumps(from: m.to).isEmpty {
                mustContinueFrom = m.to
            } else {
                mustContinueFrom = nil
                currentPlayer = 1 - currentPlayer
            }
        default:
            throw GameError.illegalMove
        }
    }

    func colorName(_ color: Int) -> String { color == 0 ? "Red" : "Black" }

    var statusText: String {
        if let text = resultText { return text }
        if mustContinueFrom != nil { return "\(colorName(currentPlayer)) must continue jumping" }
        let mustJump = legalBoardMoves(for: currentPlayer).contains { abs($0.to.x - $0.from.x) == 2 }
        return "\(colorName(currentPlayer)) to move" + (mustJump ? " — capture available" : "")
    }

    var resultText: String? {
        if let resigned { return "\(colorName(resigned)) resigned — \(colorName(1 - resigned)) wins" }
        if movesWithoutCapture >= 80 { return "Draw — no captures in 40 moves" }
        if legalBoardMoves(for: currentPlayer).isEmpty {
            return "\(colorName(1 - currentPlayer)) wins"
        }
        return nil
    }
}
