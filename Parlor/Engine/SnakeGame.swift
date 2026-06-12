import Foundation

/// Nibbles: steer the snake to the food, grow three segments per bite, and
/// don't hit the border, the level's walls, or yourself. Every six bites
/// advances the level — new wall pattern, more points per bite, and the
/// view speeds the clock. Three lives.
struct SnakeGame: GameEngine {
    static let kind = GameKind.snake
    static let width = 15
    static let height = 22
    static let bitesPerLevel = 6

    /// Body cells, head first.
    var body: [Int] = []
    var direction: GridDirection = .right
    /// Steering applied on the next tick (prevents double-turn reversals).
    var pendingDirection: GridDirection? = nil
    var walls: Set<Int> = []
    var food = 0
    var score = 0
    var lives = 3
    var level = 1
    var foodEaten = 0
    /// Segments still owed from recent meals.
    var growth = 0
    var ticks = 0
    var over = false
    /// The snake holds still until the first steer (and after each respawn),
    /// so nobody loses a life while reading the board.
    var started = false

    init() {
        spawnSnake()
        buildWalls()
        placeFood()
    }

    var currentPlayer: Int { 0 }
    var isOver: Bool { over }

    static func index(_ x: Int, _ y: Int) -> Int { y * width + x }
    static func x(_ index: Int) -> Int { index % width }
    static func y(_ index: Int) -> Int { index / width }

    private mutating func spawnSnake() {
        let startY = Self.height / 2
        let startX = Self.width / 2 - 2
        body = [Self.index(startX + 2, startY), Self.index(startX + 1, startY), Self.index(startX, startY)]
        direction = .right
        pendingDirection = nil
        growth = 0
    }

    /// Wall patterns cycle with the level; level 1 is an open field.
    private mutating func buildWalls() {
        walls = []
        let midX = Self.width / 2
        let midY = Self.height / 2
        switch (level - 1) % 4 {
        case 1:   // horizontal bar
            for x in 3..<(Self.width - 3) { walls.insert(Self.index(x, midY)) }
        case 2:   // two pillars
            for y in 4..<(Self.height - 4) where y < midY - 2 || y > midY + 2 {
                walls.insert(Self.index(4, y))
                walls.insert(Self.index(Self.width - 5, y))
            }
        case 3:   // cross with a hole in the middle
            for x in 2..<(Self.width - 2) where abs(x - midX) > 1 {
                walls.insert(Self.index(x, midY))
            }
            for y in 5..<(Self.height - 5) where abs(y - midY) > 1 {
                walls.insert(Self.index(midX, y))
            }
        default:
            break
        }
    }

    private mutating func placeFood() {
        let blocked = Set(body).union(walls)
        let free = (0..<(Self.width * Self.height)).filter { !blocked.contains($0) }
        food = free.randomElement() ?? 0
    }

    func legalMoves() -> [Move] {
        guard !over else { return [] }
        return [.snake(.tick)] + GridDirection.allCases.map { .snake(.turn($0)) }
    }

    func isLegal(_ move: Move) -> Bool {
        if case .snake = move { return !over }
        return false
    }

    mutating func apply(_ move: Move) throws {
        guard case .snake(let m) = move, !over else { throw GameError.illegalMove }
        switch m {
        case .turn(let dir):
            if dir != direction.opposite { pendingDirection = dir }
            started = true
        case .tick:
            guard started else { return }
            tick()
        }
    }

    private mutating func tick() {
        ticks += 1
        if let pending = pendingDirection, pending != direction.opposite {
            direction = pending
        }
        pendingDirection = nil

        guard let head = body.first else { return }
        let nx = Self.x(head) + direction.dx
        let ny = Self.y(head) + direction.dy

        // Border, wall, or self: lose a life (tail cell is safe — it moves).
        let movingBody = growth > 0 ? body : Array(body.dropLast())
        let next = Self.index(nx, ny)
        if !(0..<Self.width).contains(nx) || !(0..<Self.height).contains(ny)
            || walls.contains(next) || movingBody.contains(next) {
            loseLife()
            return
        }

        body.insert(next, at: 0)
        if growth > 0 {
            growth -= 1
        } else {
            body.removeLast()
        }

        if next == food {
            score += 10 * level
            foodEaten += 1
            growth += 3
            if foodEaten % Self.bitesPerLevel == 0 {
                level += 1
                score += 100
                buildWalls()
                // A fresh head position keeps the new walls fair.
                spawnSnake()
            }
            placeFood()
        }
    }

    private mutating func loseLife() {
        lives -= 1
        if lives <= 0 {
            over = true
        } else {
            spawnSnake()
            placeFood()
            started = false
        }
    }

    var statusText: String {
        "Score \(score) · Level \(level) · " + String(repeating: "●", count: max(lives, 0))
    }

    var resultText: String? {
        over ? "Game over — \(score) points · \(body.count) segments long" : nil
    }
}
