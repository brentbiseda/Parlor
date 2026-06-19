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
    /// Small/grand slams bitten off this match, per side — shown in the final result.
    var teamSlams = [0, 0]
    /// Cumulative overtricks earned by each declaring side across all deals.
    var teamGrandSlams = [0, 0]
    var teamOvertricks = [0, 0]
    /// Cumulative undertricks against each team.
    var teamUndertricks = [0, 0]
    /// Contracts made / set across the match (for the final summary).
    var contractsMade = 0
    var contractsSet = 0
    /// Contracts that were doubled or redoubled.
    var doubledContracts: Int = 0
    var redoubledContracts: Int = 0

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

    /// Returns true if any call after the last non-pass was a pass from the
    /// specified side grouping. Used to gate double legality correctly.
    private func passedSinceLastNonPass(byOwnSide: Bool) -> Bool {
        let seat = currentPlayer
        var foundNonPass = false
        for (i, call) in calls.enumerated().reversed() {
            let callSeat = (dealer + i) % 4
            if case .pass = call {
                if foundNonPass && (side(of: callSeat) == side(of: seat)) == byOwnSide {
                    return true
                }
            } else {
                foundNonPass = true
            }
        }
        return false
    }

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
        let winCard = trick.first { $0.seat == winner }?.card
        let cardLabel = winCard.map { " — \($0.rank.label)\($0.suit.symbol)" } ?? ""
        lastTrickSummary = "Trick to seat \(winner + 1)\(cardLabel)"
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

        if contract.doubling == 2 { doubledContracts += 1 }
        else if contract.doubling == 4 { redoubledContracts += 1 }
        if made {
            contractsMade += 1
            points = makingScore(contract: contract, tricks: declarerTricks, vulnerable: vul)
            teamScores[declaringSide] += points
            let overtricks = declarerTricks - needed
            if overtricks > 0 { teamOvertricks[declaringSide] += overtricks }
            var slamNote = ""
            if contract.level == 7 {
                teamSlams[declaringSide] += 1
                teamGrandSlams[declaringSide] += 1
                slamNote = " · 🎰 Grand slam!"
            } else if contract.level == 6 {
                teamSlams[declaringSide] += 1
                slamNote = " · 🎰 Small slam!"
            }
            history.append(DealRecord(summary: "Deal \(dealNumber): \(contract.label) made \(declarerTricks - 6) (+\(points))\(slamNote)"))
        } else {
            contractsSet += 1
            let down = needed - declarerTricks
            teamUndertricks[declaringSide] += down
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

    /// Summary of the most recent bid for display during auction.
    var currentBidLabel: String? {
        guard let (call, _) = lastBid, case .bid(let level, let strain) = call else { return nil }
        let x = currentDoubling == 2 ? "X" : currentDoubling == 4 ? "XX" : ""
        return "\(level)\(strain.label)\(x)"
    }

    var statusText: String {
        switch phase {
        case .auction:
            let nsVul = isVulnerable(side: 0)
            let ewVul = isVulnerable(side: 1)
            let vul: String
            if !nsVul && !ewVul { vul = "none vul" }
            else if nsVul && ewVul { vul = "🔴 both vul" }
            else { vul = "🔴 \(nsVul ? "N/S" : "E/W") vul" }
            let bidInfo = currentBidLabel.map { " · bid: \($0)" } ?? " · no bid yet"
            let scoreInfo = " · \(sideLabel(0)) \(teamScores[0]) – \(sideLabel(1)) \(teamScores[1])"
            let hcp = TrickTaking.highCardPoints(hand: hands[0])
            let hcpInfo = hands[0].isEmpty ? "" : " · your HCP \(hcp)"
            return "Deal \(dealNumber)/4 (\(vul))\(scoreInfo)\(bidInfo)\(hcpInfo)"
        case .playing:
            let c = contract?.label ?? ""
            let need = (contract?.level ?? 0) + 6
            let doubleTag = currentDoubling == 2 ? " Dbl" : currentDoubling == 4 ? " Rdbl" : ""
            let trickGap = need - declarerTricks
            let progress = trickGap > 0 ? "need \(trickGap) more" : "making+\(declarerTricks - need)"
            let vulTag = isVulnerable(side: side(of: contract?.declarer ?? 0)) ? " 🔴vul" : ""
            let remaining = 13 - tricksPlayed
            var lock = ""
            if let contract {
                let declaringSide = side(of: contract.declarer)
                if declarerTricks >= need { lock = " · ✅ contract secured" }
                else if defenderTricks > 13 - need { lock = " · 💥 set! +\(defenderTricks - (13 - need)) down" }
                else if trickGap > remaining { lock = " · 💥 going down" }
                _ = declaringSide
            }
            return "\(c)\(doubleTag)\(vulTag) · \(declarerTricks)–\(defenderTricks) · \(progress)\(lock)"
        case .gameOver:
            return resultText ?? "Game over"
        }
    }

    var resultText: String? {
        guard isOver else { return nil }
        let totalSlams = teamSlams[0] + teamSlams[1]
        let totalGrands = teamGrandSlams[0] + teamGrandSlams[1]
        var slamNote = totalSlams > 0 ? " · \(totalSlams) slam\(totalSlams == 1 ? "" : "s") bid & made 🎰" : ""
        if totalGrands > 0 { slamNote += " (\(totalGrands) grand)" }
        var extras = slamNote
        let totalOver = teamOvertricks[0] + teamOvertricks[1]
        let totalUnder = teamUndertricks[0] + teamUndertricks[1]
        if totalOver > 0 { extras += " · \(totalOver) overtrick\(totalOver == 1 ? "" : "s")" }
        if totalUnder > 0 { extras += " · \(totalUnder) down" }
        if contractsMade + contractsSet > 0 { extras += " · \(contractsMade) made / \(contractsSet) set" }
        if doubledContracts > 0 { extras += " · X2 doubled \(doubledContracts)×" }
        if redoubledContracts > 0 { extras += " · XX redoubled \(redoubledContracts)×" }
        if teamScores[0] == teamScores[1] { return "Tied at \(teamScores[0])\(extras)" }
        let winner = teamScores[0] > teamScores[1] ? 0 : 1
        return "\(sideLabel(winner)) win \(teamScores[winner])–\(teamScores[1 - winner])\(extras)"
    }

    func ranking() -> [[Int]] {
        guard isOver else { return [] }
        if teamScores[0] == teamScores[1] { return [[0, 1, 2, 3]] }
        let winner = teamScores[0] > teamScores[1] ? 0 : 1
        return [[winner, winner + 2], [1 - winner, 3 - winner]]
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
