import Foundation

enum GameKind: String, Codable, CaseIterable, Identifiable {
    // Card games
    case hearts, spades, euchre, bridge, uno, eights, gofish
    // Board games
    case chess, checkers, go, marioParty
    // Solitaire & puzzles
    case solitaire, freecell, mahjong, tetris, capsules, minesweeper
    // Arcade
    case pinball, breakout, muncher, hopper, centipede, snake, bomberman, solarStriker
    // Sports
    case football, baseball, soccer, hockey
    // Trivia & party
    case trivia
    case promptParty   // Quiplash-style fill-in-blank comedy
    case bluff         // Balderdash-style fake definitions
    case jackAttack    // You Don't Know Jack-style irreverent trivia

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hearts: return "Hearts"
        case .spades: return "Spades"
        case .euchre: return "Euchre"
        case .bridge: return "Bridge"
        case .uno: return "Wildcard"
        case .eights: return "Crazy Eights"
        case .gofish: return "Go Fish"
        case .chess: return "Chess"
        case .checkers: return "Checkers"
        case .go: return "Go"
        case .marioParty: return "Star Party"
        case .solitaire: return "Klondike"
        case .freecell: return "FreeCell"
        case .mahjong: return "Mahjongg"
        case .tetris: return "Blocks"
        case .capsules: return "Capsules"
        case .minesweeper: return "Minesweeper"
        case .pinball: return "Pinball"
        case .breakout: return "Breakout"
        case .muncher: return "Muncher"
        case .hopper: return "Hopper"
        case .centipede: return "Centipede"
        case .snake: return "Nibbles"
        case .bomberman: return "Bomberman"
        case .solarStriker: return "Solar Striker"
        case .football: return "Field Goal"
        case .baseball: return "Home Run Derby"
        case .soccer: return "Penalty Shootout"
        case .hockey: return "Air Hockey"
        case .trivia: return "Trivia Blast"
        case .promptParty: return "Prompt Party"
        case .bluff: return "Bluff!"
        case .jackAttack: return "Jack Attack"
        }
    }

    /// Maximum player count (or fixed count for non-variable games).
    var playerCount: Int {
        switch self {
        case .solitaire, .freecell, .mahjong, .tetris, .capsules, .minesweeper,
             .pinball, .breakout, .muncher, .hopper, .centipede, .snake, .bomberman, .solarStriker,
             .football, .baseball, .soccer, .hockey:
            return 1
        case .chess, .checkers, .go:
            return 2
        case .hearts, .spades, .euchre, .bridge, .uno, .eights, .gofish, .marioParty:
            return 4
        // Variable-count party games return their maximum here.
        case .trivia, .jackAttack:
            return 16
        case .promptParty, .bluff:
            return 8
        }
    }

    /// Actual player count taking into account per-session options.
    func effectivePlayerCount(options: GameOptions) -> Int {
        switch self {
        case .trivia, .promptParty, .bluff, .jackAttack:
            return options.partyPlayerCount
        default:
            return playerCount
        }
    }

    var isSolo: Bool { playerCount == 1 }

    /// True when players hold hidden hands, so pass-and-play shows a handoff screen.
    var hasHiddenInfo: Bool {
        switch self {
        case .hearts, .spades, .euchre, .bridge, .uno, .eights, .gofish: return true
        case .promptParty, .bluff: return true  // players' answers are hidden until reveal
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

    var isPartyGame: Bool {
        switch self {
        case .trivia, .promptParty, .bluff, .jackAttack: return true
        default: return false
        }
    }

    var symbolName: String {
        switch self {
        case .hearts: return "suit.heart.fill"
        case .spades: return "suit.spade.fill"
        case .euchre: return "suit.club.fill"
        case .bridge: return "suit.diamond.fill"
        case .uno: return "rectangle.portrait.on.rectangle.portrait.angled.fill"
        case .eights: return "8.circle.fill"
        case .gofish: return "fish.fill"
        case .chess: return "crown.fill"
        case .checkers: return "circle.circle.fill"
        case .go: return "circle.grid.3x3.fill"
        case .marioParty: return "die.face.5.fill"
        case .solitaire: return "rectangle.portrait.on.rectangle.portrait.fill"
        case .freecell: return "rectangle.grid.2x2.fill"
        case .mahjong: return "square.grid.3x3.fill"
        case .tetris: return "square.stack.3d.down.right.fill"
        case .capsules: return "pills.fill"
        case .minesweeper: return "flag.fill"
        case .pinball: return "bolt.circle.fill"
        case .breakout: return "squares.below.rectangle"
        case .muncher: return "circle.lefthalf.filled"
        case .hopper: return "tortoise.fill"
        case .centipede: return "ant.fill"
        case .snake: return "scribble.variable"
        case .bomberman: return "burst.fill"
        case .solarStriker: return "paperplane.fill"
        case .trivia: return "questionmark.bubble.fill"
        case .promptParty: return "pencil.and.scribble"
        case .bluff: return "theatermasks.fill"
        case .jackAttack: return "bolt.shield.fill"
        case .football: return "football.fill"
        case .baseball: return "baseball.fill"
        case .soccer: return "soccerball"
        case .hockey: return "hockey.puck.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .hearts: return "4 players · avoid points"
        case .spades: return "4 players · partnerships"
        case .euchre: return "4 players · partnerships"
        case .bridge: return "4 players · contract bridge"
        case .uno: return "4 players · shed your hand"
        case .eights: return "4 players · eights are wild"
        case .gofish: return "4 players · collect books"
        case .chess: return "2 players"
        case .checkers: return "2 players"
        case .go: return "2 players · 9×9 to 19×19"
        case .marioParty: return "4 players · roll & collect stars"
        case .solitaire: return "Solo · draw 1 or 3"
        case .freecell: return "Solo · all cards face up"
        case .mahjong: return "Solo · tile matching"
        case .tetris: return "Solo · falling blocks"
        case .capsules: return "Solo · clear the viruses"
        case .minesweeper: return "Solo · flag the mines"
        case .pinball: return "Solo · 10 themed tables"
        case .breakout: return "Solo · brick breaker"
        case .muncher: return "Solo · maze chase"
        case .hopper: return "Solo · road & river"
        case .centipede: return "Solo · garden shooter"
        case .snake: return "Solo · don't bite yourself"
        case .bomberman: return "Solo · bombs & enemies"
        case .solarStriker: return "Solo · blast the alien fleet"
        case .football: return "Solo · 10 kicks, add wind"
        case .baseball: return "Solo · 10 pitches"
        case .soccer: return "Solo · shoot 5, save 5"
        case .hockey: return "Solo · first to 7"
        case .trivia: return "2–16 players · pick categories"
        case .promptParty: return "3–8 players · write funny answers"
        case .bluff: return "3–8 players · fake definitions"
        case .jackAttack: return "2–16 players · speed trivia with screws"
        }
    }

    /// Solo games whose options deserve a quick setup sheet before starting.
    var hasSoloSetup: Bool { self == .solitaire || self == .pinball }

    /// Home-screen grouping.
    enum Section: String, CaseIterable, Identifiable {
        case cards = "Card Games"
        case boards = "Board Games"
        case puzzles = "Solitaire & Puzzles"
        case arcade = "Arcade"
        case sports = "Sports"
        var id: String { rawValue }
    }

    var section: Section {
        switch self {
        case .hearts, .spades, .euchre, .bridge, .uno, .eights, .gofish: return .cards
        case .chess, .checkers, .go, .marioParty: return .boards
        case .solitaire, .freecell, .mahjong, .tetris, .capsules, .minesweeper: return .puzzles
        case .pinball, .breakout, .muncher, .hopper, .centipede, .snake, .bomberman, .solarStriker: return .arcade
        case .football, .baseball, .soccer, .hockey: return .sports
        case .trivia, .promptParty, .bluff, .jackAttack: return .boards
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
    /// Number of players for variable-count party games (trivia, promptParty, bluff, jackAttack).
    var partyPlayerCount: Int = 4
    /// Trivia category filter — empty means all categories.
    var triviaCategories: [TriviaCategory] = []
    /// Trivia difficulty filter — nil means mixed.
    var triviaDifficulty: TriviaDifficulty? = nil

    init(goBoardSize: Int = 9, klondikeDrawThree: Bool = false, klondikeMaxPasses: Int = 0,
         botDifficulty: BotDifficulty = .normal, pinballLayout: String = "classic",
         partyPlayerCount: Int = 4, triviaCategories: [TriviaCategory] = [],
         triviaDifficulty: TriviaDifficulty? = nil) {
        self.goBoardSize = goBoardSize
        self.klondikeDrawThree = klondikeDrawThree
        self.klondikeMaxPasses = klondikeMaxPasses
        self.botDifficulty = botDifficulty
        self.pinballLayout = pinballLayout
        self.partyPlayerCount = partyPlayerCount
        self.triviaCategories = triviaCategories
        self.triviaDifficulty = triviaDifficulty
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        goBoardSize = try c.decodeIfPresent(Int.self, forKey: .goBoardSize) ?? 9
        klondikeDrawThree = try c.decodeIfPresent(Bool.self, forKey: .klondikeDrawThree) ?? false
        klondikeMaxPasses = try c.decodeIfPresent(Int.self, forKey: .klondikeMaxPasses) ?? 0
        botDifficulty = try c.decodeIfPresent(BotDifficulty.self, forKey: .botDifficulty) ?? .normal
        pinballLayout = try c.decodeIfPresent(String.self, forKey: .pinballLayout) ?? "classic"
        partyPlayerCount = try c.decodeIfPresent(Int.self, forKey: .partyPlayerCount) ?? 4
        triviaCategories = try c.decodeIfPresent([TriviaCategory].self, forKey: .triviaCategories) ?? []
        triviaDifficulty = try c.decodeIfPresent(TriviaDifficulty.self, forKey: .triviaDifficulty)
    }
}
