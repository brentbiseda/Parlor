import Foundation

// MARK: - Category / Difficulty

enum TriviaCategory: String, Codable, CaseIterable {
    case science    = "Science"
    case history    = "History"
    case geography  = "Geography"
    case sports     = "Sports"
    case movies     = "Movies & TV"
    case music      = "Music"
    case literature = "Literature"
    case technology = "Technology"
    case food       = "Food & Drink"
    case art        = "Art & Culture"

    var icon: String {
        switch self {
        case .science:    return "atom"
        case .history:    return "building.columns.fill"
        case .geography:  return "globe.americas.fill"
        case .sports:     return "trophy.fill"
        case .movies:     return "film.fill"
        case .music:      return "music.note"
        case .literature: return "book.fill"
        case .technology: return "cpu.fill"
        case .food:       return "fork.knife"
        case .art:        return "paintpalette.fill"
        }
    }

    var tintName: String {
        switch self {
        case .science:    return "blue"
        case .history:    return "brown"
        case .geography:  return "green"
        case .sports:     return "orange"
        case .movies:     return "purple"
        case .music:      return "pink"
        case .literature: return "indigo"
        case .technology: return "teal"
        case .food:       return "yellow"
        case .art:        return "red"
        }
    }
}

enum TriviaDifficulty: Int, Codable, CaseIterable {
    case easy = 0, medium = 1, hard = 2

    var pointValue: Int {
        switch self {
        case .easy:   return 5
        case .medium: return 10
        case .hard:   return 15
        }
    }

    var label: String {
        switch self {
        case .easy:   return "Easy"
        case .medium: return "Medium"
        case .hard:   return "Hard"
        }
    }
}

// MARK: - Question Model (used in TriviaQuestions.swift)

struct TriviaQ: Codable {
    let id: Int
    let cat: TriviaCategory
    let diff: TriviaDifficulty
    let q: String
    let a: [String]    // exactly 4 options
    let c: Int         // correct index 0–3
}

// MARK: - Game Engine

struct TriviaGame: GameEngine {
    static let kind = GameKind.trivia
    static let questionsPerGame = 15
    static let timeLimitSeconds = 20
    static let speedBonusFast  = 5    // extra pts for < 5 sec
    static let speedBonusMed   = 2    // extra pts for < 10 sec

    // Variable player count (1–4)
    var numPlayers: Int

    var questionIDs: [Int]        // IDs from bank, shuffled per game
    var currentQ: Int             // index into questionIDs (0..<questionsPerGame)
    var currentSeat: Int          // which seat answers next within this question's round
    var scores: [Int]             // cumulative per seat
    var answers: [[Int?]]         // [seat][questionIdx] → option index or nil
    var seed: UInt64

    // Per-question timing (view sends timeOut moves; engine ignores the exact time)
    var answerTimes: [[Int]]      // seconds taken, 99 = timed out

    var playerCount: Int { numPlayers }
    var currentPlayer: Int { currentSeat }
    var isOver: Bool { currentQ >= Self.questionsPerGame }

    init(playerCount: Int = 4) {
        numPlayers = max(1, min(4, playerCount))
        seed = UInt64.random(in: 0...UInt64.max)
        var gen = SplitMix64(seed: seed)
        let bank = TriviaQuestionBank.all
        let shuffled = (0..<bank.count).shuffled(using: &gen)
        questionIDs = shuffled.prefix(Self.questionsPerGame).map { bank[$0].id }
        // Pad to questionsPerGame if bank is small
        while questionIDs.count < Self.questionsPerGame {
            questionIDs.append(bank[Int.random(in: 0..<bank.count, using: &gen)].id)
        }
        currentQ    = 0
        currentSeat = 0
        scores      = Array(repeating: 0, count: numPlayers)
        answers     = Array(repeating: Array(repeating: nil, count: Self.questionsPerGame),
                            count: numPlayers)
        answerTimes = Array(repeating: Array(repeating: 99, count: Self.questionsPerGame),
                            count: numPlayers)
    }

    // MARK: GameEngine

    var statusText: String {
        guard !isOver else { return resultText ?? "Trivia complete!" }
        let qNum = currentQ + 1
        if let q = currentQuestion {
            return "Q\(qNum)/\(Self.questionsPerGame) · \(q.cat.rawValue) · \(q.diff.label)"
        }
        return "Q\(qNum)/\(Self.questionsPerGame)"
    }

    var resultText: String? {
        guard isOver else { return nil }
        let ranked = ranking()
        guard let top = ranked.first?.first else { return "Trivia complete!" }
        let topScore = scores[top]
        let correct = correctCount(for: top)
        var parts = ["P\(top+1) wins · \(topScore) pts · \(correct)/\(Self.questionsPerGame) correct"]
        for seat in 0..<numPlayers {
            parts.append("P\(seat+1): \(scores[seat])pts (\(correctCount(for: seat))✓)")
        }
        return parts.joined(separator: " · ")
    }

    func legalMoves() -> [Move] {
        guard !isOver else { return [] }
        return (0..<4).map { .trivia(.answer($0)) } + [.trivia(.timeOut)]
    }

    func isLegal(_ move: Move) -> Bool {
        guard !isOver else { return false }
        switch move {
        case .trivia(.answer(let idx)): return idx >= 0 && idx < 4
        case .trivia(.timeOut):         return true
        default:                        return false
        }
    }

    mutating func apply(_ move: Move) throws {
        guard !isOver else { throw GameError.gameOver }
        switch move {
        case .trivia(.answer(let idx)):
            guard idx >= 0 && idx < 4 else { throw GameError.illegalMove }
            recordAnswer(optionIndex: idx)
        case .trivia(.timeOut):
            recordAnswer(optionIndex: nil)
        default:
            throw GameError.illegalMove
        }
    }

    private mutating func recordAnswer(optionIndex: Int?) {
        guard currentSeat < numPlayers else { return }
        answers[currentSeat][currentQ] = optionIndex
        if let idx = optionIndex,
           let q = currentQuestion,
           idx == q.c {
            scores[currentSeat] += q.diff.pointValue
        }
        // Advance seat; when all seats answered, advance question
        currentSeat += 1
        if currentSeat >= numPlayers {
            currentSeat = 0
            currentQ += 1
        }
    }

    var currentQuestion: TriviaQ? {
        guard !isOver, currentQ < questionIDs.count else { return nil }
        return TriviaQuestionBank.byID(questionIDs[currentQ])
    }

    func questionAt(_ idx: Int) -> TriviaQ? {
        guard idx < questionIDs.count else { return nil }
        return TriviaQuestionBank.byID(questionIDs[idx])
    }

    func answerFor(seat: Int, question: Int) -> Int? {
        guard seat < numPlayers, question < Self.questionsPerGame else { return nil }
        return answers[seat][question]
    }

    private func correctCount(for seat: Int) -> Int {
        guard seat < numPlayers else { return 0 }
        return (0..<Self.questionsPerGame).filter { qi in
            guard let ans = answers[seat][qi], let q = questionAt(qi) else { return false }
            return ans == q.c
        }.count
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
}
