import Foundation

/// Wildcard (UNO-style shedding) for four players. Match the discard by
/// color or value; skips, reverses, draw-twos, wilds, and wild-draw-fours
/// all behave classically (no stacking). Draw one when stuck — play it or
/// keep it. First hand to empty wins the deal; everyone else ranks by the
/// points left in hand (lower is better).
struct UnoGame: GameEngine {
    static let kind = GameKind.uno

    var hands: [[UnoCard]] = Array(repeating: [], count: 4)
    var drawPile: [UnoCard] = []
    var discard: [UnoCard] = []
    /// Color in force (follows the top card; set by wild plays).
    var activeColor: UnoColor = .red
    var currentPlayer = 0
    var clockwise = true
    /// Player who drew this turn and may still play or pass.
    var drewThisTurn = false
    var winner: Int? = nil
    var lastAction: String? = nil
    /// Consecutive turns with no card played or drawn (deck fully stuck).
    var stalledTurns = 0

    init() {
        var id = 0
        var deck: [UnoCard] = []
        for color in UnoColor.allCases {
            deck.append(UnoCard(id: id, color: color, value: .number(0))); id += 1
            for n in 1...9 {
                deck.append(UnoCard(id: id, color: color, value: .number(n))); id += 1
                deck.append(UnoCard(id: id, color: color, value: .number(n))); id += 1
            }
            for _ in 0..<2 {
                deck.append(UnoCard(id: id, color: color, value: .skip)); id += 1
                deck.append(UnoCard(id: id, color: color, value: .reverse)); id += 1
                deck.append(UnoCard(id: id, color: color, value: .drawTwo)); id += 1
            }
        }
        for _ in 0..<4 {
            deck.append(UnoCard(id: id, color: nil, value: .wild)); id += 1
            deck.append(UnoCard(id: id, color: nil, value: .wildDrawFour)); id += 1
        }
        deck.shuffle()
        for seat in 0..<4 {
            hands[seat] = Array(deck.prefix(7)).sorted { $0.sortKey < $1.sortKey }
            deck.removeFirst(7)
        }
        // Flip a starting number card (action cards go back under).
        while let top = deck.first, top.color == nil || !top.isNumber {
            deck.append(deck.removeFirst())
        }
        let start = deck.removeFirst()
        discard = [start]
        activeColor = start.color ?? .red
        drawPile = deck
    }

    var currentPlayerSeat: Int { currentPlayer }
    var isOver: Bool { winner != nil }
    var topCard: UnoCard? { discard.last }

    func canPlay(_ card: UnoCard) -> Bool {
        guard let top = topCard else { return true }
        if card.color == nil { return true }                     // wilds always
        if card.color == activeColor { return true }
        return card.value.matchesValue(top.value)
    }

    func legalCards(for seat: Int) -> [UnoCard] {
        hands[seat].filter { canPlay($0) }
    }

    func legalMoves() -> [Move] {
        guard !isOver else { return [] }
        var moves: [Move] = []
        for card in legalCards(for: currentPlayer) {
            if card.color == nil {
                for color in UnoColor.allCases {
                    moves.append(.uno(.play(card, declared: color)))
                }
            } else {
                moves.append(.uno(.play(card, declared: nil)))
            }
        }
        if drewThisTurn {
            moves.append(.uno(.pass))
        } else {
            moves.append(.uno(.draw))
        }
        return moves
    }

    mutating func apply(_ move: Move) throws {
        guard case .uno(let m) = move else { throw GameError.illegalMove }
        switch m {
        case .play(let card, let declared):
            guard let index = hands[currentPlayer].firstIndex(of: card),
                  canPlay(card) else { throw GameError.illegalMove }
            if card.color == nil && declared == nil { throw GameError.illegalMove }
            hands[currentPlayer].remove(at: index)
            discard.append(card)
            activeColor = card.color ?? declared ?? .red
            lastAction = nil
            stalledTurns = 0
            if hands[currentPlayer].isEmpty {
                winner = currentPlayer
                return
            }
            drewThisTurn = false
            resolveAction(card)
        case .draw:
            guard !drewThisTurn else { throw GameError.illegalMove }
            guard let card = drawCard() else {
                // Nothing left anywhere: pass — and if the whole table is
                // stuck, end the deal in favor of the lightest hand.
                stalledTurns += 1
                if stalledTurns >= 8 {
                    winner = (0..<4).min {
                        hands[$0].reduce(0) { $0 + $1.points } < hands[$1].reduce(0) { $0 + $1.points }
                    }
                    return
                }
                advance()
                return
            }
            stalledTurns = 0
            hands[currentPlayer].append(card)
            hands[currentPlayer].sort { $0.sortKey < $1.sortKey }
            if canPlay(card) {
                drewThisTurn = true      // may play any legal card or pass
            } else {
                advance()
            }
        case .pass:
            guard drewThisTurn else { throw GameError.illegalMove }
            drewThisTurn = false
            advance()
        }
    }

    private mutating func resolveAction(_ card: UnoCard) {
        switch card.value {
        case .skip:
            lastAction = "skipped"
            advance(); advance()
        case .reverse:
            clockwise.toggle()
            lastAction = "reversed"
            advance()
        case .drawTwo:
            advance()
            forceDraw(2)
            lastAction = "drew 2 and lost the turn"
            advance()
        case .wildDrawFour:
            advance()
            forceDraw(4)
            lastAction = "drew 4 and lost the turn"
            advance()
        case .wild, .number:
            advance()
        }
    }

    private mutating func forceDraw(_ count: Int) {
        for _ in 0..<count {
            guard let card = drawCard() else { return }
            hands[currentPlayer].append(card)
        }
        hands[currentPlayer].sort { $0.sortKey < $1.sortKey }
    }

    private mutating func drawCard() -> UnoCard? {
        if drawPile.isEmpty, discard.count > 1 {
            // Reshuffle everything under the top card.
            let top = discard.removeLast()
            drawPile = discard.shuffled()
            discard = [top]
        }
        return drawPile.popLast()
    }

    private mutating func advance() {
        currentPlayer = (currentPlayer + (clockwise ? 1 : 3)) % 4
    }

    func ranking() -> [[Int]] {
        guard let winner else { return [] }
        let losers = (0..<4).filter { $0 != winner }
        let grouped = Dictionary(grouping: losers) { hands[$0].reduce(0) { $0 + $1.points } }
        return [[winner]] + grouped.keys.sorted().map { grouped[$0]!.sorted() }
    }

    func redacted(for seat: Int) -> UnoGame {
        var copy = self
        for other in 0..<4 where other != seat {
            copy.hands[other] = copy.hands[other].map {
                UnoCard(id: $0.id, color: nil, value: .number(-1))
            }
        }
        copy.drawPile = copy.drawPile.map { UnoCard(id: $0.id, color: nil, value: .number(-1)) }
        return copy
    }

    var statusText: String {
        if let winner { return "Seat \(winner + 1) goes out!" }
        var text = "\(activeColor.rawValue.capitalized) in play"
        if let lastAction { text += " · \(lastAction)" }
        if let smallest = hands.map(\.count).min(), smallest == 1 { text += " · someone's on their last card!" }
        return text
    }

    var resultText: String? {
        guard let winner else { return nil }
        return "Seat \(winner + 1) wins the deal"
    }
}

extension UnoCard {
    var isNumber: Bool {
        if case .number = value { return true }
        return false
    }

    var points: Int {
        switch value {
        case .number(let n): return max(n, 0)
        case .skip, .reverse, .drawTwo: return 20
        case .wild, .wildDrawFour: return 50
        }
    }

    var sortKey: Int {
        let colorOrder: Int
        switch color {
        case .red: colorOrder = 0
        case .yellow: colorOrder = 1
        case .green: colorOrder = 2
        case .blue: colorOrder = 3
        case nil: colorOrder = 4
        }
        return colorOrder * 100 + valueOrder
    }

    private var valueOrder: Int {
        switch value {
        case .number(let n): return n
        case .skip: return 10
        case .reverse: return 11
        case .drawTwo: return 12
        case .wild: return 13
        case .wildDrawFour: return 14
        }
    }
}

extension UnoValue {
    func matchesValue(_ other: UnoValue) -> Bool {
        switch (self, other) {
        case (.number(let a), .number(let b)): return a == b
        case (.skip, .skip), (.reverse, .reverse), (.drawTwo, .drawTwo): return true
        default: return false
        }
    }
}
