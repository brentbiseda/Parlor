import Foundation

enum GameKind: String, Codable, CaseIterable, Identifiable {
    case hearts, spades, euchre, bridge, solitaire, mahjong, chess, checkers, go

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hearts: return "Hearts"
        case .spades: return "Spades"
        case .euchre: return "Euchre"
        case .bridge: return "Bridge"
        case .solitaire: return "Solitaire"
        case .mahjong: return "Mahjongg"
        case .chess: return "Chess"
        case .checkers: return "Checkers"
        case .go: return "Go"
        }
    }

    var playerCount: Int {
        switch self {
        case .solitaire, .mahjong: return 1
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

    var symbolName: String {
        switch self {
        case .hearts: return "suit.heart.fill"
        case .spades: return "suit.spade.fill"
        case .euchre: return "suit.club.fill"
        case .bridge: return "suit.diamond.fill"
        case .solitaire: return "rectangle.portrait.on.rectangle.portrait.fill"
        case .mahjong: return "square.grid.3x3.fill"
        case .chess: return "crown.fill"
        case .checkers: return "circle.circle.fill"
        case .go: return "circle.grid.3x3.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .hearts: return "4 players · avoid points"
        case .spades: return "4 players · partnerships"
        case .euchre: return "4 players · partnerships"
        case .bridge: return "4 players · contract bridge"
        case .solitaire: return "Solo · Klondike"
        case .mahjong: return "Solo · tile matching"
        case .chess: return "2 players"
        case .checkers: return "2 players"
        case .go: return "2 players · 9×9 to 19×19"
        }
    }
}

/// Options chosen at game setup.
struct GameOptions: Codable, Hashable {
    var goBoardSize: Int = 9
    var klondikeDrawThree: Bool = false
}
