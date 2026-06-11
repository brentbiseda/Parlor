import Foundation

enum GameKind: String, Codable, CaseIterable, Identifiable {
    case hearts, spades, euchre, bridge, solitaire, freecell, mahjong, chess, checkers, go
    case pinball, breakout, tetris

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hearts: return "Hearts"
        case .spades: return "Spades"
        case .euchre: return "Euchre"
        case .bridge: return "Bridge"
        case .solitaire: return "Klondike"
        case .freecell: return "FreeCell"
        case .mahjong: return "Mahjongg"
        case .chess: return "Chess"
        case .checkers: return "Checkers"
        case .go: return "Go"
        case .pinball: return "Pinball"
        case .breakout: return "Breakout"
        case .tetris: return "Blocks"
        }
    }

    var playerCount: Int {
        switch self {
        case .solitaire, .freecell, .mahjong, .pinball, .breakout, .tetris: return 1
        case .chess, .checkers, .go: return 2
        case .hearts, .spades, .euchre, .bridge: return 4
        }
    }

    var isSolo: Bool { playerCount == 1 }

    /// True when players hold hidden hands, so pass-and-play shows a handoff screen.
    var hasHiddenInfo: Bool {
        switch self {
        case .hearts, .spades, .euchre, .bridge: return true
        default: return false
        }
    }

    /// Games that make sense in leagues and tournaments (head-to-head or full tables).
    var isCompetitive: Bool { playerCount > 1 }

    /// Partnership games where seats 0&2 face 1&3, so results come back as two teams.
    var isPartnership: Bool {
        switch self {
        case .spades, .euchre, .bridge: return true
        default: return false
        }
    }

    var symbolName: String {
        switch self {
        case .hearts: return "suit.heart.fill"
        case .spades: return "suit.spade.fill"
        case .euchre: return "suit.club.fill"
        case .bridge: return "suit.diamond.fill"
        case .solitaire: return "rectangle.portrait.on.rectangle.portrait.fill"
        case .freecell: return "rectangle.grid.2x2.fill"
        case .mahjong: return "square.grid.3x3.fill"
        case .chess: return "crown.fill"
        case .checkers: return "circle.circle.fill"
        case .go: return "circle.grid.3x3.fill"
        case .pinball: return "bolt.circle.fill"
        case .breakout: return "squares.below.rectangle"
        case .tetris: return "square.stack.3d.down.right.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .hearts: return "4 players · avoid points"
        case .spades: return "4 players · partnerships"
        case .euchre: return "4 players · partnerships"
        case .bridge: return "4 players · contract bridge"
        case .solitaire: return "Solo · draw 1 or 3"
        case .freecell: return "Solo · all cards face up"
        case .mahjong: return "Solo · tile matching"
        case .chess: return "2 players"
        case .checkers: return "2 players"
        case .go: return "2 players · 9×9 to 19×19"
        case .pinball: return "Solo · 10 themed tables"
        case .breakout: return "Solo · brick breaker"
        case .tetris: return "Solo · falling blocks"
        }
    }

    /// Solo games whose options deserve a quick setup sheet before starting.
    var hasSoloSetup: Bool { self == .solitaire || self == .pinball }

    /// Home-screen grouping.
    enum Section: String, CaseIterable, Identifiable {
        case cards = "Card Games"
        case boards = "Board Games"
        case solo = "Solo Parlor"
        var id: String { rawValue }
    }

    var section: Section {
        switch self {
        case .hearts, .spades, .euchre, .bridge: return .cards
        case .chess, .checkers, .go: return .boards
        case .solitaire, .freecell, .mahjong, .pinball, .breakout, .tetris: return .solo
        }
    }
}

/// How strong bot opponents play.
enum BotDifficulty: String, Codable, CaseIterable, Identifiable {
    case easy, normal, hard

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var blurb: String {
        switch self {
        case .easy: return "Random but legal — good for learning"
        case .normal: return "Casual play with light judgment"
        case .hard: return "Counts cards, takes captures, plays to win"
        }
    }
}

/// Options chosen at game setup. Decoding is tolerant of missing keys so
/// options persisted by older versions (in leagues, saved games, …) survive.
struct GameOptions: Codable, Hashable {
    var goBoardSize: Int = 9
    var klondikeDrawThree: Bool = false
    /// Times through the stock; 0 = unlimited.
    var klondikeMaxPasses: Int = 0
    var botDifficulty: BotDifficulty = .normal
    /// PinballTheme id.
    var pinballLayout: String = "classic"

    init(goBoardSize: Int = 9, klondikeDrawThree: Bool = false, klondikeMaxPasses: Int = 0,
         botDifficulty: BotDifficulty = .normal, pinballLayout: String = "classic") {
        self.goBoardSize = goBoardSize
        self.klondikeDrawThree = klondikeDrawThree
        self.klondikeMaxPasses = klondikeMaxPasses
        self.botDifficulty = botDifficulty
        self.pinballLayout = pinballLayout
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        goBoardSize = try c.decodeIfPresent(Int.self, forKey: .goBoardSize) ?? 9
        klondikeDrawThree = try c.decodeIfPresent(Bool.self, forKey: .klondikeDrawThree) ?? false
        klondikeMaxPasses = try c.decodeIfPresent(Int.self, forKey: .klondikeMaxPasses) ?? 0
        botDifficulty = try c.decodeIfPresent(BotDifficulty.self, forKey: .botDifficulty) ?? .normal
        pinballLayout = try c.decodeIfPresent(String.self, forKey: .pinballLayout) ?? "classic"
    }
}
