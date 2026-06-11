import Foundation

/// Chicago-style contract bridge: four deals, rotating dealer and
/// vulnerability (none / dealer's side / dealer's side / both), full auction
/// with doubles, dummy play, and standard duplicate scoring.
/// Partnerships: seats 1 & 3 (N–S) vs seats 2 & 4 (E–W).
struct BridgeGame: GameEngine {
    static let kind = GameKind.bridge

    enum Phase: Codable, Hashable {
        case auction
        case playing
        case gameOver
    }

    struct Contract: Codable, Hashable {
        var level: Int
        var strain: BridgeStrain
        var declarer: Int
        var doubling: Int   // 1, 2, or 4

        var label: String {
            let x = doubling == 2 ? "X" : doubling == 4 ? "XX" : ""
            return "\(level)\(strain.label)\(x) by seat \(declarer + 1)"
        }
    }

    struct DealRecord: Codable, Hashable {
        var summary: String
    }

    var hands: [[Card]] = Array(repeating: [], count: 4)
    var phase: Phase = .auction
    var dealNumber = 1              // 1...4
    var dealer = 0
    var calls: [BridgeCall] = []
    var contract: Contract? = nil
    var trick: [TrickPlay] = []
    var trickLeader = 0
    var tricksPlayed = 0
    var declarerTricks = 0
    var defenderTricks = 0
    var dummyRevealed = false
    var teamScores = [0, 0]
    var history: [DealRecord] = []
    var lastTrickSummary: String? = nil

    init() {
        deal()
    }

    mutating func deal() {
        let (dealt, _) = TrickTaking.deal(deck: Card.standardDeck(), players: 4, count: 13)
        hands = dealt
        calls = []
        contract = nil
        trick = []
        tricksPlayed = 0
        declarerTricks = 0
        defenderTricks = 0
        dummyRevealed = false
        phase = .auction
    }

    func side(of seat: Int) -> Int { seat % 2 }

    var dummySeat: Int? {
        contract.map { ($0.declarer + 2) % 4 }
    }

    /// Vulnerability per Chicago rotation.
    func isVulnerable(side: Int) -> Bool {
        switch dealNumber {
        case 1: return false
        case 2, 3: return self.side(of: dealer) == side
        default: return true
        }
    }

    var currentPlayer: Int {
        switch phase {
        case .auction:
            return (dealer + calls.count) % 4
        case .playing:
            return (trickLeader + trick.count) % 4
        case .gameOver:
            return 0
        }
    }

    var isOver: Bool { phase == .gameOver }

    func controller(of seat: Int) -> Int {
        if phase == .playing, let contract, seat == dummySeat { return contract.declarer }
        return seat
    }

    // MARK: - Auction

    var lastBid: (call: BridgeCall, seat: Int)? {
        for (i, call) in calls.enumerated().reversed() {
            if case .bid = call { return (call, (dealer + i) % 4) }
        }
        return nil
    }

    /// Doubling state of the standing bid: 1, 2, or 4.
    var currentDoubling: Int {
        var doubling = 1
        for call in calls.reversed() {
            switch call {
            case .bid: return doubling
            case .double: doubling = max(doubling, 2)
            case .redouble: doubling = 4
            case .pass: continue
            }
        }
        return 1
    }

    func legalCalls() -> [BridgeCall] {
        var result: [BridgeCall] = [.pass]
        let seat = currentPlayer
        let floor: (Int, BridgeStrain)? = lastBid.flatMap {
            if case .bid(let level, let strain) = $0.call { return (level, strain) }
            return nil
        }
        for level in 1...7 {
            for strain in BridgeStrain.allCases {
                if let (fl, fs) = floor {
                    guard level > fl || (level == fl && strain > fs) else { continue }
                }
                result.append(.bid(level: level, strain: strain))
            }
        }
        // Double: standing bid belongs to opponents and isn't doubled yet.
        if let (call, bidSeat) = lastBid, case .bid = call,
           side(of: bidSeat) != side(of: seat), currentDoubling == 1,
           !passedSinceLastNonPass(byOwnSide: false) {
            result.append(.double)
        }
        // Redouble: opponents doubled our side's standing bid.
        if let (_, bidSeat) = lastBid, side(of: bidSeat) == side(of: seat), currentDoubling == 2 {
            result.append(.redouble)
        }
        return result
    }

    /// Doubling/redoubling is legal only over the live call sequence; this
    /// simplified check is sufficient because intervening bids reset state.
    private func passedSinceLastNonPass(byOwnSide: Bool) -> Bool { false }

    func legalMoves() -> [Move] {
        switch phase {
        case .auction:
            return legalCalls().map { .bridgeCall($0) }
        case .playing:
            return legalCards().map { .playCard($0) }
        case .gameOver:
            return []
        }
    }

    func legalCards() -> [Card] {
        let hand = hands[currentPlayer]
        guard !trick.isEmpty else { return hand }
        return TrickTaking.followLegal(hand: hand, ledSuit: trick[0].card.suit, suitOf: { $0.suit })
    }

    mutating func apply(_ move: Move) throws {
        switch (phase, move) {
        case (.auction, .bridgeCall(let call)):
            guard legalCalls().contains(call) else { throw GameError.illegalMove }
            calls.append(call)
            checkAuctionEnd()
        case (.playing, .playCard(let card)):
            guard legalCards().contains(card) else { throw GameError.illegalMove }
            play(card)
        default:
            throw GameError.illegalMove
        }
    }

    mutating func checkAuctionEnd() {
        if calls.count == 4 && calls.allSatisfy({ $0 == .pass }) {
            history.append(DealRecord(summary: "Deal \(dealNumber): passed out"))
            lastTrickSummary = "Deal passed out"
            nextDeal()
            return
        }
        guard calls.count >= 4, calls.suffix(3).allSatisfy({ $0 == .pass }) else { return }

        // Final contract: last bid; declarer is the first player on that side
        // who bid the contract strain.
        guard let (finalCall, finalSeat) = lastBid, case .bid(let level, let strain) = finalCall else { return }
        let declaringSide = side(of: finalSeat)
        var declarer = finalSeat
        for (i, call) in calls.enumerated() {
            let seat = (dealer + i) % 4
            if case .bid(_, let s) = call, s == strain, side(of: seat) == declaringSide {
                declarer = seat
                break
            }
        }
        contract = Contract(level: level, strain: strain, declarer: declarer, doubling: currentDoubling)
        phase = .playing
        trickLeader = (declarer + 1) % 4
    }

    mutating func play(_ card: Card) {
        let seat = currentPlayer
        hands[seat].removeAll { $0 == card }
        trick.append(TrickPlay(seat: seat, card: card))
        if !dummyRevealed { dummyRevealed = true }   // after the opening lead

        guard trick.count == 4, let contract else { return }
        let led = trick[0].card.suit
        let winner = TrickTaking.winner(plays: trick, ledSuit: led, suitOf: { $0.suit },
                                        value: { TrickTaking.trumpValue($0, trump: contract.strain.suit) })
        if side(of: winner) == side(of: contract.declarer) {
            declarerTricks += 1
        } else {
            defenderTricks += 1
        }
        lastTrickSummary = "Trick to seat \(winner + 1)"
        trick = []
        trickLeader = winner
        tricksPlayed += 1
        if tricksPlayed == 13 { scoreDeal() }
    }

    mutating func scoreDeal() {
        guard let contract else { return }
        let declaringSide = side(of: contract.declarer)
        let vul = isVulnerable(side: declaringSide)
        let needed = 6 + contract.level
        let made = declarerTricks >= needed
        var points = 0

        if made {
            points = makingScore(contract: contract, tricks: declarerTricks, vulnerable: vul)
            teamScores[declaringSide] += points
            history.append(DealRecord(summary: "Deal \(dealNumber): \(contract.label) made \(declarerTricks - 6) (+\(points))"))
        } else {
            let down = needed - declarerTricks
            points = undertrickPenalty(down: down, doubling: contract.doubling, vulnerable: vul)
            teamScores[1 - declaringSide] += points
            history.append(DealRecord(summary: "Deal \(dealNumber): \(contract.label) down \(down) (\(points) to defenders)"))
        }
        nextDeal()
    }

    func makingScore(contract: Contract, tricks: Int, vulnerable: Bool) -> Int {
        let oddTricks = contract.level
        let overtricks = tricks - 6 - oddTricks
        var trickScore: Int
        switch contract.strain {
        case .clubs, .diamonds:
            trickScore = 20 * oddTricks
        case .hearts, .spades:
            trickScore = 30 * oddTricks
        case .notrump:
            trickScore = 40 + 30 * (oddTricks - 1)
        }
        trickScore *= contract.doubling

        var total = trickScore
        total += trickScore >= 100 ? (vulnerable ? 500 : 300) : 50
        if contract.level == 6 { total += vulnerable ? 750 : 500 }
        if contract.level == 7 { total += vulnerable ? 1500 : 1000 }
        if contract.doubling >= 2 { total += 25 * contract.doubling }  // 50 / 100 insult

        let perOver: Int
        switch contract.doubling {
        case 2: perOver = vulnerable ? 200 : 100
        case 4: perOver = vulnerable ? 400 : 200
        default:
            switch contract.strain {
            case .clubs, .diamonds: perOver = 20
            default: perOver = 30
            }
        }
        total += overtricks * perOver
        return total
    }

    func undertrickPenalty(down: Int, doubling: Int, vulnerable: Bool) -> Int {
        if doubling == 1 {
            return down * (vulnerable ? 100 : 50)
        }
        var total = 0
        for i in 1...down {
            let base: Int
            if vulnerable {
                base = i == 1 ? 200 : 300
            } else {
                base = i == 1 ? 100 : (i <= 3 ? 200 : 300)
            }
            total += base
        }
        return doubling == 4 ? total * 2 : total
    }

    mutating func nextDeal() {
        if dealNumber >= 4 {
            phase = .gameOver
        } else {
            dealNumber += 1
            dealer = (dealer + 1) % 4
            deal()
        }
    }

    func sideLabel(_ side: Int) -> String { side == 0 ? "Seats 1 & 3" : "Seats 2 & 4" }

    var statusText: String {
        switch phase {
        case .auction:
            let vul: String
            switch dealNumber {
            case 1: vul = "none vul"
            case 2, 3: vul = "\(sideLabel(side(of: dealer))) vul"
            default: vul = "both vul"
            }
            return "Deal \(dealNumber) of 4 (\(vul)) · auction"
        case .playing:
            let c = contract?.label ?? ""
            return "\(c) · tricks \(declarerTricks)–\(defenderTricks)"
        case .gameOver:
            return resultText ?? "Game over"
        }
    }

    var resultText: String? {
        guard isOver else { return nil }
        if teamScores[0] == teamScores[1] { return "Tied at \(teamScores[0])" }
        let winner = teamScores[0] > teamScores[1] ? 0 : 1
        return "\(sideLabel(winner)) win \(teamScores[winner])–\(teamScores[1 - winner])"
    }

    func redacted(for seat: Int) -> BridgeGame {
        var copy = self
        for other in 0..<4 where other != seat {
            // Everyone may see dummy once it's revealed.
            if dummyRevealed, other == dummySeat { continue }
            copy.hands[other] = []
        }
        return copy
    }
}
