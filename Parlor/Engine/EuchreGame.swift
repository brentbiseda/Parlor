import Foundation

/// 4-player partnership Euchre with the 24-card deck (9–A), bowers,
/// going alone, and stick-the-dealer. First team to 10 points wins.
struct EuchreGame: GameEngine {
    static let kind = GameKind.euchre

    enum Phase: Codable, Hashable {
        case orderingUp     // round 1: take the upcard suit or pass
        case callingTrump   // round 2: name another suit (dealer must)
        case dealerDiscard  // dealer picked up the upcard, discards one
        case playing
        case gameOver
    }

    var hands: [[Card]] = Array(repeating: [], count: 4)
    var kitty: [Card] = []
    var upcard: Card? = nil
    var phase: Phase = .orderingUp
    var dealer = 0
    var bidTurn = 0                 // seat currently deciding in bidding rounds
    var trump: Suit? = nil
    var makerTeam: Int? = nil
    var aloneSeat: Int? = nil       // seat playing alone
    var sittingOut: Int? = nil      // partner of the lone hand
    var trick: [TrickPlay] = []
    var trickLeader = 0
    var tricksPlayed = 0
    var trickCounts = [0, 0, 0, 0]
    var teamScores = [0, 0]
    var roundNumber = 0
    var lastTrickSummary: String? = nil
    var lastRoundResult: String? = nil
    /// Lifetime-in-game achievement counts, shown in the final result.
    var teamMarches = [0, 0]
    var teamLoneMarches = [0, 0]
    var teamEuchres = [0, 0]
    /// Current consecutive rounds won per team (resets when the other team scores).
    var teamRoundStreak = [0, 0]
    var teamBestStreak = [0, 0]
    /// Loner hands attempted vs. successfully marched, per team.
    var lonersAttempted = [0, 0]
    /// "Perfect defense" — euchred an opponent who went alone, per team.
    var perfectDefenses = [0, 0]
    /// Times each suit was called as trump (indexed by Suit.allCases order).
    var trumpCallsBySuit: [Int] = [0, 0, 0, 0]
    /// Count of alone declarations that resulted in a march (per team).
    var aloneWins: [Int] = [0, 0]
    /// Count of alone declarations that were attempted (per team) — mirrors lonersAttempted.
    var aloneAttempts: [Int] = [0, 0]
    /// Consecutive rounds where at least one player declared alone.
    var loneStreak: Int = 0
    /// Internal: tracks whether a loner was declared in the current round.
    var currentRoundHasLoner: Bool = false

    init() {
        startRound()
    }

    mutating func startRound() {
        let (dealt, rest) = TrickTaking.deal(deck: Card.euchreDeck(), players: 4, count: 5)
        hands = dealt
        kitty = rest
        upcard = kitty.first
        trump = nil
        makerTeam = nil
        aloneSeat = nil
        sittingOut = nil
        trick = []
        tricksPlayed = 0
        trickCounts = [0, 0, 0, 0]
        roundNumber += 1
        lastTrickSummary = nil
        currentRoundHasLoner = false
        bidTurn = (dealer + 1) % 4
        phase = .orderingUp
    }

    func team(of seat: Int) -> Int { seat % 2 }

    func isRightBower(_ card: Card) -> Bool {
        guard let trump else { return false }
        return card.rank == .jack && card.suit == trump
    }

    func isLeftBower(_ card: Card) -> Bool {
        guard let trump else { return false }
        return card.rank == .jack && card.suit == trump.sameColorPartner
    }

    func effectiveSuit(_ card: Card) -> Suit {
        isLeftBower(card) ? trump! : card.suit
    }

    func cardValue(_ card: Card) -> Int {
        if isRightBower(card) { return 1101 }
        if isLeftBower(card) { return 1100 }
        if card.suit == trump { return 1000 + card.rank.rawValue }
        return card.rank.rawValue
    }

    func isActive(_ seat: Int) -> Bool { seat != sittingOut }

    func nextActive(after seat: Int) -> Int {
        var s = (seat + 1) % 4
        while !isActive(s) { s = (s + 1) % 4 }
        return s
    }

    var activeCount: Int { sittingOut == nil ? 4 : 3 }

    var currentPlayer: Int {
        switch phase {
        case .orderingUp, .callingTrump:
            return bidTurn
        case .dealerDiscard:
            return dealer
        case .playing:
            var seat = trickLeader
            for _ in 0..<trick.count { seat = nextActive(after: seat) }
            return seat
        case .gameOver:
            return 0
        }
    }

    var isOver: Bool { phase == .gameOver }

    func legalMoves() -> [Move] {
        switch phase {
        case .orderingUp:
            return [.euchreCall(.pass), .euchreCall(.orderUp(alone: false)), .euchreCall(.orderUp(alone: true))]
        case .callingTrump:
            guard let upcard else { return [] }
            var moves: [Move] = []
            if bidTurn != dealer { moves.append(.euchreCall(.pass)) }  // stick the dealer
            for suit in Suit.allCases where suit != upcard.suit {
                moves.append(.euchreCall(.callTrump(suit, alone: false)))
                moves.append(.euchreCall(.callTrump(suit, alone: true)))
            }
            return moves
        case .dealerDiscard:
            return hands[dealer].map { .playCard($0) }
        case .playing:
            return legalCards().map { .playCard($0) }
        case .gameOver:
            return []
        }
    }

    func legalCards() -> [Card] {
        let hand = hands[currentPlayer]
        guard !trick.isEmpty else { return hand }
        let led = effectiveSuit(trick[0].card)
        return TrickTaking.followLegal(hand: hand, ledSuit: led, suitOf: effectiveSuit)
    }

    mutating func apply(_ move: Move) throws {
        switch (phase, move) {
        case (.orderingUp, .euchreCall(.pass)), (.callingTrump, .euchreCall(.pass)):
            guard phase == .orderingUp || bidTurn != dealer else { throw GameError.illegalMove }
            if bidTurn == dealer {
                phase = .callingTrump
                bidTurn = (dealer + 1) % 4
            } else {
                bidTurn = (bidTurn + 1) % 4
            }
        case (.orderingUp, .euchreCall(.orderUp(let alone))):
            guard let upcard else { throw GameError.illegalMove }
            setTrump(upcard.suit, caller: bidTurn, alone: alone)
            // Dealer takes up the card and discards (even when sitting out the
            // discard is harmless; standard play: dealer always picks it up).
            hands[dealer].append(upcard)
            hands[dealer] = hands[dealer].displaySorted()
            self.upcard = nil
            phase = .dealerDiscard
        case (.callingTrump, .euchreCall(.callTrump(let suit, let alone))):
            guard let upcard, suit != upcard.suit else { throw GameError.illegalMove }
            setTrump(suit, caller: bidTurn, alone: alone)
            self.upcard = nil
            beginPlay()
        case (.dealerDiscard, .playCard(let card)):
            guard hands[dealer].contains(card) else { throw GameError.illegalMove }
            hands[dealer].removeAll { $0 == card }
            beginPlay()
        case (.playing, .playCard(let card)):
            guard legalCards().contains(card) else { throw GameError.illegalMove }
            play(card)
        default:
            throw GameError.illegalMove
        }
    }

    mutating func setTrump(_ suit: Suit, caller: Int, alone: Bool) {
        trump = suit
        makerTeam = team(of: caller)
        if alone {
            aloneSeat = caller
            sittingOut = (caller + 2) % 4
            let t = team(of: caller)
            aloneAttempts[t] += 1
            currentRoundHasLoner = true
        }
        // Track suit frequency
        if let idx = Suit.allCases.firstIndex(of: suit) {
            trumpCallsBySuit[idx] += 1
        }
    }

    mutating func beginPlay() {
        phase = .playing
        var leader = (dealer + 1) % 4
        if !isActive(leader) { leader = nextActive(after: leader) }
        trickLeader = leader
    }

    mutating func play(_ card: Card) {
        let seat = currentPlayer
        hands[seat].removeAll { $0 == card }
        trick.append(TrickPlay(seat: seat, card: card))

        if trick.count == activeCount {
            let led = effectiveSuit(trick[0].card)
            let winner = TrickTaking.winner(plays: trick, ledSuit: led, suitOf: effectiveSuit, value: cardValue)
            trickCounts[winner] += 1
            let winCard = trick.first { $0.seat == winner }?.card
            let cardLabel = winCard.map { " — \($0.rank.label)\($0.suit.symbol)" } ?? ""
            lastTrickSummary = "Trick to seat \(winner + 1)\(cardLabel)"
            trick = []
            trickLeader = winner
            tricksPlayed += 1
            if tricksPlayed == 5 { finishRound() }
        }
    }

    mutating func finishRound() {
        guard let makerTeam else { return }
        if aloneSeat != nil { lonersAttempted[makerTeam] += 1 }
        let makerTricks = trickCounts[makerTeam] + trickCounts[makerTeam + 2]
        let defTricksCount = 5 - makerTricks
        let trickDetail = "\(makerTricks)-\(defTricksCount) tricks"
        let pts: Int
        let result: String
        if makerTricks >= 3 {
            if makerTricks == 5 {
                pts = aloneSeat != nil ? 4 : 2
                result = aloneSeat != nil ? "March alone! +\(pts)" : "March! +\(pts)"
                teamMarches[makerTeam] += 1
                if aloneSeat != nil {
                    teamLoneMarches[makerTeam] += 1
                    aloneWins[makerTeam] += 1
                }
            } else {
                pts = 1
                result = "Made it (+1)"
            }
            teamScores[makerTeam] += pts
            teamRoundStreak[makerTeam] += 1
            teamRoundStreak[1 - makerTeam] = 0
            if teamRoundStreak[makerTeam] > teamBestStreak[makerTeam] { teamBestStreak[makerTeam] = teamRoundStreak[makerTeam] }
            let streakStr = teamRoundStreak[makerTeam] >= 2 ? " 🔥\(teamRoundStreak[makerTeam])" : ""
            lastRoundResult = "\(teamLabel(makerTeam)) — \(result) \(trickDetail)\(streakStr)"
        } else {
            pts = 2
            teamScores[1 - makerTeam] += pts
            teamEuchres[1 - makerTeam] += 1
            if aloneSeat != nil { perfectDefenses[1 - makerTeam] += 1 }
            teamRoundStreak[1 - makerTeam] += 1
            teamRoundStreak[makerTeam] = 0
            if teamRoundStreak[1 - makerTeam] > teamBestStreak[1 - makerTeam] { teamBestStreak[1 - makerTeam] = teamRoundStreak[1 - makerTeam] }
            let eStreakStr = teamRoundStreak[1 - makerTeam] >= 2 ? " 🔥\(teamRoundStreak[1 - makerTeam])" : ""
            lastRoundResult = "\(teamLabel(makerTeam)) euchred! \(trickDetail) +2 defenders\(eStreakStr)"
        }
        // Update lone streak
        if currentRoundHasLoner {
            loneStreak += 1
        } else {
            loneStreak = 0
        }

        if teamScores.contains(where: { $0 >= 10 }) {
            phase = .gameOver
        } else {
            dealer = (dealer + 1) % 4
            startRound()
        }
    }

    func teamLabel(_ team: Int) -> String { team == 0 ? "Seats 1 & 3" : "Seats 2 & 4" }

    var statusText: String {
        switch phase {
        case .orderingUp:
            let scores = "\(teamScores[0])–\(teamScores[1])"
            let suitSymbol = upcard?.suit.symbol ?? ""
            let cardLabel = upcard.map { "\($0.rank.label)\($0.suit.symbol)" } ?? ""
            let turnLabel = " · S\(bidTurn + 1)'s turn"
            return "Round \(roundNumber) (\(scores)): order up \(cardLabel) \(suitSymbol)?\(turnLabel)"
        case .callingTrump:
            let scores = "\(teamScores[0])–\(teamScores[1])"
            let turnedDown = upcard?.suit.symbol ?? ""
            let bannedNote = " (not \(turnedDown))"
            let turnLabel = " · S\(bidTurn + 1)'s turn"
            return "Round \(roundNumber) (\(scores)): name trump\(bannedNote)\(turnLabel)"
        case .dealerDiscard:
            return "Dealer discards one card"
        case .playing:
            let scores = "\(teamScores[0])–\(teamScores[1])"
            let trickBar = (0..<4).map { "\($0 + 1):\(trickCounts[$0])" }.joined(separator: " ")
            var text = "Trump \(trump?.symbol ?? "") · T\(tricksPlayed + 1) · \(trickBar) · (\(scores))"
            if let aloneSeat { text += " · S\(aloneSeat + 1) alone" }
            if let mk = makerTeam {
                let makerTricks = trickCounts[mk] + trickCounts[mk + 2]
                let defTricks = tricksPlayed - makerTricks
                if makerTricks >= 3 { text += " · ✅ makers in" }
                else if defTricks >= 3 { text += " · 💀 euchre!" }
                else if tricksPlayed >= 2 { text += " · makers \(makerTricks), need \(3 - makerTricks)" }
            }
            if teamScores.max()! >= 8 { text += " · 🏁 match point" }
            if let last = lastRoundResult { text += " · \(last)" }
            return text
        case .gameOver:
            return resultText ?? "Game over"
        }
    }

    var resultText: String? {
        guard isOver else { return nil }
        let winner = teamScores[0] >= 10 ? 0 : 1
        var text = "\(teamLabel(winner)) win \(teamScores[winner])–\(teamScores[1 - winner])"
        let totalMarches = teamMarches[0] + teamMarches[1]
        let totalLoneMarches = teamLoneMarches[0] + teamLoneMarches[1]
        let totalEuchres = teamEuchres[0] + teamEuchres[1]
        var stats: [String] = []
        if totalLoneMarches > 0 { stats.append("\(totalLoneMarches) lone march\(totalLoneMarches == 1 ? "" : "es") 🚀") }
        if totalMarches - totalLoneMarches > 0 { stats.append("\(totalMarches - totalLoneMarches) march\(totalMarches - totalLoneMarches == 1 ? "" : "es")") }
        if totalEuchres > 0 { stats.append("\(totalEuchres) euchre\(totalEuchres == 1 ? "" : "s")") }
        let bestStreak = max(teamBestStreak[0], teamBestStreak[1])
        if bestStreak >= 3 { stats.append("🔥 \(bestStreak)-round streak") }
        let totalLoners = lonersAttempted[0] + lonersAttempted[1]
        if totalLoners > 0 {
            let pct = Int(Double(totalLoneMarches) / Double(totalLoners) * 100)
            let teamDetail = (0...1).compactMap { t -> String? in
                guard lonersAttempted[t] > 0 else { return nil }
                return "T\(t+1):\(aloneWins[t])/\(aloneAttempts[t])"
            }.joined(separator: " ")
            stats.append("\(totalLoneMarches)/\(totalLoners) loners (\(pct)%) [\(teamDetail)]")
        }
        let totalDefenses = perfectDefenses[0] + perfectDefenses[1]
        if totalDefenses > 0 { stats.append("🛡️ \(totalDefenses) perfect defense\(totalDefenses == 1 ? "" : "s")") }
        if teamScores[1 - winner] == 0 { stats.append("🥋 skunk — \(teamScores[winner])–0!") }
        // Trump suit breakdown
        let suitSymbols = Suit.allCases.map { $0.symbol }
        let totalTrumpCalls = trumpCallsBySuit.reduce(0, +)
        let suitsCalled = trumpCallsBySuit.filter { $0 > 0 }.count
        if suitsCalled >= 2 && totalTrumpCalls >= 4 {
            let breakdown = trumpCallsBySuit.enumerated()
                .filter { $0.element > 0 }
                .sorted { $0.element > $1.element }
                .map { "\(suitSymbols[$0.offset])×\($0.element)" }
                .joined(separator: " ")
            stats.append("trump split: \(breakdown)")
        } else if let dt = trumpCallsBySuit.enumerated().max(by: { $0.element < $1.element }), dt.element >= 3 {
            stats.append("\(suitSymbols[dt.offset]) dominant trump (\(dt.element)×)")
        }
        if !stats.isEmpty { text += " · " + stats.joined(separator: " · ") }
        return text
    }

    func ranking() -> [[Int]] {
        guard isOver else { return [] }
        let winner = teamScores[0] >= 10 ? 0 : 1
        return [[winner, winner + 2], [1 - winner, 3 - winner]]
    }

    func redacted(for seat: Int) -> EuchreGame {
        var copy = self
        for other in 0..<4 where other != seat { copy.hands[other] = [] }
        copy.kitty = []
        return copy
    }
}
