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
            lastTrickSummary = "Trick to seat \(winner + 1)"
            trick = []
            trickLeader = winner
            tricksPlayed += 1
            if tricksPlayed == 5 { finishRound() }
        }
    }

    mutating func finishRound() {
        guard let makerTeam else { return }
        let makerTricks = trickCounts[makerTeam] + trickCounts[makerTeam + 2]
        if makerTricks >= 3 {
            if makerTricks == 5 {
                teamScores[makerTeam] += aloneSeat != nil ? 4 : 2
            } else {
                teamScores[makerTeam] += 1
            }
        } else {
            teamScores[1 - makerTeam] += 2  // euchred
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
            return "Round \(roundNumber): order up the \(upcard?.label ?? "")?"
        case .callingTrump:
            return "Round \(roundNumber): name trump (upcard \(upcard?.label ?? "") turned down)"
        case .dealerDiscard:
            return "Dealer discards one card"
        case .playing:
            var text = "Trump \(trump?.symbol ?? "") · trick \(tricksPlayed + 1) of 5"
            if let aloneSeat { text += " · seat \(aloneSeat + 1) alone" }
            return text
        case .gameOver:
            return resultText ?? "Game over"
        }
    }

    var resultText: String? {
        guard isOver else { return nil }
        let winner = teamScores[0] >= 10 ? 0 : 1
        return "\(teamLabel(winner)) win \(teamScores[winner])–\(teamScores[1 - winner])"
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
