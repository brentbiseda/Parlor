import Foundation

/// Mahjongg solitaire on the classic 144-tile turtle layout.
/// Match free pairs of identical tiles (any flower matches any flower,
/// any season matches any season). A tile is free when nothing rests on it
/// and at least one long side (left or right) is open.
struct MahjongGame: GameEngine {
    static let kind = GameKind.mahjong

    enum TileFace: Codable, Hashable {
        case dots(Int)        // 1–9
        case bamboo(Int)      // 1–9
        case characters(Int)  // 1–9
        case wind(Int)        // 0 E, 1 S, 2 W, 3 N
        case dragon(Int)      // 0 red, 1 green, 2 white
        case flower(Int)      // 0–3, match each other
        case season(Int)      // 0–3, match each other

        func matches(_ other: TileFace) -> Bool {
            switch (self, other) {
            case (.flower, .flower), (.season, .season): return true
            default: return self == other
            }
        }

        /// Unicode mahjong tile glyph.
        var glyph: String {
            let scalar: Int
            switch self {
            case .characters(let n): scalar = 0x1F006 + n   // 🀇…
            case .bamboo(let n): scalar = 0x1F00F + n       // 🀐…
            case .dots(let n): scalar = 0x1F018 + n         // 🀙…
            case .wind(let n): scalar = 0x1F000 + n         // 🀀…
            case .dragon(let n): scalar = 0x1F004 + n       // 🀄🀅🀆
            case .flower(let n): scalar = 0x1F022 + n       // 🀢…
            case .season(let n): scalar = 0x1F026 + n       // 🀦…
            }
            return String(UnicodeScalar(scalar)!)
        }
    }

    struct Tile: Codable, Hashable, Identifiable {
        var id: Int
        var face: TileFace
        /// Position in half-tile units; a tile spans [x, x+2) × [y, y+2).
        var x: Int
        var y: Int
        var z: Int
        var removed = false
    }

    var tiles: [Tile] = []
    var matchedPairs = 0
    var shufflesUsed = 0
    /// Most free-pair matches available at any single moment (skill indicator — higher = better openings).
    var peakAvailableMatches = 0
    /// Number of times the player hit a stuck position and needed to shuffle.
    var stuckCount = 0
    /// Consecutive matches made without a shuffle (resets on shuffle).
    var currentMatchRun = 0
    var longestMatchRun = 0
    /// Times the player was down to a single available match (clutch moment).
    var clutchMoments = 0

    init() {
        let positions = MahjongGame.turtleLayout()
        var faces: [TileFace] = []
        for n in 1...9 {
            faces += [.dots(n), .bamboo(n), .characters(n)].flatMap { Array(repeating: $0, count: 4) }
        }
        for n in 0..<4 { faces += Array(repeating: .wind(n), count: 4) }
        for n in 0..<3 { faces += Array(repeating: .dragon(n), count: 4) }
        for n in 0..<4 { faces.append(.flower(n)) }
        for n in 0..<4 { faces.append(.season(n)) }
        faces.shuffle()
        tiles = zip(positions, faces).enumerated().map { i, pair in
            Tile(id: i, face: pair.1, x: pair.0.0, y: pair.0.1, z: pair.0.2)
        }
    }

    /// Classic turtle: 87 + 36 + 16 + 4 + 1 = 144 tiles.
    static func turtleLayout() -> [(Int, Int, Int)] {
        var positions: [(Int, Int, Int)] = []
        // Layer 0: rows of 12, 8, 10, 12, 12, 10, 8, 12, centered on x 0...24.
        let widths = [12, 8, 10, 12, 12, 10, 8, 12]
        for (row, w) in widths.enumerated() {
            let startX = (24 - 2 * w) / 2
            for i in 0..<w { positions.append((startX + 2 * i, row * 2, 0)) }
        }
        // Far-left tile and the two far-right tiles, vertically centered.
        positions.append((-2, 7, 0))
        positions.append((24, 7, 0))
        positions.append((26, 7, 0))
        // Layer 1: 6×6.
        for row in 0..<6 { for col in 0..<6 { positions.append((6 + 2 * col, 2 + 2 * row, 1)) } }
        // Layer 2: 4×4.
        for row in 0..<4 { for col in 0..<4 { positions.append((8 + 2 * col, 4 + 2 * row, 2)) } }
        // Layer 3: 2×2.
        for row in 0..<2 { for col in 0..<2 { positions.append((10 + 2 * col, 6 + 2 * row, 3)) } }
        // Layer 4: single capstone straddling the 2×2.
        positions.append((11, 7, 4))
        return positions
    }

    var currentPlayer: Int { 0 }
    var remainingCount: Int { tiles.lazy.filter { !$0.removed }.count }
    var isOver: Bool { remainingCount == 0 }

    func overlaps(_ a: Tile, _ b: Tile) -> Bool {
        abs(a.x - b.x) < 2 && abs(a.y - b.y) < 2
    }

    func isFree(_ tile: Tile) -> Bool {
        guard !tile.removed else { return false }
        var leftBlocked = false
        var rightBlocked = false
        for other in tiles where !other.removed && other.id != tile.id {
            if other.z == tile.z + 1 && overlaps(tile, other) { return false }
            if other.z == tile.z && abs(other.y - tile.y) < 2 {
                if other.x == tile.x - 2 { leftBlocked = true }
                if other.x == tile.x + 2 { rightBlocked = true }
            }
        }
        return !(leftBlocked && rightBlocked)
    }

    var freeTiles: [Tile] { tiles.filter { isFree($0) } }

    /// All currently matchable free pairs (used for hints and stuck detection).
    func availableMatches() -> [(Int, Int)] {
        let free = freeTiles
        var result: [(Int, Int)] = []
        for i in free.indices {
            for j in free.indices where j > i {
                if free[i].face.matches(free[j].face) {
                    result.append((free[i].id, free[j].id))
                }
            }
        }
        return result
    }

    var isStuck: Bool { !isOver && availableMatches().isEmpty }

    func legalMoves() -> [Move] {
        var moves = availableMatches().map { Move.matchTiles($0.0, $0.1) }
        if isStuck { moves.append(.shuffleRemaining) }
        return moves
    }

    mutating func apply(_ move: Move) throws {
        switch move {
        case .matchTiles(let a, let b):
            guard a != b,
                  let ta = tiles.first(where: { $0.id == a }),
                  let tb = tiles.first(where: { $0.id == b }),
                  isFree(ta), isFree(tb), ta.face.matches(tb.face) else { throw GameError.illegalMove }
            for idx in tiles.indices where tiles[idx].id == a || tiles[idx].id == b {
                tiles[idx].removed = true
            }
            matchedPairs += 1
            currentMatchRun += 1
            longestMatchRun = max(longestMatchRun, currentMatchRun)
            let available = availableMatches().count
            peakAvailableMatches = max(peakAvailableMatches, available)
            if available == 1 && !isOver { clutchMoments += 1 }
        case .shuffleRemaining:
            let activeIndices = tiles.indices.filter { !tiles[$0].removed }
            let originalFaces = activeIndices.map { tiles[$0].face }
            // Retry the shuffle a few times until a playable position appears.
            for attempt in 0..<24 {
                var faces = originalFaces
                faces.shuffle()
                for (i, idx) in activeIndices.enumerated() { tiles[idx].face = faces[i] }
                if !availableMatches().isEmpty || attempt == 23 { break }
            }
            shufflesUsed += 1
            stuckCount += 1
            currentMatchRun = 0
        default:
            throw GameError.illegalMove
        }
    }

    func isLegal(_ move: Move) -> Bool {
        switch move {
        case .matchTiles, .shuffleRemaining: return true
        default: return false
        }
    }

    var statusText: String {
        if isStuck { return "No matches left — shuffle the remaining tiles\(shufflesUsed > 0 ? " (used \(shufflesUsed))" : "")" }
        let total = 72
        let pct = matchedPairs * 100 / total
        let available = availableMatches().count
        var tail = ""
        if available == 1 { tail = " · ⚠️ only 1 move!" }
        else if remainingCount <= 8 { tail = " · 🏁 final stretch" }
        let shuffleStr = shufflesUsed > 0 ? " · 🔀 \(shufflesUsed) shuffle\(shufflesUsed == 1 ? "" : "s")" : ""
        return "\(remainingCount) tiles (\(pct)%) · \(matchedPairs) matches made\(shuffleStr) · \(available) pairs open\(tail)"
    }

    var resultText: String? {
        guard isOver else { return nil }
        var text = "Cleared all 72 pairs"
        if shufflesUsed > 0 { text += " (\(shufflesUsed) shuffle\(shufflesUsed == 1 ? "" : "s"))" }
        text += "!"
        if peakAvailableMatches >= 10 { text += " · Peak \(peakAvailableMatches) pairs open 🏆" }
        if stuckCount == 0 { text += " · 🏆 No shuffles needed!" }
        else if longestMatchRun >= 20 { text += " · 🔥 \(longestMatchRun)-match run" }
        if clutchMoments > 0 { text += " · 😰 \(clutchMoments) clutch escape\(clutchMoments == 1 ? "" : "s")" }
        return text
    }
}
