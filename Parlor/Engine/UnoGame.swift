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
    /// Seats that have announced "UNO!" (have exactly 1 card and called it).
    var calledUno: Set<Int> = []
    /// Lifetime action-card tallies for the deal, shown in resultText.
    var wildsPlayed = 0
    var reversesPlayed = 0
    var skipsPlayed = 0
    var forcedDrawCards = 0
    /// Largest hand size any seat has held this deal (a "stuck the longest" stat).
    var maxHandSize = [0, 0, 0, 0]
    /// Times each color was declared via a wild play.
    var wildColorCalls = [UnoColor: Int]()
    /// Consecutive turns seat 0 was forced to draw (without playing a card).
    var currentDrawStreak = 0
    var bestDrawStreak = 0
    /// Longest run of consecutive plays (any seat) with no draw in between.
    var currentPlayChain = 0
    var longestPlayChain = 0
    /// Times the draw pile was exhausted and reshuffled from the discard.
    var deckReshuffles = 0
    /// Consecutive wildDrawFour plays (streak tracker).
    var drawFourStreak: Int = 0
    var bestDrawFourStreak: Int = 0
    /// Total voluntary draw-one actions taken by each seat.
    var drawsBySeat: [Int] = [0, 0, 0, 0]
    /// Total Wild Draw Four cards played this deal.
    var wildDrawFoursPlayed: Int = 0
    /// Color declarations made via wild plays (separate from wildColorCalls for clarity).
    var colorsCalled: [UnoColor: Int] = [:]

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

    /// Emoji swatch for the active color.
    var currentColorEmoji: String {
        switch activeColor {
        case .red: return "🔴"
        case .yellow: return "🟡"
        case .green: return "🟢"
        case .blue: return "🔵"
        }
    }

    /// Points remaining in each hand (for standings display).
    var handPoints: [Int] { hands.map { $0.reduce(0) { $0 + $1.points } } }

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
        moves.append(.uno(.callUno))
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
            switch card.value {
            case .wild, .wildDrawFour:
                wildsPlayed += 1
                if let color = declared {
                    wildColorCalls[color, default: 0] += 1
                    colorsCalled[color, default: 0] += 1
                }
                if case .wildDrawFour = card.value {
                    wildDrawFoursPlayed += 1
                    drawFourStreak += 1
                    if drawFourStreak > bestDrawFourStreak { bestDrawFourStreak = drawFourStreak }
                } else {
                    drawFourStreak = 0
                }
            case .reverse:
                reversesPlayed += 1
                drawFourStreak = 0
            case .skip:
                skipsPlayed += 1
                drawFourStreak = 0
            case .number, .drawTwo:
                drawFourStreak = 0
            }
            if currentPlayer == 0 { currentDrawStreak = 0 }
            currentPlayChain += 1
            if currentPlayChain > longestPlayChain { longestPlayChain = currentPlayChain }
            lastAction = nil
            stalledTurns = 0
            calledUno.remove(currentPlayer)
            if hands[currentPlayer].isEmpty {
                winner = currentPlayer
                return
            }
            drewThisTurn = false
            resolveAction(card)
        case .draw:
            guard !drewThisTurn else { throw GameError.illegalMove }
            drawsBySeat[currentPlayer] += 1
            guard let card = drawCard() else {
                // Nothing left anywhere: pass — and if the whole table is
                // stuck, end the deal in favor of the lightest hand.
                stalledTurns += 1
                if stalledTurns >= 8 {
                    // Tiebreak by hand points; sort seats for determinism.
                    let pts = (0..<4).sorted { hands[$0].reduce(0) { $0 + $1.points } < hands[$1].reduce(0) { $0 + $1.points } }
                    winner = pts.first
                    return
                }
                advance()
                return
            }
            stalledTurns = 0
            currentPlayChain = 0
            calledUno.remove(currentPlayer)
            hands[currentPlayer].append(card)
            hands[currentPlayer].sort { $0.sortKey < $1.sortKey }
            maxHandSize[currentPlayer] = max(maxHandSize[currentPlayer], hands[currentPlayer].count)
            if canPlay(card) {
                drewThisTurn = true      // may play any legal card or pass
            } else {
                if currentPlayer == 0 {
                    currentDrawStreak += 1
                    if currentDrawStreak > bestDrawStreak { bestDrawStreak = currentDrawStreak }
                }
                advance()
            }
        case .pass:
            guard drewThisTurn else { throw GameError.illegalMove }
            drewThisTurn = false
            advance()
        case .callUno:
            // Mark UNO for seats with exactly 1 card (including current player pre-play).
            for seat in 0..<4 where hands[seat].count == 1 {
                calledUno.insert(seat)
            }
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
        forcedDrawCards += count
        for _ in 0..<count {
            guard let card = drawCard() else { return }
            hands[currentPlayer].append(card)
        }
        hands[currentPlayer].sort { $0.sortKey < $1.sortKey }
        maxHandSize[currentPlayer] = max(maxHandSize[currentPlayer], hands[currentPlayer].count)
    }

    private mutating func drawCard() -> UnoCard? {
        if drawPile.isEmpty, discard.count > 1 {
            // Reshuffle everything under the top card.
            let top = discard.removeLast()
            drawPile = discard.shuffled()
            discard = [top]
            deckReshuffles += 1
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
        let dirArrow = clockwise ? "→" : "←"
        var text = "\(currentColorEmoji) \(activeColor.rawValue.capitalized) · \(dirArrow)"
        if let lastAction { text += " · \(lastAction)" }
        let counts = hands.enumerated().map { "\($0.element.count)" }.joined(separator: "/")
        text += " · \(counts)"
        if drawPile.count <= 5 { text += " · ⚠️ pile \(drawPile.count)" }
        let unoCalls = calledUno.sorted().map { "S\($0 + 1)" }
        if !unoCalls.isEmpty { text += " · UNO: \(unoCalls.joined(separator: " "))" }
        // Flag any seat at exactly 1 card that has NOT called UNO (catchable).
        let exposed = (0..<4).filter { hands[$0].count == 1 && !calledUno.contains($0) }
        if !exposed.isEmpty {
            text += " · 🚨 " + exposed.map { "S\($0 + 1) no UNO!" }.joined(separator: " ")
        }
        // Highlight the closest threat to going out.
        if let threat = (0..<4).min(by: { hands[$0].count < hands[$1].count }),
           hands[threat].count <= 2, threat != currentPlayer {
            text += " · ⚠️ S\(threat + 1) has \(hands[threat].count)"
        }
        return text
    }

    /// Traditional Uno scoring: the winner collects the points left in every
    /// other player's hand.
    var winnerScore: Int {
        guard let winner else { return 0 }
        return (0..<4).filter { $0 != winner }
            .reduce(0) { $0 + hands[$1].reduce(0) { $0 + $1.points } }
    }

    var resultText: String? {
        guard let winner else { return nil }
        var text = "Seat \(winner + 1) wins the deal"
        if winnerScore > 0 { text += " (+\(winnerScore) pts)" }
        var stats: [String] = []
        if wildsPlayed > 0 { stats.append("\(wildsPlayed) wild\(wildsPlayed == 1 ? "" : "s")") }
        if skipsPlayed > 0 { stats.append("\(skipsPlayed) skip\(skipsPlayed == 1 ? "" : "s")") }
        if reversesPlayed > 0 { stats.append("\(reversesPlayed) reverse\(reversesPlayed == 1 ? "" : "s")") }
        if forcedDrawCards > 0 { stats.append("\(forcedDrawCards) forced draws") }
        if !stats.isEmpty { text += " · " + stats.joined(separator: " · ") }
        if let biggest = maxHandSize.indices.max(by: { maxHandSize[$0] < maxHandSize[$1] }), maxHandSize[biggest] > 7 {
            text += " · Seat \(biggest + 1) held \(maxHandSize[biggest]) at peak 😬"
        }
        // Wild Draw Four count
        if wildDrawFoursPlayed >= 2 { text += " · ⚡ WD4×\(wildDrawFoursPlayed)" }
        // Most-declared color via wilds
        if !colorsCalled.isEmpty {
            if let topColor = colorsCalled.max(by: { $0.value < $1.value }) {
                text += " · 🎨 \(topColor.key.rawValue.capitalized) called most (\(topColor.value)×)"
            }
        }
        // Wild color preference distribution
        if wildsPlayed >= 3, !wildColorCalls.isEmpty {
            if let favColor = wildColorCalls.max(by: { $0.value < $1.value }) {
                text += " · 🎨 favored \(favColor.key.rawValue.capitalized) \(favColor.value)×"
            }
        }
        // Check for rainbow player (called all 4 colors)
        if wildColorCalls.keys.count == UnoColor.allCases.count {
            text += " · 🌈 all 4 colors called"
        }
        if bestDrawStreak >= 4 { text += " · 😵 \(bestDrawStreak) forced draws in a row" }
        if bestDrawFourStreak >= 2 { text += " · 🃏 \(bestDrawFourStreak)-Draw4 streak" }
        if longestPlayChain >= 6 { text += " · ⚡ \(longestPlayChain)-play chain" }
        if deckReshuffles > 0 { text += " · 🔄 \(deckReshuffles) deck drought\(deckReshuffles == 1 ? "" : "s")" }
        // Comeback: the winner once held the biggest hand at the table.
        if let biggest = maxHandSize.indices.max(by: { maxHandSize[$0] < maxHandSize[$1] }),
           biggest == winner, maxHandSize[winner] >= 9 {
            text += " · 🔄 comeback from \(maxHandSize[winner]) cards!"
        }
        // Per-seat draw tally (only if anyone drew ≥2 total)
        let totalDraws = drawsBySeat.reduce(0, +)
        if totalDraws >= 4 {
            let drawSummary = drawsBySeat.enumerated()
                .map { i, d in "S\(i + 1):\(d)" }
                .joined(separator: " ")
            text += " · 🃏 draws: \(drawSummary)"
        }
        return text
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
