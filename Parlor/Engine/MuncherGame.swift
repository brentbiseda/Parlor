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

    /// Each ghost has a distinct targeting personality.
    enum GhostType: Int, Codable, Hashable, CaseIterable {
        case blinky  // 0: direct chase toward pac
        case pinky   // 1: 4 cells ahead of pac's direction
        case inky    // 2: flanking (blinky offset mirrored through pac)
        case clyde   // 3: chase when far, scatter when close
    }

    struct Ghost: Codable, Hashable {
        var pos: Int
        var dir: GridDirection = .left
        var home: Int
        var releaseAtTick: Int
        var inBox: Bool = true
        var type: GhostType = .blinky
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
    var totalGhostsEaten = 0
    var maxGhostCombo = 0
    var score = 0
    var lives = 3
    var level = 1
    var ticks = 0
    var over = false
    /// Bonus fruit: appears at the spawn point every 60 pellets, briefly.
    var fruit: Int? = nil
    var fruitTicksLeft = 0
    var pelletsEaten = 0
    /// Total bonus fruits eaten this game.
    var fruitsEaten = 0
    /// Power pellets consumed this game.
    var powerPelletsEaten = 0
    /// Mazes fully cleared this game.
    var mazesCleared = 0
    /// Times all four ghosts were eaten in a single power pellet.
    var ghostEfficientRuns: Int = 0
    /// Scatter/chase phase: ghosts scatter to corners for the first 7 s, then chase.
    /// Each phase index: even = scatter (ticks), odd = chase (ticks). -1 = infinite final chase.
    static let scatterChaseCycle: [Int] = [420, 1200, 300, 1200, 300, -1]
    var scatterPhaseIndex = 0
    var scatterPhaseTicks = 0

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
            Ghost(pos: spawn, home: spawn, releaseAtTick: 8 + i * 24,
                  type: GhostType(rawValue: i) ?? .blinky)
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
        if frightenedTicks > 0 {
            if frightenedTicks == 1 && ghostsEatenThisPower == 4 {
                ghostEfficientRuns += 1
            }
            frightenedTicks -= 1
        } else {
            // Advance scatter/chase phase cycle.
            let cycle = Self.scatterChaseCycle
            if scatterPhaseIndex < cycle.count {
                let duration = cycle[scatterPhaseIndex]
                if duration > 0 {
                    scatterPhaseTicks += 1
                    if scatterPhaseTicks >= duration {
                        scatterPhaseIndex += 1
                        scatterPhaseTicks = 0
                    }
                }
            }
        }

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
            powerPelletsEaten += 1
        }
        if let f = fruit {
            fruitTicksLeft -= 1
            if pac == f {
                score += 100 * level
                fruitsEaten += 1
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
            mazesCleared += 1
            score += 500
            resetBoard()
        }
    }

    /// The corridor cell just above the ghost box.
    private var boxExit: Int { 7 * Self.width + 9 }

    var isScatterPhase: Bool {
        !frightened && scatterPhaseIndex < Self.scatterChaseCycle.count && scatterPhaseIndex % 2 == 0
    }

    /// Scatter corner target per ghost type.
    func scatterTarget(for type: GhostType) -> Int {
        switch type {
        case .blinky: return 2                                   // top-right
        case .pinky:  return Self.width - 3                     // top-left
        case .inky:   return (Self.height - 1) * Self.width + 2 // bottom-right
        case .clyde:  return (Self.height - 1) * Self.width + Self.width - 3 // bottom-left
        }
    }

    /// Manhattan target for each personality during chase phase.
    func chaseTarget(for ghost: Ghost) -> Int {
        switch ghost.type {
        case .blinky:
            return pac
        case .pinky:
            // 4 cells ahead in pac's direction (clamped).
            let tx = max(0, min(Self.width - 1, Self.x(pac) + pacDir.dx * 4))
            let ty = max(0, min(Self.height - 1, Self.y(pac) + pacDir.dy * 4))
            return ty * Self.width + tx
        case .inky:
            // Midpoint between blinky and 2 cells ahead of pac, mirrored.
            let blinky = ghosts.first { $0.type == .blinky }?.pos ?? pac
            let mx = Self.x(pac) + pacDir.dx * 2
            let my = Self.y(pac) + pacDir.dy * 2
            let tx = max(0, min(Self.width - 1, mx + (mx - Self.x(blinky))))
            let ty = max(0, min(Self.height - 1, my + (my - Self.y(blinky))))
            return ty * Self.width + tx
        case .clyde:
            // Chase when >8 away, scatter to corner when close.
            let dx = abs(Self.x(ghost.pos) - Self.x(pac))
            let dy = abs(Self.y(ghost.pos) - Self.y(pac))
            return dx + dy > 8 ? pac : scatterTarget(for: .clyde)
        }
    }

    /// ~12% chance to wander at an intersection; blinky stays disciplined.
    private func ghostWander(_ ghost: Ghost) -> Bool {
        guard ghost.type != .blinky else { return false }
        return Int.random(in: 0..<100) < 12
    }

    private mutating func moveGhost(_ ghost: inout Ghost) {
        let options = GridDirection.allCases.filter { direction in
            direction != ghost.dir.opposite && step(from: ghost.pos, direction: direction) != nil
        }
        let choices = options.isEmpty
            ? GridDirection.allCases.filter { step(from: ghost.pos, direction: $0) != nil }
            : options
        guard !choices.isEmpty else { return }

        let target: Int
        if frightened {
            // Flee: maximize distance to pac.
            let pick = choices.max { d1, d2 in
                let n1 = step(from: ghost.pos, direction: d1).map {
                    abs(Self.x($0) - Self.x(pac)) + abs(Self.y($0) - Self.y(pac)) } ?? 0
                let n2 = step(from: ghost.pos, direction: d2).map {
                    abs(Self.x($0) - Self.x(pac)) + abs(Self.y($0) - Self.y(pac)) } ?? 0
                return n1 < n2
            } ?? choices[0]
            ghost.dir = pick
            if let next = step(from: ghost.pos, direction: pick) { ghost.pos = next }
            return
        }

        target = isScatterPhase ? scatterTarget(for: ghost.type) : chaseTarget(for: ghost)

        func dist(_ direction: GridDirection) -> Int {
            guard let next = step(from: ghost.pos, direction: direction) else { return .max }
            return abs(Self.x(next) - Self.x(target)) + abs(Self.y(next) - Self.y(target))
        }

        // At a real intersection (3+ open exits), occasionally take a non-optimal
        // turn so ghosts aren't perfectly predictable.
        var pick: GridDirection
        if choices.count >= 3, ghostWander(ghost) {
            pick = choices.randomElement() ?? choices[0]
        } else {
            pick = choices.min { dist($0) < dist($1) } ?? choices[0]
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
                totalGhostsEaten += 1
                maxGhostCombo = max(maxGhostCombo, ghostsEatenThisPower)
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
        scatterPhaseIndex = 0
        scatterPhaseTicks = 0
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
        let totalInitialPellets = 240  // approx total in the maze
        let pelletsLeft = pellets.count + powerPellets.count
        var text = "Score \(score) · Level \(level) · \(pelletsEaten) dots · " + String(repeating: "●", count: max(lives, 0))
        if pelletsLeft <= 12 && pelletsLeft > 0 { text += " · 🏁 \(pelletsLeft) left" }
        if frightened {
            text += " · ⚡ FRIGHT \(frightenedTicks)"
            if ghostsEatenThisPower > 0 {
                text += " ×\(ghostsEatenThisPower) (\(200 * (1 << min(ghostsEatenThisPower, 3)))pts)"
            }
        } else if isScatterPhase {
            let cycle = Self.scatterChaseCycle
            if scatterPhaseIndex < cycle.count {
                let remaining = cycle[scatterPhaseIndex] - scatterPhaseTicks
                text += " · 👻 SCATTER (\(remaining))"
            }
        }
        let _ = totalInitialPellets  // suppress unused warning
        return text
    }

    var resultText: String? {
        guard over else { return nil }
        var text = "Game over — \(score) points · level \(level)"
        if totalGhostsEaten > 0 { text += " · \(totalGhostsEaten) ghost\(totalGhostsEaten == 1 ? "" : "s") eaten" }
        if maxGhostCombo >= 3 { text += " · 👻 ×\(maxGhostCombo) best combo!" }
        if mazesCleared > 0 { text += " · 🏆 \(mazesCleared) maze\(mazesCleared == 1 ? "" : "s") cleared" }
        if fruitsEaten > 0 { text += " · 🍒 \(fruitsEaten) fruit\(fruitsEaten == 1 ? "" : "s")" }
        if powerPelletsEaten > 0 {
            let eff = String(format: "%.1f", Double(totalGhostsEaten) / Double(powerPelletsEaten))
            text += " · ⚡ \(eff) ghosts/pellet"
        }
        if ghostEfficientRuns > 0 { text += " · 💀 \(ghostEfficientRuns) perfect power pellet\(ghostEfficientRuns == 1 ? "" : "s")" }
        return text
    }
}
