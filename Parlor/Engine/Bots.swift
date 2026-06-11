import Foundation

/// Simple opponents that fill empty seats. They play random legal moves with
/// a few light heuristics so card games stay sensible.
enum Bot {
    static func chooseMove(for game: AnyGame) -> Move? {
        switch game.engine {
        case let g as SpadesGame where g.phase == .bidding:
            return .bid(estimateSpadesBid(hand: g.hands[g.currentPlayer]))
        case let g as BridgeGame where g.phase == .auction:
            return .bridgeCall(bridgeBotCall(game: g))
        case let g as EuchreGame where g.phase == .orderingUp || g.phase == .callingTrump:
            return .euchreCall(euchreBotCall(game: g))
        case let g as GoGame:
            return goBotMove(game: g)
        default:
            let moves = game.legalMoves().filter { $0 != .resign }
            return moves.randomElement() ?? game.legalMoves().first
        }
    }

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

    static func goBotMove(game: GoGame) -> Move {
        // Random legal point, but don't fill our own single-point eyes,
        // and pass once the board gets crowded or the opponent passed late.
        let stoneValue = game.currentPlayer + 1
        let candidates = game.legalPoints().filter { p in
            !game.neighbors(p).allSatisfy { game.stone(at: $0) == stoneValue }
        }
        let emptyCount = game.board.lazy.filter { $0 == 0 }.count
        if candidates.isEmpty || emptyCount < game.size { return .pass }
        return .place(candidates.randomElement()!)
    }
}
