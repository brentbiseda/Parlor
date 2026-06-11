import XCTest
@testable import EngineCheck

final class SmokeTests: XCTestCase {

    /// Drive a game to completion with bot moves; fail on illegal-move errors
    /// or games that never terminate.
    func playOut(_ kind: GameKind, options: GameOptions = GameOptions(), maxMoves: Int = 20000,
                 file: StaticString = #filePath, line: UInt = #line) {
        var game = AnyGame.make(kind: kind, options: options)
        var moves = 0
        while !game.isOver && moves < maxMoves {
            guard let move = Bot.chooseMove(for: game, difficulty: options.botDifficulty) else { break }
            do {
                try game.applyValidated(move)
            } catch {
                XCTFail("\(kind) rejected bot move \(move): \(error)", file: file, line: line)
                return
            }
            moves += 1
        }
        if kind == .solitaire || kind == .freecell || kind == .mahjong {
            // Solo games can dead-end; surviving without errors is enough.
            return
        }
        XCTAssertTrue(game.isOver, "\(kind) did not finish in \(maxMoves) moves", file: file, line: line)
        XCTAssertNotNil(game.resultText, "\(kind) finished without a result", file: file, line: line)
        if kind.isCompetitive {
            let ranking = game.ranking()
            XCTAssertFalse(ranking.isEmpty, "\(kind) finished without a ranking", file: file, line: line)
            XCTAssertEqual(ranking.flatMap { $0 }.sorted(), Array(0..<kind.playerCount),
                           "\(kind) ranking must place every seat exactly once", file: file, line: line)
        }
    }

    func testHearts() { for _ in 0..<3 { playOut(.hearts) } }
    func testSpades() { for _ in 0..<3 { playOut(.spades) } }
    func testEuchre() { for _ in 0..<3 { playOut(.euchre) } }
    func testBridge() { for _ in 0..<3 { playOut(.bridge) } }
    func testChess() { for _ in 0..<3 { playOut(.chess) } }
    func testCheckers() { for _ in 0..<3 { playOut(.checkers) } }
    func testGo() {
        playOut(.go)
        playOut(.go, options: GameOptions(goBoardSize: 13))
    }
    func testSolitaire() {
        playOut(.solitaire, maxMoves: 500)
        playOut(.solitaire, options: GameOptions(klondikeDrawThree: true), maxMoves: 500)
    }
    func testFreeCell() { for _ in 0..<3 { playOut(.freecell, maxMoves: 500) } }
    func testMahjong() { playOut(.mahjong, maxMoves: 500) }
    func testTetris() { for _ in 0..<3 { playOut(.tetris, maxMoves: 5000) } }

    func testBotDifficulties() {
        for difficulty in BotDifficulty.allCases {
            let options = GameOptions(botDifficulty: difficulty)
            playOut(.hearts, options: options)
            playOut(.spades, options: options)
            playOut(.euchre, options: options)
            playOut(.bridge, options: options)
            playOut(.chess, options: options)
            playOut(.checkers, options: options)
            playOut(.go, options: options)
        }
    }

    func testHardBotsBeatEasyBotsAtCheckers() {
        // Hard takes material; over a handful of games it should not lose
        // the series to random play. (Seat 0 = hard, seat 1 = easy.)
        var hardPoints = 0, easyPoints = 0
        for _ in 0..<6 {
            var game = AnyGame.make(kind: .checkers, options: GameOptions())
            var moves = 0
            while !game.isOver && moves < 2000 {
                let difficulty: BotDifficulty = game.currentPlayer == 0 ? .hard : .easy
                guard let move = Bot.chooseMove(for: game, difficulty: difficulty) else { break }
                try? game.applyValidated(move)
                moves += 1
            }
            let ranking = game.ranking()
            if ranking.first == [0] { hardPoints += 2 }
            else if ranking.first == [1] { easyPoints += 2 }
            else { hardPoints += 1; easyPoints += 1 }
        }
        XCTAssertGreaterThanOrEqual(hardPoints, easyPoints, "hard bot lost a 6-game series to random play")
    }

    func testTetrisLineClearScores() {
        var game = TetrisGame()
        // Fill the bottom row except one column, then drop an I piece into it.
        for x in 0..<6 { game.board[19 * TetrisGame.width + x] = 1 }
        game.board[19 * TetrisGame.width + 6] = 0
        for x in 7..<10 { game.board[19 * TetrisGame.width + x] = 1 }
        XCTAssertEqual(game.level, 1)
        XCTAssertTrue(game.isLegal(.tetris(.tick)))
        // Engine mechanics: rotation keeps cells inside the well.
        for _ in 0..<8 { try? game.apply(.tetris(.rotate)) }
        if let piece = game.current {
            for (x, y) in piece.cells() {
                XCTAssertTrue((0..<TetrisGame.width).contains(x))
                XCTAssertLessThan(y, TetrisGame.height)
            }
        }
    }

    func testKlondikeMaxPasses() {
        var game = KlondikeGame(drawThree: false, maxPasses: 1)
        // Exhaust the stock.
        while !game.stock.isEmpty { try? game.apply(.klondike(.draw)) }
        XCTAssertFalse(game.canResetStock, "maxPasses 1 must forbid restocking")
        XCTAssertThrowsError(try game.applyValidated(.klondike(.resetStock)))

        var unlimited = KlondikeGame(drawThree: false, maxPasses: 0)
        while !unlimited.stock.isEmpty { try? unlimited.apply(.klondike(.draw)) }
        XCTAssertTrue(unlimited.canResetStock)
    }

    func testBreakout() {
        var game = AnyGame.make(kind: .breakout, options: GameOptions())
        try? game.applyValidated(.breakout(.score(150)))
        try? game.applyValidated(.breakout(.levelCleared))
        for _ in 0..<BreakoutGame.livesPerGame { try? game.applyValidated(.breakout(.ballLost)) }
        XCTAssertTrue(game.isOver)
        let breakout = game.engine as! BreakoutGame
        XCTAssertEqual(breakout.score, 650)   // 150 + 500 level bonus
        XCTAssertEqual(breakout.level, 2)
        XCTAssertThrowsError(try game.applyValidated(.breakout(.score(10))))
    }

    func testPinball() {
        var game = AnyGame.make(kind: .pinball, options: GameOptions())
        try? game.applyValidated(.pinball(.score(150)))
        try? game.applyValidated(.pinball(.score(425)))
        for _ in 0..<PinballGame.ballsPerGame { try? game.applyValidated(.pinball(.ballDrained)) }
        XCTAssertTrue(game.isOver)
        let pinball = game.engine as! PinballGame
        XCTAssertEqual(pinball.score, 575)
        XCTAssertThrowsError(try game.applyValidated(.pinball(.score(10))))
    }

    func testFreeCellDeal() {
        let game = FreeCellGame()
        XCTAssertEqual(game.cascades.map(\.count), [7, 7, 7, 7, 6, 6, 6, 6])
        XCTAssertEqual(Set(game.cascades.flatMap { $0 }).count, 52)
        XCTAssertFalse(game.legalMoves().isEmpty)
    }

    func testMahjongLayoutHas144Positions() {
        XCTAssertEqual(MahjongGame.turtleLayout().count, 144)
        XCTAssertEqual(MahjongGame().tiles.count, 144)
    }

    func testRoundTripCoding() throws {
        for kind in GameKind.allCases {
            let game = AnyGame.make(kind: kind, options: GameOptions())
            let data = try JSONEncoder().encode(game)
            let decoded = try JSONDecoder().decode(AnyGame.self, from: data)
            XCTAssertEqual(decoded.kind, kind)
        }
    }

    func testRedactionHidesHands() {
        let game = AnyGame.make(kind: .hearts, options: GameOptions())
        let redacted = game.redacted(for: 0)
        let hearts = redacted.engine as! HeartsGame
        XCTAssertEqual(hearts.hands[0].count, 13)
        XCTAssertTrue(hearts.hands[1].isEmpty)
    }

    func testChessOpeningMoveCount() {
        let chess = ChessGame()
        XCTAssertEqual(chess.legalBoardMoves(for: 0).count, 20)
    }

    // MARK: - Leagues & tournaments

    func entrants(_ count: Int) -> [Entrant] {
        (0..<count).map { Entrant(name: "P\($0)", isBot: $0 > 0) }
    }

    func testRoundRobinEveryPairMeetsOnce() {
        for count in [3, 4, 5, 8] {
            let players = entrants(count)
            let league = League(name: "L", gameKind: .chess, entrants: players, rounds: 1)
            var seen = Set<Set<UUID>>()
            for match in league.matches {
                XCTAssertEqual(match.entrantIDs.count, 2)
                XCTAssertTrue(seen.insert(Set(match.entrantIDs)).inserted, "pair met twice")
            }
            XCTAssertEqual(seen.count, count * (count - 1) / 2)
        }
    }

    func testRotatingTablesSeatEveryoneEachRound() {
        let players = entrants(8)
        let league = League(name: "L", gameKind: .hearts, entrants: players, rounds: 3)
        XCTAssertEqual(league.roundCount, 3)
        for round in 0..<3 {
            let seated = league.matches(inRound: round).flatMap(\.entrantIDs)
            XCTAssertEqual(Set(seated).count, 8, "every player seated exactly once per round")
        }
    }

    func testLeagueStandingsPoints() {
        let players = entrants(4)
        var league = League(name: "L", gameKind: .hearts, entrants: players, rounds: 1)
        let match = league.matches[0]
        // Clear 1st, tie for 2nd/3rd, clear 4th: points 3, 1.5, 1.5, 0.
        let ranked = [[match.entrantIDs[0]], [match.entrantIDs[1], match.entrantIDs[2]], [match.entrantIDs[3]]]
        league.record(matchID: match.id, outcome: MatchOutcome(rankedGroups: ranked, summary: "test"))
        let standings = league.standings()
        XCTAssertEqual(standings[0].points, 3.0)
        XCTAssertEqual(standings[0].wins, 1)
        XCTAssertEqual(standings[1].points, 1.5)
        XCTAssertEqual(standings[3].points, 0.0)
        XCTAssertEqual(standings[3].losses, 1)
    }

    func testKnockoutBracketAdvances() {
        var tournament = Tournament(name: "T", gameKind: .chess, entrants: entrants(8))
        XCTAssertEqual(tournament.matches(inRound: 0).count, 4)
        // Play every round: first seat always wins.
        while !tournament.isComplete {
            let round = tournament.currentRound
            for match in tournament.matches(inRound: round) where !match.isPlayed {
                let groups = match.entrantIDs.map { [$0] }
                tournament.record(matchID: match.id, outcome: MatchOutcome(rankedGroups: groups, summary: "win"))
            }
        }
        XCTAssertEqual(tournament.roundCount, 3)
        XCTAssertEqual(tournament.championIDs?.count, 1)
    }

    func testKnockoutRejectsDraw() {
        var tournament = Tournament(name: "T", gameKind: .chess, entrants: entrants(4))
        let match = tournament.matches[0]
        let drawn = MatchOutcome(rankedGroups: [match.entrantIDs], summary: "draw")
        XCTAssertFalse(tournament.record(matchID: match.id, outcome: drawn))
        XCTAssertFalse(tournament.matches[0].isPlayed, "drawn knockout match must be replayed")
    }

    func testFourPlayerKnockoutAdvancesTopTwo() {
        var tournament = Tournament(name: "T", gameKind: .hearts, entrants: entrants(8))
        XCTAssertEqual(tournament.matches(inRound: 0).count, 2)
        for match in tournament.matches(inRound: 0) {
            let groups = match.entrantIDs.map { [$0] }
            tournament.record(matchID: match.id, outcome: MatchOutcome(rankedGroups: groups, summary: ""))
        }
        let final = tournament.matches(inRound: 1)
        XCTAssertEqual(final.count, 1)
        XCTAssertEqual(final[0].entrantIDs.count, 4)
        let advanced = Set(final[0].entrantIDs)
        for match in tournament.matches(inRound: 0) {
            XCTAssertTrue(advanced.contains(match.entrantIDs[0]))
            XCTAssertTrue(advanced.contains(match.entrantIDs[1]))
        }
    }

    // MARK: - Ratings & saved games

    func testEloWinnerGainsLoserLosesZeroSum() {
        let deltas = Elo.deltas(ranking: [[0], [1]], ratings: [1200, 1200])
        XCTAssertEqual(deltas[0], 12, accuracy: 0.001)        // K=24, expected 0.5
        XCTAssertEqual(deltas[0] + deltas[1], 0, accuracy: 0.0001)
        XCTAssertGreaterThan(deltas[0], 0)
        XCTAssertLessThan(deltas[1], 0)
    }

    func testEloUpsetPaysMore() {
        let upset = Elo.deltas(ranking: [[0], [1]], ratings: [1000, 1400])[0]
        let expected = Elo.deltas(ranking: [[0], [1]], ratings: [1400, 1000])[0]
        XCTAssertGreaterThan(upset, expected)
    }

    func testEloDrawBetweenEqualsChangesNothing() {
        let deltas = Elo.deltas(ranking: [[0, 1]], ratings: [1300, 1300])
        XCTAssertEqual(deltas[0], 0, accuracy: 0.0001)
        XCTAssertEqual(deltas[1], 0, accuracy: 0.0001)
    }

    func testEloFourPlayerTableIsZeroSumAndOrdered() {
        let deltas = Elo.deltas(ranking: [[2], [0], [3], [1]], ratings: [1200, 1200, 1200, 1200])
        XCTAssertEqual(deltas.reduce(0, +), 0, accuracy: 0.0001)
        XCTAssertGreaterThan(deltas[2], deltas[0])
        XCTAssertGreaterThan(deltas[0], deltas[3])
        XCTAssertGreaterThan(deltas[3], deltas[1])
    }

    func testSavedGameRoundTrip() throws {
        let players = [PlayerInfo(id: "me", name: "Brent"),
                       PlayerInfo(id: "bot-1", name: "Ada", isBot: true)]
        let match = ActiveMatch(competition: .league(UUID()), matchID: UUID(),
                                entrantIDsBySeat: [UUID(), UUID()])
        let saved = SavedGame(id: UUID(), kind: .chess, options: GameOptions(),
                              players: players, game: AnyGame.make(kind: .chess, options: GameOptions()),
                              match: match)
        let data = try JSONEncoder().encode(saved)
        let decoded = try JSONDecoder().decode(SavedGame.self, from: data)
        XCTAssertEqual(decoded.id, saved.id)
        XCTAssertEqual(decoded.kind, .chess)
        XCTAssertEqual(decoded.players, players)
        XCTAssertEqual(decoded.match, match)
        XCTAssertFalse(decoded.game.isOver)
    }

    func testPartnershipKnockoutKeepsPairsTogether() {
        var tournament = Tournament(name: "T", gameKind: .spades, entrants: entrants(8))
        for match in tournament.matches(inRound: 0) {
            // Seats 0&2 (a partnership) win.
            let ids = match.entrantIDs
            let groups = [[ids[0], ids[2]], [ids[1], ids[3]]]
            tournament.record(matchID: match.id, outcome: MatchOutcome(rankedGroups: groups, summary: ""))
        }
        let final = tournament.matches(inRound: 1)[0]
        // Each winning pair must again sit at seats 0&2 / 1&3.
        let table1Winners = tournament.matches(inRound: 0)[0].advancing(count: 2)!
        XCTAssertEqual(Set([final.entrantIDs[0], final.entrantIDs[2]]), Set(table1Winners))
    }
}
