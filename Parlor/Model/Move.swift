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

enum TetrisMove: Codable, Hashable {
    case left, right, rotate, softDrop, hardDrop
    case tick            // gravity step, driven by the view's timer
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
}
