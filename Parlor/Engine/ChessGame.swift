import Foundation

enum ChessPieceKind: String, Codable, CaseIterable, Hashable {
    case pawn, knight, bishop, rook, queen, king
}

struct ChessPiece: Codable, Hashable {
    var color: Int   // 0 = white (seat 0), 1 = black (seat 1)
    var kind: ChessPieceKind

    var glyph: String {
        switch (color, kind) {
        case (0, .king): return "♔"
        case (0, .queen): return "♕"
        case (0, .rook): return "♖"
        case (0, .bishop): return "♗"
        case (0, .knight): return "♘"
        case (0, .pawn): return "♙"
        case (1, .king): return "♚"
        case (1, .queen): return "♛"
        case (1, .rook): return "♜"
        case (1, .bishop): return "♝"
        case (1, .knight): return "♞"
        default: return "♟"
        }
    }
}

/// Full-rules chess: castling, en passant, promotion, check, checkmate,
/// stalemate, the 50-move rule, and basic insufficient-material draws.
/// Board coordinates: (x, y) with y = 0 as white's back rank.
struct ChessGame: GameEngine {
    static let kind = GameKind.chess

    var board: [ChessPiece?] = Array(repeating: nil, count: 64)
    var currentPlayer = 0
    var castlingRights = [true, true, true, true]   // [white K-side, white Q-side, black K-side, black Q-side]
    var enPassantTarget: Point? = nil
    var halfmoveClock = 0
    var moveNumber = 1
    var resigned: Int? = nil
    var lastMove: BoardMove? = nil

    init() {
        let back: [ChessPieceKind] = [.rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook]
        for x in 0..<8 {
            self[Point(x: x, y: 0)] = ChessPiece(color: 0, kind: back[x])
            self[Point(x: x, y: 1)] = ChessPiece(color: 0, kind: .pawn)
            self[Point(x: x, y: 6)] = ChessPiece(color: 1, kind: .pawn)
            self[Point(x: x, y: 7)] = ChessPiece(color: 1, kind: back[x])
        }
    }

    subscript(_ p: Point) -> ChessPiece? {
        get { board[p.y * 8 + p.x] }
        set { board[p.y * 8 + p.x] = newValue }
    }

    func onBoard(_ p: Point) -> Bool { (0..<8).contains(p.x) && (0..<8).contains(p.y) }

    func kingSquare(_ color: Int) -> Point? {
        for i in 0..<64 where board[i]?.color == color && board[i]?.kind == .king {
            return Point(x: i % 8, y: i / 8)
        }
        return nil
    }

    func isAttacked(_ square: Point, by color: Int) -> Bool {
        // Pawns
        let dir = color == 0 ? 1 : -1
        for dx in [-1, 1] {
            let p = Point(x: square.x + dx, y: square.y - dir)
            if onBoard(p), let piece = self[p], piece.color == color, piece.kind == .pawn { return true }
        }
        // Knights
        for (dx, dy) in [(1, 2), (2, 1), (-1, 2), (-2, 1), (1, -2), (2, -1), (-1, -2), (-2, -1)] {
            let p = Point(x: square.x + dx, y: square.y + dy)
            if onBoard(p), let piece = self[p], piece.color == color, piece.kind == .knight { return true }
        }
        // Sliding pieces and king
        let lines: [(Int, Int, [ChessPieceKind])] = [
            (1, 0, [.rook, .queen]), (-1, 0, [.rook, .queen]), (0, 1, [.rook, .queen]), (0, -1, [.rook, .queen]),
            (1, 1, [.bishop, .queen]), (1, -1, [.bishop, .queen]), (-1, 1, [.bishop, .queen]), (-1, -1, [.bishop, .queen]),
        ]
        for (dx, dy, kinds) in lines {
            var p = Point(x: square.x + dx, y: square.y + dy)
            var steps = 0
            while onBoard(p) {
                steps += 1
                if let piece = self[p] {
                    if piece.color == color && (kinds.contains(piece.kind) || (steps == 1 && piece.kind == .king)) {
                        return true
                    }
                    break
                }
                p = Point(x: p.x + dx, y: p.y + dy)
            }
        }
        return false
    }

    func inCheck(_ color: Int) -> Bool {
        guard let king = kingSquare(color) else { return false }
        return isAttacked(king, by: 1 - color)
    }

    /// Pseudo-legal destinations for the piece at `from` (no self-check filter).
    func pseudoMoves(from: Point) -> [BoardMove] {
        guard let piece = self[from] else { return [] }
        var moves: [BoardMove] = []
        let color = piece.color

        func push(_ to: Point) {
            moves.append(BoardMove(from: from, to: to))
        }

        switch piece.kind {
        case .pawn:
            let dir = color == 0 ? 1 : -1
            let startRank = color == 0 ? 1 : 6
            let one = Point(x: from.x, y: from.y + dir)
            if onBoard(one), self[one] == nil {
                push(one)
                let two = Point(x: from.x, y: from.y + 2 * dir)
                if from.y == startRank, self[two] == nil { push(two) }
            }
            for dx in [-1, 1] {
                let to = Point(x: from.x + dx, y: from.y + dir)
                guard onBoard(to) else { continue }
                if let target = self[to], target.color != color { push(to) }
                else if to == enPassantTarget { push(to) }
            }
        case .knight:
            for (dx, dy) in [(1, 2), (2, 1), (-1, 2), (-2, 1), (1, -2), (2, -1), (-1, -2), (-2, -1)] {
                let to = Point(x: from.x + dx, y: from.y + dy)
                if onBoard(to), self[to]?.color != color { push(to) }
            }
        case .king:
            for dx in -1...1 {
                for dy in -1...1 where dx != 0 || dy != 0 {
                    let to = Point(x: from.x + dx, y: from.y + dy)
                    if onBoard(to), self[to]?.color != color { push(to) }
                }
            }
            // Castling
            let rank = color == 0 ? 0 : 7
            if from == Point(x: 4, y: rank), !inCheck(color) {
                let kIdx = color * 2, qIdx = color * 2 + 1
                if castlingRights[kIdx],
                   self[Point(x: 5, y: rank)] == nil, self[Point(x: 6, y: rank)] == nil,
                   self[Point(x: 7, y: rank)]?.kind == .rook, self[Point(x: 7, y: rank)]?.color == color,
                   !isAttacked(Point(x: 5, y: rank), by: 1 - color),
                   !isAttacked(Point(x: 6, y: rank), by: 1 - color) {
                    push(Point(x: 6, y: rank))
                }
                if castlingRights[qIdx],
                   self[Point(x: 3, y: rank)] == nil, self[Point(x: 2, y: rank)] == nil, self[Point(x: 1, y: rank)] == nil,
                   self[Point(x: 0, y: rank)]?.kind == .rook, self[Point(x: 0, y: rank)]?.color == color,
                   !isAttacked(Point(x: 3, y: rank), by: 1 - color),
                   !isAttacked(Point(x: 2, y: rank), by: 1 - color) {
                    push(Point(x: 2, y: rank))
                }
            }
        case .rook, .bishop, .queen:
            var dirs: [(Int, Int)] = []
            if piece.kind != .bishop { dirs += [(1, 0), (-1, 0), (0, 1), (0, -1)] }
            if piece.kind != .rook { dirs += [(1, 1), (1, -1), (-1, 1), (-1, -1)] }
            for (dx, dy) in dirs {
                var to = Point(x: from.x + dx, y: from.y + dy)
                while onBoard(to) {
                    if let target = self[to] {
                        if target.color != color { push(to) }
                        break
                    }
                    push(to)
                    to = Point(x: to.x + dx, y: to.y + dy)
                }
            }
        }

        // Expand pawn promotions.
        if piece.kind == .pawn {
            let promotionRank = color == 0 ? 7 : 0
            moves = moves.flatMap { move -> [BoardMove] in
                guard move.to.y == promotionRank else { return [move] }
                return [ChessPieceKind.queen, .rook, .bishop, .knight].map {
                    BoardMove(from: move.from, to: move.to, promotion: $0)
                }
            }
        }
        return moves
    }

    func legalBoardMoves(for color: Int) -> [BoardMove] {
        var result: [BoardMove] = []
        for i in 0..<64 where board[i]?.color == color {
            let from = Point(x: i % 8, y: i / 8)
            for move in pseudoMoves(from: from) {
                var copy = self
                copy.execute(move)
                if !copy.inCheck(color) { result.append(move) }
            }
        }
        return result
    }

    /// Apply `move` to the board without legality checks or turn bookkeeping.
    mutating func execute(_ move: BoardMove) {
        guard let piece = self[move.from] else { return }
        let color = piece.color

        // En passant capture removes the bypassed pawn.
        if piece.kind == .pawn, move.to == enPassantTarget, self[move.to] == nil {
            self[Point(x: move.to.x, y: move.from.y)] = nil
        }
        // Castling moves the rook too.
        if piece.kind == .king, abs(move.to.x - move.from.x) == 2 {
            let rank = move.from.y
            if move.to.x == 6 {
                self[Point(x: 5, y: rank)] = self[Point(x: 7, y: rank)]
                self[Point(x: 7, y: rank)] = nil
            } else {
                self[Point(x: 3, y: rank)] = self[Point(x: 0, y: rank)]
                self[Point(x: 0, y: rank)] = nil
            }
        }

        let captured = self[move.to] != nil
        self[move.to] = move.promotion.map { ChessPiece(color: color, kind: $0) } ?? piece
        self[move.from] = nil

        // Update castling rights.
        if piece.kind == .king {
            castlingRights[color * 2] = false
            castlingRights[color * 2 + 1] = false
        }
        for (square, idx) in [(Point(x: 7, y: 0), 0), (Point(x: 0, y: 0), 1), (Point(x: 7, y: 7), 2), (Point(x: 0, y: 7), 3)] {
            if move.from == square || move.to == square { castlingRights[idx] = false }
        }

        // En passant target after a double pawn push.
        if piece.kind == .pawn, abs(move.to.y - move.from.y) == 2 {
            enPassantTarget = Point(x: move.from.x, y: (move.from.y + move.to.y) / 2)
        } else {
            enPassantTarget = nil
        }

        halfmoveClock = (piece.kind == .pawn || captured) ? 0 : halfmoveClock + 1
    }

    var isOver: Bool {
        resigned != nil || legalBoardMoves(for: currentPlayer).isEmpty || isDraw
    }

    var isDraw: Bool {
        if halfmoveClock >= 100 { return true }
        // Insufficient material: K vs K, K+minor vs K.
        let pieces = board.compactMap { $0 }.filter { $0.kind != .king }
        if pieces.isEmpty { return true }
        if pieces.count == 1, [.bishop, .knight].contains(pieces[0].kind) { return true }
        return false
    }

    func legalMoves() -> [Move] {
        guard resigned == nil, !isDraw else { return [] }
        return legalBoardMoves(for: currentPlayer).map { .board($0) } + [.resign]
    }

    mutating func apply(_ move: Move) throws {
        switch move {
        case .resign:
            resigned = currentPlayer
        case .board(let m):
            guard legalBoardMoves(for: currentPlayer).contains(m) else { throw GameError.illegalMove }
            execute(m)
            lastMove = m
            if currentPlayer == 1 { moveNumber += 1 }
            currentPlayer = 1 - currentPlayer
        default:
            throw GameError.illegalMove
        }
    }

    func colorName(_ color: Int) -> String { color == 0 ? "White" : "Black" }

    var statusText: String {
        if let text = resultText { return text }
        let check = inCheck(currentPlayer) ? " — check!" : ""
        return "Move \(moveNumber): \(colorName(currentPlayer)) to play\(check)"
    }

    var resultText: String? {
        if let resigned { return "\(colorName(resigned)) resigned — \(colorName(1 - resigned)) wins" }
        if legalBoardMoves(for: currentPlayer).isEmpty {
            if inCheck(currentPlayer) {
                return "Checkmate — \(colorName(1 - currentPlayer)) wins"
            }
            return "Stalemate — draw"
        }
        if isDraw { return "Draw" }
        return nil
    }
}
