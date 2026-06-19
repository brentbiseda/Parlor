import Foundation

/// Go Fish for four players: ask anyone for a rank you hold; take all
/// matches and go again, or "go fish" — draw one, and keep the turn only if
/// you fish up the asked rank. Four of a kind lays down as a book. When all
/// 13 books are made, the most books wins.
struct GoFishGame: GameEngine {
    static let kind = GameKind.gofish

    var hands: [[Card]] = Array(repeating: [], count: 4)
    var stock: [Card] = []
    var books: [[Rank]] = Array(repeating: [], count: 4)
    var currentPlayer = 0
    var lastEvent: String? = nil
    /// Most recently completed book ("Seat 2 booked Ks!"), cleared on next ask.
    var lastBookEvent: String? = nil
    /// Books completed by a lucky pond draw (the 4th card came straight off the stock).
    var luckyPondBooks = 0
    /// Current human-player consecutive successful asks (resets on "Go fish!").
    var askStreak = 0
    var bestAskStreak = 0
    /// Table-wide ask tally: total asks and ones that landed a match.
    var totalAsks = 0
    var successfulAsks = 0
    /// Largest single haul (cards received from one ask).
    var biggestHaul = 0
    /// Per-seat: how many times each opponent gave cards to the current player (asks that landed).
    var asksLandedBySeat: [Int] = [0, 0, 0, 0]
    /// Per-seat: total cards drawn from stock (pond draws).
    var pondDrawsBySeat: [Int] = [0, 0, 0, 0]

    init() {
        var deck = Card.standardDeck().shuffled()
        for seat in 0..<4 {
            hands[seat] = Array(deck.prefix(5)).displaySorted()
            deck.removeFirst(5)
        }
        stock = deck
        for seat in 0..<4 { layDownBooks(seat) }
    }

    var totalBooks: Int { books.reduce(0) { $0 + $1.count } }
    var isOver: Bool { totalBooks == 13 }

    func askableRanks(for seat: Int) -> [Rank] {
        Array(Set(hands[seat].map(\.rank))).sorted()
    }

    func legalMoves() -> [Move] {
        guard !isOver else { return [] }
        var moves: [Move] = []
        for rank in askableRanks(for: currentPlayer) {
            for target in 0..<4 where target != currentPlayer && !hands[target].isEmpty {
                moves.append(.fish(.ask(seat: target, rank: rank)))
            }
        }
        if moves.isEmpty {
            let fallbackTarget = (1..<4)
                .map { (currentPlayer + $0) % 4 }
                .first { !hands[$0].isEmpty } ?? (currentPlayer + 1) % 4
            let fallbackRank = askableRanks(for: currentPlayer).first ?? .ace
            moves.append(.fish(.ask(seat: fallbackTarget, rank: fallbackRank)))
        }
        return moves
    }

    func isLegal(_ move: Move) -> Bool {
        guard case .fish(.ask(let target, let rank)) = move, !isOver,
              target != currentPlayer, (0..<4).contains(target) else { return false }
        if askableRanks(for: currentPlayer).isEmpty { return true }
        return hands[currentPlayer].contains { $0.rank == rank } && !hands[target].isEmpty
    }

    mutating func apply(_ move: Move) throws {
        guard case .fish(.ask(let target, let rank)) = move else { throw GameError.illegalMove }
        lastBookEvent = nil

        if hands[currentPlayer].isEmpty {
            refill(currentPlayer)
            advanceIfStuck()
            return
        }

        totalAsks += 1
        let matches = hands[target].filter { $0.rank == rank }
        if !matches.isEmpty {
            successfulAsks += 1
            asksLandedBySeat[target] += 1
            if matches.count > biggestHaul { biggestHaul = matches.count }
            hands[target].removeAll { $0.rank == rank }
            hands[currentPlayer].append(contentsOf: matches)
            hands[currentPlayer] = hands[currentPlayer].displaySorted()
            let plural = matches.count == 1 ? "" : "s"
            lastEvent = "S\(currentPlayer + 1) asked S\(target + 1) for \(rank.label)s — got \(matches.count) card\(plural)"
            let booksBefore = books[currentPlayer].count
            layDownBooks(currentPlayer)
            if books[currentPlayer].count > booksBefore {
                lastBookEvent = "S\(currentPlayer + 1) books \(rank.label)s! (\(books[currentPlayer].count) books)"
            }
            currentPondDrySpell = 0
            if currentPlayer == 0 { askStreak += 1; if askStreak > bestAskStreak { bestAskStreak = askStreak } }
            advanceIfStuck(keepTurn: true)
        } else {
            if currentPlayer == 0 { askStreak = 0 }
            pondDrawsBySeat[currentPlayer] += 1
            if let drawn = stock.popLast() {
                hands[currentPlayer].append(drawn)
                hands[currentPlayer] = hands[currentPlayer].displaySorted()
                let booksBefore = books[currentPlayer].count
                layDownBooks(currentPlayer)
                if books[currentPlayer].count > booksBefore {
                    luckyPondBooks += 1
                    lastBookEvent = "🍀 S\(currentPlayer + 1) books \(drawn.rank.label)s from the pond!"
                }
                if drawn.rank == rank {
                    lastEvent = "S\(currentPlayer + 1) asked S\(target + 1) for \(rank.label)s — fished one up!"
                    if currentPlayer == 0 { askStreak += 1; if askStreak > bestAskStreak { bestAskStreak = askStreak } }
                    advanceIfStuck(keepTurn: true)
                    return
                }
            }
            lastEvent = "S\(currentPlayer + 1) asked S\(target + 1) for \(rank.label)s — go fish"
            currentPondDrySpell += 1
            if currentPondDrySpell > pondDrySpells { pondDrySpells = currentPondDrySpell }
            advanceIfStuck()
        }
    }

    private mutating func advanceIfStuck(keepTurn: Bool = false) {
        if !keepTurn { currentPlayer = (currentPlayer + 1) % 4 }
        var hops = 0
        while !isOver && hops < 4 {
            if hands[currentPlayer].isEmpty { refill(currentPlayer) }
            if !hands[currentPlayer].isEmpty { return }
            currentPlayer = (currentPlayer + 1) % 4
            hops += 1
        }
    }

    private mutating func refill(_ seat: Int) {
        guard hands[seat].isEmpty, !stock.isEmpty else { return }
        hands[seat] = Array(stock.suffix(5)).displaySorted()
        stock.removeLast(min(5, stock.count))
        layDownBooks(seat)
    }

    private mutating func layDownBooks(_ seat: Int) {
        let byRank = Dictionary(grouping: hands[seat], by: \.rank)
        for (rank, cards) in byRank where cards.count == 4 {
            hands[seat].removeAll { $0.rank == rank }
            books[seat].append(rank)
        }
    }

    func ranking() -> [[Int]] {
        guard isOver else { return [] }
        let grouped = Dictionary(grouping: 0..<4) { books[$0].count }
        return grouped.keys.sorted(by: >).map { grouped[$0]!.sorted() }
    }

    func redacted(for seat: Int) -> GoFishGame {
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
        let bookStr = books.enumerated().map { "S\($0 + 1):\($1.count)" }.joined(separator: " ")
        let handStr = hands.enumerated().map { "S\($0 + 1):\($1.count)🃏" }.joined(separator: " ")
        let pondStr = stock.isEmpty ? "pond empty" : "pond \(stock.count)"
        var text = "Books \(totalBooks)/13 · \(pondStr) · \(bookStr) · hands \(handStr)"
        let topBooks = books.map(\.count).max() ?? 0
        if topBooks > 0 {
            let leaders = (0..<4).filter { books[$0].count == topBooks }
            if leaders.count == 1 { text += " · 👑 S\(leaders[0] + 1) leads" }
        }
        if totalAsks > 0 {
            let pct = totalAsks > 0 ? Int(Double(successfulAsks) * 100 / Double(totalAsks)) : 0
            text += " · 🎣 \(pct)%"
        }
        if let ev = lastBookEvent { text += " · \(ev)" }
        else if let ev = lastEvent { text += " · \(ev)" }
        return text
    }

    /// Count of consecutive "Go fish!" responses (pond dry spells)
    var pondDrySpells = 0
    private var currentPondDrySpell = 0
    /// Alias for luckyPondBooks — ponds books where the drawn card immediately completes a set.
    var pondLuck: Int { luckyPondBooks }

    var resultText: String? {
        guard isOver else { return nil }
        let best = books.map(\.count).max() ?? 0
        let bookStr = books.enumerated().map { "S\($0 + 1):\($1.count)" }.joined(separator: " ")
        let winners = (0..<4).filter { books[$0].count == best }.map { "Seat \($0 + 1)" }
        var text = "\(winners.joined(separator: " & ")) win with \(best) books [\(bookStr)]"
        if luckyPondBooks > 0 { text += " · 🌊×\(luckyPondBooks) lucky pond" }
        if bestAskStreak >= 3 { text += " · 🔥 \(bestAskStreak)-ask streak" }
        if biggestHaul >= 2 { text += " · 🎣 Biggest haul: \(biggestHaul)" }
        if totalAsks > 0 {
            let pct = Int((Double(successfulAsks) / Double(totalAsks)) * 100)
            text += " · asked \(totalAsks)× (\(pct)% hit)"
        }
        if pondDrySpells >= 3 { text += " · 🌵 \(pondDrySpells) go-fish in a row" }
        // Show per-seat pond draw counts if any seat drew notably more
        if let heaviestFisher = pondDrawsBySeat.indices.max(by: { pondDrawsBySeat[$0] < pondDrawsBySeat[$1] }),
           pondDrawsBySeat[heaviestFisher] >= 5 {
            text += " · 🎣 S\(heaviestFisher + 1) fished \(pondDrawsBySeat[heaviestFisher])×"
        }
        return text
    }
}
