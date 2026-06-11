import Foundation

struct LobbyState: Codable, Hashable {
    var gameKind: GameKind
    var options = GameOptions()
    var hostID: String
    /// Seat order; bots appear with `isBot = true`. Count may be below the
    /// game's player count until the host starts and bots fill the gap.
    var players: [PlayerInfo] = []
}

/// Every message exchanged between devices.
enum Envelope: Codable {
    case hello(PlayerInfo)                  // joiner → host
    case lobby(LobbyState)                  // host → everyone
    case start(game: AnyGame, seat: Int)    // host → one player (redacted for them)
    case state(game: AnyGame, seat: Int)    // host → one player (redacted for them)
    case propose(move: Move, seat: Int)     // player → host
    case rejected(reason: String)           // host → player whose move failed
    case ended                              // host left / closed the table

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func decoded(from data: Data) throws -> Envelope {
        try JSONDecoder().decode(Envelope.self, from: data)
    }
}

enum Identity {
    static var playerID: String {
        let key = "parlor.playerID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }
}
