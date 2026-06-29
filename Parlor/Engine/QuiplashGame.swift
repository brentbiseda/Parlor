import Foundation

// MARK: - Prompt Party (Quiplash-style)

struct QuiplashGame: GameEngine {
    static let kind = GameKind.promptParty
    static let promptsPerGame = 8

    var numPlayers: Int
    var promptIDs: [Int]          // shuffled indices into QuiplashPromptBank.all
    var currentPromptIdx: Int     // 0 ..< promptsPerGame
    var phase: Phase
    var currentActor: Int         // seat currently writing or voting
    var answers: [[String]]       // [promptIdx][seat]
    var votes: [[Int]]            // [promptIdx][voterSeat] → seat they voted for, -1 = not yet
    var scores: [Int]
    var seed: UInt64

    enum Phase: String, Codable { case writing, voting, revealing, over }

    // MARK: - Init

    init(playerCount: Int = 4) {
        numPlayers = max(3, min(8, playerCount))
        seed = UInt64.random(in: 0...UInt64.max)
        var gen = SplitMix64(seed: seed)
        let bank = QuiplashPromptBank.all
        let shuffled = (0..<bank.count).shuffled(using: &gen)
        promptIDs = shuffled.prefix(Self.promptsPerGame).map { bank[$0].id }
        while promptIDs.count < Self.promptsPerGame {
            promptIDs.append(bank[Int.random(in: 0..<bank.count, using: &gen)].id)
        }
        currentPromptIdx = 0
        phase = .writing
        currentActor = 0
        answers = Array(repeating: Array(repeating: "", count: numPlayers), count: Self.promptsPerGame)
        votes   = Array(repeating: Array(repeating: -1, count: numPlayers), count: Self.promptsPerGame)
        scores  = Array(repeating: 0, count: numPlayers)
    }

    // MARK: - GameEngine

    var playerCount: Int { numPlayers }
    var currentPlayer: Int { phase == .over ? 0 : currentActor }
    var isOver: Bool { phase == .over }

    var currentPrompt: QuiplashPrompt? {
        guard currentPromptIdx < promptIDs.count else { return nil }
        return QuiplashPromptBank.byID(promptIDs[currentPromptIdx])
    }

    var statusText: String {
        guard !isOver else { return resultText ?? "Prompt Party complete!" }
        let n = currentPromptIdx + 1
        switch phase {
        case .writing:
            return "Prompt \(n)/\(Self.promptsPerGame) · \(playerName(currentActor)) writing…"
        case .voting:
            return "Prompt \(n)/\(Self.promptsPerGame) · \(playerName(currentActor)) voting…"
        case .revealing:
            return "Prompt \(n)/\(Self.promptsPerGame) · Results!"
        case .over:
            return resultText ?? ""
        }
    }

    var resultText: String? {
        guard isOver else { return nil }
        let ranked = ranking()
        guard let top = ranked.first?.first else { return "Prompt Party complete!" }
        var parts = ["\(playerName(top)) wins! · \(scores[top]) pts"]
        for seat in 0..<numPlayers {
            parts.append("\(playerName(seat)): \(scores[seat])pts")
        }
        return parts.joined(separator: " · ")
    }

    func legalMoves() -> [Move] {
        guard !isOver else { return [] }
        switch phase {
        case .writing:
            return [.quiplash(.answer(""))]   // placeholder; isLegal handles any String
        case .voting:
            return votableSeats.map { .quiplash(.vote($0)) }
        case .revealing:
            return [.quiplash(.advance)]
        case .over:
            return []
        }
    }

    func isLegal(_ move: Move) -> Bool {
        guard !isOver else { return false }
        switch (phase, move) {
        case (.writing, .quiplash(.answer(_))): return true
        case (.voting,  .quiplash(.vote(let seat))): return votableSeats.contains(seat)
        case (.revealing, .quiplash(.advance)):      return true
        default: return false
        }
    }

    mutating func apply(_ move: Move) throws {
        switch (phase, move) {
        case (.writing, .quiplash(.answer(let text))):
            answers[currentPromptIdx][currentActor] = text
            advanceWriter()
        case (.voting, .quiplash(.vote(let seat))):
            votes[currentPromptIdx][currentActor] = seat
            advanceVoter()
        case (.revealing, .quiplash(.advance)):
            advancePrompt()
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
            } else {
                groups.append([seat])
            }
        }
        return groups
    }

    func redacted(for seat: Int) -> QuiplashGame {
        guard phase == .writing else { return self }
        var copy = self
        // During writing, hide all answers except the current actor's
        for p in 0..<Self.promptsPerGame {
            for s in 0..<numPlayers where s != currentActor {
                copy.answers[p][s] = ""
            }
        }
        return copy
    }

    // MARK: - Helpers

    var votableSeats: [Int] {
        (0..<numPlayers).filter { $0 != currentActor }
    }

    private func playerName(_ seat: Int) -> String { "P\(seat + 1)" }

    private mutating func advanceWriter() {
        currentActor += 1
        if currentActor >= numPlayers {
            currentActor = 0
            phase = .voting
        }
    }

    private mutating func advanceVoter() {
        currentActor += 1
        if currentActor >= numPlayers {
            tallyVotes(for: currentPromptIdx)
            currentActor = 0
            phase = .revealing
        }
    }

    private mutating func tallyVotes(for promptIdx: Int) {
        var voteTally = [Int: Int]()
        for voter in 0..<numPlayers {
            let chosen = votes[promptIdx][voter]
            if chosen >= 0 { voteTally[chosen, default: 0] += 1 }
        }
        let allVotedFor = Set(voteTally.keys)
        // Award points: 100 per vote; bonus 500 if all others voted for same seat
        for (seat, count) in voteTally {
            scores[seat] += count * 100
            if allVotedFor.count == 1 && allVotedFor.first == seat {
                scores[seat] += 500  // unanimous "Quiplash!"
            }
        }
    }

    private mutating func advancePrompt() {
        currentPromptIdx += 1
        if currentPromptIdx >= Self.promptsPerGame {
            phase = .over
        } else {
            phase = .writing
            currentActor = 0
        }
    }

    // Computed public fields for views
    var currentAnswers: [String] {
        guard currentPromptIdx < answers.count else { return [] }
        return answers[currentPromptIdx]
    }

    var currentVoteTally: [Int: Int] {
        guard currentPromptIdx < votes.count else { return [:] }
        var tally = [Int: Int]()
        for v in votes[currentPromptIdx] where v >= 0 {
            tally[v, default: 0] += 1
        }
        return tally
    }
}
