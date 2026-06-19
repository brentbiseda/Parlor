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
    var mustContinueFrom: Point? = nil
    var resigned: Int? = nil
    var movesWithoutCapture = 0
    var lastMove: BoardMove? = nil
    var lastMoveDesc: String? = nil   // human-readable summary of the last move
    var jumpChainDepth = 0
    var longestMultiJump = 0
    /// Count of moves that involved ≥2 captures (multi-jumps).
    var multiJumpCount: Int = 0
    /// Total kings crowned per color this game.
    var kingsCreated = [0, 0]
    /// Tracks largest piece deficit for red (for comeback detection; negative means red was ahead).
    var maxDeficit = 0
    /// Largest piece advantage black ever had over red (for black comeback detection).
    var maxBlackDeficit = 0
    /// Times a king captured another king.
    var kingToKingCaptures: Int = 0
    /// Pieces lost per color (0 = red, 1 = black).
    var piecesLost: [Int] = [0, 0]
    /// Position hash frequency map for 3-fold repetition draw detection.
    var positionHashes: [Int: Int] = [:]

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
        resigned != nil || legalBoardMoves(for: currentPlayer).isEmpty || movesWithoutCapture >= 80 || isThreefoldRepetition
    }

    func legalMoves() -> [Move] {
        guard resigned == nil else { return [] }
        let moves = legalBoardMoves(for: currentPlayer).map { Move.board($0) }
        return moves.isEmpty ? [] : moves + [.resign]
    }

    private func colLabel(_ x: Int) -> String { String(UnicodeScalar(("a" as UnicodeScalar).value + UInt32(x))!) }
    private func cellLabel(_ p: Point) -> String { "\(colLabel(p.x))\(p.y + 1)" }

    mutating func apply(_ move: Move) throws {
        switch move {
        case .resign:
            resigned = currentPlayer
            lastMoveDesc = "\(colorName(currentPlayer)) resigned"
        case .board(let m):
            guard legalBoardMoves(for: currentPlayer).contains(m), var piece = self[m.from] else {
                throw GameError.illegalMove
            }
            let isContinuing = mustContinueFrom != nil
            let isJump = abs(m.to.x - m.from.x) == 2
            if isJump {
                let over = Point(x: (m.from.x + m.to.x) / 2, y: (m.from.y + m.to.y) / 2)
                // Check if this is a king capturing a king
                if let captured = self[over] {
                    if piece.king && captured.king { kingToKingCaptures += 1 }
                    piecesLost[captured.color] += 1
                }
                self[over] = nil
                movesWithoutCapture = 0
                jumpChainDepth = isContinuing ? jumpChainDepth + 1 : 1
            } else {
                movesWithoutCapture += 1
                jumpChainDepth = 0
            }

            let crowningRank = piece.color == 0 ? 7 : 0
            let crowned = !piece.king && m.to.y == crowningRank
            if crowned { piece.king = true; kingsCreated[piece.color] += 1 }
            self[m.from] = nil
            self[m.to] = piece
            lastMove = m

            let kinged = crowned ? " ♛" : ""
            let capture = isJump ? "×" : "–"
            lastMoveDesc = "\(colorName(currentPlayer)) \(cellLabel(m.from))\(capture)\(cellLabel(m.to))\(kinged)"

            if isJump && !crowned && !jumps(from: m.to).isEmpty {
                mustContinueFrom = m.to
            } else {
                if jumpChainDepth > 1 {
                    longestMultiJump = max(longestMultiJump, jumpChainDepth)
                    multiJumpCount += 1
                }
                mustContinueFrom = nil
                currentPlayer = 1 - currentPlayer
                // Track piece deficits for comeback detection (both colors)
                let redPieces = pieceCount(color: 0)
                let blackPieces = pieceCount(color: 1)
                let deficit = blackPieces - redPieces
                if deficit > maxDeficit { maxDeficit = deficit }
                let blackDeficit = redPieces - blackPieces
                if blackDeficit > maxBlackDeficit { maxBlackDeficit = blackDeficit }
                // Track position for 3-fold repetition
                let hash = boardHash()
                positionHashes[hash, default: 0] += 1
            }
        default:
            throw GameError.illegalMove
        }
    }

    func colorName(_ color: Int) -> String { color == 0 ? "Red" : "Black" }

    func pieceCount(color: Int) -> Int { board.compactMap { $0 }.filter { $0.color == color }.count }
    func kingCount(color: Int) -> Int  { board.compactMap { $0 }.filter { $0.color == color && $0.king }.count }

    /// Lightweight board state hash for 3-fold repetition detection.
    func boardHash() -> Int {
        var h = currentPlayer
        for (i, piece) in board.enumerated() {
            if let p = piece {
                h ^= (i + 1) &* (p.color == 0 ? 0x9e3779b9 : 0x6b4c2a1f) &* (p.king ? 0xf0e4d3c2 : 0xa1b2c3d4)
            }
        }
        return h
    }

    var isThreefoldRepetition: Bool {
        positionHashes.values.contains { $0 >= 3 }
    }

    var statusText: String {
        if let text = resultText { return text }
        let r = pieceCount(color: 0); let rk = kingCount(color: 0)
        let b = pieceCount(color: 1); let bk = kingCount(color: 1)
        let pieceInfo = "R:\(r)(K:\(rk)) B:\(b)(K:\(bk))"
        if mustContinueFrom != nil { return "⚡ \(colorName(currentPlayer)) multi-jump · \(pieceInfo)" }
        let moves = legalBoardMoves(for: currentPlayer)
        let captureCount = moves.filter { abs($0.to.x - $0.from.x) == 2 }.count
        let moveInfo: String
        if captureCount > 0 {
            moveInfo = captureCount == 1 ? " — must capture!" : " — must capture (\(captureCount) options)"
        } else {
            moveInfo = " to move"
        }
        let repeatWarn = positionHashes.values.contains { $0 >= 2 } ? " · ⚠️ repeat×2" : ""
        let drawWarn = movesWithoutCapture > 60 ? " · draw in \((80 - movesWithoutCapture) / 2)m\(repeatWarn)" : repeatWarn
        // Material edge (kings count double).
        let rMat = r + rk; let bMat = b + bk
        var edge = ""
        if rMat != bMat { edge = rMat > bMat ? " · R+\(rMat - bMat)" : " · B+\(bMat - rMat)" }
        // Crown warning: pieces on back row that could be captured before crowning
        let lastStr = lastMoveDesc.map { " · \($0)" } ?? ""
        return "\(colorName(currentPlayer))\(moveInfo) · \(pieceInfo)\(edge)\(drawWarn.isEmpty ? "" : drawWarn)\(lastStr)"
    }

    var resultText: String? {
        if let resigned { return "\(colorName(resigned)) resigned — \(colorName(1 - resigned)) wins" }
        if isThreefoldRepetition { return "Draw — position repeated 3 times" }
        if movesWithoutCapture >= 80 { return "Draw — no captures in 40 moves" }
        if legalBoardMoves(for: currentPlayer).isEmpty {
            let winner = colorName(1 - currentPlayer)
            let loser = colorName(currentPlayer)
            let r = pieceCount(color: 0); let b = pieceCount(color: 1)
            // Comeback: winner was down 4+ pieces at some point
            let redWon = (1 - currentPlayer == 0)
            let isComeback = (redWon && maxDeficit >= 4) || (!redWon && maxBlackDeficit >= 4)
            var text = "\(winner) wins \(max(r, b))–\(min(r, b)) · \(loser) has no moves"
            if min(r, b) == 0 { text += " · 💪 total wipeout!" }
            else if max(r, b) - min(r, b) >= 6 { text += " · 👑 dominant win" }
            if multiJumpCount > 0 { text += " · ⚡\(multiJumpCount) multi-jump\(multiJumpCount == 1 ? "" : "s")" }
            if longestMultiJump > 1 { text += " · Max chain: \(longestMultiJump)" }
            let totalKings = kingsCreated[0] + kingsCreated[1]
            if totalKings > 0 { text += " · Kings: R:\(kingsCreated[0]) B:\(kingsCreated[1])" }
            if kingToKingCaptures > 0 { text += " · 👑×\(kingToKingCaptures) king capture\(kingToKingCaptures == 1 ? "" : "s")" }
            if isComeback { text += " · 🔄 comeback from −\(maxDeficit)!" }
            let totalLost = piecesLost[0] + piecesLost[1]
            if totalLost > 0 { text += " · R lost \(piecesLost[0]) · B lost \(piecesLost[1])" }
            return text
        }
        return nil
    }

    func ranking() -> [[Int]] {
        guard isOver else { return [] }
        if let resigned { return [[1 - resigned], [resigned]] }
        if movesWithoutCapture >= 80 || isThreefoldRepetition { return [[0, 1]] }
        return [[1 - currentPlayer], [currentPlayer]]
    }
}
