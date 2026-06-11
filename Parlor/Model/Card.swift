import Foundation

enum Suit: String, Codable, CaseIterable, Hashable, Comparable {
    case clubs, diamonds, hearts, spades

    var symbol: String {
        switch self {
        case .clubs: return "♣"
        case .diamonds: return "♦"
        case .hearts: return "♥"
        case .spades: return "♠"
        }
    }

    var isRed: Bool { self == .hearts || self == .diamonds }

    /// The other suit of the same color (used for the left bower in Euchre).
    var sameColorPartner: Suit {
        switch self {
        case .clubs: return .spades
        case .spades: return .clubs
        case .hearts: return .diamonds
        case .diamonds: return .hearts
        }
    }

    static func < (lhs: Suit, rhs: Suit) -> Bool {
        lhs.sortIndex < rhs.sortIndex
    }

    private var sortIndex: Int {
        switch self {
        case .clubs: return 0
        case .diamonds: return 1
        case .spades: return 2
        case .hearts: return 3
        }
    }
}

enum Rank: Int, Codable, CaseIterable, Hashable, Comparable {
    case two = 2, three, four, five, six, seven, eight, nine, ten
    case jack, queen, king, ace

    var label: String {
        switch self {
        case .ace: return "A"
        case .king: return "K"
        case .queen: return "Q"
        case .jack: return "J"
        default: return String(rawValue)
        }
    }

    static func < (lhs: Rank, rhs: Rank) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct Card: Codable, Hashable, Identifiable {
    var suit: Suit
    var rank: Rank

    var id: String { rank.label + suit.rawValue }
    var label: String { rank.label + suit.symbol }

    static func standardDeck() -> [Card] {
        Suit.allCases.flatMap { suit in Rank.allCases.map { Card(suit: suit, rank: $0) } }
    }

    /// 24-card Euchre deck: 9 through Ace.
    static func euchreDeck() -> [Card] {
        Suit.allCases.flatMap { suit in
            Rank.allCases.filter { $0 >= .nine }.map { Card(suit: suit, rank: $0) }
        }
    }
}

extension Array where Element == Card {
    /// Sorted for hand display: grouped by suit, ascending rank.
    func displaySorted() -> [Card] {
        sorted { ($0.suit, $0.rank.rawValue) < ($1.suit, $1.rank.rawValue) }
    }

    func ofSuit(_ suit: Suit) -> [Card] { filter { $0.suit == suit } }
}

func < (lhs: (Suit, Int), rhs: (Suit, Int)) -> Bool {
    lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
}
