import Foundation

/// Crazy Eights for four players with a standard deck: match the discard's
/// suit or rank, eights are wild and nominate a suit, draw one when stuck
/// (play it or keep it), pass when the stock is gone. First out wins; the
/// rest rank by points left in hand (8 = 50, faces = 10, ace = 1).
///
/// Power cards:
///   2 — "draw two": next player must draw 2 (or stack another 2 to pass
///       the debt forward). Stacking resolves when a player can't or won't
///       stack — they draw the accumulated total.
///   Q — "skip": next player loses their turn.
///   8 — wild: nominate any suit.
struct EightsGame: GameEngine {
    static let kind = GameKind.eights

    var hands: [[Card]] = Array(repeating: [], count: 4)
    var stock: [Card] = []
    var discard: [Card] = []
    var activeSuit: Suit = .clubs
    var currentPlayer = 0
    var drewThisTurn = false
    var winner: Int? = nil
    var consecutivePasses = 0
    var endedByBlock = false
    /// Accumulated draw-two debt: the next player must draw this many or stack.
    var pendingDraw = 0
    /// True when the current player was skipped by a Queen.
    var wasSkipped = false
    /// Times an 8 was played and actually changed the active suit (shown in resultText).
    var suitChanges = 0
    /// Times the discard pile was recycled back into the stock when it ran dry.
    var stockReshuffles = 0
    /// Consecutive eights played in a row by any player.
    var currentEightStreak = 0
    var bestEightStreak = 0
    /// Total cards opponents were forced to draw via stacked 2s.
    var cardsForced = 0
    /// Largest single draw-two debt that ever resolved.
    var biggestDrawHit = 0
    /// Number of consecutive 2s currently stacked without resolution.
    var currentDrawChain = 0
    /// Peak consecutive 2s stacked in one chain this game.
    var maxDrawChain = 0
    /// Distinct suits that have been the active suit at any point (rainbow game = all 4).
    var suitsSeen: Set<Suit> = []
    /// Queens played (skips dealt out).
    var queensPlayed = 0
    /// Times an 8 was played (wild suit change).
    var eightPlays = 0
    /// Consecutive 8s played in a row (suit changes run).
    var currentSuitChangeRun: Int = 0
    var bestSuitChangeRun: Int = 0
    /// Total cards drawn by each seat (voluntary + forced).
    var cardsDrawnBySeat: [Int] = [0, 0, 0, 0]
    /// Peak accumulated draw-two debt that was ever pending at one time.
    var maxPendingDraw: Int = 0
    /// How many times each seat was skipped by a Queen this game.
    var skipCount: [Int] = [0, 0, 0, 0]

    init() {
        var deck = Card.standardDeck().shuffled()
        for seat in 0..<4 {
            hands[seat] = Array(deck.prefix(5)).displaySorted()
            deck.removeFirst(5)
        }
        while deck.first?.rank == .eight { deck.append(deck.removeFirst()) }
        let start = deck.removeFirst()
        discard = [start]
        activeSuit = start.suit
        suitsSeen = [start.suit]
        stock = deck
    }

    var isOver: Bool { winner != nil || endedByBlock }
    var topCard: Card? { discard.last }

    func canPlay(_ card: Card) -> Bool {
        // During a pending draw, only a 2 can be stacked.
        if pendingDraw > 0 { return card.rank == .two }
        if card.rank == .eight { return true }
        return card.suit == activeSuit || card.rank == topCard?.rank
    }

    func legalCards(for seat: Int) -> [Card] {
        hands[seat].filter { canPlay($0) }
    }

    func legalMoves() -> [Move] {
        guard !isOver else { return [] }
        var moves: [Move] = []
        for card in legalCards(for: currentPlayer) {
            if card.rank == .eight {
                for suit in Suit.allCases {
                    moves.append(.eights(.play(card, nominated: suit)))
                }
            } else {
                moves.append(.eights(.play(card, nominated: nil)))
            }
        }
        // If there's a pending draw and no 2 to stack, or stock gone, draw/pass.
        if pendingDraw > 0 {
            if legalCards(for: currentPlayer).isEmpty {
                moves.append(.eights(.draw))
            }
        } else if drewThisTurn || stock.isEmpty {
            moves.append(.eights(.pass))
        } else {
            moves.append(.eights(.draw))
        }
        return moves
    }

    mutating func apply(_ move: Move) throws {
        guard case .eights(let m) = move else { throw GameError.illegalMove }
        switch m {
        case .play(let card, let nominated):
            guard let index = hands[currentPlayer].firstIndex(of: card),
                  canPlay(card) else { throw GameError.illegalMove }
            if card.rank == .eight && nominated == nil { throw GameError.illegalMove }
            hands[currentPlayer].remove(at: index)
            discard.append(card)
            let newSuit = card.rank == .eight ? (nominated ?? card.suit) : card.suit
            if card.rank == .eight && newSuit != activeSuit { suitChanges += 1 }
            if card.rank == .eight {
                eightPlays += 1
                currentEightStreak += 1
                if currentEightStreak > bestEightStreak { bestEightStreak = currentEightStreak }
                currentSuitChangeRun += 1
                if currentSuitChangeRun > bestSuitChangeRun { bestSuitChangeRun = currentSuitChangeRun }
            } else {
                currentEightStreak = 0
                currentSuitChangeRun = 0
            }
            activeSuit = newSuit
            suitsSeen.insert(newSuit)
            consecutivePasses = 0
            drewThisTurn = false

            // Power card effects.
            let isTwo = card.rank == .two
            let isQueen = card.rank == .queen
            if isQueen { queensPlayed += 1 }
            if isTwo {
                pendingDraw += 2
                if pendingDraw > maxPendingDraw { maxPendingDraw = pendingDraw }
                currentDrawChain += 1
                if currentDrawChain > maxDrawChain { maxDrawChain = currentDrawChain }
            } else {
                pendingDraw = 0           // resolved by a non-2 play
                currentDrawChain = 0
            }

            if hands[currentPlayer].isEmpty {
                winner = currentPlayer
                return
            }
            currentPlayer = (currentPlayer + 1) % 4
            // Skip: queen skips the next player.
            if isQueen {
                wasSkipped = true
                skipCount[currentPlayer] += 1
                currentPlayer = (currentPlayer + 1) % 4
            } else {
                wasSkipped = false
            }
        case .draw:
            // Forced draw from pending debt, or voluntary single draw.
            let drawCount = pendingDraw > 0 ? pendingDraw : 1
            if pendingDraw > 0 {
                cardsForced += pendingDraw
                biggestDrawHit = max(biggestDrawHit, pendingDraw)
            }
            cardsDrawnBySeat[currentPlayer] += drawCount
            pendingDraw = 0
            currentDrawChain = 0
            for _ in 0..<drawCount {
                if stock.isEmpty, discard.count > 1 {
                    // Reshuffle all but the top discard card back into stock.
                    let top = discard.removeLast()
                    stock = discard.shuffled()
                    discard = [top]
                    stockReshuffles += 1
                }
                guard !stock.isEmpty else { break }
                let card = stock.removeLast()
                hands[currentPlayer].append(card)
            }
            hands[currentPlayer] = hands[currentPlayer].displaySorted()
            consecutivePasses = 0
            if drawCount == 1, let last = hands[currentPlayer].last, canPlay(last) {
                drewThisTurn = true
            } else {
                drewThisTurn = false
                currentPlayer = (currentPlayer + 1) % 4
            }
        case .pass:
            guard drewThisTurn || stock.isEmpty else { throw GameError.illegalMove }
            drewThisTurn = false
            consecutivePasses += 1
            if consecutivePasses >= 4 {
                endedByBlock = true
                return
            }
            currentPlayer = (currentPlayer + 1) % 4
        }
    }

    func handPoints(_ seat: Int) -> Int {
        hands[seat].reduce(0) { total, card in
            switch card.rank {
            case .eight: return total + 50
            case .king, .queen, .jack: return total + 10
            case .ace: return total + 1
            case .ten: return total + 10
            default: return total + card.rank.rawValue
            }
        }
    }

    func ranking() -> [[Int]] {
        guard isOver else { return [] }
        if let winner {
            let losers = (0..<4).filter { $0 != winner }
            let grouped = Dictionary(grouping: losers, by: handPoints)
            return [[winner]] + grouped.keys.sorted().map { grouped[$0]!.sorted() }
        }
        let grouped = Dictionary(grouping: 0..<4, by: handPoints)
        return grouped.keys.sorted().map { grouped[$0]!.sorted() }
    }

    func redacted(for seat: Int) -> EightsGame {
        var copy = self
        let blank = Card(suit: .clubs, rank: .two)
        for other in 0..<4 where other != seat {
            copy.hands[other] = Array(repeating: blank, count: hands[other].count)
        }
        copy.stock = Array(repeating: blank, count: stock.count)
        return copy
    }

    var statusText: String {
        if isOver { return resultText ?? "Game over" }
        var text = "\(activeSuit.symbol) · stock \(stock.count)"
        if pendingDraw > 0 { text += " · DRAW \(pendingDraw)!" }
        if wasSkipped { text += " · SKIP" }
        let counts = (0..<4).map { "\(hands[$0].count)" }.joined(separator: "/")
        text += " · hands \(counts)"
        if let threat = (0..<4).min(by: { hands[$0].count < hands[$1].count }), hands[threat].count == 1 {
            text += " · 🚨 Seat \(threat + 1) on last card!"
        }
        return text
    }

    var resultText: String? {
        var extras = suitChanges > 0 ? " · 🃏 \(suitChanges) suit change\(suitChanges == 1 ? "" : "s")" : ""
        if eightPlays > 0 { extras += " · 8️⃣ \(eightPlays) eight\(eightPlays == 1 ? "" : "s") played" }
        if stockReshuffles > 0 { extras += " · \(stockReshuffles) reshuffle\(stockReshuffles == 1 ? "" : "s")" }
        if bestEightStreak >= 3 { extras += " · ×\(bestEightStreak) eights streak!" }
        if cardsForced > 0 { extras += " · ➕ \(cardsForced) cards forced" }
        if biggestDrawHit >= 4 { extras += " · 💥 \(biggestDrawHit)-card stack hit" }
        if suitsSeen.count == 4 { extras += " · 🌈 Rainbow game!" }
        if queensPlayed > 0 { extras += " · 👸 \(queensPlayed) skip\(queensPlayed == 1 ? "" : "s")" }
        if bestSuitChangeRun >= 3 { extras += " · 🔄 best \(bestSuitChangeRun)-change run" }
        // Max draw chain (peak draw-two debt in one chain)
        if maxPendingDraw >= 4 { extras += " · Max draw chain: \(maxPendingDraw)" }
        // Per-seat skip tally (Queens played against each seat)
        let totalSkips = skipCount.reduce(0, +)
        if totalSkips >= 2 {
            if let mostSkipped = skipCount.indices.max(by: { skipCount[$0] < skipCount[$1] }),
               skipCount[mostSkipped] >= 2 {
                extras += " · 👸 S\(mostSkipped + 1) skipped \(skipCount[mostSkipped])×"
            }
        }
        if let winner { return "Seat \(winner + 1) goes out first!\(extras)" }
        if endedByBlock {
            let best = (0..<4).min { handPoints($0) < handPoints($1) } ?? 0
            return "Blocked — Seat \(best + 1) wins with fewest points\(extras)"
        }
        return nil
    }
}
