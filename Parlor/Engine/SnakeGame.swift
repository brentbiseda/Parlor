import Foundation

/// Nibbles: steer the snake to the food, grow three segments per bite, and
/// don't hit the border, the level's walls, or yourself. Every six bites
/// advances the level — a new wall pattern appears, points per bite scale up,
/// and the view speeds the clock. Three lives.
///
/// Wall patterns cycle every six levels:
///   0: open field
///   1: horizontal bar with a gap
///   2: two vertical pillars with centre gap
///   3: cross with centre hole
///   4: four corner blocks
///   5: diagonal channel
///
/// Every 3rd food item is a bonus star (★) worth 3× points but only lasts
/// 20 ticks before vanishing.
struct SnakeGame: GameEngine {
    static let kind = GameKind.snake
    static let width = 15
    static let height = 22
    static let bitesPerLevel = 6
    static let growthPerBite = 3
    static let startingLives = 3
    static let pointsPerBite = 10    // multiplied by level
    static let levelBonus = 100
    static let bonusMultiplier = 3
    static let bonusTTL = 20         // ticks before bonus vanishes

    // MARK: - State

    var body: [Int] = []
    var direction: GridDirection = .right
    var pendingDirection: GridDirection? = nil
    var walls: Set<Int> = []
    var food = 0
    var bonusFood: Int? = nil        // nil when no bonus is active
    var bonusTicks = 0               // countdown to vanish
    var bonusFoodEaten = 0           // count of ★ items successfully grabbed
    var score = 0
    var lives = startingLives
    var level = 1
    var foodEaten = 0
    var growth = 0
    var ticks = 0
    var ticksThisLife = 0
    var bestTicksPerLife = 0
    var over = false
    var started = false
    var justLeveledUp = false
    var comboCount = 0               // consecutive bites while still growing
    var bestCombo = 0                // longest consecutive-bite combo this game
    var deathsThisLevel = 0
    var perfectLevelCount = 0
    var bestLength = 3               // peak body cell count achieved
    var totalDeaths = 0             // lives lost across the whole game
    var bestBitesPerLife = 0       // most bites collected on a single life
    var bitesThisLife = 0
    var bonusFoodMissed = 0        // bonus stars that vanished uneaten
    var wallCollisions = 0        // times snake hit a wall/boundary
    var totalDistance: Int = 0    // total cells traveled (successful moves only)

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

    // MARK: - Setup helpers

    private mutating func spawnSnake() {
        let cx = Self.width / 2 - 1
        let cy = Self.height / 2
        body = [Self.index(cx + 2, cy), Self.index(cx + 1, cy), Self.index(cx, cy)]
        direction = .right
        pendingDirection = nil
        growth = 0
    }

    private mutating func buildWalls() {
        walls = []
        let midX = Self.width / 2
        let midY = Self.height / 2
        switch (level - 1) % 6 {
        case 0:
            break   // open field
        case 1:
            // Horizontal bar with a three-cell gap.
            for x in 0..<Self.width where abs(x - midX) > 1 {
                walls.insert(Self.index(x, midY))
            }
        case 2:
            // Two vertical pillars that stop before the centre.
            for y in 2..<(Self.height - 2) where y < midY - 2 || y > midY + 2 {
                walls.insert(Self.index(4, y))
                walls.insert(Self.index(Self.width - 5, y))
            }
        case 3:
            // Cross with a two-cell hole in the middle.
            for x in 2..<(Self.width - 2) where abs(x - midX) > 1 {
                walls.insert(Self.index(x, midY))
            }
            for y in 5..<(Self.height - 5) where abs(y - midY) > 1 {
                walls.insert(Self.index(midX, y))
            }
        case 4:
            // Four corner blocks.
            let bx = 3; let by = 4
            for dx in 0..<3 {
                for dy in 0..<3 {
                    walls.insert(Self.index(bx + dx, by + dy))
                    walls.insert(Self.index(Self.width - 1 - bx - dx, by + dy))
                    walls.insert(Self.index(bx + dx, Self.height - 1 - by - dy))
                    walls.insert(Self.index(Self.width - 1 - bx - dx, Self.height - 1 - by - dy))
                }
            }
        default:
            // Diagonal channel: two short diagonal walls.
            for i in 0..<5 {
                walls.insert(Self.index(2 + i, 4 + i))
                walls.insert(Self.index(Self.width - 3 - i, Self.height - 5 - i))
            }
        }
    }

    private mutating func placeFood() {
        let blocked = Set(body).union(walls).union(bonusFood.map { Set([$0]) } ?? [])
        let free = (0..<(Self.width * Self.height)).filter { !blocked.contains($0) }
        food = free.randomElement() ?? firstFreeCell(blocked: blocked)
        // Every 3rd bite triggers a bonus item on the next placement.
        if foodEaten > 0 && foodEaten % 3 == 0 && bonusFood == nil {
            let bonusFree = free.filter { $0 != food }
            bonusFood = bonusFree.randomElement()
            bonusTicks = Self.bonusTTL
        }
    }

    private func firstFreeCell(blocked: Set<Int>) -> Int {
        (0..<(Self.width * Self.height)).first { !blocked.contains($0) } ?? 0
    }

    // MARK: - Move protocol

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
        justLeveledUp = false
        switch m {
        case .turn(let dir):
            if dir != direction.opposite { pendingDirection = dir }
            started = true
        case .tick:
            guard started else { return }
            tick()
        }
    }

    // MARK: - Tick

    private mutating func tick() {
        ticks += 1
        ticksThisLife += 1

        // Bonus food timeout.
        if bonusFood != nil {
            bonusTicks -= 1
            if bonusTicks <= 0 { bonusFood = nil; bonusFoodMissed += 1 }
        }

        if let pending = pendingDirection, pending != direction.opposite {
            direction = pending
        }
        pendingDirection = nil

        guard let head = body.first else { return }
        let nx = Self.x(head) + direction.dx
        let ny = Self.y(head) + direction.dy

        let movingBody = growth > 0 ? body : Array(body.dropLast())
        let next = Self.index(nx, ny)

        if !(0..<Self.width).contains(nx) || !(0..<Self.height).contains(ny)
            || walls.contains(next) || movingBody.contains(next) {
            comboCount = 0
            // Count wall/boundary collisions separately from self-collisions
            if !(0..<Self.width).contains(nx) || !(0..<Self.height).contains(ny) || walls.contains(next) {
                wallCollisions += 1
            }
            loseLife()
            return
        }

        totalDistance += 1
        body.insert(next, at: 0)
        if growth > 0 {
            growth -= 1
        } else {
            body.removeLast()
        }

        if next == food {
            let wasGrowing = growth > 0
            if wasGrowing { comboCount += 1; bestCombo = max(bestCombo, comboCount) } else { comboCount = 0 }
            let comboBonus = comboCount > 0 ? comboCount * Self.pointsPerBite : 0
            score += Self.pointsPerBite * level + comboBonus
            foodEaten += 1
            bitesThisLife += 1
            growth += Self.growthPerBite
            bestLength = max(bestLength, body.count + growth)
            if foodEaten % Self.bitesPerLevel == 0 {
                level += 1
                score += Self.levelBonus
                justLeveledUp = true
                if deathsThisLevel == 0 {
                    perfectLevelCount += 1
                    score += 50 * (level - 1)    // 50×prev_level bonus for perfect run
                }
                deathsThisLevel = 0
                buildWalls()
                spawnSnake()
            }
            placeFood()
        } else if let bf = bonusFood, next == bf {
            score += Self.pointsPerBite * level * Self.bonusMultiplier
            bonusFoodEaten += 1
            bonusFood = nil
        }
    }

    private mutating func loseLife() {
        bestTicksPerLife = max(bestTicksPerLife, ticksThisLife)
        bestBitesPerLife = max(bestBitesPerLife, bitesThisLife)
        bitesThisLife = 0
        ticksThisLife = 0
        deathsThisLevel += 1
        totalDeaths += 1
        lives -= 1
        if lives <= 0 {
            over = true
        } else {
            spawnSnake()
            placeFood()
            started = false
        }
    }

    // MARK: - Status

    var statusText: String {
        let liveDots = String(repeating: "●", count: max(lives, 0))
        if justLeveledUp { return "Level \(level)! \(liveDots) · \(score) pts" }
        let comboStr = comboCount > 1 ? " · combo ×\(comboCount)" : ""
        let bonusStr: String
        if bonusFood != nil {
            bonusStr = bonusTicks <= 5 ? " · ⭐ bonus \(bonusTicks)!" : " · ⭐ bonus!"
        } else { bonusStr = "" }
        let bitesLeft = Self.bitesPerLevel - (foodEaten % Self.bitesPerLevel)
        let nextStr = bitesLeft <= 2 ? " · \(bitesLeft)→L\(level + 1)" : ""
        return "Score \(score) · L\(level) · \(liveDots)\(comboStr)\(bonusStr)\(nextStr)"
    }

    var resultText: String? {
        guard over else { return nil }
        var text = "Game over — \(score) pts · L\(level) · \(foodEaten) bites · peak \(bestLength) segs"
        if bonusFoodEaten > 0 {
            text += " · ⭐ \(bonusFoodEaten) bonus"
            let attempts = bonusFoodEaten + bonusFoodMissed
            if attempts > 0 && bonusFoodMissed == 0 { text += " (all grabbed!)" }
        }
        if bestTicksPerLife > 0 { text += " · best run: \(bestTicksPerLife) ticks" }
        if perfectLevelCount > 0 { text += " · ⭐ \(perfectLevelCount) perfect level\(perfectLevelCount == 1 ? "" : "s")" }
        if bestCombo >= 3 { text += " · ⚡ best combo ×\(bestCombo)" }
        let liveBites = max(bestBitesPerLife, bitesThisLife)
        if liveBites >= 6 { text += " · 🍎 \(liveBites) bites in one life" }
        if totalDeaths <= 1 && level > 2 { text += " · 🛡️ steady hand" }
        if wallCollisions > 0 { text += " · 💀 \(wallCollisions) wall hit\(wallCollisions == 1 ? "" : "s")" }
        if totalDistance > 0 { text += " · Traveled \(totalDistance) cells" }
        return text
    }
}
