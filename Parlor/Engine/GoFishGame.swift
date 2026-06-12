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

    /// Ranks the seat may ask for (must hold at least one).
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
        // Empty hand or no valid target: draw (modeled as asking nobody is
        // not allowed, so refill instead).
        if moves.isEmpty {
            moves.append(.fish(.ask(seat: (currentPlayer + 1) % 4, rank: .ace)))
        }
        return moves
    }

    func isLegal(_ move: Move) -> Bool {
        guard case .fish(.ask(let target, let rank)) = move, !isOver,
              target != currentPlayer, (0..<4).contains(target) else { return false }
        // A player with no askable rank gets a free pass-style ask.
        if askableRanks(for: currentPlayer).isEmpty { return true }
        return hands[currentPlayer].contains { $0.rank == rank } && !hands[target].isEmpty
    }

    mutating func apply(_ move: Move) throws {
        guard case .fish(.ask(let target, let rank)) = move else { throw GameError.illegalMove }

        // Out of cards: draw up to 5 to get back in the game, then the turn passes.
        if hands[currentPlayer].isEmpty {
            refill(currentPlayer)
            advanceIfStuck()
            return
        }

        let matches = hands[target].filter { $0.rank == rank }
        if !matches.isEmpty {
            hands[target].removeAll { $0.rank == rank }
            hands[currentPlayer].append(contentsOf: matches)
            hands[currentPlayer] = hands[currentPlayer].displaySorted()
            lastEvent = "took \(matches.count) \(rank.label)\(matches.count == 1 ? "" : "s")"
            layDownBooks(currentPlayer)
            advanceIfStuck(keepTurn: true)
        } else {
            // Go fish.
            if let drawn = stock.popLast() {
                hands[currentPlayer].append(drawn)
                hands[currentPlayer] = hands[currentPlayer].displaySorted()
                layDownBooks(currentPlayer)
                if drawn.rank == rank {
                    lastEvent = "fished up the \(rank.label)!"
                    advanceIfStuck(keepTurn: true)
                    return
                }
            }
            lastEvent = "go fish"
            advanceIfStuck()
        }
    }

    /// Move the turn (or keep it), skipping players who are stuck with no
    /// cards once the stock is empty.
    private mutating func advanceIfStuck(keepTurn: Bool = false) {
        if !keepTurn { currentPlayer = (currentPlayer + 1) % 4 }
        var hops = 0
        while !isOver && hops < 4 {
            if hands[currentPlayer].isEmpty {
                refill(currentPlayer)
            }
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
        var text = "Books \(totalBooks)/13 · stock \(stock.count)"
        if let lastEvent { text += " · \(lastEvent)" }
        return text
    }

    var resultText: String? {
        guard isOver else { return nil }
        let best = books.map(\.count).max() ?? 0
        let winners = (0..<4).filter { books[$0].count == best }.map { "Seat \($0 + 1)" }
        return "\(winners.joined(separator: " & ")) win\(winners.count == 1 ? "s" : "") with \(best) books"
    }
}
