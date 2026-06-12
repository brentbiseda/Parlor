import Foundation

/// Bot opponents at three strengths:
/// - **easy** — random legal moves everywhere (even bids), good for learning;
/// - **normal** — sensible bids and calls, casual random card play;
/// - **hard** — counts the trick, ducks points in Hearts, wins cheaply in
///   trump games, takes and protects material in chess/checkers, and grabs
///   captures in Go.
enum Bot {
    static func chooseMove(for game: AnyGame, difficulty: BotDifficulty = .normal) -> Move? {
        switch difficulty {
        case .easy:
            return easyMove(game)
        case .normal:
            return normalMove(game)
        case .hard:
            return hardMove(game) ?? normalMove(game)
        }
    }

    // MARK: - Easy

    private static func easyMove(_ game: AnyGame) -> Move? {
        // Go still needs the eye-avoiding pass logic or games never end.
        if let g = game.engine as? GoGame { return goBotMove(game: g, difficulty: .easy) }
        let moves = game.legalMoves().filter { $0 != .resign }
        return moves.randomElement() ?? game.legalMoves().first
    }

    // MARK: - Normal (bidding judgment, casual play)

    private static func normalMove(_ game: AnyGame) -> Move? {
        switch game.engine {
        case let g as SpadesGame where g.phase == .bidding:
            return .bid(estimateSpadesBid(hand: g.hands[g.currentPlayer]))
        case let g as BridgeGame where g.phase == .auction:
            return .bridgeCall(bridgeBotCall(game: g))
        case let g as EuchreGame where g.phase == .orderingUp || g.phase == .callingTrump:
            return .euchreCall(euchreBotCall(game: g))
        case let g as GoGame:
            return goBotMove(game: g, difficulty: .normal)
        case is UnoGame, is EightsGame:
            // Casual but not silly: play a random card when one is playable
            // rather than drawing for no reason.
            let moves = game.legalMoves()
            let plays = moves.filter {
                if case .uno(.play) = $0 { return true }
                if case .eights(.play) = $0 { return true }
                return false
            }
            return plays.randomElement() ?? moves.randomElement()
        default:
            let moves = game.legalMoves().filter { $0 != .resign }
            return moves.randomElement() ?? game.legalMoves().first
        }
    }

    // MARK: - Hard

    private static func hardMove(_ game: AnyGame) -> Move? {
        switch game.engine {
        case let g as HeartsGame where g.phase == .passing:
            return .passCards(hardHeartsPass(g))
        case let g as HeartsGame where g.phase == .playing:
            return hardHeartsPlay(g).map { .playCard($0) }
        case let g as SpadesGame where g.phase == .playing:
            let seat = g.currentPlayer
            let card = hardTrickPlay(legal: g.legalCards(), trick: g.trick,
                                     partner: (seat + 2) % 4,
                                     suitOf: { $0.suit },
                                     value: { TrickTaking.trumpValue($0, trump: .spades) })
            return card.map { .playCard($0) }
        case let g as EuchreGame where g.phase == .playing:
            let seat = g.currentPlayer
            let partner = (seat + 2) % 4
            let card = hardTrickPlay(legal: g.legalCards(), trick: g.trick,
                                     partner: partner == g.sittingOut ? nil : partner,
                                     suitOf: g.effectiveSuit,
                                     value: g.cardValue)
            return card.map { .playCard($0) }
        case let g as BridgeGame where g.phase == .playing:
            let seat = g.currentPlayer
            let trump = g.contract?.strain.suit
            let card = hardTrickPlay(legal: g.legalCards(), trick: g.trick,
                                     partner: (seat + 2) % 4,
                                     suitOf: { $0.suit },
                                     value: { TrickTaking.trumpValue($0, trump: trump) })
            return card.map { .playCard($0) }
        case let g as ChessGame:
            return hardChessMove(g)
        case let g as CheckersGame:
            return hardCheckersMove(g)
        case let g as GoGame:
            return goBotMove(game: g, difficulty: .hard)
        case let g as UnoGame:
            return hardUnoMove(g)
        case let g as EightsGame:
            return hardEightsMove(g)
        case let g as GoFishGame:
            return hardGoFishMove(g)
        default:
            return nil   // bidding phases & solo games fall through to normal
        }
    }

    // MARK: - Shedding & fishing games

    /// Dump expensive action cards early, keep wilds for emergencies, and
    /// declare the color we hold the most of.
    static func hardUnoMove(_ g: UnoGame) -> Move? {
        let seat = g.currentPlayer
        let legal = g.legalCards(for: seat)
        guard !legal.isEmpty else {
            return g.drewThisTurn ? .uno(.pass) : .uno(.draw)
        }
        func colorCount(_ color: UnoColor) -> Int {
            g.hands[seat].filter { $0.color == color }.count
        }
        let bestColor = UnoColor.allCases.max { colorCount($0) < colorCount($1) } ?? .red
        // Prefer colored cards (saving wilds), action cards before numbers.
        let colored = legal.filter { $0.color != nil }
        if let pick = colored.max(by: { $0.points < $1.points }) {
            return .uno(.play(pick, declared: nil))
        }
        let wild = legal.first { $0.color == nil }
        return wild.map { .uno(.play($0, declared: bestColor)) }
    }

    /// Save eights for when we're stuck; otherwise shed the priciest card.
    static func hardEightsMove(_ g: EightsGame) -> Move? {
        let seat = g.currentPlayer
        let legal = g.legalCards(for: seat)
        let nonEights = legal.filter { $0.rank != .eight }
        if let pick = nonEights.max(by: { $0.rank.rawValue < $1.rank.rawValue }) {
            return .eights(.play(pick, nominated: nil))
        }
        if let eight = legal.first {
            let suits = Dictionary(grouping: g.hands[seat].filter { $0.rank != .eight }, by: \.suit)
            let best = suits.max { $0.value.count < $1.value.count }?.key ?? eight.suit
            return .eights(.play(eight, nominated: best))
        }
        if g.drewThisTurn || g.stock.isEmpty { return .eights(.pass) }
        return .eights(.draw)
    }

    /// Ask for a rank we're closest to booking, from a random live hand.
    /// (Random target/rank choice matters: a deterministic asker can chase
    /// the wrong player forever once the stock runs dry.)
    static func hardGoFishMove(_ g: GoFishGame) -> Move? {
        let seat = g.currentPlayer
        let counts = Dictionary(grouping: g.hands[seat], by: \.rank)
        guard let bestCount = counts.values.map(\.count).max() else {
            return g.legalMoves().randomElement()
        }
        let candidates = counts.filter { $0.value.count >= max(bestCount - 1, 1) }.keys
        guard let rank = candidates.randomElement(),
              let target = (0..<4).filter({ $0 != seat && !g.hands[$0].isEmpty }).randomElement()
        else { return g.legalMoves().randomElement() }
        return .fish(.ask(seat: target, rank: rank))
    }

    // MARK: - Hearts judgment

    private static let queenOfSpades = Card(suit: .spades, rank: .queen)

    private static func heartsPoints(_ card: Card) -> Int {
        if card == queenOfSpades { return 13 }
        return card.suit == .hearts ? 1 : 0
    }

    /// Pass the dangerous cards: Q♠ first, then big spades, then high hearts,
    /// then the highest of everything else.
    static func hardHeartsPass(_ g: HeartsGame) -> [Card] {
        let hand = g.hands[g.currentPlayer]
        let ranked = hand.sorted { a, b in
            func danger(_ c: Card) -> Int {
                if c == queenOfSpades { return 1000 }
                if c.suit == .spades && c.rank >= .king { return 900 + c.rank.rawValue }
                if c.suit == .hearts { return 500 + c.rank.rawValue }
                return c.rank.rawValue
            }
            return danger(a) > danger(b)
        }
        return Array(ranked.prefix(3)).displaySorted()
    }

    static func hardHeartsPlay(_ g: HeartsGame) -> Card? {
        let legal = g.legalCards()
        guard !legal.isEmpty else { return nil }

        if g.trick.isEmpty {
            // Lead low, preferring non-hearts.
            return legal.min {
                ($0.suit == .hearts ? 1 : 0, $0.rank.rawValue) < ($1.suit == .hearts ? 1 : 0, $1.rank.rawValue)
            }
        }

        let led = g.trick[0].card.suit
        let following = legal.filter { $0.suit == led }
        let winningRank = g.trick.filter { $0.card.suit == led }.map(\.card.rank.rawValue).max() ?? 0

        if !following.isEmpty {
            let ducks = following.filter { $0.rank.rawValue < winningRank }
            if !ducks.isEmpty {
                // Slip the Q♠ under a higher spade when we safely can.
                if led == .spades, ducks.contains(queenOfSpades) { return queenOfSpades }
                return ducks.max { $0.rank.rawValue < $1.rank.rawValue }
            }
            // Forced to win: shed the highest card, but cling to the Q♠.
            let candidates = following.filter { $0 != queenOfSpades }
            return (candidates.isEmpty ? following : candidates)
                .max { $0.rank.rawValue < $1.rank.rawValue }
        }

        // Void in the led suit: unload the most dangerous card.
        if legal.contains(queenOfSpades) { return queenOfSpades }
        if let bigSpade = legal.filter({ $0.suit == .spades && $0.rank >= .king })
            .max(by: { $0.rank.rawValue < $1.rank.rawValue }) {
            return bigSpade
        }
        if let heart = legal.filter({ $0.suit == .hearts })
            .max(by: { $0.rank.rawValue < $1.rank.rawValue }) {
            return heart
        }
        return legal.max { $0.rank.rawValue < $1.rank.rawValue }
    }

    // MARK: - Trump-game judgment (Spades, Euchre, Bridge)

    /// Duck cheaply when partner has the trick, win as cheaply as possible
    /// otherwise, and throw the lowest card when the trick is lost.
    static func hardTrickPlay(legal: [Card], trick: [TrickPlay], partner: Int?,
                              suitOf: (Card) -> Suit, value: (Card) -> Int) -> Card? {
        guard !legal.isEmpty else { return nil }

        if trick.isEmpty {
            // Lead the lowest side-suit card; lead low trump only when forced.
            let side = legal.filter { value($0) < 1000 }
            return (side.isEmpty ? legal : side).min { value($0) < value($1) }
        }

        let led = suitOf(trick[0].card)
        let winnerSoFar = TrickTaking.winner(plays: trick, ledSuit: led, suitOf: suitOf, value: value)
        let winningValue = trick
            .filter { suitOf($0.card) == led || value($0.card) >= 1000 }
            .map { value($0.card) }
            .max() ?? 0

        if let partner, winnerSoFar == partner, trick.count >= 2 {
            return legal.min { value($0) < value($1) }
        }
        let winners = legal.filter { card in
            (suitOf(card) == led || value(card) >= 1000) && value(card) > winningValue
        }
        if let cheapest = winners.min(by: { value($0) < value($1) }) {
            return cheapest
        }
        return legal.min { value($0) < value($1) }
    }

    // MARK: - Bidding heuristics (all difficulties above easy)

    static func estimateSpadesBid(hand: [Card]) -> Int {
        var tricks = 0.0
        for card in hand {
            switch (card.suit, card.rank) {
            case (.spades, let r) where r >= .jack: tricks += 1
            case (.spades, _): tricks += 0.5
            case (_, .ace): tricks += 1
            case (_, .king): tricks += 0.5
            default: break
            }
        }
        return max(1, min(7, Int(tricks.rounded())))
    }

    static func highCardPoints(_ hand: [Card]) -> Int {
        hand.reduce(0) {
            $0 + max(0, $1.rank.rawValue - 10)   // J=1, Q=2, K=3, A=4
        }
    }

    static func bridgeBotCall(game: BridgeGame) -> BridgeCall {
        // Open 1 of the longest suit with 13+ HCP if nobody has bid; otherwise pass.
        guard game.lastBid == nil else { return .pass }
        let hand = game.hands[game.currentPlayer]
        guard highCardPoints(hand) >= 13 else { return .pass }
        let bySuit = Dictionary(grouping: hand, by: \.suit)
        let longest = bySuit.max { $0.value.count < $1.value.count }?.key ?? .clubs
        let strain: BridgeStrain
        switch longest {
        case .clubs: strain = .clubs
        case .diamonds: strain = .diamonds
        case .hearts: strain = .hearts
        case .spades: strain = .spades
        }
        return .bid(level: 1, strain: strain)
    }

    static func euchreBotCall(game: EuchreGame) -> EuchreCall {
        let hand = game.hands[game.currentPlayer]
        func trumpStrength(_ suit: Suit) -> Int {
            hand.reduce(0) { total, card in
                if card.rank == .jack && (card.suit == suit || card.suit == suit.sameColorPartner) {
                    return total + 3
                }
                return total + (card.suit == suit ? card.rank.rawValue - 8 : 0)
            }
        }
        if game.phase == .orderingUp, let upcard = game.upcard {
            return trumpStrength(upcard.suit) >= 8 ? .orderUp(alone: false) : .pass
        }
        let candidates = Suit.allCases.filter { $0 != game.upcard?.suit }
        let best = candidates.max { trumpStrength($0) < trumpStrength($1) } ?? .clubs
        if trumpStrength(best) >= 8 || game.currentPlayer == game.dealer {
            return .callTrump(best, alone: false)
        }
        return .pass
    }

    // MARK: - Chess

    private static func chessValue(_ kind: ChessPieceKind) -> Int {
        switch kind {
        case .pawn: return 1
        case .knight, .bishop: return 3
        case .rook: return 5
        case .queen: return 9
        case .king: return 100
        }
    }

    /// Greedy capture search with one ply of lookahead: take material, don't
    /// hang pieces, jump on checkmate when it's there.
    static func hardChessMove(_ g: ChessGame) -> Move? {
        let me = g.currentPlayer
        let moves = g.legalBoardMoves(for: me)
        guard !moves.isEmpty else { return nil }
        var best: (score: Double, move: BoardMove)? = nil
        for move in moves {
            var copy = g
            guard (try? copy.apply(.board(move))) != nil else { continue }
            let captured = g[move.to].map { chessValue($0.kind) }
                ?? (g[move.from]?.kind == .pawn && move.to.x != move.from.x ? 1 : 0)   // en passant
            let replies = copy.legalBoardMoves(for: 1 - me)
            if replies.isEmpty {
                if copy.inCheck(1 - me) { return .board(move) }   // checkmate
                continue   // stalemate — only if nothing better
            }
            let hanging = replies.map { copy[$0.to].map { chessValue($0.kind) } ?? 0 }.max() ?? 0
            let promotion = move.promotion != nil ? 8.0 : 0.0
            let check = copy.inCheck(1 - me) ? 0.3 : 0.0
            let score = Double(captured) + promotion + check
                - Double(hanging) * 0.9
                + Double.random(in: 0..<0.2)
            if best == nil || score > best!.score { best = (score, move) }
        }
        return best.map { .board($0.move) } ?? moves.randomElement().map { .board($0) }
    }

    // MARK: - Checkers

    private static func checkersMaterial(_ g: CheckersGame, color: Int) -> Double {
        var total = 0.0
        for piece in g.board.compactMap({ $0 }) where piece.color == color {
            total += piece.king ? 1.6 : 1.0
        }
        return total
    }

    /// Material-greedy with a one-move lookahead for return jumps.
    static func hardCheckersMove(_ g: CheckersGame) -> Move? {
        let me = g.currentPlayer
        let moves = g.legalBoardMoves(for: me)
        guard !moves.isEmpty else { return nil }
        var best: (score: Double, move: BoardMove)? = nil
        for move in moves {
            var copy = g
            guard (try? copy.apply(.board(move))) != nil else { continue }
            var score = checkersMaterial(copy, color: me) - checkersMaterial(copy, color: 1 - me)
            if copy.currentPlayer == me {
                score += 0.8   // multi-jump continues
            } else {
                let returnJumps = copy.legalBoardMoves(for: 1 - me)
                    .contains { abs($0.to.x - $0.from.x) == 2 }
                if returnJumps { score -= 0.9 }
            }
            score += Double.random(in: 0..<0.1)
            if best == nil || score > best!.score { best = (score, move) }
        }
        return best.map { .board($0.move) }
    }

    // MARK: - Go

    static func goBotMove(game: GoGame, difficulty: BotDifficulty) -> Move {
        // Random legal point, but don't fill our own single-point eyes,
        // and pass once the board gets crowded or the game has dragged on
        // (the move-count cap stops endless random capture cycles).
        let stoneValue = game.currentPlayer + 1
        let candidates = game.legalPoints().filter { p in
            !game.neighbors(p).allSatisfy { game.stone(at: $0) == stoneValue }
        }
        let emptyCount = game.board.lazy.filter { $0 == 0 }.count
        if candidates.isEmpty || emptyCount < game.size || game.moveCount > game.size * game.size * 3 {
            return .pass
        }
        if difficulty == .hard {
            // Take the biggest capture on the board when one exists.
            let captures = candidates.compactMap { point -> (Point, Int)? in
                guard let result = game.tryPlace(point, color: game.currentPlayer),
                      result.captured > 0 else { return nil }
                return (point, result.captured)
            }
            if let best = captures.max(by: { $0.1 < $1.1 }) {
                return .place(best.0)
            }
        }
        return .place(candidates.randomElement()!)
    }
}
