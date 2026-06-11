import Foundation

/// 4-player partnership Spades (seats 0&2 vs 1&3). Bids 0–13 with 0 = nil.
/// Spades are always trump and can't be led until broken. Contracts score
/// 10 × bid plus 1 per bag; collecting 10 bags costs 100. Nil is ±100.
/// First team to 500 wins (or last above −200).
struct SpadesGame: GameEngine {
    static let kind = GameKind.spades

    enum Phase: Codable, Hashable {
        case bidding
        case playing
        case gameOver
    }

    var hands: [[Card]] = Array(repeating: [], count: 4)
    var phase: Phase = .bidding
    var dealer = 0
    var bids: [Int?] = Array(repeating: nil, count: 4)
    var tricksWon = [0, 0, 0, 0]
    var trick: [TrickPlay] = []
    var trickLeader = 0
    var tricksPlayed = 0
    var spadesBroken = false
    var teamScores = [0, 0]
    var teamBags = [0, 0]
    var roundNumber = 0
    var lastTrickSummary: String? = nil

    init() {
        startRound()
    }

    mutating func startRound() {
        let (dealt, _) = TrickTaking.deal(deck: Card.standardDeck(), players: 4, count: 13)
        hands = dealt
        bids = Array(repeating: nil, count: 4)
        tricksWon = [0, 0, 0, 0]
        trick = []
        tricksPlayed = 0
        spadesBroken = false
        roundNumber += 1
        trickLeader = (dealer + 1) % 4
        phase = .bidding
    }

    var currentPlayer: Int {
        switch phase {
        case .bidding:
            // Bid in order starting left of dealer.
            for offset in 1...4 {
                let seat = (dealer + offset) % 4
                if bids[seat] == nil { return seat }
            }
            return 0
        case .playing:
            return (trickLeader + trick.count) % 4
        case .gameOver:
            return 0
        }
    }

    var isOver: Bool { phase == .gameOver }

    func legalMoves() -> [Move] {
        switch phase {
        case .gameOver:
            return []
        case .bidding:
            return (0...13).map { .bid($0) }
        case .playing:
            return legalCards().map { .playCard($0) }
        }
    }

    func legalCards() -> [Card] {
        let hand = hands[currentPlayer]
        if trick.isEmpty {
            if !spadesBroken {
                let nonSpades = hand.filter { $0.suit != .spades }
                if !nonSpades.isEmpty { return nonSpades }
            }
            return hand
        }
        return TrickTaking.followLegal(hand: hand, ledSuit: trick[0].card.suit, suitOf: { $0.suit })
    }

    mutating func apply(_ move: Move) throws {
        switch (phase, move) {
        case (.bidding, .bid(let n)):
            guard (0...13).contains(n) else { throw GameError.illegalMove }
            bids[currentPlayer] = n
            if bids.allSatisfy({ $0 != nil }) {
                phase = .playing
                trickLeader = (dealer + 1) % 4
            }
        case (.playing, .playCard(let card)):
            guard legalCards().contains(card) else { throw GameError.illegalMove }
            play(card)
        default:
            throw GameError.illegalMove
        }
    }

    mutating func play(_ card: Card) {
        let seat = currentPlayer
        hands[seat].removeAll { $0 == card }
        trick.append(TrickPlay(seat: seat, card: card))
        if card.suit == .spades { spadesBroken = true }

        if trick.count == 4 {
            let led = trick[0].card.suit
            let winner = TrickTaking.winner(plays: trick, ledSuit: led, suitOf: { $0.suit },
                                            value: { TrickTaking.trumpValue($0, trump: .spades) })
            tricksWon[winner] += 1
            lastTrickSummary = "Trick to seat \(winner + 1)"
            trick = []
            trickLeader = winner
            tricksPlayed += 1
            if tricksPlayed == 13 { finishRound() }
        }
    }

    mutating func finishRound() {
        for team in 0...1 {
            let a = team, b = team + 2
            var roundScore = 0
            var contract = 0
            var contractTricks = 0
            for seat in [a, b] {
                let bid = bids[seat] ?? 0
                if bid == 0 {
                    roundScore += tricksWon[seat] == 0 ? 100 : -100
                } else {
                    contract += bid
                    contractTricks += tricksWon[seat]
                }
            }
            // Nil bidder's tricks still help cover the partner's contract.
            let teamTricks = tricksWon[a] + tricksWon[b]
            if contract > 0 {
                if teamTricks >= contract {
                    let bags = teamTricks - contract
                    roundScore += contract * 10 + bags
                    teamBags[team] += bags
                    if teamBags[team] >= 10 {
                        teamBags[team] -= 10
                        roundScore -= 100
                    }
                } else {
                    roundScore -= contract * 10
                }
            }
            _ = contractTricks
            teamScores[team] += roundScore
        }

        if teamScores.contains(where: { $0 >= 500 }) || teamScores.contains(where: { $0 <= -200 }) {
            phase = .gameOver
        } else {
            dealer = (dealer + 1) % 4
            startRound()
        }
    }

    func teamLabel(_ team: Int) -> String { team == 0 ? "Seats 1 & 3" : "Seats 2 & 4" }

    var statusText: String {
        switch phase {
        case .bidding:
            let made = bids.compactMap { $0 }.count
            return "Round \(roundNumber): bidding (\(made)/4)"
        case .playing:
            let contracts = (0..<4).map { seat in bids[seat].map { $0 == 0 ? "nil" : "\($0)" } ?? "–" }
            return "Bids \(contracts.joined(separator: "/")) · trick \(tricksPlayed + 1) of 13"
        case .gameOver:
            return resultText ?? "Game over"
        }
    }

    var resultText: String? {
        guard isOver else { return nil }
        let winner = teamScores[0] >= teamScores[1] ? 0 : 1
        return "\(teamLabel(winner)) win \(teamScores[winner])–\(teamScores[1 - winner])"
    }

    func ranking() -> [[Int]] {
        guard isOver else { return [] }
        let winner = teamScores[0] >= teamScores[1] ? 0 : 1
        return [[winner, winner + 2], [1 - winner, 3 - winner]]
    }

    func redacted(for seat: Int) -> SpadesGame {
        var copy = self
        for other in 0..<4 where other != seat { copy.hands[other] = [] }
        return copy
    }
}
