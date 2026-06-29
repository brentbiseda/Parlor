import Foundation

// MARK: - Jack Attack (You Don't Know Jack-style irreverent trivia)

struct JackAttackGame: GameEngine {
    static let kind = GameKind.jackAttack
    static let questionsPerGame = 20
    static let timeLimitSeconds = 15     // faster than regular trivia
    static let basePoints = 2000         // max points per question
    static let pointsPerSecond = 100     // deducted per second used

    var numPlayers: Int
    var questionIDs: [Int]        // from JackAttackQuestionBank
    var currentQ: Int
    var currentSeat: Int
    var scores: [Int]
    var answers: [[Int?]]         // [seat][questionIdx]
    var screwsLeft: [Int]         // screws remaining per seat (1 each)
    var screwedSeat: Int?         // seat currently being screwed
    var screwedBy: Int?           // who played the screw
    var seed: UInt64

    init(playerCount: Int = 4) {
        numPlayers = max(2, min(16, playerCount))
        seed = UInt64.random(in: 0...UInt64.max)
        var gen = SplitMix64(seed: seed)
        let bank = JackAttackQuestionBank.all
        let shuffled = (0..<bank.count).shuffled(using: &gen)
        questionIDs = shuffled.prefix(Self.questionsPerGame).map { bank[$0].id }
        while questionIDs.count < Self.questionsPerGame {
            questionIDs.append(bank[Int.random(in: 0..<bank.count, using: &gen)].id)
        }
        currentQ    = 0
        currentSeat = 0
        scores      = Array(repeating: 0, count: numPlayers)
        answers     = Array(repeating: Array(repeating: nil, count: Self.questionsPerGame), count: numPlayers)
        screwsLeft  = Array(repeating: 1, count: numPlayers)
        screwedSeat = nil
        screwedBy   = nil
    }

    // MARK: - GameEngine

    var playerCount: Int { numPlayers }
    var currentPlayer: Int { screwedSeat ?? currentSeat }
    var isOver: Bool { currentQ >= Self.questionsPerGame }

    var currentQuestion: JackAttackQuestion? {
        guard !isOver, currentQ < questionIDs.count else { return nil }
        return JackAttackQuestionBank.byID(questionIDs[currentQ])
    }

    var statusText: String {
        guard !isOver else { return resultText ?? "Jack Attack over!" }
        let base = "Q\(currentQ + 1)/\(Self.questionsPerGame)"
        if let s = screwedSeat, let by = screwedBy {
            return "\(base) · 🔩 P\(by + 1) screwed P\(s + 1)!"
        }
        return "\(base) · P\(currentSeat + 1)'s question"
    }

    var resultText: String? {
        guard isOver else { return nil }
        let ranked = ranking()
        guard let top = ranked.first?.first else { return "Jack Attack over!" }
        var parts = ["P\(top + 1) wins! · \(scores[top]) pts"]
        for seat in 0..<numPlayers { parts.append("P\(seat + 1): \(scores[seat])pts") }
        return parts.joined(separator: " · ")
    }

    func legalMoves() -> [Move] {
        guard !isOver else { return [] }
        var moves: [Move] = (0..<4).map { .jackAttack(.answer($0, timeUsed: 0)) }
        moves.append(.jackAttack(.timeOut))
        // Screw moves (if current seat has screws left and this isn't already a screwed turn)
        if screwedSeat == nil && screwsLeft[currentSeat] > 0 {
            for s in 0..<numPlayers where s != currentSeat {
                moves.append(.jackAttack(.screw(s)))
            }
        }
        return moves
    }

    func isLegal(_ move: Move) -> Bool {
        guard !isOver else { return false }
        switch move {
        case .jackAttack(.answer(let i, _)): return i >= 0 && i < 4
        case .jackAttack(.timeOut):           return true
        case .jackAttack(.screw(let s)):
            return screwedSeat == nil && s != currentSeat && screwsLeft[currentSeat] > 0
        default: return false
        }
    }

    mutating func apply(_ move: Move) throws {
        guard !isOver else { throw GameError.gameOver }
        switch move {
        case .jackAttack(.answer(let idx, let timeUsed)):
            guard idx >= 0 && idx < 4 else { throw GameError.illegalMove }
            let answerer = screwedSeat ?? currentSeat
            answers[answerer][currentQ] = idx
            if let q = currentQuestion, idx == q.correctIndex {
                let pts = max(200, Self.basePoints - timeUsed * Self.pointsPerSecond)
                if screwedSeat != nil {
                    // Screwed player answered correctly — they get points, screwer loses some
                    scores[answerer] += pts
                    if let by = screwedBy { scores[by] = max(0, scores[by] - 500) }
                } else {
                    scores[answerer] += pts
                }
            } else if let by = screwedBy {
                // Wrong answer on a screw — screwer gets consolation points
                scores[by] += 500
            }
            clearScrew()
            advanceSeat()

        case .jackAttack(.timeOut):
            clearScrew()
            advanceSeat()

        case .jackAttack(.screw(let target)):
            guard screwedSeat == nil, target != currentSeat, screwsLeft[currentSeat] > 0 else {
                throw GameError.illegalMove
            }
            screwedBy   = currentSeat
            screwedSeat = target
            screwsLeft[currentSeat] -= 1

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

    // MARK: - Helpers

    private mutating func clearScrew() {
        screwedSeat = nil
        screwedBy   = nil
    }

    private mutating func advanceSeat() {
        currentSeat += 1
        if currentSeat >= numPlayers {
            currentSeat = 0
            currentQ += 1
        }
    }

    func answerFor(seat: Int, question: Int) -> Int? {
        guard seat < numPlayers, question < Self.questionsPerGame else { return nil }
        return answers[seat][question]
    }
}

// MARK: - Question model + bank

struct JackAttackQuestion: Codable {
    let id: Int
    let q: String                   // irreverently phrased question
    let a: [String]                 // 4 options
    let correctIndex: Int
    let category: String
}

enum JackAttackQuestionBank {
    static var all: [JackAttackQuestion] { questions }
    static func byID(_ id: Int) -> JackAttackQuestion? { all.first { $0.id == id } }

    static let questions: [JackAttackQuestion] = [
        // Pop culture
        JackAttackQuestion(id: 1, q: "Quick! Before your brain gives up: which planet is ACTUALLY closest to Earth on average?", a: ["Venus","Mars","Jupiter","Mercury"], correctIndex: 3, category: "Science"),
        JackAttackQuestion(id: 2, q: "The ancient Romans had a god for literally everything. Which one was the god of doorways and beginnings?", a: ["Jupiter","Janus","Mars","Mercury"], correctIndex: 1, category: "History"),
        JackAttackQuestion(id: 3, q: "Your body has more of these than stars in the Milky Way. What is it?", a: ["Cells","Hairs","Nerve endings","Bacteria"], correctIndex: 3, category: "Science"),
        JackAttackQuestion(id: 4, q: "In what year did the first iPhone launch? Think carefully — it matters.", a: ["2005","2006","2007","2008"], correctIndex: 2, category: "Technology"),
        JackAttackQuestion(id: 5, q: "Shakespeare's Hamlet says 'To be or not to be.' But which soliloquy is this actually from?", a: ["Act 1 Scene 1","Act 2 Scene 2","Act 3 Scene 1","Act 5 Scene 2"], correctIndex: 2, category: "Literature"),
        JackAttackQuestion(id: 6, q: "The most dangerous animal on Earth kills about 700,000 humans per year. What is it (spoiler: it's embarrassing)?", a: ["Shark","Snake","Hippo","Mosquito"], correctIndex: 3, category: "Science"),
        JackAttackQuestion(id: 7, q: "How many sides does a snowflake have? (Don't you dare say 'it depends.')", a: ["4","5","6","8"], correctIndex: 2, category: "Science"),
        JackAttackQuestion(id: 8, q: "Walt Disney was actually cryogenically frozen. True or false?", a: ["True, probably","False, he was cremated","True, confirmed","False, he was buried"], correctIndex: 1, category: "Pop Culture"),
        JackAttackQuestion(id: 9, q: "Which US state has the longest coastline? (Hint: it's cold.)", a: ["California","Florida","Maine","Alaska"], correctIndex: 3, category: "Geography"),
        JackAttackQuestion(id: 10, q: "The inventor of the World Wide Web was knighted by the Queen. What was his name?", a: ["Bill Gates","Tim Berners-Lee","Vint Cerf","Marc Andreessen"], correctIndex: 1, category: "Technology"),
        JackAttackQuestion(id: 11, q: "Which of these is NOT an actual Pokémon?", a: ["Snorlax","Geodude","Clamperl","Dragonite"], correctIndex: 3, category: "Pop Culture"),
        JackAttackQuestion(id: 12, q: "If you could fit ALL the planets in the solar system between Earth and the Moon — could you? (Yes or no.)", a: ["No, not even close","Yes, with room to spare","Only if you stack them","Barely, just Mars"], correctIndex: 1, category: "Science"),
        JackAttackQuestion(id: 13, q: "The Great Wall of China is visible from space. Totally a lie. But WHO first spread this myth?", a: ["Napoleon","Marco Polo","Henry Norman in 1932","Buzz Aldrin"], correctIndex: 2, category: "History"),
        JackAttackQuestion(id: 14, q: "What's the fastest thing in the universe? (One answer is technically not correct for reasons we won't get into.)", a: ["Light","Cosmic rays","Gravity waves","Sound in osmium"], correctIndex: 0, category: "Science"),
        JackAttackQuestion(id: 15, q: "Taylor Swift has more Grammy Awards than any other artist. As of 2024, how many?", a: ["11","14","16","22"], correctIndex: 1, category: "Music"),
        JackAttackQuestion(id: 16, q: "Which country invented champagne? (Careful — this one's a trap.)", a: ["France","Germany","Spain","England"], correctIndex: 0, category: "Food"),
        JackAttackQuestion(id: 17, q: "The word 'sandwich' comes from the Earl of Sandwich. What was he actually doing when he invented it?", a: ["Gambling","Hunting","Writing","Fighting"], correctIndex: 0, category: "History"),
        JackAttackQuestion(id: 18, q: "How many times has the Eiffel Tower been painted?", a: ["3","7","18","32"], correctIndex: 2, category: "Art"),
        JackAttackQuestion(id: 19, q: "Cleopatra lived closer to the Moon landing than to the building of the pyramids. This is:", a: ["False, obviously","True, completely true","Roughly equal","Only true if you squint"], correctIndex: 1, category: "History"),
        JackAttackQuestion(id: 20, q: "A group of flamingos is called a:", a: ["Flock","Colony","Flamboyance","Gaggle"], correctIndex: 2, category: "Science"),
        JackAttackQuestion(id: 21, q: "The human eye can distinguish approximately how many colors?", a: ["100,000","1 million","10 million","100 million"], correctIndex: 2, category: "Science"),
        JackAttackQuestion(id: 22, q: "Which country consumes the most chocolate per capita?", a: ["Belgium","Germany","United States","Switzerland"], correctIndex: 3, category: "Food"),
        JackAttackQuestion(id: 23, q: "If you laid all the nerves in your body end to end, how far would they stretch?", a: ["1 mile","50 miles","100 miles","47 miles"], correctIndex: 2, category: "Science"),
        JackAttackQuestion(id: 24, q: "The Olympics were canceled three times. Which one was NOT a reason?", a: ["World War I","World War II","A global pandemic in 1918","The Cold War"], correctIndex: 3, category: "Sports"),
        JackAttackQuestion(id: 25, q: "Who was the first female Prime Minister of any country?", a: ["Margaret Thatcher","Indira Gandhi","Golda Meir","Sirimavo Bandaranaike"], correctIndex: 3, category: "History"),
        JackAttackQuestion(id: 26, q: "Which country has won the most FIFA World Cups?", a: ["Germany","Italy","Argentina","Brazil"], correctIndex: 3, category: "Sports"),
        JackAttackQuestion(id: 27, q: "What is the most shoplifted book in the world?", a: ["The Bible","Harry Potter","The Communist Manifesto","The Guinness Book of World Records"], correctIndex: 0, category: "Literature"),
        JackAttackQuestion(id: 28, q: "Oxford University is older than which empire?", a: ["Roman Empire","Byzantine Empire","Ottoman Empire","Aztec Empire"], correctIndex: 2, category: "History"),
        JackAttackQuestion(id: 29, q: "A shrimp's heart is located where?", a: ["In its tail","In its head","It doesn't have one","Near its gills"], correctIndex: 1, category: "Science"),
        JackAttackQuestion(id: 30, q: "Which planet rotates backwards compared to most others?", a: ["Mars","Saturn","Venus","Neptune"], correctIndex: 2, category: "Science"),
        JackAttackQuestion(id: 31, q: "The dot above the letter 'i' and 'j' is called a:", a: ["Tittle","Serif","Glyph","Diacritic"], correctIndex: 0, category: "Language"),
        JackAttackQuestion(id: 32, q: "How long does it take light from the sun to reach Earth?", a: ["1 second","8 minutes","43 minutes","1 hour"], correctIndex: 1, category: "Science"),
        JackAttackQuestion(id: 33, q: "The Monopoly man does NOT have which accessory that everyone swears he has?", a: ["Top hat","Cane","Monocle","Briefcase of money"], correctIndex: 2, category: "Pop Culture"),
        JackAttackQuestion(id: 34, q: "What percentage of the ocean has been explored by humans?", a: ["20%","50%","80%","Less than 20%"], correctIndex: 3, category: "Science"),
        JackAttackQuestion(id: 35, q: "The inventor of the telephone, Alexander Graham Bell, also invented what unexpected device?", a: ["Metal detector","Television","Microwave","Submarine"], correctIndex: 0, category: "Technology"),
        JackAttackQuestion(id: 36, q: "How many muscles does it take to smile (roughly)?", a: ["6","12","17","43"], correctIndex: 2, category: "Science"),
        JackAttackQuestion(id: 37, q: "Napoleon Bonaparte was 5'6\" tall — roughly average for his time. Where did the 'short' myth come from?", a: ["British propaganda","His tall guards","An accounting error","Victor Hugo's novel"], correctIndex: 0, category: "History"),
        JackAttackQuestion(id: 38, q: "Which came first — the chicken or the egg? (Science actually has an answer.)", a: ["Chicken","Egg","They evolved simultaneously","It's impossible to know"], correctIndex: 1, category: "Science"),
        JackAttackQuestion(id: 39, q: "What is the rarest blood type?", a: ["O negative","AB negative","B negative","Golden blood (Rh-null)"], correctIndex: 3, category: "Science"),
        JackAttackQuestion(id: 40, q: "The first video game ever played in outer space was:", a: ["Pong","Tetris","Pac-Man","Doom"], correctIndex: 1, category: "Technology"),
    ]
}
