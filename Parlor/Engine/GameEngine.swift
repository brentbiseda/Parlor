import Foundation

enum GameError: Error, LocalizedError {
    case illegalMove
    case notYourTurn
    case gameOver

    var errorDescription: String? {
        switch self {
        case .illegalMove: return "That move isn't allowed."
        case .notYourTurn: return "It isn't your turn."
        case .gameOver: return "The game is over."
        }
    }
}

protocol GameEngine: Codable {
    static var kind: GameKind { get }
    var playerCount: Int { get }
    /// Seat index expected to act next. Meaningless once `isOver`.
    var currentPlayer: Int { get }
    var isOver: Bool { get }
    /// One-line description of what's happening, shown above the table.
    var statusText: String { get }
    /// Final outcome once `isOver`.
    var resultText: String? { get }
    /// Legal moves for `currentPlayer`. Used by bots and to validate proposals.
    func legalMoves() -> [Move]
    /// Whether `move` is acceptable right now. Defaults to `legalMoves().contains`;
    /// games with free-form selections (Hearts passing, Klondike) override this.
    func isLegal(_ move: Move) -> Bool
    mutating func apply(_ move: Move) throws
    /// Copy safe to send to `seat`: other players' hidden cards blanked out.
    func redacted(for seat: Int) -> Self
    /// Seat that physically acts for `seat` (Bridge: declarer plays dummy).
    func controller(of seat: Int) -> Int
    /// Final standings once `isOver`: seats grouped by finishing rank, best
    /// group first; tied seats share a group. Empty while the game runs.
    /// Leagues and tournaments use this to award points and advance players.
    func ranking() -> [[Int]]
}

extension GameEngine {
    var playerCount: Int { Self.kind.playerCount }
    var resultText: String? { nil }
    func redacted(for seat: Int) -> Self { self }
    func controller(of seat: Int) -> Int { seat }
    func ranking() -> [[Int]] { isOver ? [Array(0..<playerCount)] : [] }

    func isLegal(_ move: Move) -> Bool { legalMoves().contains(move) }

    mutating func applyValidated(_ move: Move) throws {
        guard !isOver else { throw GameError.gameOver }
        guard isLegal(move) else { throw GameError.illegalMove }
        try apply(move)
    }
}

/// Type-erased wrapper so one Codable payload carries any game across the wire.
struct AnyGame: Codable {
    var engine: any GameEngine

    init(_ engine: any GameEngine) { self.engine = engine }

    var kind: GameKind { type(of: engine).kind }
    var playerCount: Int { engine.playerCount }
    var currentPlayer: Int { engine.currentPlayer }
    var isOver: Bool { engine.isOver }
    var statusText: String { engine.statusText }
    var resultText: String? { engine.resultText }
    func legalMoves() -> [Move] { engine.legalMoves() }
    func controller(of seat: Int) -> Int { engine.controller(of: seat) }
    func ranking() -> [[Int]] { engine.ranking() }
    func redacted(for seat: Int) -> AnyGame { AnyGame(redactedEngine(for: seat)) }

    mutating func applyValidated(_ move: Move) throws {
        var copy = engine
        try copy.applyValidated(move)
        engine = copy
    }

    private func redactedEngine(for seat: Int) -> any GameEngine {
        switch engine {
        case let g as HeartsGame: return g.redacted(for: seat)
        case let g as SpadesGame: return g.redacted(for: seat)
        case let g as EuchreGame: return g.redacted(for: seat)
        case let g as BridgeGame: return g.redacted(for: seat)
        case let g as UnoGame: return g.redacted(for: seat)
        case let g as EightsGame: return g.redacted(for: seat)
        case let g as GoFishGame: return g.redacted(for: seat)
        default: return engine
        }
    }

    enum CodingKeys: String, CodingKey { case kind, data }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(GameKind.self, forKey: .kind)
        switch kind {
        case .hearts: engine = try c.decode(HeartsGame.self, forKey: .data)
        case .spades: engine = try c.decode(SpadesGame.self, forKey: .data)
        case .euchre: engine = try c.decode(EuchreGame.self, forKey: .data)
        case .bridge: engine = try c.decode(BridgeGame.self, forKey: .data)
        case .solitaire: engine = try c.decode(KlondikeGame.self, forKey: .data)
        case .freecell: engine = try c.decode(FreeCellGame.self, forKey: .data)
        case .mahjong: engine = try c.decode(MahjongGame.self, forKey: .data)
        case .chess: engine = try c.decode(ChessGame.self, forKey: .data)
        case .checkers: engine = try c.decode(CheckersGame.self, forKey: .data)
        case .go: engine = try c.decode(GoGame.self, forKey: .data)
        case .pinball: engine = try c.decode(PinballGame.self, forKey: .data)
        case .breakout: engine = try c.decode(BreakoutGame.self, forKey: .data)
        case .tetris: engine = try c.decode(TetrisGame.self, forKey: .data)
        case .capsules: engine = try c.decode(CapsulesGame.self, forKey: .data)
        case .minesweeper: engine = try c.decode(MinesweeperGame.self, forKey: .data)
        case .muncher: engine = try c.decode(MuncherGame.self, forKey: .data)
        case .hopper: engine = try c.decode(HopperGame.self, forKey: .data)
        case .centipede: engine = try c.decode(CentipedeGame.self, forKey: .data)
        case .snake: engine = try c.decode(SnakeGame.self, forKey: .data)
        case .uno: engine = try c.decode(UnoGame.self, forKey: .data)
        case .eights: engine = try c.decode(EightsGame.self, forKey: .data)
        case .gofish: engine = try c.decode(GoFishGame.self, forKey: .data)
        case .football: engine = try c.decode(FootballGame.self, forKey: .data)
        case .baseball: engine = try c.decode(BaseballGame.self, forKey: .data)
        case .soccer: engine = try c.decode(SoccerGame.self, forKey: .data)
        case .hockey: engine = try c.decode(HockeyGame.self, forKey: .data)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        switch engine {
        case let g as HeartsGame: try c.encode(g, forKey: .data)
        case let g as SpadesGame: try c.encode(g, forKey: .data)
        case let g as EuchreGame: try c.encode(g, forKey: .data)
        case let g as BridgeGame: try c.encode(g, forKey: .data)
        case let g as KlondikeGame: try c.encode(g, forKey: .data)
        case let g as FreeCellGame: try c.encode(g, forKey: .data)
        case let g as PinballGame: try c.encode(g, forKey: .data)
        case let g as BreakoutGame: try c.encode(g, forKey: .data)
        case let g as TetrisGame: try c.encode(g, forKey: .data)
        case let g as CapsulesGame: try c.encode(g, forKey: .data)
        case let g as MinesweeperGame: try c.encode(g, forKey: .data)
        case let g as MuncherGame: try c.encode(g, forKey: .data)
        case let g as HopperGame: try c.encode(g, forKey: .data)
        case let g as CentipedeGame: try c.encode(g, forKey: .data)
        case let g as SnakeGame: try c.encode(g, forKey: .data)
        case let g as UnoGame: try c.encode(g, forKey: .data)
        case let g as EightsGame: try c.encode(g, forKey: .data)
        case let g as GoFishGame: try c.encode(g, forKey: .data)
        case let g as FootballGame: try c.encode(g, forKey: .data)
        case let g as BaseballGame: try c.encode(g, forKey: .data)
        case let g as SoccerGame: try c.encode(g, forKey: .data)
        case let g as HockeyGame: try c.encode(g, forKey: .data)
        case let g as MahjongGame: try c.encode(g, forKey: .data)
        case let g as ChessGame: try c.encode(g, forKey: .data)
        case let g as CheckersGame: try c.encode(g, forKey: .data)
        case let g as GoGame: try c.encode(g, forKey: .data)
        default: throw EncodingError.invalidValue(engine, .init(codingPath: [], debugDescription: "Unknown engine"))
        }
    }

    static func make(kind: GameKind, options: GameOptions) -> AnyGame {
        switch kind {
        case .hearts: return AnyGame(HeartsGame())
        case .spades: return AnyGame(SpadesGame())
        case .euchre: return AnyGame(EuchreGame())
        case .bridge: return AnyGame(BridgeGame())
        case .solitaire: return AnyGame(KlondikeGame(drawThree: options.klondikeDrawThree,
                                                     maxPasses: options.klondikeMaxPasses))
        case .freecell: return AnyGame(FreeCellGame())
        case .mahjong: return AnyGame(MahjongGame())
        case .chess: return AnyGame(ChessGame())
        case .checkers: return AnyGame(CheckersGame())
        case .go: return AnyGame(GoGame(size: options.goBoardSize))
        case .pinball: return AnyGame(PinballGame())
        case .breakout: return AnyGame(BreakoutGame())
        case .tetris: return AnyGame(TetrisGame())
        case .capsules: return AnyGame(CapsulesGame())
        case .minesweeper: return AnyGame(MinesweeperGame())
        case .muncher: return AnyGame(MuncherGame())
        case .hopper: return AnyGame(HopperGame())
        case .centipede: return AnyGame(CentipedeGame())
        case .snake: return AnyGame(SnakeGame())
        case .uno: return AnyGame(UnoGame())
        case .eights: return AnyGame(EightsGame())
        case .gofish: return AnyGame(GoFishGame())
        case .football: return AnyGame(FootballGame())
        case .baseball: return AnyGame(BaseballGame())
        case .soccer: return AnyGame(SoccerGame())
        case .hockey: return AnyGame(HockeyGame())
        }
    }
}
