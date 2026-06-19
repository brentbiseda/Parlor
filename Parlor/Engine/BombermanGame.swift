import Foundation

/// Bomberman-style arcade game. 15×13 grid, 3 enemy types, chain explosions,
/// 6 power-up types (including remote detonator, shield, skull penalty),
/// auto-advancing levels, bonus cherry items, and kick mechanic.
struct BombermanGame: GameEngine {
    static let kind = GameKind.bomberman
    static let cols = 15
    static let rows = 13

    // MARK: - Nested types

    enum Cell: Int, Codable {
        case empty = 0, wall = 1, block = 2
        case powerBomb = 3, powerBlast = 4, powerSpeed = 5
        case powerRemote = 6, powerSkull = 7, powerShield = 8
    }

    enum EnemyKind: Int, Codable, CaseIterable {
        case balloon = 0   // slow random wander
        case ghost   = 1   // medium speed, prefers open corridors
        case demon   = 2   // fast, pursues player within 7 cells
    }

    struct BomberBomb: Codable, Identifiable {
        var id: Int
        var x, y: Int
        var fuseLeft: Int
        var radius: Int
        var remote: Bool

        init(id: Int, x: Int, y: Int, fuseLeft: Int, radius: Int, remote: Bool = false) {
            self.id = id; self.x = x; self.y = y
            self.fuseLeft = fuseLeft; self.radius = radius; self.remote = remote
        }
    }

    struct BomberExplosion: Codable {
        var cells: [Int]
        var ticksLeft: Int
        var killCount: Int

        init(cells: [Int], ticksLeft: Int, killCount: Int = 0) {
            self.cells = cells; self.ticksLeft = ticksLeft; self.killCount = killCount
        }
    }

    struct BomberEnemy: Codable, Identifiable {
        var id: Int
        var x, y: Int
        var direction: GridDirection
        var alive: Bool
        var moveCooldown: Int
        var speed: Int
        var kind: EnemyKind
    }

    // MARK: - State

    var grid: [Cell]
    var playerX = 1, playerY = 1
    var playerDir: GridDirection = .up   // facing direction for kick + view chevron
    var playerAlive = true
    var invincibleTicks = 0    // post-hit invincibility
    var shieldTicks = 0        // power-up invincibility (powerShield)
    var skullTicks = 0         // penalty: effective bombs=1, blast=1
    var livesLeft = 3

    var maxBombs = 1           // base; skull doesn't modify this field
    var blastRadius = 2        // base
    var speedBoosts = 0
    var hasRemote = false

    var score = 0
    var bombs: [BomberBomb] = []
    var explosions: [BomberExplosion] = []
    var enemies: [BomberEnemy] = []
    var tickCount = 0
    var level = 1
    var levelClearCountdown = 0    // counts down 80 ticks after all enemies die

    // Stats preserved across levels
    var enemiesKilled = 0
    var blocksDestroyed = 0
    var bombsPlaced = 0
    var maxChain = 0
    var powerUpsCollected = 0
    var levelsCleared = 0
    var deathsThisLevel = 0
    var survivalTicks = 0
    var totalExplosionCells = 0
    var maxKillCombo = 0

    // Bonus cherry item: flat storage for Codable safety (no tuple/struct)
    var bonusItemX = -1, bonusItemY = -1
    var bonusItemTicks = 0

    private var currentChain = 0
    private var nextBombID = 0
    private var nextEnemyID = 0

    // MARK: - Computed properties

    var effectiveMaxBombs: Int    { skullTicks > 0 ? 1 : min(maxBombs, 8) }
    var effectiveBlastRadius: Int { skullTicks > 0 ? 1 : min(blastRadius, 8) }
    var isInvincible: Bool        { invincibleTicks > 0 || shieldTicks > 0 }
    var levelClearing: Bool       { levelClearCountdown > 0 }
    var hasBonusItem: Bool        { bonusItemX >= 0 }

    // MARK: - Init

    init() {
        grid = Array(repeating: .empty, count: Self.cols * Self.rows)
        populateLevel(1)
    }

    // MARK: - Grid helpers

    func idx(_ x: Int, _ y: Int) -> Int { y * Self.cols + x }
    func onGrid(_ x: Int, _ y: Int) -> Bool {
        (0..<Self.cols).contains(x) && (0..<Self.rows).contains(y)
    }

    func cell(_ x: Int, _ y: Int) -> Cell {
        guard onGrid(x, y) else { return .wall }
        return grid[idx(x, y)]
    }

    func isSolid(_ x: Int, _ y: Int) -> Bool {
        let c = cell(x, y)
        return c == .wall || c == .block
    }

    func hasBomb(_ x: Int, _ y: Int) -> Bool {
        bombs.contains { $0.x == x && $0.y == y }
    }

    var dangerCells: Set<Int> {
        var result = Set<Int>()
        for bomb in bombs {
            result.insert(idx(bomb.x, bomb.y))
            for dir in [GridDirection.up, .down, .left, .right] {
                for r in 1...max(bomb.radius, 1) {
                    let nx = bomb.x + dir.dx * r
                    let ny = bomb.y + dir.dy * r
                    guard onGrid(nx, ny) else { break }
                    if cell(nx, ny) == .wall { break }
                    result.insert(idx(nx, ny))
                    if cell(nx, ny) == .block { break }
                }
            }
        }
        return result
    }

    func inExplosion(_ x: Int, _ y: Int) -> Bool {
        let i = idx(x, y)
        return explosions.contains { $0.cells.contains(i) }
    }

    // MARK: - Level setup

    private mutating func populateLevel(_ lvl: Int) {
        level = lvl
        grid = Array(repeating: .empty, count: Self.cols * Self.rows)

        for x in 0..<Self.cols { grid[idx(x, 0)] = .wall; grid[idx(x, Self.rows-1)] = .wall }
        for y in 0..<Self.rows { grid[idx(0, y)] = .wall; grid[idx(Self.cols-1, y)] = .wall }
        for y in stride(from: 2, to: Self.rows-1, by: 2) {
            for x in stride(from: 2, to: Self.cols-1, by: 2) {
                grid[idx(x, y)] = .wall
            }
        }

        let density = min(0.52 + Double(lvl - 1) * 0.04, 0.72)
        let safeZone: Set<Int> = [idx(1,1), idx(2,1), idx(1,2), idx(3,1), idx(1,3)]
        for y in 1..<Self.rows-1 {
            for x in 1..<Self.cols-1 {
                let i = idx(x, y)
                guard grid[i] == .empty, !safeZone.contains(i) else { continue }
                if Double.random(in: 0..<1) < density { grid[i] = .block }
            }
        }

        enemies = []
        let spawnPositions: [(Int, Int)] = [
            (Self.cols-2, 1), (1, Self.rows-2), (Self.cols-2, Self.rows-2),
            (Self.cols/2, Self.rows/2), (Self.cols-3, 2), (2, Self.rows-3),
            (Self.cols/2, 2), (Self.cols-2, Self.rows/2),
        ]
        let kindSeq: [EnemyKind] = [.balloon, .balloon, .ghost, .demon, .ghost, .demon, .balloon, .demon]
        let totalEnemies = min(2 + lvl, spawnPositions.count)
        for i in 0..<totalEnemies {
            let (ex, ey) = spawnPositions[i]
            let gi = idx(ex, ey)
            if grid[gi] == .block { grid[gi] = .empty }
            let kind = kindSeq[i % kindSeq.count]
            // Speed scales up each level (improvement #16): lower value = moves faster
            let spd: Int
            switch kind {
            case .balloon: spd = max(7 - (lvl - 1), 3)
            case .ghost:   spd = max(5 - (lvl - 1), 2)
            case .demon:   spd = max(3 - (lvl - 1), 1)
            }
            enemies.append(BomberEnemy(
                id: nextEnemyID, x: ex, y: ey,
                direction: GridDirection.allCases[i % 4],
                alive: true, moveCooldown: i * 2, speed: spd, kind: kind
            ))
            nextEnemyID += 1
        }

        playerX = 1; playerY = 1; playerDir = .up
        playerAlive = true
        invincibleTicks = 0; shieldTicks = 0; skullTicks = 0
        bombs = []; explosions = []
        bonusItemX = -1; bonusItemY = -1; bonusItemTicks = 0
        levelClearCountdown = 0
        deathsThisLevel = 0
        currentChain = 0
    }

    // MARK: - GameEngine protocol

    var currentPlayer: Int { 0 }
    var isOver: Bool { livesLeft <= 0 }

    func legalMoves() -> [Move] {
        guard !isOver else { return [] }
        var moves: [Move] = [.bomberman(.tick)]
        guard playerAlive, !levelClearing else { return moves }
        for dir in GridDirection.allCases {
            let nx = playerX + dir.dx; let ny = playerY + dir.dy
            if !isSolid(nx, ny) && !hasBomb(nx, ny) {
                moves.append(.bomberman(.move(dir)))
            }
        }
        if bombs.count < effectiveMaxBombs && !hasBomb(playerX, playerY) {
            moves.append(.bomberman(.placeBomb))
        }
        let kx = playerX + playerDir.dx; let ky = playerY + playerDir.dy
        if hasBomb(kx, ky) { moves.append(.bomberman(.kick)) }
        if hasRemote && bombs.contains(where: { $0.remote }) {
            moves.append(.bomberman(.detonate))
        }
        return moves
    }

    func isLegal(_ move: Move) -> Bool {
        if case .bomberman = move { return !isOver }
        return false
    }

    mutating func apply(_ move: Move) throws {
        guard case .bomberman(let m) = move else { throw GameError.illegalMove }
        switch m {

        case .move(let dir):
            guard playerAlive, !levelClearing else { break }
            let nx = playerX + dir.dx; let ny = playerY + dir.dy
            guard !isSolid(nx, ny) && !hasBomb(nx, ny) else { throw GameError.illegalMove }
            playerDir = dir
            playerX = nx; playerY = ny
            collectPowerUp()
            collectBonusItem()

        case .placeBomb:
            guard playerAlive, !levelClearing,
                  bombs.count < effectiveMaxBombs, !hasBomb(playerX, playerY)
            else { throw GameError.illegalMove }
            let isRemote = hasRemote && !bombs.contains(where: { $0.remote })
            bombs.append(BomberBomb(
                id: nextBombID, x: playerX, y: playerY,
                fuseLeft: 120, radius: effectiveBlastRadius,
                remote: isRemote
            ))
            nextBombID += 1
            bombsPlaced += 1
            currentChain = 0

        case .kick:
            guard playerAlive, !levelClearing else { break }
            let kx = playerX + playerDir.dx; let ky = playerY + playerDir.dy
            guard let bi = bombs.firstIndex(where: { $0.x == kx && $0.y == ky }) else {
                throw GameError.illegalMove
            }
            var tx = kx + playerDir.dx; var ty = ky + playerDir.dy
            while onGrid(tx, ty) && !isSolid(tx, ty) && !hasBomb(tx, ty) {
                tx += playerDir.dx; ty += playerDir.dy
            }
            tx -= playerDir.dx; ty -= playerDir.dy
            if tx != kx || ty != ky { bombs[bi].x = tx; bombs[bi].y = ty }

        case .detonate:
            guard hasRemote else { throw GameError.illegalMove }
            for i in bombs.indices where bombs[i].remote { bombs[i].fuseLeft = 0 }

        case .tick:
            tickCount += 1
            survivalTicks += 1
            if invincibleTicks > 0 { invincibleTicks -= 1 }
            if shieldTicks > 0     { shieldTicks -= 1 }
            if skullTicks > 0      { skullTicks -= 1 }

            if levelClearCountdown > 0 {
                levelClearCountdown -= 1
                if levelClearCountdown == 0 { populateLevel(level + 1) }
                return
            }

            advanceBonusItem()
            advanceBombs()
            advanceExplosions()
            advanceEnemies()
            if playerAlive { checkPlayerDamage() }

            if !enemies.isEmpty && enemies.allSatisfy({ !$0.alive }) {
                let bonus = 1000 * level + (deathsThisLevel == 0 ? 500 : 0)
                score += bonus
                levelsCleared += 1
                levelClearCountdown = 80
            }
        }
    }

    // MARK: - Bonus cherry item

    private mutating func advanceBonusItem() {
        if hasBonusItem {
            bonusItemTicks -= 1
            if bonusItemTicks <= 0 { bonusItemX = -1; bonusItemY = -1 }
            return
        }
        guard tickCount % 250 == 0, Double.random(in: 0..<1) < 0.65 else { return }
        var candidates: [(Int, Int)] = []
        for y in 1..<Self.rows-1 {
            for x in 1..<Self.cols-1 {
                if cell(x, y) == .empty && !hasBomb(x, y) { candidates.append((x, y)) }
            }
        }
        if let (cx, cy) = candidates.randomElement() {
            bonusItemX = cx; bonusItemY = cy; bonusItemTicks = 140
        }
    }

    private mutating func collectBonusItem() {
        guard hasBonusItem, bonusItemX == playerX, bonusItemY == playerY else { return }
        score += 500
        bonusItemX = -1; bonusItemY = -1
    }

    // MARK: - Bomb logic

    private mutating func advanceBombs() {
        var toExplode: [BomberBomb] = []
        var surviving: [BomberBomb] = []
        for var bomb in bombs {
            if !bomb.remote { bomb.fuseLeft -= 1 }
            let chainHit = explosions.contains { $0.cells.contains(idx(bomb.x, bomb.y)) }
            if bomb.fuseLeft <= 0 || chainHit { toExplode.append(bomb) }
            else { surviving.append(bomb) }
        }
        bombs = surviving
        for bomb in toExplode { explodeBomb(bomb) }
    }

    private mutating func explodeBomb(_ bomb: BomberBomb) {
        currentChain += 1
        if currentChain > maxChain { maxChain = currentChain }

        var cells: [Int] = [idx(bomb.x, bomb.y)]
        for dir in [GridDirection.up, .down, .left, .right] {
            for r in 1...max(bomb.radius, 1) {
                let nx = bomb.x + dir.dx * r; let ny = bomb.y + dir.dy * r
                guard onGrid(nx, ny) else { break }
                let c = cell(nx, ny)
                if c == .wall { break }
                cells.append(idx(nx, ny))
                if c == .block { destroyBlock(nx, ny); break }
            }
        }
        totalExplosionCells += cells.count
        score += 50

        var kills = 0
        for i in enemies.indices where enemies[i].alive {
            if cells.contains(idx(enemies[i].x, enemies[i].y)) {
                enemies[i].alive = false
                enemiesKilled += 1
                kills += 1
            }
        }
        if kills > 0 {
            if kills > maxKillCombo { maxKillCombo = kills }
            score += 200 * kills * max(kills, currentChain)
        }
        explosions.append(BomberExplosion(cells: cells, ticksLeft: 25, killCount: kills))
    }

    private mutating func destroyBlock(_ x: Int, _ y: Int) {
        blocksDestroyed += 1
        score += 10
        if Double.random(in: 0..<1) < 0.30 {
            // Weighted: good power-ups appear 8x more often than skull
            let pus: [Cell] = [
                .powerBomb, .powerBomb, .powerBlast, .powerBlast,
                .powerSpeed, .powerSpeed, .powerRemote, .powerShield,
                .powerSkull
            ]
            grid[idx(x, y)] = pus.randomElement()!
        } else {
            grid[idx(x, y)] = .empty
        }
    }

    private mutating func advanceExplosions() {
        for i in explosions.indices { explosions[i].ticksLeft -= 1 }
        explosions.removeAll { $0.ticksLeft <= 0 }
        if explosions.isEmpty { currentChain = 0 }
    }

    // MARK: - Enemy AI

    private mutating func advanceEnemies() {
        for i in enemies.indices {
            guard enemies[i].alive else { continue }
            enemies[i].moveCooldown -= 1
            guard enemies[i].moveCooldown <= 0 else { continue }
            enemies[i].moveCooldown = enemies[i].speed
            moveEnemy(index: i)
        }
    }

    private mutating func moveEnemy(index i: Int) {
        let e = enemies[i]
        let dirs = GridDirection.allCases

        if e.kind == .demon {
            let dx = playerX - e.x; let dy = playerY - e.y
            if abs(dx) + abs(dy) <= 7 && playerAlive {
                let preferred: GridDirection = abs(dx) > abs(dy)
                    ? (dx > 0 ? .right : .left)
                    : (dy > 0 ? .down : .up)
                for dir in [preferred] + dirs.filter({ $0 != preferred }).shuffled() {
                    let nx = e.x + dir.dx; let ny = e.y + dir.dy
                    if !isSolid(nx, ny) {
                        enemies[i].x = nx; enemies[i].y = ny; enemies[i].direction = dir; return
                    }
                }
                return
            }
        }

        if e.kind == .ghost {
            let openness = dirs.map { dir -> (GridDirection, Int) in
                var count = 0
                for r in 1...4 {
                    let nx = e.x + dir.dx * r; let ny = e.y + dir.dy * r
                    guard !isSolid(nx, ny) else { break }
                    count += 1
                }
                return (dir, count)
            }.sorted { $0.1 > $1.1 }
            for (dir, _) in openness {
                let nx = e.x + dir.dx; let ny = e.y + dir.dy
                if !isSolid(nx, ny) {
                    enemies[i].x = nx; enemies[i].y = ny; enemies[i].direction = dir; return
                }
            }
            return
        }

        // Balloon: maintain direction, turn on block
        let nx = e.x + e.direction.dx; let ny = e.y + e.direction.dy
        if !isSolid(nx, ny) {
            enemies[i].x = nx; enemies[i].y = ny
        } else {
            var options = dirs.filter { $0 != e.direction && $0 != e.direction.opposite }.shuffled()
            options.append(e.direction.opposite)
            for dir in options {
                let mx = e.x + dir.dx; let my = e.y + dir.dy
                if !isSolid(mx, my) {
                    enemies[i].direction = dir; enemies[i].x = mx; enemies[i].y = my; return
                }
            }
        }
    }

    // MARK: - Player damage & power-ups

    private mutating func checkPlayerDamage() {
        guard !isInvincible else { return }
        let pi = idx(playerX, playerY)
        let hitByBlast = explosions.contains { $0.cells.contains(pi) }
        let hitByEnemy = enemies.contains { $0.alive && $0.x == playerX && $0.y == playerY }
        if hitByBlast || hitByEnemy { playerHit() }
    }

    private mutating func playerHit() {
        deathsThisLevel += 1
        livesLeft -= 1
        score = max(0, score - 150)
        if livesLeft <= 0 {
            playerAlive = false
        } else {
            invincibleTicks = 90
            playerX = 1; playerY = 1; playerDir = .up
            bombs = []   // clear bombs on death so player respawns safely
        }
    }

    private mutating func collectPowerUp() {
        let c = cell(playerX, playerY)
        switch c {
        case .powerBomb:
            maxBombs = min(maxBombs + 1, 8)
            grid[idx(playerX, playerY)] = .empty; score += 100; powerUpsCollected += 1
        case .powerBlast:
            blastRadius = min(blastRadius + 1, 8)
            grid[idx(playerX, playerY)] = .empty; score += 100; powerUpsCollected += 1
        case .powerSpeed:
            speedBoosts = min(speedBoosts + 1, 3)
            grid[idx(playerX, playerY)] = .empty; score += 100; powerUpsCollected += 1
        case .powerRemote:
            hasRemote = true
            grid[idx(playerX, playerY)] = .empty; score += 150; powerUpsCollected += 1
        case .powerShield:
            shieldTicks = max(shieldTicks, 180)
            grid[idx(playerX, playerY)] = .empty; score += 150; powerUpsCollected += 1
        case .powerSkull:
            skullTicks = 120
            grid[idx(playerX, playerY)] = .empty
        default: break
        }
    }

    // MARK: - Status & result

    var statusText: String {
        if livesLeft <= 0 { return "Game over · \(score) pts · Lv\(level)" }
        if levelClearing {
            let stars = deathsThisLevel == 0 ? " ⭐" : ""
            return "Level \(level) cleared!\(stars) +\(1000 * level + (deathsThisLevel == 0 ? 500 : 0)) pts"
        }
        let livesStr = (0..<min(livesLeft, 5)).map { _ in "❤️" }.joined()
        let alive = enemies.filter { $0.alive }.count
        let bStr = effectiveMaxBombs > 1 ? " · 💣×\(effectiveMaxBombs)" : ""
        let rStr = effectiveBlastRadius > 2 ? " · 💥r\(effectiveBlastRadius)" : ""
        let sStr = speedBoosts > 0 ? " · ⚡×\(speedBoosts)" : ""
        let mods = [skullTicks > 0 ? "💀" : nil, shieldTicks > 0 ? "🛡" : nil, hasRemote ? "📡" : nil]
            .compactMap { $0 }.joined()
        let modStr = mods.isEmpty ? "" : " · \(mods)"
        return "\(livesStr) \(score) · 👾\(alive)/\(enemies.count) · Lv\(level)\(bStr)\(rStr)\(sStr)\(modStr)"
    }

    var resultText: String? {
        guard isOver else { return nil }
        var parts: [String] = ["Game over — \(score) pts"]
        if levelsCleared > 0 { parts.append("🏆 \(levelsCleared) level\(levelsCleared == 1 ? "" : "s")") }
        if enemiesKilled > 0 { parts.append("💀 \(enemiesKilled) kills") }
        if maxKillCombo > 1  { parts.append("💥 ×\(maxKillCombo) combo") }
        if blocksDestroyed > 0 { parts.append("🧱 \(blocksDestroyed) blocks") }
        if bombsPlaced > 0   { parts.append("💣 \(bombsPlaced) bombs") }
        if maxChain > 1      { parts.append("🔗 chain ×\(maxChain)") }
        if powerUpsCollected > 0 { parts.append("⚡ \(powerUpsCollected) power-ups") }
        let secs = survivalTicks / 10
        if secs > 0 { parts.append("⏱ \(secs)s") }
        return parts.joined(separator: " · ")
    }

    func ranking() -> [[Int]] { [[0]] }
}
