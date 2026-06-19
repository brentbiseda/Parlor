import Foundation

/// Hopper: hop a frog across five lanes of traffic and a five-lane river to
/// the lily pads. Lanes scroll on the view's `.hopper(.tick)` clock; the
/// frog rides logs and turtles, drowns in open water, and gets flattened by
/// trucks. Fill all five pads to advance a level. Three lives.
struct HopperGame: GameEngine {
    static let kind = GameKind.hopper
    static let width = 13
    /// Rows top→bottom: 0 pads, 1–5 river, 6 median, 7–11 road, 12 start.
    static let height = 13

    struct Lane: Codable, Hashable {
        /// Bitmask-ish occupancy: cell x is solid when `pattern` contains x
        /// (cars on roads, logs/turtles on the river). Patterns shift by
        /// `direction` one cell every `period` ticks.
        var cells: Set<Int>
        var direction: Int      // -1 left, +1 right
        var period: Int         // ticks per shift (smaller = faster)
        var offset: Int = 0     // accumulated shift, for rendering smoothness
    }

    var riverLanes: [Lane] = []   // rows 1...5
    var roadLanes: [Lane] = []    // rows 7...11
    var frogX = width / 2
    var frogY = height - 1
    var homePads: Set<Int> = []   // pad slots filled (x positions)
    var score = 0
    var lives = 3
    var level = 1
    var ticks = 0
    var highestRow = height - 1   // for forward-progress scoring
    var over = false
    /// Invincibility ticks remaining after a respawn (prevents double-deaths).
    var invincibleTicks = 0
    static let respawnInvincibilityTicks = 6
    /// Ticks elapsed since this crossing attempt started (reset on respawn and pad landing).
    var crossingTicks = 0
    /// Total successful frog crossings this game (each pad landing counts).
    var crossings = 0
    /// Crossings where the frog never died on that approach AND earned a time bonus.
    var perfectCrossings = 0
    /// Full levels cleared (all 5 pads filled).
    var levelsCleared = 0
    /// Consecutive crossings without losing a life.
    var crossingStreak = 0
    var bestCrossingStreak = 0
    /// Lives at the start of the current crossing approach (reset on respawn/landing).
    var livesAtCrossingStart = 3
    /// Fewest ticks taken to complete any crossing this game (0 = none yet).
    var fastestCrossing = 0
    /// Total lives lost this game.
    var livesLost = 0
    /// Times the frog was hit by traffic.
    var roadKills: Int = 0
    /// Times the frog drowned in the river.
    var drownings: Int = 0
    /// Max time-bonus ticks budget per crossing (scales with level).
    static let timeBonusBudget = 200

    static let padXs = [1, 4, 6, 8, 11]

    init() {
        buildLanes()
    }

    private mutating func buildLanes() {
        func lane(spacing: Int, length: Int, direction: Int, period: Int) -> Lane {
            var cells = Set<Int>()
            var x = Int.random(in: 0..<spacing)
            while x < Self.width + length {
                for i in 0..<length { cells.insert((x + i) % Self.width) }
                x += spacing + length
            }
            return Lane(cells: cells, direction: direction, period: period)
        }
        let speedUp = max(0, level - 1)
        riverLanes = [
            lane(spacing: 3, length: 3, direction: 1, period: max(2, 4 - speedUp)),   // row 1: long logs
            lane(spacing: 3, length: 2, direction: -1, period: max(2, 3 - speedUp)),  // row 2: turtles
            lane(spacing: 4, length: 4, direction: 1, period: max(1, 3 - speedUp)),   // row 3: long logs
            lane(spacing: 3, length: 2, direction: -1, period: max(2, 4 - speedUp)),  // row 4: turtles
            lane(spacing: 3, length: 3, direction: 1, period: max(2, 3 - speedUp)),   // row 5: logs
        ]
        roadLanes = [
            lane(spacing: 5, length: 2, direction: -1, period: max(2, 4 - speedUp)),  // row 7: trucks
            lane(spacing: 4, length: 1, direction: 1, period: max(1, 3 - speedUp)),   // row 8: cars
            lane(spacing: 5, length: 1, direction: -1, period: max(1, 2)),            // row 9: fast cars
            lane(spacing: 4, length: 2, direction: 1, period: max(2, 4 - speedUp)),   // row 10
            lane(spacing: 4, length: 1, direction: -1, period: max(2, 3 - speedUp)),  // row 11
        ]
    }

    var currentPlayer: Int { 0 }
    var isOver: Bool { over }

    /// The lane occupying `row`, if any.
    func lane(atRow row: Int) -> Lane? {
        if (1...5).contains(row) { return riverLanes[row - 1] }
        if (7...11).contains(row) { return roadLanes[row - 7] }
        return nil
    }

    func isSolid(row: Int, x: Int) -> Bool {
        lane(atRow: row)?.cells.contains((x % Self.width + Self.width) % Self.width) ?? false
    }

    func legalMoves() -> [Move] {
        guard !over else { return [] }
        return [.hopper(.tick)] + GridDirection.allCases.map { .hopper(.hop($0)) }
    }

    func isLegal(_ move: Move) -> Bool {
        if case .hopper = move { return !over }
        return false
    }

    mutating func apply(_ move: Move) throws {
        guard case .hopper(let m) = move, !over else { throw GameError.illegalMove }
        switch m {
        case .hop(let direction):
            hop(direction)
        case .tick:
            tick()
        }
    }

    private mutating func hop(_ direction: GridDirection) {
        let nx = frogX + direction.dx
        let ny = frogY + direction.dy
        guard (0..<Self.width).contains(nx), (0..<Self.height).contains(ny) else { return }
        frogX = nx
        frogY = ny
        if ny < highestRow {
            highestRow = ny
            score += 10
        }
        resolveFrogCell(afterHop: true)
    }

    private mutating func tick() {
        ticks += 1
        crossingTicks += 1
        if invincibleTicks > 0 { invincibleTicks -= 1 }
        // Shift lanes on their periods; carry the frog with river traffic.
        for row in [1, 2, 3, 4, 5, 7, 8, 9, 10, 11] {
            let isRiver = row <= 5
            let laneIndex = isRiver ? row - 1 : row - 7
            var lane = isRiver ? riverLanes[laneIndex] : roadLanes[laneIndex]
            guard ticks % lane.period == 0 else { continue }
            lane.cells = Set(lane.cells.map {
                (($0 + lane.direction) % Self.width + Self.width) % Self.width
            })
            lane.offset += lane.direction
            if isRiver { riverLanes[laneIndex] = lane } else { roadLanes[laneIndex] = lane }
            if frogY == row && isRiver {
                // Riding a log: drift with it (washed off the edge = gone).
                let newX = frogX + lane.direction
                if (0..<Self.width).contains(newX) {
                    frogX = newX
                } else {
                    loseLife()
                    return
                }
            }
        }
        resolveFrogCell(afterHop: false)
    }

    private mutating func resolveFrogCell(afterHop: Bool) {
        guard invincibleTicks == 0 else { return }  // brief post-respawn grace period
        switch frogY {
        case 0:
            // Lily pads: land on an open one or splash.
            if let pad = Self.padXs.min(by: { abs($0 - frogX) < abs($1 - frogX) }),
               abs(pad - frogX) <= 1, !homePads.contains(pad) {
                homePads.insert(pad)
                crossings += 1
                if fastestCrossing == 0 || crossingTicks < fastestCrossing { fastestCrossing = crossingTicks }
                crossingStreak += 1
                bestCrossingStreak = max(bestCrossingStreak, crossingStreak)
                // Time bonus: up to 50 pts for fast crossing.
                let budget = Self.timeBonusBudget
                let timeBonus = max(0, (budget - crossingTicks) * 50 / budget)
                score += 50 + timeBonus
                if timeBonus > 0 && lives == livesAtCrossingStart { perfectCrossings += 1 }
                if homePads.count == Self.padXs.count {
                    levelsCleared += 1
                    level += 1
                    score += 250 + 50 * level  // escalating level-clear bonus
                    homePads = []
                    buildLanes()
                }
                respawn()
            } else {
                loseLife()
            }
        case 1...5:
            if !isSolid(row: frogY, x: frogX) { loseLife() }   // open water
        case 7...11:
            if isSolid(row: frogY, x: frogX) { loseLife() }    // traffic
        default:
            break
        }
    }

    private mutating func loseLife() {
        crossingStreak = 0
        if (1...5).contains(frogY) {
            drownings += 1
        } else {
            roadKills += 1
        }
        livesLost += 1
        lives -= 1
        if lives <= 0 {
            over = true
        } else {
            respawn()
        }
    }

    private mutating func respawn() {
        frogX = Self.width / 2
        frogY = Self.height - 1
        highestRow = Self.height - 1
        crossingTicks = 0
        livesAtCrossingStart = lives
        invincibleTicks = Self.respawnInvincibilityTicks
    }

    var zoneLabel: String {
        if frogY == 0 { return "🏁 home" }
        if (1...5).contains(frogY) { return "🌊 river" }
        if frogY == 6 { return "🟩 safe" }
        if (7...11).contains(frogY) { return "🚗 road" }
        return "🟩 start"
    }

    var statusText: String {
        let timeLeft = max(0, Self.timeBonusBudget - crossingTicks)
        let timerStr = timeLeft > 0 ? " · ⏱\(timeLeft)" : ""
        let padsLeft = Self.padXs.count - homePads.count
        let streakStr = crossingStreak >= 3 ? " · 🔥\(crossingStreak)" : ""
        return "Score \(score) · \(zoneLabel) · Pads \(padsLeft) left · Lv\(level)\(timerStr)\(streakStr) · " +
               String(repeating: "●", count: max(lives, 0))
    }

    var resultText: String? {
        guard over else { return nil }
        var parts = ["Game over — \(score) pts", "level \(level)"]
        if levelsCleared > 0 { parts.append("\(levelsCleared) level\(levelsCleared == 1 ? "" : "s") cleared") }
        if crossings > 0 { parts.append("\(crossings) crossing\(crossings == 1 ? "" : "s")") }
        if perfectCrossings > 0 { parts.append("⭐ \(perfectCrossings) perfect") }
        if bestCrossingStreak >= 3 { parts.append("🔥 \(bestCrossingStreak)-crossing streak") }
        if fastestCrossing > 0 { parts.append("⚡ fastest \(fastestCrossing) ticks") }
        if livesLost == 0 { parts.append("🛡️ flawless!") }
        else {
            parts.append("\(livesLost) life\(livesLost == 1 ? "" : "s") lost")
            if roadKills > 0 || drownings > 0 {
                parts.append("\(roadKills) flattened, \(drownings) drowned")
            }
        }
        if ticks > 0 { parts.append("\(ticks) ticks survived") }
        return parts.joined(separator: " · ")
    }
}
