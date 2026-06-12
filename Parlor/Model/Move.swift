import Foundation

struct Point: Codable, Hashable {
    var x: Int
    var y: Int
}

struct BoardMove: Codable, Hashable {
    var from: Point
    var to: Point
    var promotion: ChessPieceKind? = nil
}

enum BridgeStrain: String, Codable, CaseIterable, Hashable, Comparable {
    case clubs, diamonds, hearts, spades, notrump

    var label: String {
        switch self {
        case .notrump: return "NT"
        case .clubs: return "♣"
        case .diamonds: return "♦"
        case .hearts: return "♥"
        case .spades: return "♠"
        }
    }

    var order: Int {
        switch self {
        case .clubs: return 0
        case .diamonds: return 1
        case .hearts: return 2
        case .spades: return 3
        case .notrump: return 4
        }
    }

    var suit: Suit? {
        switch self {
        case .clubs: return .clubs
        case .diamonds: return .diamonds
        case .hearts: return .hearts
        case .spades: return .spades
        case .notrump: return nil
        }
    }

    static func < (lhs: BridgeStrain, rhs: BridgeStrain) -> Bool { lhs.order < rhs.order }
}

enum BridgeCall: Codable, Hashable {
    case pass
    case bid(level: Int, strain: BridgeStrain)
    case double
    case redouble

    var label: String {
        switch self {
        case .pass: return "Pass"
        case .bid(let level, let strain): return "\(level)\(strain.label)"
        case .double: return "X"
        case .redouble: return "XX"
        }
    }
}

enum EuchreCall: Codable, Hashable {
    case pass
    case orderUp(alone: Bool)
    case callTrump(Suit, alone: Bool)
}

enum FreeCellMove: Codable, Hashable {
    case cascadeToFree(col: Int, cell: Int)
    case cascadeToFoundation(col: Int)
    /// Move the run of the top `count` cards of `from` onto `to`.
    case cascadeToCascade(from: Int, count: Int, to: Int)
    case freeToFoundation(cell: Int)
    case freeToCascade(cell: Int, to: Int)
}

/// Pinball plays out in a physics scene; the engine just keeps score,
/// so its "moves" are events reported by the table.
enum PinballEvent: Codable, Hashable {
    case score(Int)
    case ballDrained
}

/// Breakout works like pinball: physics in the scene, score in the engine.
enum BreakoutEvent: Codable, Hashable {
    case score(Int)
    case ballLost
    case levelCleared
}

/// Shared by Blocks (tetrominoes) and Capsules (pill-dropping) — same controls.
enum TetrisMove: Codable, Hashable {
    case left, right, rotate, softDrop, hardDrop
    case tick            // gravity step, driven by the view's timer
}

/// Four-way movement for the tick-based maze and crossing games.
enum GridDirection: String, Codable, Hashable, CaseIterable {
    case up, down, left, right

    var dx: Int { self == .left ? -1 : (self == .right ? 1 : 0) }
    var dy: Int { self == .up ? -1 : (self == .down ? 1 : 0) }
    var opposite: GridDirection {
        switch self {
        case .up: return .down
        case .down: return .up
        case .left: return .right
        case .right: return .left
        }
    }
}

enum MinesweeperMove: Codable, Hashable {
    case reveal(x: Int, y: Int)
    case flag(x: Int, y: Int)
}

/// Muncher (maze chase): steer and let the clock run.
enum MazeMove: Codable, Hashable {
    case go(GridDirection)
    case tick
}

/// Hopper (road & river crossing): hop or let traffic move.
enum HopperMove: Codable, Hashable {
    case hop(GridDirection)
    case tick
}

/// Snake: steer and let the clock slither.
enum SnakeMove: Codable, Hashable {
    case turn(GridDirection)
    case tick
}

/// Scorekeeping events reported by the arcade & sports scenes
/// (Centipede, Football, Baseball, Soccer, Hockey).
enum ArcadeEvent: Codable, Hashable {
    case score(Int)
    case opponentScore(Int)
    case attempt             // a kick, pitch, or penalty consumed
    case lifeLost
    case levelUp
}

enum UnoColor: String, Codable, Hashable, CaseIterable {
    case red, yellow, green, blue
}

enum UnoValue: Codable, Hashable, Equatable {
    case number(Int)         // 0–9
    case skip, reverse, drawTwo
    case wild, wildDrawFour
}

struct UnoCard: Codable, Hashable, Identifiable {
    /// Unique per physical card so duplicates in hand stay distinct.
    var id: Int
    var color: UnoColor?     // nil = wild
    var value: UnoValue
}

enum UnoMove: Codable, Hashable {
    case play(UnoCard, declared: UnoColor?)
    case draw
    case pass                // keep a drawn-but-unwanted card
}

enum EightsMove: Codable, Hashable {
    case play(Card, nominated: Suit?)   // suit choice rides along with an 8
    case draw
    case pass                           // stock empty and nothing playable
}

enum GoFishMove: Codable, Hashable {
    case ask(seat: Int, rank: Rank)
}

enum KlondikeMove: Codable, Hashable {
    case draw
    case resetStock
    case wasteToFoundation
    case wasteToTableau(Int)
    case tableauToFoundation(Int)
    /// Move the run starting at `index` within face-up cards of column `from` onto column `to`.
    case tableauToTableau(from: Int, index: Int, to: Int)
    case foundationToTableau(foundation: Int, to: Int)
}

/// One move type shared by every game so networking stays trivial.
/// Each engine validates only the cases it understands.
enum Move: Codable, Hashable {
    // Card games
    case playCard(Card)
    case passCards([Card])          // Hearts: choose 3 to pass
    case bid(Int)                   // Spades (0 = nil bid)
    case bridgeCall(BridgeCall)
    case euchreCall(EuchreCall)
    // Board games
    case board(BoardMove)           // chess & checkers
    case place(Point)               // go
    case pass                       // go
    case resign
    // Solo games
    case klondike(KlondikeMove)
    case freecell(FreeCellMove)
    case matchTiles(Int, Int)       // mahjong tile ids
    case shuffleRemaining           // mahjong rescue
    case pinball(PinballEvent)
    case breakout(BreakoutEvent)
    case tetris(TetrisMove)
    case capsules(TetrisMove)
    case minesweeper(MinesweeperMove)
    case maze(MazeMove)
    case hopper(HopperMove)
    case snake(SnakeMove)
    case arcade(ArcadeEvent)        // centipede, football, baseball, soccer, hockey
    // Shedding & fishing card games
    case uno(UnoMove)
    case eights(EightsMove)
    case fish(GoFishMove)
}
