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
    var biggestCapture = 0           // most stones taken in a single move
    var longestCaptureRun = 0        // consecutive turns with a capture
    private var currentCaptureRun = 0
    /// Total passes per player this game.
    var passCount: [Int] = [0, 0]
    /// Largest connected group of stones placed by either player.
    var largestGroup: Int = 0
    var koPoint: Point? = nil
    var resigned: Int? = nil
    var lastPlaced: Point? = nil
    var moveCount = 0
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

    /// Count liberties for the group at `p`. Returns 0 if the point is empty.
    func libertyCount(at p: Point) -> Int {
        let color = stone(at: p)
        guard color != 0 else { return 0 }
        var visited: Set<Int> = [index(p)]
        var frontier = [p]
        var liberties: Set<Int> = []
        while let current = frontier.popLast() {
            for n in neighbors(current) {
                let i = index(n)
                if board[i] == 0 {
                    liberties.insert(i)
                } else if board[i] == color && !visited.contains(i) {
                    visited.insert(i)
                    frontier.append(n)
                }
            }
        }
        return liberties.count
    }

    /// Points of stones (of either color) whose group is in atari (1 liberty).
    var atariPoints: Set<Point> {
        var result: Set<Point> = []
        var checked: Set<Int> = []
        for y in 0..<size {
            for x in 0..<size {
                let p = Point(x: x, y: y)
                let i = index(p)
                guard board[i] != 0, !checked.contains(i) else { continue }
                if libertyCount(at: p) == 1 {
                    // Mark all stones in this group
                    var frontier = [p]
                    var visited: Set<Int> = [i]
                    let color = board[i]
                    while let cur = frontier.popLast() {
                        result.insert(cur)
                        checked.insert(index(cur))
                        for n in neighbors(cur) {
                            let ni = index(n)
                            if board[ni] == color && !visited.contains(ni) {
                                visited.insert(ni)
                                frontier.append(n)
                            }
                        }
                    }
                } else {
                    checked.insert(i)
                }
            }
        }
        return result
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
            if result.captured > biggestCapture { biggestCapture = result.captured }
            if result.captured > 0 {
                currentCaptureRun += 1
                if currentCaptureRun > longestCaptureRun { longestCaptureRun = currentCaptureRun }
            } else {
                currentCaptureRun = 0
            }
            board = result.board
            lastPlaced = p
            consecutivePasses = 0
            moveCount += 1
            // Track largest group
            let grp = group(at: p, in: board)
            if grp.points.count > largestGroup { largestGroup = grp.points.count }
            currentPlayer = 1 - currentPlayer
        case .pass:
            passCount[currentPlayer] += 1
            currentCaptureRun = 0
            consecutivePasses += 1
            koPoint = nil
            lastPlaced = nil
            moveCount += 1
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

    /// Count of black stones currently on the board.
    var blackStones: Int { board.filter { $0 == 1 }.count }
    /// Count of white stones currently on the board.
    var whiteStones: Int { board.filter { $0 == 2 }.count }

    var statusText: String {
        if let text = resultText { return text }
        let moveLabel = moveCount > 0 ? " #\(moveCount)" : ""
        var text = "\(colorName(currentPlayer))\(moveLabel) to play"
        if consecutivePasses == 1 { text += " · 1 pass → scoring soon" }
        // Ko warning: the ko point is a forbidden position until broken
        if koPoint != nil { text += " · ⛔ Ko" }
        let stoneTotal = blackStones + whiteStones
        if stoneTotal > 0 { text += " · ●\(blackStones) ○\(whiteStones)" }
        if captures[0] + captures[1] > 0 { text += " · cap B\(captures[0])–W\(captures[1])" }
        let atari = atariPoints
        if !atari.isEmpty { text += " · ⚠️ atari(\(atari.count))" }
        let (b, w) = areaScores()
        text += " · est. B\(Int(b.rounded()))–W\(String(format: "%.1f", w))"
        let margin = b - w
        if abs(margin) >= 0.5 {
            let leader = margin > 0 ? "B" : "W"
            text += " (\(leader)+\(String(format: "%.1f", abs(margin))))"
        } else {
            text += " (even)"
        }
        return text
    }

    var resultText: String? {
        var captureNote = captures[0] + captures[1] > 0 ? " · B cap \(captures[0]) W cap \(captures[1])" : ""
        if biggestCapture > 1 { captureNote += " · Max capture: \(biggestCapture) stones" }
        if longestCaptureRun >= 3 { captureNote += " · 🔗 \(longestCaptureRun)-turn capture run" }
        let moveNote = " · \(moveCount) moves"
        let totalPasses = passCount[0] + passCount[1]
        let passNote = totalPasses > 0 ? " · \(totalPasses) passes" : ""
        let groupNote = largestGroup >= 5 ? " · Largest group: \(largestGroup) stones" : ""
        if let resigned { return "\(colorName(resigned)) resigned — \(colorName(1 - resigned)) wins\(moveNote)\(captureNote)\(passNote)\(groupNote)" }
        guard consecutivePasses >= 2 else { return nil }
        let (black, white) = areaScores()
        if black == white { return "Draw at \(black)\(moveNote)\(captureNote)\(passNote)\(groupNote)" }
        let winner = black > white ? "Black" : "White"
        return String(format: "%@ wins %.1f – %.1f (komi %.1f)%@%@%@%@", winner, max(black, white), min(black, white), komi, moveNote, captureNote, passNote, groupNote)
    }

    func ranking() -> [[Int]] {
        guard isOver else { return [] }
        if let resigned { return [[1 - resigned], [resigned]] }
        let (black, white) = areaScores()
        if black == white { return [[0, 1]] }
        return black > white ? [[0], [1]] : [[1], [0]]
    }
}
