import Foundation

/// Go with area (Chinese) scoring and komi 6.5. Suicide is illegal, simple ko
/// is enforced, and two consecutive passes end the game. Capture dead stones
/// before passing — territory counting treats every stone on the board as alive.
/// Seat 0 is black, seat 1 is white.
struct GoGame: GameEngine {
    static let kind = GameKind.go

    var size: Int
    /// 0 empty, 1 black, 2 white.
    var board: [Int]
    var currentPlayer = 0
    var consecutivePasses = 0
    var captures = [0, 0]            // stones captured BY black, white
    var koPoint: Point? = nil
    var resigned: Int? = nil
    var lastPlaced: Point? = nil
    var komi: Double { 6.5 }

    init(size: Int = 9) {
        self.size = [9, 13, 19].contains(size) ? size : 9
        self.board = Array(repeating: 0, count: self.size * self.size)
    }

    func index(_ p: Point) -> Int { p.y * size + p.x }
    func stone(at p: Point) -> Int { board[index(p)] }
    func onBoard(_ p: Point) -> Bool { (0..<size).contains(p.x) && (0..<size).contains(p.y) }

    func neighbors(_ p: Point) -> [Point] {
        [Point(x: p.x + 1, y: p.y), Point(x: p.x - 1, y: p.y),
         Point(x: p.x, y: p.y + 1), Point(x: p.x, y: p.y - 1)].filter(onBoard)
    }

    /// Connected group containing `p` plus whether it has any liberty.
    func group(at p: Point, in board: [Int]) -> (points: Set<Int>, hasLiberty: Bool) {
        let color = board[index(p)]
        guard color != 0 else { return ([], true) }
        var visited: Set<Int> = [index(p)]
        var frontier = [p]
        var hasLiberty = false
        while let current = frontier.popLast() {
            for n in neighbors(current) {
                let i = index(n)
                if board[i] == 0 {
                    hasLiberty = true
                } else if board[i] == color && !visited.contains(i) {
                    visited.insert(i)
                    frontier.append(n)
                }
            }
        }
        return (visited, hasLiberty)
    }

    /// Result of playing `p` for `color`, or nil if illegal (occupied/suicide/ko).
    func tryPlace(_ p: Point, color: Int) -> (board: [Int], captured: Int)? {
        guard stone(at: p) == 0, p != koPoint else { return nil }
        var next = board
        let stoneValue = color + 1
        next[index(p)] = stoneValue

        var captured = 0
        for n in neighbors(p) where next[index(n)] != 0 && next[index(n)] != stoneValue {
            let g = group(at: n, in: next)
            if !g.hasLiberty {
                captured += g.points.count
                for i in g.points { next[i] = 0 }
            }
        }
        // Suicide check after removing captures.
        if !group(at: p, in: next).hasLiberty { return nil }
        return (next, captured)
    }

    var isOver: Bool { resigned != nil || consecutivePasses >= 2 }

    func legalPoints() -> [Point] {
        var result: [Point] = []
        for y in 0..<size {
            for x in 0..<size {
                let p = Point(x: x, y: y)
                if tryPlace(p, color: currentPlayer) != nil { result.append(p) }
            }
        }
        return result
    }

    func legalMoves() -> [Move] {
        guard !isOver else { return [] }
        return legalPoints().map { .place($0) } + [.pass, .resign]
    }

    mutating func apply(_ move: Move) throws {
        switch move {
        case .place(let p):
            guard onBoard(p), let result = tryPlace(p, color: currentPlayer) else { throw GameError.illegalMove }
            // Simple ko: single-stone capture that leaves a single-stone group
            // in atari bans immediate recapture at the vacated point.
            koPoint = nil
            if result.captured == 1 {
                let myGroup = group(at: p, in: result.board)
                if myGroup.points.count == 1 {
                    for n in neighbors(p) where board[index(n)] != 0 && result.board[index(n)] == 0 {
                        koPoint = n
                    }
                }
            }
            captures[currentPlayer] += result.captured
            board = result.board
            lastPlaced = p
            consecutivePasses = 0
            currentPlayer = 1 - currentPlayer
        case .pass:
            consecutivePasses += 1
            koPoint = nil
            lastPlaced = nil
            currentPlayer = 1 - currentPlayer
        case .resign:
            resigned = currentPlayer
        default:
            throw GameError.illegalMove
        }
    }

    /// Area score: stones on the board plus empty regions bordered by one color only.
    func areaScores() -> (black: Double, white: Double) {
        var black = 0, white = 0
        var visited = Set<Int>()
        for i in board.indices {
            switch board[i] {
            case 1: black += 1
            case 2: white += 1
            default:
                guard !visited.contains(i) else { continue }
                // Flood-fill the empty region and find which colors border it.
                var region: Set<Int> = [i]
                var frontier = [Point(x: i % size, y: i / size)]
                var borders = Set<Int>()
                while let p = frontier.popLast() {
                    for n in neighbors(p) {
                        let ni = index(n)
                        if board[ni] == 0 {
                            if region.insert(ni).inserted { frontier.append(n) }
                        } else {
                            borders.insert(board[ni])
                        }
                    }
                }
                visited.formUnion(region)
                if borders == [1] { black += region.count }
                if borders == [2] { white += region.count }
            }
        }
        return (Double(black), Double(white) + komi)
    }

    func colorName(_ color: Int) -> String { color == 0 ? "Black" : "White" }

    var statusText: String {
        if let text = resultText { return text }
        var text = "\(colorName(currentPlayer)) to play"
        if consecutivePasses == 1 { text += " · opponent passed" }
        if captures[0] + captures[1] > 0 { text += " · captures \(captures[0])–\(captures[1])" }
        return text
    }

    var resultText: String? {
        if let resigned { return "\(colorName(resigned)) resigned — \(colorName(1 - resigned)) wins" }
        guard consecutivePasses >= 2 else { return nil }
        let (black, white) = areaScores()
        if black == white { return "Draw at \(black)" }
        let winner = black > white ? "Black" : "White"
        return String(format: "%@ wins %.1f – %.1f (komi %.1f)", winner, max(black, white), min(black, white), komi)
    }
}
