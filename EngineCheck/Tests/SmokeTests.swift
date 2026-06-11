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
            guard let move = Bot.chooseMove(for: game) else { break }
            do {
                try game.applyValidated(move)
            } catch {
                XCTFail("\(kind) rejected bot move \(move): \(error)", file: file, line: line)
                return
            }
            moves += 1
        }
        if kind == .solitaire || kind == .mahjong {
            // Solo games can dead-end; surviving without errors is enough.
            return
        }
        XCTAssertTrue(game.isOver, "\(kind) did not finish in \(maxMoves) moves", file: file, line: line)
        XCTAssertNotNil(game.resultText, "\(kind) finished without a result", file: file, line: line)
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
    func testMahjong() { playOut(.mahjong, maxMoves: 500) }

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
}
