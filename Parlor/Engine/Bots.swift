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
            return .bid(contextAwareSpadesBid(g))
        case let g as BridgeGame where g.phase == .auction:
            return .bridgeCall(bridgeBotCall(game: g))
        case let g as EuchreGame where g.phase == .orderingUp || g.phase == .callingTrump:
            return .euchreCall(euchreBotCall(game: g))
        case let g as GoGame:
            return goBotMove(game: g, difficulty: .normal)
        case let g as UnoGame:
            // Call UNO the moment we sit on a single card (avoids the penalty).
            let seat = g.currentPlayer
            if g.hands[seat].count == 1, !g.calledUno.contains(seat) {
                return .uno(.callUno)
            }
            let moves = game.legalMoves()
            let plays = moves.filter { if case .uno(.play) = $0 { return true }; return false }
            return plays.randomElement() ?? moves.randomElement()
        case is EightsGame:
            let moves = game.legalMoves()
            let plays = moves.filter { if case .eights(.play) = $0 { return true }; return false }
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
            return hardSpadesPlay(g).map { .playCard($0) }
        case let g as EuchreGame where g.phase == .playing:
            let seat = g.currentPlayer
            let partner = (seat + 2) % 4
            let legal = g.legalCards()
            // Maker leading the first trick with a strong trump holding: lead a
            // high trump (bower) to draw out opponents' trump.
            if g.trick.isEmpty, g.makerTeam == g.team(of: seat) {
                let trumpCards = legal.filter { g.effectiveSuit($0) == g.trump }
                if trumpCards.count >= 3, let topTrump = trumpCards.max(by: { g.cardValue($0) < g.cardValue($1) }) {
                    return .playCard(topTrump)
                }
            }
            let card = hardTrickPlay(legal: legal, trick: g.trick,
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
        let opponentsEarly = (0..<4).filter { $0 != seat }
        let nearWin = opponentsEarly.map { g.hands[$0].count }.min() ?? 10 <= 2
        let colored = legal.filter { $0.color != nil }
        func isAction(_ c: UnoCard) -> Bool {
            switch c.value { case .skip, .reverse, .drawTwo: return true; default: return false }
        }
        func isDrawTwo(_ c: UnoCard) -> Bool { if case .drawTwo = c.value { return true }; return false }
        let wild = legal.first { $0.color == nil }
        let wildDrawFour = legal.first { if case .wildDrawFour = $0.value { return true }; return false }
        let opponents = (0..<4).filter { $0 != seat }
        let opponentMinHand = opponents.map { g.hands[$0].count }.min() ?? 10
        // With a large hand (5+ cards), prefer punishing draw cards early.
        if g.hands[seat].count >= 5 {
            if let drawTwo = colored.first(where: isDrawTwo) {
                return .uno(.play(drawTwo, declared: nil))
            }
            if let w4 = wildDrawFour {
                return .uno(.play(w4, declared: bestColor))
            }
        }
        // If an opponent is about to go out, hit them with a disruptive action card or WD4.
        if nearWin {
            if let w4 = wildDrawFour { return .uno(.play(w4, declared: bestColor)) }
            if let disrupt = colored.filter(isAction).max(by: { $0.points < $1.points }) {
                return .uno(.play(disrupt, declared: nil))
            }
        }
        // When we have ≤ 2 cards, prefer WD4 to stop opponents from winning.
        if opponentMinHand <= 2, let w4 = wildDrawFour {
            return .uno(.play(w4, declared: bestColor))
        }
        // Prefer matching current color first, then by rank, then shed numbers.
        let matchColor = colored.filter { $0.color == bestColor }
        if let pick = matchColor.max(by: { $0.points < $1.points }) {
            return .uno(.play(pick, declared: nil))
        }
        // Otherwise shed number cards first (preserve action cards), favoring
        // cards outside our dominant color to consolidate the hand.
        let numbers = colored.filter { !isAction($0) }
        if let pick = numbers.min(by: {
            (($0.color == bestColor ? 1 : 0), -$0.points) < (($1.color == bestColor ? 1 : 0), -$1.points)
        }) {
            return .uno(.play(pick, declared: nil))
        }
        if let pick = colored.max(by: { $0.points < $1.points }) {
            return .uno(.play(pick, declared: nil))
        }
        // Fall through to wilds.
        return wild.map { .uno(.play($0, declared: bestColor)) }
    }

    /// Save eights for when we're stuck; otherwise shed the priciest card.
    static func hardEightsMove(_ g: EightsGame) -> Move? {
        let seat = g.currentPlayer
        let legal = g.legalCards(for: seat)
        // Under a draw-two attack, stack a 2 if we can to pass the debt on.
        if g.pendingDraw > 0 {
            if let two = legal.first(where: { $0.rank == .two }) {
                return .eights(.play(two, nominated: nil))
            }
            return .eights(.draw)
        }
        let opponents = (0..<4).filter { $0 != seat }
        let opponentMinHand = opponents.map { g.hands[$0].count }.min() ?? 10
        // Disrupt a near-out opponent with a 2 (draw debt) or Queen (skip).
        if opponentMinHand <= 2 {
            if let two = legal.first(where: { $0.rank == .two }) { return .eights(.play(two, nominated: nil)) }
            if let queen = legal.first(where: { $0.rank == .queen }) { return .eights(.play(queen, nominated: nil)) }
        }
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

    /// Pass 3 cards with direction awareness:
    ///   Left  — unload high-rank non-hearts to set up short suits (opponent gets them).
    ///   Right — unload high hearts aggressively (receiving player is downstream of us).
    ///   Across — dump highest overall point cards symmetrically.
    ///   Hold  — no pass; keep the dangerous cards but don't self-inflict.
    static func hardHeartsPass(_ g: HeartsGame) -> [Card] {
        let hand = g.hands[g.currentPlayer]

        func danger(_ c: Card, direction: HeartsGame.PassDirection) -> Int {
            switch direction {
            case .left:
                // Sending left: try to create a void in a side suit; dump A/K/Q of clubs or diamonds.
                if c == queenOfSpades { return 1000 }
                if c.suit == .spades && c.rank >= .king { return 900 + c.rank.rawValue }
                if c.suit == .clubs || c.suit == .diamonds { return 400 + c.rank.rawValue }
                if c.suit == .hearts { return 300 + c.rank.rawValue }
                return c.rank.rawValue
            case .right:
                // Sending right: the recipient is our downstream opponent — burden them with hearts.
                if c == queenOfSpades { return 1000 }
                if c.suit == .hearts { return 800 + c.rank.rawValue }
                if c.suit == .spades && c.rank >= .king { return 600 + c.rank.rawValue }
                return c.rank.rawValue
            case .across:
                // Sending across (partner direction in trick games, but opponent in Hearts):
                // pure point-danger ranking.
                if c == queenOfSpades { return 1000 }
                if c.suit == .spades && c.rank >= .king { return 900 + c.rank.rawValue }
                if c.suit == .hearts { return 500 + c.rank.rawValue }
                return c.rank.rawValue
            case .hold:
                return 0   // no pass; this branch is unreachable but satisfies exhaustiveness
            }
        }

        let dir = g.passDirection
        // Void-creation bonus: cards in a short (2-card) side suit are worth
        // shedding to set up future discards of hearts/Q♠.
        let bySuit = Dictionary(grouping: hand, by: \.suit)
        func adjusted(_ c: Card) -> Int {
            var score = danger(c, direction: dir)
            let suitLen = bySuit[c.suit]?.count ?? 0
            if c.suit != .hearts && c != queenOfSpades && (suitLen == 2 || suitLen == 1) {
                score += 250   // encourage voiding short suits (but below Q♠/high-spade danger)
            }
            return score
        }
        let ranked = hand.sorted { adjusted($0) > adjusted($1) }
        return Array(ranked.prefix(3)).displaySorted()
    }

    /// True when `seat` appears to be attempting a moon shoot:
    ///   - Has taken ≥ 2 heart tricks OR holds both the Q♠ and 4+ hearts.
    ///   - Has not let any points reach another player this round.
    ///   - OR has a premium hand (≥7 hearts + Q♠) before any points have landed.
    private static func attemptingMoonShoot(_ g: HeartsGame, seat: Int) -> Bool {
        let myPoints = g.roundPoints[seat]
        let othersHavePoints = (0..<4).filter { $0 != seat }.contains { g.roundPoints[$0] > 0 }
        guard !othersHavePoints else { return false }
        let hand = g.hands[seat]
        let heartsInHand = hand.filter { $0.suit == .hearts }.count
        let hasQueen = hand.contains(queenOfSpades)
        if myPoints >= 8 { return true }
        if hasQueen && heartsInHand >= 4 { return true }
        // Proactive shoot: premium hand — 7+ hearts plus Q♠ before any points landed.
        if myPoints == 0 && hasQueen && heartsInHand >= 7 { return true }
        return false
    }

    // Backward-compat alias used below.
    private static func attemptingMoonShot(_ g: HeartsGame, seat: Int) -> Bool {
        attemptingMoonShoot(g, seat: seat)
    }

    static func hardHeartsPlay(_ g: HeartsGame) -> Card? {
        let legal = g.legalCards()
        guard !legal.isEmpty else { return nil }
        let seat = g.currentPlayer

        // Moon-shoot mode: if we're attempting it, always take the trick aggressively.
        if attemptingMoonShot(g, seat: seat) {
            if g.trick.isEmpty {
                // Lead highest hearts or Q♠ to maintain control.
                let pointCards = legal.filter { heartsPoints($0) > 0 }.sorted { $0.rank.rawValue > $1.rank.rawValue }
                if let top = pointCards.first { return top }
            } else {
                let led = g.trick[0].card.suit
                let following = legal.filter { $0.suit == led }
                let winningRank = g.trick.filter { $0.card.suit == led }.map(\.card.rank.rawValue).max() ?? 0
                if !following.isEmpty {
                    // Win the trick if possible.
                    let winners = following.filter { $0.rank.rawValue > winningRank }
                    if !winners.isEmpty { return winners.min { $0.rank.rawValue < $1.rank.rawValue } }
                    return following.max { $0.rank.rawValue < $1.rank.rawValue }
                }
                // Void: dump a low side card (save the point cards for later tricks).
                let nonPoints = legal.filter { heartsPoints($0) == 0 }
                return (nonPoints.isEmpty ? legal : nonPoints).min { $0.rank.rawValue < $1.rank.rawValue }
            }
        }

        if g.trick.isEmpty {
            // If losing (highest score among players with scores > 0), dump Q♠ ASAP on lead.
            let myScore = g.scores[seat]
            let maxScore = g.scores.max() ?? 0
            let holdingQueen = legal.contains(queenOfSpades)
            if holdingQueen && myScore == maxScore && myScore > 0 {
                let nonQueenSpades = legal.filter { $0.suit == .spades && $0 != queenOfSpades }
                if nonQueenSpades.isEmpty && g.heartsBroken {
                    return queenOfSpades
                }
            }
            // If winning (lowest score), bleed hearts when safe.
            let minScore = g.scores.min() ?? 0
            if myScore == minScore && g.heartsBroken && g.tricksPlayed >= 4 {
                let hearts = legal.filter { $0.suit == .hearts }
                if hearts.count >= 2, let lowest = hearts.min(by: { $0.rank.rawValue < $1.rank.rawValue }) {
                    return lowest
                }
            }
            let nonHearts = legal.filter { $0.suit != .hearts }
            let pool = (!g.heartsBroken && !nonHearts.isEmpty) ? nonHearts : legal
            if let safeLead = TrickTaking.safeLead(from: pool, trump: nil) { return safeLead }
            return pool.min { $0.rank.rawValue < $1.rank.rawValue }
        }

        let led = g.trick[0].card.suit
        let following = legal.filter { $0.suit == led }
        let winningRank = g.trick.filter { $0.card.suit == led }.map(\.card.rank.rawValue).max() ?? 0

        if !following.isEmpty {
            let trickPoints = g.trick.reduce(0) { $0 + g.points(for: $1.card) }
            if g.trick.count == 3 && trickPoints == 0 {
                return following.max { $0.rank.rawValue < $1.rank.rawValue }
            }
            let ducks = following.filter { $0.rank.rawValue < winningRank }
            if !ducks.isEmpty {
                if led == .spades, ducks.contains(queenOfSpades) { return queenOfSpades }
                return ducks.max { $0.rank.rawValue < $1.rank.rawValue }
            }
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
            // Lead a side-suit ace (a near-certain winner) when we hold one;
            // otherwise lead the lowest side-suit card and keep trump back.
            let side = legal.filter { value($0) < 1000 }
            let pool = side.isEmpty ? legal : side
            if let ace = pool.first(where: { $0.rank == .ace }) { return ace }
            return pool.min { value($0) < value($1) }
        }

        let led = suitOf(trick[0].card)
        let winnerSoFar = TrickTaking.winner(plays: trick, ledSuit: led, suitOf: suitOf, value: value)
        let winningValue = trick
            .filter { suitOf($0.card) == led || value($0.card) >= 1000 }
            .map { value($0.card) }
            .max() ?? 0

        // Duck when partner is winning: always if they're last unbeaten, or when
        // partner is winning with a commanding high card (likely to hold up).
        if let partner, winnerSoFar == partner {
            let partnerCommands = winningValue >= value(Card(suit: led, rank: .king))
            if trick.count >= 2 || partnerCommands {
                return legal.min { value($0) < value($1) }
            }
        }
        let winners = legal.filter { card in
            (suitOf(card) == led || value(card) >= 1000) && value(card) > winningValue
        }
        if let cheapest = winners.min(by: { value($0) < value($1) }) {
            return cheapest
        }
        return legal.min { value($0) < value($1) }
    }

    /// Spades play with nil awareness: a nil bidder ducks every trick, and a
    /// nil bidder's partner tries to win tricks to cover them.
    static func hardSpadesPlay(_ g: SpadesGame) -> Card? {
        let seat = g.currentPlayer
        let legal = g.legalCards()
        guard !legal.isEmpty else { return nil }
        let value: (Card) -> Int = { TrickTaking.trumpValue($0, trump: .spades) }
        let iAmNil = g.bids[seat] == 0
        let partner = (seat + 2) % 4
        let partnerNil = g.bids[partner] == 0

        // I bid nil: play as low as possible without winning.
        if iAmNil {
            if g.trick.isEmpty { return legal.min { value($0) < value($1) } }
            let led = g.trick[0].card.suit
            let winningValue = g.trick.filter { $0.card.suit == led || value($0.card) >= 1000 }.map { value($0.card) }.max() ?? 0
            let following = legal.filter { $0.suit == led }
            if !following.isEmpty {
                let safe = following.filter { value($0) < winningValue }
                return (safe.isEmpty ? following : safe).min { value($0) < value($1) }
            }
            // Void: discard the highest non-spade to shed danger, else lowest spade.
            let nonSpades = legal.filter { $0.suit != .spades }
            if let dump = nonSpades.max(by: { $0.rank.rawValue < $1.rank.rawValue }) { return dump }
            return legal.min { value($0) < value($1) }
        }

        // Partner bid nil and hasn't been covered yet: try to win to protect them.
        if partnerNil, !g.trick.isEmpty {
            let led = g.trick[0].card.suit
            let partnerInTrick = g.trick.first { $0.seat == partner }
            let winnerSoFar = TrickTaking.winner(plays: g.trick, ledSuit: led, suitOf: { $0.suit }, value: value)
            // If partner is currently winning (danger!), overtake them cheaply.
            if winnerSoFar == partner || partnerInTrick != nil {
                let winningValue = g.trick.filter { $0.card.suit == led || value($0.card) >= 1000 }.map { value($0.card) }.max() ?? 0
                let overtakers = legal.filter { ($0.suit == led || value($0) >= 1000) && value($0) > winningValue }
                if let cheap = overtakers.min(by: { value($0) < value($1) }) { return cheap }
            }
        }

        // Bag avoidance: if our team has already made its bid and is one bag
        // away from the −100 overflow penalty, duck this trick to stay clean.
        let team = seat % 2
        let teamTricks = g.tricksWon[team] + g.tricksWon[team + 2]
        let contract = g.teamContract(team)
        if contract > 0, teamTricks >= contract, g.teamBags[team] % 10 >= 9, !g.trick.isEmpty {
            let led = g.trick[0].card.suit
            let winningValue = g.trick.filter { $0.card.suit == led || value($0.card) >= 1000 }.map { value($0.card) }.max() ?? 0
            let following = legal.filter { $0.suit == led }
            let pool = following.isEmpty ? legal.filter { $0.suit != .spades } : following
            let ducks = pool.filter { value($0) < winningValue }
            if let duck = ducks.max(by: { value($0) < value($1) }) { return duck }
        }

        return hardTrickPlay(legal: legal, trick: g.trick, partner: partner,
                             suitOf: { $0.suit }, value: value)
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
        let bySuit = Dictionary(grouping: hand, by: \.suit)
        let spadeCount = bySuit[.spades]?.count ?? 0
        // Long-suit tricks: cards beyond the 4th in a side suit tend to run.
        for suit in Suit.allCases where suit != .spades {
            let len = bySuit[suit]?.count ?? 0
            if len >= 5 { tricks += Double(len - 4) * 0.5 }
        }
        // Ruffing tricks: short side suits become trumps when we hold spares.
        if spadeCount >= 3 {
            for suit in Suit.allCases where suit != .spades {
                let len = bySuit[suit]?.count ?? 0
                if len == 0 { tricks += 1.0 }        // void
                else if len == 1 { tricks += 0.5 }   // singleton
            }
        }
        // Nil bid when hand has no high cards and only low spades. Require a
        // cushion of low cards (≤9) so the hand can duck under everything, and
        // avoid nil with a long spade suit (hard to dodge the lead).
        let hasHighCard = hand.contains { $0.rank >= .queen }
        let highSpades = hand.filter { $0.suit == .spades && $0.rank >= .ten }
        let lowCards = hand.filter { $0.rank <= .nine }.count
        // Danger singletons: A or K in a suit where we have ≤ 1 card is risky for nil
        // (opponent leads that suit, we're forced to play our high card).
        let hasDangerSingleton: Bool = {
            for suit in Suit.allCases where suit != .spades {
                let suitCards = bySuit[suit] ?? []
                if suitCards.count <= 1 && suitCards.contains(where: { $0.rank >= .king }) { return true }
            }
            return false
        }()
        if !hasHighCard && highSpades.isEmpty && spadeCount <= 1 && lowCards >= 9 && !hasDangerSingleton { return 0 }
        return max(1, min(8, Int(tricks.rounded())))
    }

    /// Bid-aware Spades bidding: adjusts the raw hand estimate for partner nil coverage
    /// and bag-penalty danger. If partner has already bid nil, we must bid at least 2 more
    /// to absorb the tricks they'll duck. If our team bags are at 8+, shave 1 to avoid overflow.
    static func contextAwareSpadesBid(_ g: SpadesGame) -> Int {
        let seat = g.currentPlayer
        let hand = g.hands[seat]
        var bid = estimateSpadesBid(hand: hand)
        guard bid > 0 else { return 0 }  // nil bid stays nil

        let partner = (seat + 2) % 4
        let team = seat % 2

        // Partner bid nil: we cover their ducks — bump up to ensure ≥2 bid
        if let partnerBid = g.bids[partner], partnerBid == 0 {
            bid = max(bid, 2)
            // Also avoid nil ourselves when partner is already going nil
            if bid == 0 { bid = 2 }
        }

        // Partner bid high: we can afford to bid conservatively
        if let partnerBid = g.bids[partner], partnerBid >= 6, bid >= 3 {
            bid = max(1, bid - 1)
        }

        // Bag danger: at 8+ bags, bid 1 less to avoid the −100 overflow
        if g.teamBags[team] >= 8 && bid > 1 {
            bid -= 1
        }

        return max(1, min(8, bid))
    }

    static func highCardPoints(_ hand: [Card]) -> Int {
        hand.reduce(0) {
            $0 + max(0, $1.rank.rawValue - 10)   // J=1, Q=2, K=3, A=4
        }
    }

    static func bridgeBotCall(game: BridgeGame) -> BridgeCall {
        // Only open; pass when someone has already bid (simple bot keeps auction clean).
        guard game.lastBid == nil else { return .pass }
        let hand = game.hands[game.currentPlayer]
        let hcp = highCardPoints(hand)
        guard hcp >= 13 else { return .pass }
        let bySuit = Dictionary(grouping: hand, by: \.suit)
        // Balanced hand (no void, no singleton).
        let suitCounts = Suit.allCases.map { bySuit[$0]?.count ?? 0 }
        let isBalanced = suitCounts.min()! >= 2 && suitCounts.max()! <= 5
        // Strong balanced openings: 2NT (20-21), then 1NT (15-17).
        if isBalanced && (20...21).contains(hcp) { return .bid(level: 2, strain: .notrump) }
        if isBalanced && (15...17).contains(hcp) { return .bid(level: 1, strain: .notrump) }
        // Choose the longest suit; break ties by preferring majors, then quality.
        func suitQuality(_ s: Suit) -> Int {
            (bySuit[s] ?? []).reduce(0) { $0 + max(0, $1.rank.rawValue - 10) }
        }
        func suitRank(_ s: Suit) -> Int { [Suit.clubs, .diamonds, .hearts, .spades].firstIndex(of: s)! }
        let longest = Suit.allCases.max { a, b in
            let la = bySuit[a]?.count ?? 0, lb = bySuit[b]?.count ?? 0
            if la != lb { return la < lb }
            let majorA = a == .hearts || a == .spades
            let majorB = b == .hearts || b == .spades
            if majorA != majorB { return !majorA && majorB }
            if suitQuality(a) != suitQuality(b) { return suitQuality(a) < suitQuality(b) }
            return suitRank(a) < suitRank(b)
        } ?? .clubs
        let strain: BridgeStrain
        switch longest {
        case .clubs: strain = .clubs
        case .diamonds: strain = .diamonds
        case .hearts: strain = .hearts
        case .spades: strain = .spades
        }
        return .bid(level: 1, strain: strain)
    }

    /// Minimum trump-strength score to order up or call trump.
    /// Each bower = 3, each trump card = rank−8 (9=1, T=2, J/Q/K=3, A=5).
    static let euchreTrumpThreshold = 8

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
        func hasBothBowers(_ suit: Suit) -> Bool {
            hand.contains { $0.rank == .jack && $0.suit == suit } &&
            hand.contains { $0.rank == .jack && $0.suit == suit.sameColorPartner }
        }
        func trumpCount(_ suit: Suit) -> Int {
            hand.filter { $0.suit == suit || ($0.rank == .jack && $0.suit == suit.sameColorPartner) }.count
        }
        func hasRightBower(_ suit: Suit) -> Bool {
            hand.contains { $0.rank == .jack && $0.suit == suit }
        }
        // A near-lock loner: right bower + trump ace + 3+ trump total,
        // OR right bower + 3 more trump even without left bower (strong suit control).
        func strongLoner(_ suit: Suit) -> Bool {
            let hasTrumpAce = hand.contains { $0.suit == suit && $0.rank == .ace }
            return hasBothBowers(suit) && trumpCount(suit) >= 4
                || (hasRightBower(suit) && hasTrumpAce && trumpCount(suit) >= 4)
                || (hasRightBower(suit) && trumpCount(suit) >= 4 && !hasBothBowers(suit))
        }
        // Off-suit aces are likely winners; add a point each toward the call.
        func sideAceBonus(_ suit: Suit) -> Int {
            hand.filter { $0.suit != suit && $0.suit != suit.sameColorPartner && $0.rank == .ace }.count
        }
        // Go alone when holding both bowers + 2 or more additional trump (very strong hand).
        if game.phase == .orderingUp, let upcard = game.upcard {
            let suit = upcard.suit
            // Don't gift a strong upcard to an opponent dealer with a weak hand.
            let dealerIsOpponent = game.team(of: game.dealer) != game.team(of: game.currentPlayer)
            let strength = trumpStrength(suit) + sideAceBonus(suit)
            let goAlone = strongLoner(suit)
            if dealerIsOpponent && upcard.rank == .jack && strength < euchreTrumpThreshold + 1 { return .pass }
            return strength >= euchreTrumpThreshold ? .orderUp(alone: goAlone) : .pass
        }
        let candidates = Suit.allCases.filter { $0 != game.upcard?.suit }
        let best = candidates.max { (trumpStrength($0) + sideAceBonus($0)) < (trumpStrength($1) + sideAceBonus($1)) } ?? .clubs
        if (trumpStrength(best) + sideAceBonus(best)) >= euchreTrumpThreshold || game.currentPlayer == game.dealer {
            let goAlone = strongLoner(best)
            return .callTrump(best, alone: goAlone)
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

    /// Static evaluation of a chess position from `player`'s perspective.
    /// Material + centrality + development + pawn structure + rook activity.
    private static func evaluateChess(_ g: ChessGame, for player: Int) -> Double {
        var score = 0.0
        // Pre-compute pawn column presence for each color (for structure bonuses).
        var pawnCols = [[Bool]](repeating: [Bool](repeating: false, count: 8), count: 2)
        var pawnRowByCol = [[Int?]](repeating: [Int?](repeating: nil, count: 8), count: 2)
        for y in 0..<8 {
            for x in 0..<8 {
                if let p = g[Point(x: x, y: y)], p.kind == .pawn {
                    pawnCols[p.color][x] = true
                    if pawnRowByCol[p.color][x] == nil { pawnRowByCol[p.color][x] = y }
                }
            }
        }
        for y in 0..<8 {
            for x in 0..<8 {
                guard let piece = g[Point(x: x, y: y)] else { continue }
                let val = Double(chessValue(piece.kind))
                let sign: Double = piece.color == player ? 1 : -1
                let cx = Double(x), cy = Double(y)
                let centrality = (3.5 - abs(cx - 3.5)) * (3.5 - abs(cy - 3.5)) * 0.01
                var bonus = 0.0
                switch piece.kind {
                case .pawn:
                    // Advancement
                    bonus += piece.color == 0 ? (7 - cy) * 0.04 : cy * 0.04
                    // Doubled pawn penalty: another own pawn on same file
                    if pawnRowByCol[piece.color][x] != y { bonus -= 0.2 }
                    // Passed pawn bonus: no opposing pawn on same or adjacent files ahead
                    let opp = 1 - piece.color
                    let adjacentFiles = [max(0, x-1), x, min(7, x+1)]
                    let frontRowRange = piece.color == 0 ? Array((y+1)..<8) : Array((0..<y).reversed())
                    let blocked = frontRowRange.contains { row in
                        adjacentFiles.contains { col in g[Point(x: col, y: row)]?.kind == .pawn && g[Point(x: col, y: row)]?.color == opp }
                    }
                    if !blocked { bonus += 0.35 }
                case .rook:
                    // Rook on open file (no own pawn blocking)
                    if !pawnCols[piece.color][x] { bonus += pawnCols[1 - piece.color][x] ? 0.15 : 0.25 }
                case .bishop:
                    // Bishop pair bonus applied when evaluating second bishop
                    let bishops = g.board.compactMap { $0 }.filter { $0.color == piece.color && $0.kind == .bishop }
                    if bishops.count >= 2 { bonus += 0.1 }
                default: break
                }
                score += sign * (val + centrality + bonus)
            }
        }
        return score
    }

    /// 2-ply alpha-beta minimax chess bot. Evaluates all opponent responses to
    /// each candidate move and picks the move with the best guaranteed outcome.
    static func hardChessMove(_ g: ChessGame) -> Move? {
        let me = g.currentPlayer
        let moves = g.legalBoardMoves(for: me)
        guard !moves.isEmpty else { return nil }

        // Move ordering: captures and promotions first (improves alpha-beta cutoffs).
        let ordered = moves.sorted { a, b in
            let aCapture = g[a.to] != nil || a.promotion != nil
            let bCapture = g[b.to] != nil || b.promotion != nil
            return aCapture && !bCapture
        }

        var best: (score: Double, move: BoardMove)? = nil
        var alpha = -Double.infinity

        for move in ordered {
            var copy = g
            guard (try? copy.apply(.board(move))) != nil else { continue }

            let oppMoves = copy.legalBoardMoves(for: 1 - me)
            let score: Double
            if oppMoves.isEmpty {
                // Terminal: checkmate = huge win; stalemate = draw (small penalty vs winning).
                score = copy.inCheck(1 - me) ? 999.0 : -0.5
            } else {
                // Minimise: pick opponent's best reply, then evaluate.
                var minScore = Double.infinity
                for oppMove in oppMoves {
                    var copy2 = copy
                    guard (try? copy2.apply(.board(oppMove))) != nil else { continue }
                    let s = evaluateChess(copy2, for: me)
                    if s < minScore { minScore = s }
                    if minScore <= alpha { break }  // alpha-beta pruning
                }
                score = minScore
            }

            let jitter = Double.random(in: 0..<0.05)
            if best == nil || score + jitter > best!.score {
                best = (score + jitter, move)
                alpha = max(alpha, score)
            }
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

    /// Static evaluation of checkers position from `player`'s perspective:
    /// material balance + advancement + king-safety + back-rank bonus.
    private static func evaluateCheckers(_ g: CheckersGame, for player: Int) -> Double {
        var score = checkersMaterial(g, color: player) - checkersMaterial(g, color: 1 - player)
        for (i, piece) in g.board.enumerated() {
            guard let p = piece else { continue }
            let row = Double(i / 8)
            let sign: Double = p.color == player ? 1 : -1
            if !p.king {
                let advance = p.color == 0 ? row / 7.0 : (7.0 - row) / 7.0
                score += sign * advance * 0.12
            }
            let homeRank = p.color == 0 ? 0.0 : 7.0
            if row == homeRank { score += sign * 0.08 }
        }
        return score
    }

    /// Recursive alpha-beta for checkers. `depth` counts half-plies remaining.
    private static func checkersAlphaBeta(_ g: CheckersGame, depth: Int, alpha: inout Double, beta: Double, me: Int) -> Double {
        if depth == 0 || g.isOver {
            return evaluateCheckers(g, for: me) + (g.isOver && g.currentPlayer != me ? 50 : 0)
        }
        let mover = g.currentPlayer
        let moves = g.legalBoardMoves(for: mover)
        if moves.isEmpty { return evaluateCheckers(g, for: me) }
        if mover == me {
            var value = -Double.infinity
            for move in moves {
                var copy = g
                guard (try? copy.apply(.board(move))) != nil else { continue }
                let child = checkersAlphaBeta(copy, depth: depth - 1, alpha: &alpha, beta: beta, me: me)
                value = max(value, child)
                alpha = max(alpha, value)
                if alpha >= beta { break }
            }
            return value
        } else {
            var value = Double.infinity
            var a = alpha
            for move in moves {
                var copy = g
                guard (try? copy.apply(.board(move))) != nil else { continue }
                let child = checkersAlphaBeta(copy, depth: depth - 1, alpha: &a, beta: value, me: me)
                value = min(value, child)
                if a >= value { break }
            }
            return value
        }
    }

    /// 3-ply alpha-beta minimax checkers bot. Handles multi-jump chains.
    static func hardCheckersMove(_ g: CheckersGame) -> Move? {
        let me = g.currentPlayer
        let moves = g.legalBoardMoves(for: me)
        guard !moves.isEmpty else { return nil }

        // Prioritise jumps (mandatory in checkers, and they produce deeper trees).
        let jumps = moves.filter { abs($0.to.x - $0.from.x) == 2 }
        let ordered = jumps.isEmpty ? moves : jumps + moves.filter { abs($0.to.x - $0.from.x) != 2 }

        var best: (score: Double, move: BoardMove)? = nil
        var alpha = -Double.infinity

        for move in ordered {
            var copy = g
            guard (try? copy.apply(.board(move))) != nil else { continue }
            var a = alpha
            let score = checkersAlphaBeta(copy, depth: 4, alpha: &a, beta: Double.infinity, me: me)
            let jitter = Double.random(in: 0..<0.04)
            if best == nil || score + jitter > best!.score {
                best = (score + jitter, move)
                alpha = max(alpha, score)
            }
        }

        return best.map { .board($0.move) }
    }

    // MARK: - Go

    static func goBotMove(game: GoGame, difficulty: BotDifficulty) -> Move {
        // Random legal point, but don't fill our own single-point eyes,
        // and pass once the board gets crowded or the game has dragged on.
        let stoneValue = game.currentPlayer + 1
        let candidates = game.legalPoints().filter { p in
            !game.neighbors(p).allSatisfy { game.stone(at: $0) == stoneValue }
        }
        let emptyCount = game.board.lazy.filter { $0 == 0 }.count
        if candidates.isEmpty || emptyCount < game.size || game.moveCount > game.size * game.size * 3 {
            return .pass
        }
        if difficulty == .hard {
            // 1. Take the biggest capture.
            let captures = candidates.compactMap { point -> (Point, Int)? in
                guard let result = game.tryPlace(point, color: game.currentPlayer),
                      result.captured > 0 else { return nil }
                return (point, result.captured)
            }
            if let best = captures.max(by: { $0.1 < $1.1 }) { return .place(best.0) }

            // 2. Put opponent groups in atari (reduce to 1 liberty).
            let oppColor = game.currentPlayer == 0 ? 2 : 1
            var visitedGroups = Set<Int>()
            var atariMoves: [Point] = []
            for i in game.board.indices where game.board[i] == oppColor {
                guard !visitedGroups.contains(i) else { continue }
                let p = Point(x: i % game.size, y: i / game.size)
                let grp = game.group(at: p, in: game.board)
                visitedGroups.formUnion(grp.points)
                var libs = Set<Int>()
                for idx in grp.points {
                    let gp = Point(x: idx % game.size, y: idx / game.size)
                    for n in game.neighbors(gp) where game.board[game.index(n)] == 0 {
                        libs.insert(game.index(n))
                    }
                }
                if libs.count == 2 {
                    for libIdx in libs {
                        let lp = Point(x: libIdx % game.size, y: libIdx / game.size)
                        if candidates.contains(lp) { atariMoves.append(lp) }
                    }
                }
            }
            if let atari = atariMoves.randomElement() { return .place(atari) }

            // 2.5. Rescue our own groups in atari by extending to gain liberties.
            let myColorEarly = game.currentPlayer + 1
            var visitedMine = Set<Int>()
            var rescueMoves: [Point] = []
            for i in game.board.indices where game.board[i] == myColorEarly {
                guard !visitedMine.contains(i) else { continue }
                let p = Point(x: i % game.size, y: i / game.size)
                let grp = game.group(at: p, in: game.board)
                visitedMine.formUnion(grp.points)
                var libs = Set<Int>()
                for idx in grp.points {
                    let gp = Point(x: idx % game.size, y: idx / game.size)
                    for n in game.neighbors(gp) where game.board[game.index(n)] == 0 {
                        libs.insert(game.index(n))
                    }
                }
                guard libs.count == 1, let libIdx = libs.first else { continue }
                let lp = Point(x: libIdx % game.size, y: libIdx / game.size)
                // Only rescue if extending actually increases liberties.
                if candidates.contains(lp), let result = game.tryPlace(lp, color: game.currentPlayer) {
                    let newGrp = game.group(at: lp, in: result.board)
                    var newLibs = Set<Int>()
                    for idx in newGrp.points {
                        let gp = Point(x: idx % game.size, y: idx / game.size)
                        for n in game.neighbors(gp) where result.board[game.index(n)] == 0 { newLibs.insert(game.index(n)) }
                    }
                    if newLibs.count >= 2 { rescueMoves.append(lp) }
                }
            }
            if let rescue = rescueMoves.randomElement() { return .place(rescue) }

            // 3. Avoid self-atari: skip moves that would leave our new group with 1 liberty.
            let myColor = game.currentPlayer + 1
            let nonSelfAtari = candidates.filter { p in
                guard let result = game.tryPlace(p, color: game.currentPlayer) else { return false }
                let grp = game.group(at: p, in: result.board)
                var libs = Set<Int>()
                for idx in grp.points {
                    let gp = Point(x: idx % game.size, y: idx / game.size)
                    for n in game.neighbors(gp) where result.board[game.index(n)] == 0 {
                        libs.insert(game.index(n))
                    }
                }
                return libs.count > 1
            }

            // 4. Prefer moves that form eyes: an empty cell fully surrounded by our stones.
            // Playing adjacent to an eye-point reinforces group stability.
            let safePool = nonSelfAtari.isEmpty ? candidates : nonSelfAtari
            let eyeMoves = safePool.filter { p in
                // Check if placing here would create an adjacent empty cell surrounded by our color.
                guard let result = game.tryPlace(p, color: game.currentPlayer) else { return false }
                for n in game.neighbors(p) {
                    if result.board[game.index(n)] == 0 {
                        let allOurs = game.neighbors(n).allSatisfy { nb in
                            result.board[game.index(nb)] == myColor
                        }
                        if allOurs { return true }
                    }
                }
                return false
            }
            if let pick = eyeMoves.randomElement() { return .place(pick) }

            // 5. Play near existing stones (cohesive formation).
            let adjacent = safePool.filter { p in
                game.neighbors(p).contains { game.stone(at: $0) == myColor }
            }
            if let pick = adjacent.randomElement() { return .place(pick) }
            if let pick = nonSelfAtari.randomElement() { return .place(pick) }
        }
        return .place(candidates.randomElement()!)
    }
}
