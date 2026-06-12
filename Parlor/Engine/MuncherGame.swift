import Foundation

/// Muncher: a tick-based maze chase. Steer with `.maze(.go(_:))`; the view's
/// timer submits `.maze(.tick)` to advance the world one cell. Four ghosts
/// chase greedily (with a dash of randomness), power pellets turn the tables,
/// clearing the maze bumps the level, and three lives end the run.
struct MuncherGame: GameEngine {
    static let kind = GameKind.muncher
    static let width = 19
    static let height = 21

    /// '#' wall, '.' pellet, 'o' power pellet, '-' empty corridor,
    /// 'G' ghost spawn (in the box), 'M' player spawn, 'T' tunnel mouth.
    /// Every row is exactly 19 characters (checked by a smoke test).
    static let mazeRows = [
        "###################",
        "#........#........#",
        "#o##.###.#.###.##o#",
        "#.................#",
        "#.##.#.#####.#.##.#",
        "#....#...#...#....#",
        "####.#.#####.#.####",
        "####.#---------####",
        "####.#-#GG#--#.####",
        "T....#-#GG#--#....T",
        "####.#-------#.####",
        "####.#.#####.#.####",
        "#....#...#...#....#",
        "#.##.###.#.###.##.#",
        "#o.#.....M.....#.o#",
        "##.#.#.#####.#.#.##",
        "#....#...#...#....#",
        "#.######.#.######.#",
        "#.................#",
        "#.##.###.#.###.##.#",
        "###################",
    ]

    struct Ghost: Codable, Hashable {
        var pos: Int
        var dir: GridDirection = .left
        var home: Int
        var releaseAtTick: Int
        var inBox: Bool = true
    }

    var walls: Set<Int> = []
    var pellets: Set<Int> = []
    var powerPellets: Set<Int> = []
    var pac: Int = 0
    var pacSpawn: Int = 0
    var pacDir: GridDirection = .left
    var queuedDir: GridDirection? = nil
    var ghosts: [Ghost] = []
    var frightenedTicks = 0
    var ghostsEatenThisPower = 0
    var score = 0
    var lives = 3
    var level = 1
    var ticks = 0
    var over = false
    /// Bonus fruit: appears at the spawn point every 60 pellets, briefly.
    var fruit: Int? = nil
    var fruitTicksLeft = 0
    var pelletsEaten = 0

    init() {
        var ghostSpawns: [Int] = []
        for (y, row) in Self.mazeRows.enumerated() {
            for (x, char) in row.enumerated() {
                let index = y * Self.width + x
                switch char {
                case "#": walls.insert(index)
                case ".": pellets.insert(index)
                case "o": powerPellets.insert(index)
                case "G": ghostSpawns.append(index)
                case "M": pacSpawn = index
                default: break
                }
            }
        }
        pac = pacSpawn
        ghosts = ghostSpawns.enumerated().map { (i, spawn) in
            Ghost(pos: spawn, home: spawn, releaseAtTick: 8 + i * 24)
        }
    }

    var currentPlayer: Int { 0 }
    var isOver: Bool { over }
    var frightened: Bool { frightenedTicks > 0 }

    static func x(_ index: Int) -> Int { index % width }
    static func y(_ index: Int) -> Int { index / width }

    func isOpen(_ index: Int) -> Bool {
        index >= 0 && index < Self.width * Self.height && !walls.contains(index)
    }

    /// One step in `direction`, wrapping through the tunnel row.
    func step(from index: Int, direction: GridDirection) -> Int? {
        var nx = Self.x(index) + direction.dx
        let ny = Self.y(index) + direction.dy
        if nx < 0 { nx = Self.width - 1 }            // tunnel wrap
        if nx >= Self.width { nx = 0 }
        guard (0..<Self.height).contains(ny) else { return nil }
        let next = ny * Self.width + nx
        return isOpen(next) ? next : nil
    }

    func legalMoves() -> [Move] {
        guard !over else { return [] }
        return [.maze(.tick)] + GridDirection.allCases.map { .maze(.go($0)) }
    }

    func isLegal(_ move: Move) -> Bool {
        if case .maze = move { return !over }
        return false
    }

    mutating func apply(_ move: Move) throws {
        guard case .maze(let m) = move, !over else { throw GameError.illegalMove }
        switch m {
        case .go(let direction):
            queuedDir = direction
        case .tick:
            tick()
        }
    }

    private mutating func tick() {
        ticks += 1
        if frightenedTicks > 0 { frightenedTicks -= 1 }

        // Pac: take the queued turn as soon as it's open.
        if let queued = queuedDir, step(from: pac, direction: queued) != nil {
            pacDir = queued
            queuedDir = nil
        }
        let pacBefore = pac
        if let next = step(from: pac, direction: pacDir) { pac = next }

        // Munch.
        if pellets.remove(pac) != nil {
            score += 10
            pelletsEaten += 1
            if pelletsEaten % 60 == 0 && fruit == nil {
                fruit = pacSpawn
                fruitTicksLeft = 55
            }
        }
        if powerPellets.remove(pac) != nil {
            score += 50
            frightenedTicks = max(60 - level * 6, 24)
            ghostsEatenThisPower = 0
        }
        if let f = fruit {
            fruitTicksLeft -= 1
            if pac == f {
                score += 100 * level
                fruit = nil
            } else if fruitTicksLeft <= 0 {
                fruit = nil
            }
        }

        if checkGhostContact(pacBefore: pacBefore, ghostsBefore: ghosts.map(\.pos)) { return }

        // Ghosts (frightened ghosts limp: skip every third tick).
        let ghostsBefore = ghosts.map(\.pos)
        for i in ghosts.indices {
            if ghosts[i].inBox {
                if ticks >= ghosts[i].releaseAtTick {
                    ghosts[i].inBox = false
                    ghosts[i].pos = boxExit
                    ghosts[i].dir = Bool.random() ? .left : .right
                }
                continue
            }
            if frightened && ticks % 3 == 0 { continue }
            var ghost = ghosts[i]
            moveGhost(&ghost)
            ghosts[i] = ghost
        }

        if checkGhostContact(pacBefore: pacBefore, ghostsBefore: ghostsBefore) { return }

        // Maze cleared → next level.
        if pellets.isEmpty && powerPellets.isEmpty {
            level += 1
            score += 500
            resetBoard()
        }
    }

    /// The corridor cell just above the ghost box.
    private var boxExit: Int { 7 * Self.width + 9 }

    private mutating func moveGhost(_ ghost: inout Ghost) {
        let options = GridDirection.allCases.filter { direction in
            direction != ghost.dir.opposite && step(from: ghost.pos, direction: direction) != nil
        }
        let choices = options.isEmpty
            ? GridDirection.allCases.filter { step(from: ghost.pos, direction: $0) != nil }
            : options
        guard !choices.isEmpty else { return }

        func distanceToPac(_ direction: GridDirection) -> Int {
            guard let next = step(from: ghost.pos, direction: direction) else { return .max }
            let dx = abs(Self.x(next) - Self.x(pac))
            let dy = abs(Self.y(next) - Self.y(pac))
            return dx + dy
        }

        let pick: GridDirection
        if frightened {
            pick = choices.max { distanceToPac($0) < distanceToPac($1) } ?? choices[0]
        } else if Double.random(in: 0..<1) < 0.25 {
            pick = choices.randomElement()!   // a little chaos keeps corners safe-ish
        } else {
            pick = choices.min { distanceToPac($0) < distanceToPac($1) } ?? choices[0]
        }
        ghost.dir = pick
        if let next = step(from: ghost.pos, direction: pick) { ghost.pos = next }
    }

    /// Handles touch and pass-through collisions. Returns true when the
    /// world was reset (life lost) or the game ended.
    private mutating func checkGhostContact(pacBefore: Int, ghostsBefore: [Int]) -> Bool {
        for i in ghosts.indices where !ghosts[i].inBox {
            let touching = ghosts[i].pos == pac
            let swapped = ghosts[i].pos == pacBefore && ghostsBefore[i] == pac
            guard touching || swapped else { continue }
            if frightened {
                ghostsEatenThisPower += 1
                score += 200 * (1 << min(ghostsEatenThisPower - 1, 3))
                ghosts[i].inBox = true
                ghosts[i].pos = ghosts[i].home
                ghosts[i].releaseAtTick = ticks + 20
            } else {
                lives -= 1
                if lives <= 0 {
                    over = true
                } else {
                    resetPositions()
                }
                return true
            }
        }
        return false
    }

    private mutating func resetPositions() {
        pac = pacSpawn
        pacDir = .left
        queuedDir = nil
        frightenedTicks = 0
        fruit = nil
        fruitTicksLeft = 0
        for i in ghosts.indices {
            ghosts[i].pos = ghosts[i].home
            ghosts[i].inBox = true
            ghosts[i].releaseAtTick = ticks + 8 + i * 24
        }
    }

    private mutating func resetBoard() {
        for (y, row) in Self.mazeRows.enumerated() {
            for (x, char) in row.enumerated() {
                let index = y * Self.width + x
                if char == "." { pellets.insert(index) }
                if char == "o" { powerPellets.insert(index) }
            }
        }
        resetPositions()
    }

    var statusText: String {
        "Score \(score) · Level \(level) · " + String(repeating: "●", count: max(lives, 0))
    }

    var resultText: String? {
        over ? "Game over — \(score) points · level \(level)" : nil
    }
}
