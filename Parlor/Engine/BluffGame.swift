import Foundation

// MARK: - Bluff! (Balderdash-style fake definitions)

struct BluffGame: GameEngine {
    static let kind = GameKind.bluff
    static let roundsPerGame = 8

    var numPlayers: Int
    var wordIDs: [Int]              // shuffled indices into BluffWordBank.all
    var currentRound: Int           // 0 ..< roundsPerGame
    var phase: Phase
    var currentActor: Int           // seat currently writing fake definition
    /// shuffledOrder[round] maps answer-display-index → seat (-1 = real definition)
    var shuffledOrders: [[Int]]
    var definitions: [[String]]     // [round][seat] → their fake definition
    var votes: [Int]                // [voterSeat] → display-index chosen this round, -1 = not yet
    var scores: [Int]
    var seed: UInt64

    enum Phase: String, Codable { case defining, voting, revealing, over }

    init(playerCount: Int = 4) {
        numPlayers = max(3, min(8, playerCount))
        seed = UInt64.random(in: 0...UInt64.max)
        var gen = SplitMix64(seed: seed)
        let bank = BluffWordBank.all
        let shuffled = (0..<bank.count).shuffled(using: &gen)
        wordIDs = shuffled.prefix(Self.roundsPerGame).map { bank[$0].id }
        while wordIDs.count < Self.roundsPerGame {
            wordIDs.append(bank[Int.random(in: 0..<bank.count, using: &gen)].id)
        }
        currentRound = 0
        phase = .defining
        currentActor = 0
        definitions = Array(repeating: Array(repeating: "", count: numPlayers), count: Self.roundsPerGame)
        votes = Array(repeating: -1, count: numPlayers)
        scores = Array(repeating: 0, count: numPlayers)
        // Pre-generate shuffled answer orders for each round
        // Each order is a list of seats (0..numPlayers-1) + -1 for the real answer
        let n = numPlayers
        shuffledOrders = (0..<Self.roundsPerGame).map { _ in
            var order = Array(0..<n) + [-1]
            order.shuffle(using: &gen)
            return order
        }
    }

    // MARK: - GameEngine

    var playerCount: Int { numPlayers }
    var currentPlayer: Int { phase == .over ? 0 : currentActor }
    var isOver: Bool { phase == .over }

    var currentWord: BluffWord? {
        guard currentRound < wordIDs.count else { return nil }
        return BluffWordBank.byID(wordIDs[currentRound])
    }

    var statusText: String {
        guard !isOver else { return resultText ?? "Bluff! complete." }
        let n = currentRound + 1
        switch phase {
        case .defining:  return "Round \(n)/\(Self.roundsPerGame) · P\(currentActor + 1) defining…"
        case .voting:    return "Round \(n)/\(Self.roundsPerGame) · P\(currentActor + 1) voting…"
        case .revealing: return "Round \(n)/\(Self.roundsPerGame) · Results!"
        case .over:      return resultText ?? ""
        }
    }

    var resultText: String? {
        guard isOver else { return nil }
        let ranked = ranking()
        guard let top = ranked.first?.first else { return "Bluff! complete." }
        var parts = ["P\(top + 1) wins! · \(scores[top]) pts"]
        for seat in 0..<numPlayers { parts.append("P\(seat + 1): \(scores[seat])pts") }
        return parts.joined(separator: " · ")
    }

    func legalMoves() -> [Move] {
        guard !isOver else { return [] }
        switch phase {
        case .defining:  return [.bluff(.define(""))]    // isLegal handles any text
        case .voting:    return votableIndices.map { .bluff(.vote($0)) }
        case .revealing: return [.bluff(.advance)]
        case .over:      return []
        }
    }

    func isLegal(_ move: Move) -> Bool {
        guard !isOver else { return false }
        switch (phase, move) {
        case (.defining,  .bluff(.define(_))):          return true
        case (.voting,    .bluff(.vote(let i))):        return votableIndices.contains(i)
        case (.revealing, .bluff(.advance)):             return true
        default: return false
        }
    }

    mutating func apply(_ move: Move) throws {
        switch (phase, move) {
        case (.defining, .bluff(.define(let text))):
            definitions[currentRound][currentActor] = text
            advanceDefiner()
        case (.voting, .bluff(.vote(let idx))):
            guard idx != shuffledOrders[currentRound].firstIndex(of: currentActor) else {
                throw GameError.illegalMove  // can't vote for your own fake
            }
            votes[currentActor] = idx
            advanceVoter()
        case (.revealing, .bluff(.advance)):
            advanceRound()
        default:
            throw GameError.illegalMove
        }
    }

    func ranking() -> [[Int]] {
        guard isOver else { return [] }
        let sorted = (0..<numPlayers).sorted { scores[$0] > scores[$1] }
        var groups: [[Int]] = []
        for seat in sorted {
            if let last = groups.last, let rep = last.first, scores[rep] == scores[seat] {
                groups[groups.count - 1].append(seat)
            } else { groups.append([seat]) }
        }
        return groups
    }

    func redacted(for seat: Int) -> BluffGame {
        guard phase == .defining else { return self }
        var copy = self
        for r in 0..<Self.roundsPerGame {
            for s in 0..<numPlayers where s != currentActor {
                copy.definitions[r][s] = ""
            }
        }
        return copy
    }

    // MARK: - Helpers

    /// Display order for current round: array of (label, text, ownerSeat or -1 for real)
    func displayedAnswers(for round: Int) -> [(label: String, text: String, seat: Int)] {
        guard round < shuffledOrders.count, let word = BluffWordBank.byID(wordIDs[round]) else { return [] }
        let order = shuffledOrders[round]
        let letters = ["A","B","C","D","E","F","G","H","I"]
        return order.enumerated().map { idx, seat in
            let text = seat == -1 ? word.realDefinition : definitions[round][seat]
            return (label: letters[idx], text: text, seat: seat)
        }
    }

    /// Display-index positions that the current voter can pick (not their own)
    var votableIndices: [Int] {
        let myOwnIdx = shuffledOrders[currentRound].firstIndex(of: currentActor) ?? -1
        return (0..<shuffledOrders[currentRound].count).filter { $0 != myOwnIdx }
    }

    private mutating func advanceDefiner() {
        currentActor += 1
        if currentActor >= numPlayers {
            currentActor = 0
            phase = .voting
        }
    }

    private mutating func advanceVoter() {
        currentActor += 1
        if currentActor >= numPlayers {
            tallyRound(currentRound)
            currentActor = 0
            phase = .revealing
        }
    }

    private mutating func tallyRound(_ round: Int) {
        guard round < shuffledOrders.count else { return }
        let order = shuffledOrders[round]
        let realIdx = order.firstIndex(of: -1) ?? -1
        for voter in 0..<numPlayers {
            let chosen = votes[voter]
            if chosen < 0 { continue }
            if chosen == realIdx {
                // Guessed the real definition: 2 pts
                scores[voter] += 2
            } else {
                // Fell for someone's fake: 1 pt to fake author
                let fakeAuthor = order[chosen]
                if fakeAuthor >= 0 { scores[fakeAuthor] += 1 }
            }
        }
        // Nobody guessed real → author of each fake gets 1 extra (the word was truly hard)
        let guessedReal = votes.contains { $0 == realIdx }
        if !guessedReal {
            for seat in 0..<numPlayers { scores[seat] += 1 }
        }
    }

    private mutating func advanceRound() {
        votes = Array(repeating: -1, count: numPlayers)
        currentRound += 1
        if currentRound >= Self.roundsPerGame {
            phase = .over
        } else {
            phase = .defining
            currentActor = 0
        }
    }
}
