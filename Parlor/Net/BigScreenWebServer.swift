import Foundation
import Network

// MARK: - HTTP helpers

private struct WebResponse {
    var status: Int
    var contentType: String
    var body: Data

    static func json(_ dict: [String: Any], status: Int = 200) -> WebResponse {
        let data = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
        return WebResponse(status: status, contentType: "application/json", body: data)
    }
    static func html(_ html: String) -> WebResponse {
        WebResponse(status: 200, contentType: "text/html; charset=utf-8", body: Data(html.utf8))
    }
    static func error(_ msg: String, status: Int = 400) -> WebResponse {
        json(["error": msg], status: status)
    }
    static func notFound() -> WebResponse { json(["error": "Not found"], status: 404) }
    static func ok() -> WebResponse {
        WebResponse(status: 200, contentType: "application/json", body: Data("{}".utf8))
    }

    func wire() -> Data {
        let text = [200:"OK",400:"Bad Request",404:"Not Found",500:"Internal Server Error"][status] ?? "Unknown"
        let hdr = "HTTP/1.1 \(status) \(text)\r\n" +
            "Content-Type: \(contentType)\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "Access-Control-Allow-Origin: *\r\n" +
            "Access-Control-Allow-Headers: Content-Type\r\n" +
            "Connection: close\r\n\r\n"
        return Data(hdr.utf8) + body
    }
}

// MARK: - Web Server

/// Minimal HTTP server that runs alongside a BigScreen host session.
/// Players on the same Wi-Fi network can open the URL in a browser and
/// play the game without installing the Parlor app.
@MainActor
final class BigScreenWebServer: ObservableObject {
    private var listener: NWListener?
    @Published var localURL: URL?

    weak var session: GameSession?

    private struct WebPlayer {
        var playerID: String
        var sessionID: String
        var name: String
        var seat: Int
    }
    private var webPlayers: [String: WebPlayer] = [:]  // sessionID → player

    // MARK: Lifecycle

    func start(with session: GameSession) {
        self.session = session
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: params) else { return }
        self.listener = listener

        listener.newConnectionHandler = { [weak self] conn in
            Task { @MainActor [weak self] in self?.handle(conn) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, case .ready = state,
                      let port = self.listener?.port?.rawValue,
                      let ip = Self.localIPv4() else { return }
                self.localURL = URL(string: "http://\(ip):\(port)")
            }
        }
        listener.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        webPlayers = [:]
        localURL = nil
    }

    // MARK: Connection

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, _ in
            Task { @MainActor [weak self] in
                guard let self, let data, !data.isEmpty,
                      let text = String(data: data, encoding: .utf8) else {
                    connection.cancel(); return
                }
                let response = self.route(text)
                connection.send(content: response.wire(), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    // MARK: Routing

    private func route(_ raw: String) -> WebResponse {
        let lines = raw.components(separatedBy: "\r\n")
        guard let first = lines.first else { return .error("Bad request") }
        let parts = first.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return .error("Bad request") }
        let method = String(parts[0])
        let rawPath = String(parts[1])
        let (path, query) = Self.parsePath(rawPath)

        var body: [String: Any] = [:]
        if let range = raw.range(of: "\r\n\r\n") {
            let bodyText = String(raw[range.upperBound...])
            if !bodyText.isEmpty, let d = bodyText.data(using: .utf8),
               let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                body = j
            }
        }

        switch (method, path) {
        case (_, "/"):          return .html(Self.controllerPage)
        case ("GET", "/api/lobby"):  return apiLobby()
        case ("POST", "/api/join"):  return apiJoin(body: body)
        case ("GET", "/api/state"):  return apiState(sessionID: query["id"] ?? "")
        case ("POST", "/api/move"):  return apiMove(body: body)
        case ("OPTIONS", _):        return .ok()
        default:                    return .notFound()
        }
    }

    // MARK: API endpoints

    private func apiLobby() -> WebResponse {
        guard let session else { return .error("No session") }
        let seats: [[String: Any]] = (0..<session.seatsTotal).map { seat in
            let p = session.lobby.players[safe: seat]
            return ["seat": seat, "name": p?.name ?? "", "filled": p != nil]
        }
        return .json([
            "gameName": session.lobby.gameKind.title,
            "seatsTotal": session.seatsTotal,
            "seatsFilled": session.seatsFilled,
            "started": session.game != nil,
            "seats": seats
        ])
    }

    private func apiJoin(body: [String: Any]) -> WebResponse {
        guard let session else { return .error("No session") }
        let rawName = body["name"] as? String ?? ""
        let name = String(rawName.trimmingCharacters(in: .whitespaces).prefix(20))
        guard !name.isEmpty else { return .error("Name required") }
        guard session.game == nil else { return .error("Game already started — wait for the next round") }
        guard session.seatsFilled < session.seatsTotal else { return .error("Game is full") }

        let playerID = "web-\(UUID().uuidString.prefix(8))"
        let sessionID = UUID().uuidString
        guard session.addWebPlayer(PlayerInfo(id: playerID, name: name)) else {
            return .error("Could not join")
        }
        let seat = session.seatsFilled - 1
        webPlayers[sessionID] = WebPlayer(playerID: playerID, sessionID: sessionID, name: name, seat: seat)
        return .json(["sessionID": sessionID, "seat": seat, "name": name,
                      "gameName": session.lobby.gameKind.title])
    }

    private func apiState(sessionID: String) -> WebResponse {
        guard let session else { return .error("No session") }
        guard let wp = webPlayers[sessionID] else { return .error("Session expired") }

        guard let game = session.game else {
            let joinedNames = webPlayers.values.sorted { $0.seat < $1.seat }.map { $0.name }
            return .json([
                "waiting": true,
                "statusText": "Waiting for host to start\u{2026}",
                "seatsFilled": session.seatsFilled,
                "seatsTotal": session.seatsTotal,
                "mySeat": wp.seat,
                "myName": wp.name,
                "joinedNames": joinedNames
            ])
        }

        let engine = game.engine.redacted(for: wp.seat)
        let isMyTurn = engine.currentPlayer == wp.seat && !engine.isOver

        var result: [String: Any] = [
            "isOver": engine.isOver,
            "statusText": engine.statusText,
            "isMyTurn": isMyTurn,
            "mySeat": wp.seat,
            "myName": wp.name,
            "currentPlayer": engine.currentPlayer,
            "currentPlayerName": session.playerName(seat: engine.currentPlayer)
        ]
        if let rt = engine.resultText { result["resultText"] = rt }
        if engine.isOver { result["ranking"] = engine.ranking() }
        result["seatNames"] = (0..<session.seatsTotal).map { session.playerName(seat: $0) }
        // Partnership info: seats 0&2 vs 1&3 for Spades/Euchre/Bridge
        let isPartnershipGame = session.lobby.gameKind.isPartnership
        if isPartnershipGame {
            let partnerSeat = (wp.seat + 2) % 4
            result["partnerSeat"] = partnerSeat
            result["partnerName"] = session.playerName(seat: partnerSeat)
        }

        // --- Trivia ---
        if let tg = engine as? TriviaGame, let q = tg.currentQuestion {
            result["triviaQuestion"] = q.q
            result["triviaCategory"] = q.cat.rawValue
            if isMyTurn {
                let lm = engine.legalMoves()
                let letters = ["A", "B", "C", "D"]
                result["moves"] = lm.enumerated().compactMap { i, m -> [String: Any]? in
                    guard case .trivia(.answer(let idx)) = m,
                          let letter = letters[safe: idx],
                          let optText = q.a[safe: idx] else { return nil }
                    return ["index": i, "label": letter, "desc": optText]
                }
            }
            return .json(result)
        }

        // Legal moves for turn (empty when waiting)
        let legalMoves = isMyTurn ? engine.legalMoves() : []

        // card label → first move index (for .playCard and .eights non-eight plays)
        var cardMoveIndex: [String: Int] = [:]
        for (i, m) in legalMoves.enumerated() {
            switch m {
            case .playCard(let c) where cardMoveIndex[c.label] == nil:
                cardMoveIndex[c.label] = i
            case .eights(.play(let c, .none)) where cardMoveIndex[c.label] == nil:
                cardMoveIndex[c.label] = i
            default: break
            }
        }

        // Serialize [Card] with legal/moveIdx annotations
        func cardHand(_ cards: [Card]) -> [[String: Any]] {
            cards.map { c in
                var d: [String: Any] = [
                    "label": c.label,
                    "isRed": c.suit == .hearts || c.suit == .diamonds,
                    "legal": cardMoveIndex[c.label] != nil
                ]
                if let idx = cardMoveIndex[c.label] { d["moveIdx"] = idx }
                return d
            }
        }
        func trickArr(_ trick: [TrickPlay]) -> [[String: Any]] {
            trick.map { tp in [
                "seat": tp.seat,
                "label": tp.card.label,
                "isRed": tp.card.suit == .hearts || tp.card.suit == .diamonds
            ] }
        }
        func genericMoves() -> [[String: Any]] {
            legalMoves.enumerated().map { i, m in ["index": i, "label": m.webLabel] }
        }

        // --- Hearts ---
        if let g = engine as? HeartsGame {
            result["hand"] = cardHand(g.hands[safe: wp.seat] ?? [])
            result["trick"] = trickArr(g.trick)
            result["scores"] = g.scores
            result["tricksWon"] = g.tricksWonThisRound
            result["handSizes"] = (0..<4).map { g.hands[safe: $0]?.count ?? 0 }
            if g.phase == .passing && isMyTurn {
                result["phase"] = "passCards"
                result["passCount"] = 3
                result["passDirection"] = g.passDirection.label
            }
            if g.isShootingMoon {
                result["isShootingMoon"] = true
                result["moonShooterSeat"] = g.moonShooterSeat
            }
            if let lts = g.lastTrickSummary { result["lastTrickSummary"] = lts }
            let received = g.receivedCards[safe: wp.seat] ?? []
            if !received.isEmpty && g.phase == .playing {
                result["receivedCards"] = received.map { c -> [String: Any] in
                    ["label": c.label, "isRed": c.suit == .hearts || c.suit == .diamonds]
                }
            }
            // [37] Round history for score panel
            if !g.roundHistory.isEmpty {
                result["roundHistory"] = Array(g.roundHistory.prefix(5))
                result["roundNumber"] = g.roundNumber
            }
            // [44] Q♠ lurking warning
            if !g.queenPlayed && g.phase == .playing { result["queenLurking"] = true }
            // [72] Round points so far this round
            if g.phase == .playing { result["roundPoints"] = g.roundPoints }
            // [82] Tricks-won progress for visual bar
            let heartsTricksPlayed = g.tricksWonThisRound.reduce(0, +)
            result["tricksTotal"] = heartsTricksPlayed
            return .json(result)
        }

        // --- Spades ---
        if let g = engine as? SpadesGame {
            result["hand"] = cardHand(g.hands[safe: wp.seat] ?? [])
            result["trick"] = trickArr(g.trick)
            result["teamScores"] = g.teamScores
            result["tricksWon"] = g.tricksWon
            result["handSizes"] = (0..<4).map { g.hands[safe: $0]?.count ?? 0 }
            result["bids"] = g.bids.map { b -> String in
                guard let bid = b else { return "?" }
                return bid == 0 ? "Nil" : "\(bid)"
            }
            result["teamBags"] = g.teamBags
            result["sandbagsWarning"] = g.sandbagsWarning
            if let lts = g.lastTrickSummary { result["lastTrickSummary"] = lts }
            // [81] Spades round summary flash
            if let lrs = g.lastRoundSummary { result["lastRoundSummary"] = lrs }
            result["gamePhase"] = g.phase == .bidding ? "bidding" : "playing"
            if g.phase == .bidding && isMyTurn {
                result["moves"] = genericMoves()
                // [32] Recommended bid chip
                let myHand = g.hands[safe: wp.seat] ?? []
                result["recommendedBid"] = Bot.estimateSpadesBid(hand: myHand)
            }
            // [82] Tricks-won progress bar
            let totalTricksPlayed = g.tricksWon.reduce(0, +)
            result["tricksTotal"] = totalTricksPlayed
            return .json(result)
        }

        // --- Euchre ---
        if let g = engine as? EuchreGame {
            result["hand"] = cardHand(g.hands[safe: wp.seat] ?? [])
            result["trick"] = trickArr(g.trick)
            result["teamScores"] = g.teamScores
            result["tricksWon"] = g.trickCounts
            result["handSizes"] = (0..<4).map { g.hands[safe: $0]?.count ?? 0 }
            if let ts = g.trump { result["trump"] = ts.symbol }
            if let uc = g.upcard {
                result["upcard"] = uc.label
                result["upcardRed"] = uc.suit == .hearts || uc.suit == .diamonds
            }
            if g.aloneSeat != nil { result["goingAlone"] = true }
            if let mt = g.makerTeam { result["makerTeam"] = mt }
            let inBidding = g.phase != .playing && g.phase != .gameOver
            result["gamePhase"] = inBidding ? "bidding" : "playing"
            if inBidding && isMyTurn { result["moves"] = genericMoves() }
            // [42] Round result flash + team tricks
            if let lrr = g.lastRoundResult { result["lastRoundResult"] = lrr }
            result["isEuchre"] = true
            result["euchreTeamTricks"] = [g.trickCounts[0] + g.trickCounts[2], g.trickCounts[1] + g.trickCounts[3]]
            // [95] Euchre win streak
            result["euchreTeamStreak"] = g.teamRoundStreak
            return .json(result)
        }

        // --- Bridge ---
        if let g = engine as? BridgeGame {
            result["hand"] = cardHand(g.hands[safe: wp.seat] ?? [])
            result["trick"] = trickArr(g.trick)
            result["teamScores"] = g.teamScores
            result["handSizes"] = (0..<4).map { g.hands[safe: $0]?.count ?? 0 }
            let inAuction = g.phase == .auction
            result["gamePhase"] = inAuction ? "auction" : "playing"
            if inAuction && isMyTurn { result["moves"] = genericMoves() }
            if g.dummyRevealed, let ds = g.dummySeat {
                result["dummySeat"] = ds
                let dHand = g.hands[safe: ds] ?? []
                if !dHand.isEmpty {
                    result["dummyHand"] = dHand.map { c -> [String: Any] in
                        ["label": c.label, "isRed": c.suit == .hearts || c.suit == .diamonds]
                    }
                }
            }
            // [33] Contract progress chip during play
            if g.phase == .playing, let c = g.contract {
                let needed = 6 + c.level
                let progress = g.declarerTricks >= needed
                    ? "Making +\(g.declarerTricks - needed)"
                    : "Need \(needed - g.declarerTricks) more"
                result["contractChip"] = "\(c.level)\(c.strain.label): \(progress)"
                result["imDeclarer"] = (wp.seat % 2 == c.declarer % 2)
            }
            // [61] Vulnerability display
            let mySide = wp.seat % 2
            let oppSide = 1 - mySide
            let myVul = g.isVulnerable(side: mySide)
            let oppVul = g.isVulnerable(side: oppSide)
            if myVul && oppVul { result["vulLabel"] = "Both Vul" }
            else if myVul { result["vulLabel"] = "You Vul" }
            else if oppVul { result["vulLabel"] = "Opp Vul" }
            else { result["vulLabel"] = "None Vul" }
            result["myVul"] = myVul
            return .json(result)
        }

        // --- Eights ---
        if let g = engine as? EightsGame {
            // Group 8-play suit choices by card label
            var eightSuits: [String: [[String: Any]]] = [:]
            for (i, m) in legalMoves.enumerated() {
                if case .eights(.play(let c, .some(let suit))) = m {
                    eightSuits[c.label, default: []].append(["suit": suit.symbol, "index": i])
                }
            }
            let myHand = g.hands[safe: wp.seat] ?? []
            result["hand"] = myHand.map { c -> [String: Any] in
                var d: [String: Any] = [
                    "label": c.label,
                    "isRed": c.suit == .hearts || c.suit == .diamonds
                ]
                if let idx = cardMoveIndex[c.label] {
                    d["legal"] = true; d["moveIdx"] = idx
                } else if eightSuits[c.label] != nil {
                    d["legal"] = true; d["isEight"] = true
                } else {
                    d["legal"] = false
                }
                return d
            }
            if !eightSuits.isEmpty {
                result["eightMoves"] = eightSuits.map { label, suits -> [String: Any] in
                    ["card": label, "suits": suits]
                }
            }
            if let top = g.topCard {
                result["topCard"] = top.label
                result["topCardRed"] = top.suit == .hearts || top.suit == .diamonds
            }
            result["activeSuit"] = g.activeSuit.symbol
            if g.pendingDraw > 0 { result["pendingDraw"] = g.pendingDraw }
            result["handSizes"] = (0..<g.hands.count).map { g.hands[safe: $0]?.count ?? 0 }
            var extra: [[String: Any]] = []
            for (i, m) in legalMoves.enumerated() {
                if case .eights(.draw) = m { extra.append(["index": i, "label": "Draw"]) }
                else if case .eights(.pass) = m { extra.append(["index": i, "label": "Pass"]) }
            }
            if !extra.isEmpty { result["extraMoves"] = extra }
            return .json(result)
        }

        // --- Uno ---
        if let g = engine as? UnoGame {
            func unoLabel(_ c: UnoCard) -> String {
                switch c.value {
                case .number(let n): return "\(n)"
                case .skip: return "⊘"; case .reverse: return "⇄"
                case .drawTwo: return "+2"; case .wild: return "W"; case .wildDrawFour: return "+4"
                }
            }
            var unoIdx: [Int: Int] = [:]        // cardID → move index (colored cards)
            var wildChoices: [Int: [[String: Any]]] = [:]  // cardID → [{color, index}]
            for (i, m) in legalMoves.enumerated() {
                if case .uno(.play(let c, let declared)) = m {
                    if c.color == nil, let color = declared {
                        wildChoices[c.id, default: []].append(["color": color.rawValue, "index": i])
                    } else if c.color != nil, unoIdx[c.id] == nil {
                        unoIdx[c.id] = i
                    }
                }
            }
            let myHand = g.hands[safe: wp.seat] ?? []
            result["hand"] = myHand.map { c -> [String: Any] in
                var d: [String: Any] = [
                    "label": unoLabel(c),
                    "color": c.color?.rawValue ?? "wild",
                    "id": c.id
                ]
                if let idx = unoIdx[c.id] {
                    d["legal"] = true; d["moveIdx"] = idx
                } else if let choices = wildChoices[c.id] {
                    d["legal"] = true; d["colorChoices"] = choices
                } else {
                    d["legal"] = false
                }
                return d
            }
            result["isUno"] = true
            result["drawPileCount"] = g.drawPile.count   // [35] LOW! warning
            if let top = g.topCard {
                result["topCard"] = unoLabel(top)
                result["topCardColor"] = top.color?.rawValue ?? "wild"
            }
            result["activeColor"] = g.activeColor.rawValue
            result["handSizes"] = (0..<g.hands.count).map { g.hands[safe: $0]?.count ?? 0 }
            var extra: [[String: Any]] = []
            for (i, m) in legalMoves.enumerated() {
                if case .uno(.draw) = m { extra.append(["index": i, "label": "Draw"]) }
                else if case .uno(.pass) = m { extra.append(["index": i, "label": "Pass"]) }
                else if case .uno(.callUno) = m { extra.append(["index": i, "label": "UNO!"]) }
            }
            if !extra.isEmpty { result["extraMoves"] = extra }
            return .json(result)
        }

        // --- GoFish ---
        if let g = engine as? GoFishGame {
            result["hand"] = cardHand(g.hands[safe: wp.seat] ?? [])
            result["books"] = (g.books[safe: wp.seat] ?? []).map { $0.label }
            result["handSizes"] = (0..<g.hands.count).map { g.hands[safe: $0]?.count ?? 0 }
            // [34] Book counts per seat + last event
            result["bookCounts"] = (0..<g.hands.count).map { g.books[safe: $0]?.count ?? 0 }
            if let le = g.lastEvent { result["lastEvent"] = le }
            // [45] Book completion flash
            if let lbe = g.lastBookEvent { result["lastBookEvent"] = lbe }
            // [76] Pond size for fish visualization
            result["pondCount"] = g.stock.count
            if isMyTurn { result["moves"] = genericMoves() }
            return .json(result)
        }

        // --- [73-75] Arcade spectator HUDs ---
        if let g = engine as? TetrisGame {
            result["gameType"] = "tetris"
            result["arcadeScore"] = g.score
            result["arcadeLevel"] = g.lines / 10 + 1
            result["arcadeLines"] = g.lines
            result["arcadeCombo"] = g.combo
            // [91] Extra Tetris stats
            result["arcadeStackHeight"] = g.stackHeight
            if let lc = g.lastClearLabel { result["arcadeClearLabel"] = lc }
            return .json(result)
        }
        if let g = engine as? SnakeGame {
            result["gameType"] = "snake"
            result["arcadeScore"] = g.score
            result["arcadeLevel"] = g.level
            result["arcadeLives"] = g.lives
            // [92] Snake speed label + bonus food active
            result["arcadeSpeedLabel"] = g.speedLabel
            result["arcadeBonusActive"] = g.bonusFood != nil
            return .json(result)
        }
        if let g = engine as? CapsulesGame {
            result["gameType"] = "capsules"
            result["arcadeScore"] = g.score
            result["arcadeLevel"] = g.level
            result["levelsCleared"] = g.levelsCleared
            result["maxChain"] = g.maxChain
            result["totalVirusesCleared"] = g.totalVirusesCleared
            return .json(result)
        }
        // [94] FreeCell spectator HUD
        if let g = engine as? FreeCellGame {
            result["gameType"] = "freecell"
            result["foundationCount"] = g.foundationCount
            result["isDeadlocked"] = g.deadlocked
            result["autoFinishAvailable"] = g.autoFinishAvailable
            return .json(result)
        }

        // --- [62] Bomberman live HUD ---
        if let g = engine as? BombermanGame {
            result["gameType"] = "bomberman"
            result["bomberScore"] = g.score
            result["bomberLives"] = g.livesLeft
            result["bomberLevel"] = g.level
            result["levelsCleared"] = g.levelsCleared
            if isMyTurn { result["moves"] = genericMoves() }
            return .json(result)
        }

        // --- [41] Star Party (MarioParty) ---
        if let g = engine as? MarioPartyGame {
            result["gameType"] = "starParty"
            result["positions"] = g.positions
            result["coins"] = g.coins
            result["stars"] = g.stars
            result["scores"] = g.stars
            result["starSpace"] = g.starSpace
            result["roundNumber"] = min(g.round, MarioPartyGame.totalRounds)
            result["totalRounds"] = MarioPartyGame.totalRounds
            if let lr = g.lastRoll { result["lastRoll"] = lr }
            if let le = g.lastEvent { result["lastEvent"] = le }
            if let mg = g.minigamePhase {
                result["isMinigame"] = true
                result["minigameName"] = mg.displayName
            }
            if isMyTurn { result["moves"] = genericMoves() }
            return .json(result)
        }

        // --- [50] Klondike Solitaire ---
        if let g = engine as? KlondikeGame {
            result["gameType"] = "klondike"
            result["stockCount"] = g.stock.count
            result["foundationProgress"] = g.foundationProgress
            if let wc = g.waste.last {
                let isRed = wc.suit == .hearts || wc.suit == .diamonds
                result["wasteTop"] = ["label": wc.label, "isRed": isRed] as [String: Any]
            }
            result["foundationTops"] = (0..<4).map { i -> [String: Any] in
                if let c = g.foundations[safe: i]?.last {
                    let isRed = c.suit == .hearts || c.suit == .diamonds
                    return ["label": c.label, "isRed": isRed, "count": g.foundations[safe: i]?.count ?? 0]
                }
                return ["empty": true, "count": 0]
            }
            result["tableau"] = g.tableau.enumerated().map { col, pile -> [String: Any] in
                var entry: [String: Any] = ["col": col, "faceDown": pile.faceDown.count, "faceUpCount": pile.faceUp.count]
                // [68] Send top 3 face-up cards so JS can show a mini-stack
                let topCards = pile.faceUp.suffix(3).map { c -> [String: Any] in
                    ["label": c.label, "isRed": c.suit == .hearts || c.suit == .diamonds]
                }
                entry["topCards"] = topCards
                return entry
            }
            result["moves"] = legalMoves.enumerated().map { i, m -> [String: Any] in ["index": i, "label": m.webLabel] }
            return .json(result)
        }

        // --- Quiplash (Prompt Party) ---
        if let g = engine as? QuiplashGame {
            result["gameType"] = "promptParty"
            result["phase"] = g.phase.rawValue
            result["scores"] = g.scores
            result["promptNumber"] = g.currentPromptIdx + 1
            result["totalPrompts"] = QuiplashGame.promptsPerGame
            if let prompt = g.currentPrompt { result["promptText"] = prompt.text }
            switch g.phase {
            case .writing:
                let myAnswer = g.answers[safe: g.currentPromptIdx]?[safe: wp.seat] ?? ""
                if !myAnswer.isEmpty { result["myAnswer"] = myAnswer }
            case .voting:
                if isMyTurn {
                    var voteOptions: [[String: Any]] = []
                    for (i, m) in legalMoves.enumerated() {
                        if case .quiplash(.vote(let seat)) = m {
                            let ans = g.answers[safe: g.currentPromptIdx]?[safe: seat] ?? ""
                            voteOptions.append(["text": ans, "moveIndex": i])
                        }
                    }
                    result["voteOptions"] = voteOptions
                }
            case .revealing:
                let promptAnswers = g.answers[safe: g.currentPromptIdx] ?? []
                let promptVotes = g.votes[safe: g.currentPromptIdx] ?? []
                let seatNamesArr = (0..<session.seatsTotal).map { session.playerName(seat: $0) }
                var revealItems: [[String: Any]] = []
                for (seat, ans) in promptAnswers.enumerated() where !ans.isEmpty {
                    let voteCount = promptVotes.filter { $0 == seat }.count
                    revealItems.append(["text": ans, "seatName": seatNamesArr[safe: seat] ?? "P\(seat+1)", "votes": voteCount])
                }
                result["revealItems"] = revealItems
                result["moves"] = legalMoves.enumerated().map { i, _ in ["index": i, "label": "Next \u{27A4}"] as [String: Any] }
            case .over: break
            }
            return .json(result)
        }

        // --- Bluff! ---
        if let g = engine as? BluffGame {
            result["gameType"] = "bluff"
            result["phase"] = g.phase.rawValue
            result["scores"] = g.scores
            result["roundNumber"] = g.currentRound + 1
            result["totalRounds"] = BluffGame.roundsPerGame
            if let word = g.currentWord { result["bluffWord"] = word.word }
            switch g.phase {
            case .defining:
                let myDef = g.definitions[safe: g.currentRound]?[safe: wp.seat] ?? ""
                if !myDef.isEmpty { result["myDefinition"] = myDef }
            case .voting:
                if isMyTurn {
                    let answers = g.displayedAnswers(for: g.currentRound)
                    var voteOptions: [[String: Any]] = []
                    for (i, m) in legalMoves.enumerated() {
                        if case .bluff(.vote(let displayIdx)) = m,
                           let ans = answers[safe: displayIdx] {
                            voteOptions.append(["label": ans.label, "text": ans.text, "moveIndex": i])
                        }
                    }
                    result["voteOptions"] = voteOptions
                }
            case .revealing:
                let answers = g.displayedAnswers(for: g.currentRound)
                var revealItems: [[String: Any]] = []
                for (displayIdx, ans) in answers.enumerated() {
                    let voteCount = g.votes.filter { $0 == displayIdx }.count
                    revealItems.append(["label": ans.label, "text": ans.text, "isReal": ans.seat == -1, "votes": voteCount])
                }
                result["revealItems"] = revealItems
                result["moves"] = legalMoves.enumerated().map { i, _ in ["index": i, "label": "Next \u{27A4}"] as [String: Any] }
            case .over: break
            }
            return .json(result)
        }

        // --- JackAttack ---
        if let g = engine as? JackAttackGame {
            result["gameType"] = "jackAttack"
            result["scores"] = g.scores
            result["questionNumber"] = g.currentQ + 1
            result["totalQuestions"] = JackAttackGame.questionsPerGame
            if let q = g.currentQuestion {
                result["questionText"] = q.q
                if isMyTurn {
                    let letters = ["A", "B", "C", "D"]
                    var answerMoves: [[String: Any]] = []
                    var screwMoves: [[String: Any]] = []
                    let seatNamesArr = (0..<session.seatsTotal).map { session.playerName(seat: $0) }
                    for (i, m) in legalMoves.enumerated() {
                        switch m {
                        case .jackAttack(.answer(let idx, _)):
                            answerMoves.append(["index": i, "label": letters[safe: idx] ?? "\(idx)", "desc": q.a[safe: idx] ?? ""])
                        case .jackAttack(.screw(let seat)):
                            screwMoves.append(["index": i, "label": "Screw \(seatNamesArr[safe: seat] ?? "P\(seat+1)")"])
                        default: break
                        }
                    }
                    result["moves"] = answerMoves
                    result["screwMoves"] = screwMoves
                }
            }
            if let ss = g.screwedSeat { result["screwedSeat"] = ss }
            if let sb = g.screwedBy { result["screwedBy"] = sb }
            result["screwsLeft"] = g.screwsLeft[safe: wp.seat] ?? 0
            return .json(result)
        }

        // --- [83-85] Chess board game status ---
        if let g = engine as? ChessGame {
            result["gameType"] = "chess"
            result["inCheck"] = g.inCheck(g.currentPlayer)
            result["moveNumber"] = g.moveNumber
            result["materialBalance"] = g.materialBalance
            result["checksDelivered"] = g.checksDelivered
            if isMyTurn { result["moves"] = genericMoves() }
            return .json(result)
        }

        // --- [85] Checkers last move info ---
        if let g = engine as? CheckersGame {
            result["gameType"] = "checkers"
            if let lmd = g.lastMoveDesc { result["lastMoveDesc"] = lmd }
            result["redPieces"] = g.pieceCount(color: 0)
            result["blackPieces"] = g.pieceCount(color: 1)
            result["movesWithoutCapture"] = g.movesWithoutCapture
            if isMyTurn { result["moves"] = genericMoves() }
            return .json(result)
        }

        // --- Generic fallback ---
        if isMyTurn { result["moves"] = genericMoves() }
        return .json(result)
    }

    private func apiMove(body: [String: Any]) -> WebResponse {
        guard let session else { return .error("No session") }
        guard let sessionID = body["id"] as? String,
              let wp = webPlayers[sessionID] else { return .error("Session expired") }
        guard let game = session.game, !game.isOver else { return .error("Game not active") }
        guard game.currentPlayer == wp.seat else { return .error("Not your turn") }

        // Multi-card pass (Hearts pass phase)
        if let labels = body["passLabels"] as? [String] {
            let cards = labels.compactMap { lbl in Self.cardByLabel(lbl) }
            guard cards.count == 3 else { return .error("Select exactly 3 cards") }
            session.submitFromWeb(move: .passCards(cards), seat: wp.seat)
            return .json(["ok": true])
        }

        // Text-based move (Quiplash writing phase, Bluff defining phase)
        if let text = body["moveText"] as? String, !text.isEmpty {
            let trimmed = String(text.trimmingCharacters(in: .whitespaces).prefix(200))
            if game.engine is QuiplashGame {
                session.submitFromWeb(move: .quiplash(.answer(trimmed)), seat: wp.seat)
                return .json(["ok": true])
            } else if game.engine is BluffGame {
                session.submitFromWeb(move: .bluff(.define(trimmed)), seat: wp.seat)
                return .json(["ok": true])
            }
            return .error("Text move not supported for this game")
        }

        // Standard single-move by index
        guard let idx = body["moveIndex"] as? Int else { return .error("Missing moveIndex") }
        let moves = game.engine.legalMoves()
        guard moves.indices.contains(idx) else { return .error("Invalid move index") }
        session.submitFromWeb(move: moves[idx], seat: wp.seat)
        return .json(["ok": true])
    }

    // MARK: Helpers

    private static func cardByLabel(_ label: String) -> Card? {
        for suit in Suit.allCases {
            for rank in Rank.allCases {
                let c = Card(suit: suit, rank: rank)
                if c.label == label { return c }
            }
        }
        return nil
    }

static func parsePath(_ raw: String) -> (String, [String: String]) {
        guard let qi = raw.firstIndex(of: "?") else { return (raw, [:]) }
        let path = String(raw[raw.startIndex..<qi])
        let qs = String(raw[raw.index(after: qi)...])
        var q: [String: String] = [:]
        for pair in qs.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                q[String(kv[0])] = String(kv[1]).removingPercentEncoding ?? String(kv[1])
            }
        }
        return (path, q)
    }

    static func localIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        // Prefer en0 (Wi-Fi), then en1, then any other non-loopback up/running interface.
        var wifiAddr: String?
        var fallbackAddr: String?
        var ptr = ifaddr
        while let curr = ptr {
            defer { ptr = curr.pointee.ifa_next }
            let flags = Int32(curr.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_RUNNING) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard curr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(curr.pointee.ifa_addr,
                        socklen_t(curr.pointee.ifa_addr.pointee.sa_len),
                        &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let addr = String(cString: host)
            guard !addr.isEmpty else { continue }
            let name = String(cString: curr.pointee.ifa_name)
            if name == "en0" { wifiAddr = addr }
            else if name == "en1" && wifiAddr == nil { fallbackAddr = addr }
            else if fallbackAddr == nil { fallbackAddr = addr }
        }
        return wifiAddr ?? fallbackAddr
    }

    // MARK: Embedded HTML controller page

    static let controllerPage = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
    <meta name="apple-mobile-web-app-title" content="Parlor">
    <meta name="theme-color" content="#0d1220">
    <title>Parlor</title>
    <style>
    *{box-sizing:border-box;margin:0;padding:0;-webkit-tap-highlight-color:transparent}
    body{background:#0d1220;color:#e8eaf0;font-family:-apple-system,BlinkMacSystemFont,sans-serif;min-height:100vh;padding-bottom:max(env(safe-area-inset-bottom),24px)}
    .hdr{display:flex;align-items:center;justify-content:space-between;padding:14px 16px 4px}
    .hdr-title{font-size:22px;font-weight:800;letter-spacing:-.4px}
    .hdr-title span{color:#64b5f6}
    .conn{width:8px;height:8px;border-radius:50%;background:#4caf50;flex-shrink:0;transition:background .4s}
    .conn.bad{background:#ef5350}
    #gname{text-align:center;color:rgba(255,255,255,.35);font-size:12px;padding:0 16px 10px}
    .card{background:rgba(255,255,255,.055);border-radius:18px;padding:14px 16px;margin:6px 10px;border:1px solid rgba(255,255,255,.09)}
    .btn{display:block;width:100%;padding:14px 12px;border:none;border-radius:12px;font-size:16px;font-weight:600;margin:6px 0;cursor:pointer;background:rgba(255,255,255,.1);color:#e8eaf0;transition:opacity .1s,transform .1s}
    .btn:active{transform:scale(.97);opacity:.75}
    .btn:disabled{opacity:.38;pointer-events:none}
    .btn.primary{background:linear-gradient(135deg,#1976d2,#0d47a1)}
    .btn.accent{background:linear-gradient(135deg,#00acc1,#006064)}
    @keyframes glow-pulse{0%,100%{box-shadow:0 0 0 0 rgba(129,212,250,.35)}60%{box-shadow:0 0 0 10px rgba(129,212,250,0)}}
    .turn-card{background:linear-gradient(135deg,rgba(21,101,192,.28),rgba(13,71,161,.18));border:1px solid rgba(100,181,246,.35);border-radius:18px;padding:14px 16px;margin:6px 10px;animation:glow-pulse 2s ease-in-out infinite}
    .turn-title{text-align:center;font-size:21px;font-weight:800;color:#81d4fa;letter-spacing:-.3px}
    .wait-card{background:rgba(255,255,255,.035);border-radius:18px;padding:12px 16px;margin:6px 10px;border:1px solid rgba(255,255,255,.07)}
    .wait-txt{text-align:center;color:rgba(255,255,255,.4);font-size:14px;padding:6px 0}
    .wait-name{color:rgba(255,255,255,.75);font-weight:700}
    .err{color:#ef9a9a;font-size:13px;text-align:center;margin:6px 0}
    .pbar{height:5px;background:rgba(255,255,255,.08);border-radius:3px;margin:8px 0;overflow:hidden}
    .pfill{height:100%;background:linear-gradient(90deg,#1976d2,#64b5f6);border-radius:3px;transition:width .4s}
    input[type=text]{display:block;width:100%;padding:14px;border:none;border-radius:12px;font-size:16px;background:rgba(255,255,255,.1);color:#fff;margin:12px 0 6px;outline:none}
    input[type=text]::placeholder{color:rgba(255,255,255,.35)}
    input[type=text]:focus{background:rgba(255,255,255,.15);box-shadow:0 0 0 2.5px rgba(100,181,246,.5)}
    .seat-strip{display:flex;align-items:center;justify-content:center;gap:8px;padding:7px 14px;background:rgba(255,255,255,.035);border-bottom:1px solid rgba(255,255,255,.07)}
    .my-badge{background:rgba(100,181,246,.18);color:#64b5f6;border-radius:8px;padding:3px 10px;font-weight:700;font-size:13px;border:1px solid rgba(100,181,246,.3)}
    .partner-badge{background:rgba(255,183,77,.14);color:#ffb74d;border-radius:8px;padding:3px 10px;font-weight:700;font-size:12px;border:1px solid rgba(255,183,77,.28)}
    .status-bar{text-align:center;font-size:13px;color:rgba(255,255,255,.46);padding:5px 16px 2px;line-height:1.4}
    .chip-row{display:flex;flex-wrap:wrap;gap:5px;padding:4px 10px 5px;justify-content:center}
    .chip{background:rgba(255,255,255,.07);border-radius:7px;padding:3px 9px;font-size:12px;color:rgba(255,255,255,.6);border:1px solid rgba(255,255,255,.1)}
    .chip.trump{background:rgba(255,183,77,.15);color:#ffb74d;border-color:rgba(255,183,77,.32);font-size:14px;font-weight:700}
    .chip.alone{background:rgba(239,83,80,.14);color:#ef9a9a;border-color:rgba(239,83,80,.3);font-weight:700}
    .chip.upcard{font-weight:700}
    .score-row{display:flex;gap:5px;padding:4px 10px 5px;overflow-x:auto}
    .score-cell{flex:1;min-width:50px;background:rgba(255,255,255,.055);border-radius:10px;padding:6px 4px;text-align:center;border:1px solid rgba(255,255,255,.07)}
    .score-cell.me{background:rgba(100,181,246,.12);border-color:rgba(100,181,246,.3)}
    .score-cell.partner{background:rgba(255,183,77,.1);border-color:rgba(255,183,77,.28)}
    .score-cell.active{background:rgba(129,212,250,.1);border-color:rgba(129,212,250,.38)}
    .score-name{font-size:9px;font-weight:700;color:rgba(255,255,255,.45);overflow:hidden;white-space:nowrap;max-width:100%;text-overflow:ellipsis}
    .score-you{font-size:8px;color:#64b5f6;font-weight:600}
    .score-par{font-size:8px;color:#ffb74d;font-weight:600}
    .score-sub{font-size:8px;color:rgba(255,255,255,.0)}
    .score-val{font-size:18px;font-weight:900;line-height:1.1}
    .bids-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:4px;padding:4px 10px 5px}
    .bid-cell{background:rgba(255,255,255,.055);border-radius:8px;padding:5px 3px;text-align:center;border:1px solid rgba(255,255,255,.07)}
    .bid-cell.me{background:rgba(100,181,246,.12);border-color:rgba(100,181,246,.3)}
    .bid-cell.cur{border-color:rgba(255,213,79,.5);background:rgba(255,213,79,.09)}
    .bid-name{font-size:9px;color:rgba(255,255,255,.42);overflow:hidden;white-space:nowrap;text-overflow:ellipsis}
    .bid-val{font-size:17px;font-weight:800}
    .bid-sub{font-size:9px;color:rgba(129,212,250,.7);font-weight:600}
    .compass{display:grid;grid-template-columns:1fr auto 1fr;grid-template-rows:auto auto auto;gap:4px 6px;padding:8px 10px}
    .compass-top{grid-column:2;grid-row:1;justify-self:center}
    .compass-left{grid-column:1;grid-row:2;justify-self:end;align-self:center}
    .compass-center{grid-column:2;grid-row:2;justify-self:center}
    .compass-right{grid-column:3;grid-row:2;justify-self:start;align-self:center}
    .compass-bottom{grid-column:2;grid-row:3;justify-self:center}
    .trick-zone{display:flex;flex-direction:column;align-items:center;gap:3px}
    .trick-name{font-size:9px;color:rgba(255,255,255,.38);text-align:center;max-width:64px;overflow:hidden;white-space:nowrap}
    .trick-name.ml{color:#64b5f6;font-weight:700}
    .trick-name.pl{color:#ffb74d;font-weight:700}
    .trick-tally{font-size:8px;color:rgba(255,255,255,.3);text-align:center}
    .trick-card{background:#fff;color:#222;border-radius:8px;padding:4px 7px;text-align:center;font-size:15px;font-weight:800;min-width:40px;border:2.5px solid transparent;line-height:1.2}
    .trick-card.red{color:#c62828}
    .trick-card.winner{border-color:#ffd54f;box-shadow:0 0 10px rgba(255,213,79,.4)}
    .trick-card.empty{background:rgba(255,255,255,.07);color:transparent;border:2px dashed rgba(255,255,255,.14);min-height:34px}
    .hgrid{display:grid;grid-template-columns:repeat(auto-fill,minmax(60px,1fr));gap:6px;padding:2px}
    .hcard{background:#fff;color:#222;border-radius:11px;text-align:center;cursor:pointer;border:3px solid transparent;transition:border-color .1s,transform .12s,box-shadow .12s,opacity .15s;line-height:1;user-select:none;display:flex;flex-direction:column;align-items:stretch;min-height:70px;overflow:hidden}
    .hcard.red .rank,.hcard.red .suit-big,.hcard.red .rank-bot{color:#c62828}
    .hcard:active{transform:translateY(-4px);box-shadow:0 8px 18px rgba(0,0,0,.4)}
    .hcard.legal{border-color:#ffd54f;box-shadow:0 0 8px rgba(255,213,79,.22)}
    .hcard.legal:active{transform:translateY(-6px);box-shadow:0 10px 22px rgba(255,213,79,.3)}
    .hcard.sel{border-color:#ff8f00;background:#fff8e1;transform:translateY(-6px)}
    .hcard.dim{opacity:0.17;cursor:default;pointer-events:none}
    .rank{font-size:13px;font-weight:800;line-height:1;padding:4px 5px 0;text-align:left}
    .suit-big{font-size:22px;line-height:1;padding:2px 0;flex:1;display:flex;align-items:center;justify-content:center}
    .rank-bot{font-size:13px;font-weight:800;line-height:1;padding:0 5px 4px;text-align:right;transform:rotate(180deg)}
    .bgrid{display:grid;grid-template-columns:repeat(4,1fr);gap:6px}
    .bbtn{background:rgba(255,255,255,.08);border:1px solid rgba(255,255,255,.14);border-radius:10px;color:#e8eaf0;font-size:17px;font-weight:700;padding:13px 0;cursor:pointer;transition:all .1s}
    .bbtn:active{transform:scale(.95);background:#1565c0}
    .bbtn:disabled{opacity:.38;pointer-events:none}
    .agrid{display:grid;grid-template-columns:1fr 1fr;gap:8px}
    .abtn{background:rgba(255,255,255,.07);border:1.5px solid rgba(255,255,255,.13);border-radius:13px;color:#e8eaf0;font-size:14px;font-weight:600;padding:14px 10px;cursor:pointer;text-align:left;transition:all .1s;display:flex;align-items:center;gap:8px}
    .abtn:active{transform:scale(.97);background:rgba(21,101,192,.4)}
    .abtn:disabled{opacity:.38;pointer-events:none}
    .aletter{background:#1565c0;color:#fff;border-radius:7px;width:26px;height:26px;text-align:center;line-height:26px;font-size:14px;font-weight:800;flex-shrink:0}
    .adesc{font-size:13px;font-weight:500;color:#e8eaf0;flex:1}
    .qcard{background:rgba(255,255,255,.06);border-radius:14px;padding:15px 16px;margin:4px 0;font-size:16px;font-weight:600;line-height:1.45;text-align:center;border:1px solid rgba(255,255,255,.1)}
    .qcat{text-align:center;font-size:11px;font-weight:700;color:rgba(255,255,255,.38);text-transform:uppercase;letter-spacing:1px;padding:4px 0 2px}
    .top-card-row{display:flex;align-items:center;gap:12px;padding:4px 0}
    .uno-ctile{width:100%;padding:10px 4px 8px;text-align:center;font-size:19px;font-weight:800;border-radius:10px;cursor:pointer;border:2.5px solid transparent;color:#fff;line-height:1;user-select:none;transition:all .1s;min-height:60px;display:flex;align-items:center;justify-content:center}
    .uno-ctile.dim{opacity:0.17;cursor:default;pointer-events:none}
    .uno-ctile:active{transform:translateY(-2px)}
    .uno-ctile.legal{border-color:rgba(255,255,255,.55);box-shadow:0 0 8px rgba(255,255,255,.2)}
    .suit-row{padding:6px 0;display:flex;flex-wrap:wrap;gap:7px;justify-content:center;align-items:center}
    .sbtn{background:rgba(100,181,246,.12);border:2px solid #64b5f6;border-radius:10px;color:#64b5f6;font-size:24px;font-weight:800;padding:12px 18px;cursor:pointer;transition:all .1s}
    .sbtn:active{background:#64b5f6;color:#fff}
    .uno-color-btn{border:none;border-radius:10px;color:#fff;font-size:15px;font-weight:700;padding:13px 16px;cursor:pointer;text-transform:capitalize;min-width:80px;transition:opacity .1s}
    .uno-color-btn:active{opacity:.72}
    .slabel{font-size:10px;color:rgba(255,255,255,.3);text-align:center;margin-bottom:8px;text-transform:uppercase;letter-spacing:.7px}
    .ibar{display:flex;flex-wrap:wrap;gap:5px;padding:4px 10px 5px;justify-content:center}
    .ichip{background:rgba(255,255,255,.07);border-radius:7px;padding:3px 9px;font-size:12px;color:rgba(255,255,255,.6)}
    .result-big{text-align:center;font-size:26px;font-weight:800;padding:10px 0 4px}
    .result-body{text-align:center;padding:10px 4px;opacity:.8;line-height:1.6;font-size:14px;white-space:pre-wrap}
    /* [6] Score delta badges */
    @keyframes delta-fade{0%{opacity:1;transform:translateY(0)}80%{opacity:.8;transform:translateY(-14px)}100%{opacity:0;transform:translateY(-20px)}}
    .s-delta{position:absolute;top:-3px;right:2px;font-size:10px;font-weight:800;pointer-events:none;animation:delta-fade 2.2s ease forwards;border-radius:5px;padding:1px 4px}
    .s-delta.pos{color:#a5d6a7;background:rgba(46,125,50,.25)}
    .s-delta.neg{color:#ef9a9a;background:rgba(183,28,28,.25)}
    .score-cell{position:relative}
    /* [3] Hearts received cards strip */
    .recv-strip{display:flex;gap:4px;align-items:center;flex-wrap:wrap;padding:7px 10px;background:rgba(100,181,246,.08);border-radius:10px;margin:4px 10px;border:1px solid rgba(100,181,246,.18)}
    .recv-label{font-size:11px;color:#64b5f6;font-weight:700;margin-right:4px;flex-shrink:0}
    .recv-card{background:#fff;color:#222;border-radius:6px;padding:2px 6px;font-size:14px;font-weight:800;min-width:32px;text-align:center;border:1.5px solid rgba(100,181,246,.4)}
    .recv-card.red{color:#c62828}
    /* [4] Bridge dummy hand */
    .dummy-zone{padding:6px 10px}
    .dummy-suits{display:flex;flex-direction:column;gap:4px}
    .dummy-suit-row{display:flex;gap:4px;align-items:center;flex-wrap:wrap}
    .dummy-suit-sym{font-size:14px;font-weight:800;width:18px;flex-shrink:0}
    .dummy-c{background:#fff;color:#222;border-radius:5px;padding:2px 6px;font-size:13px;font-weight:800;text-align:center}
    .dummy-c.red{color:#c62828}
    /* [5] GoFish rank grid */
    .rank-grid{display:grid;grid-template-columns:repeat(5,1fr);gap:5px}
    .rank-btn{background:rgba(255,255,255,.08);border:1px solid rgba(255,255,255,.14);border-radius:10px;color:#e8eaf0;font-size:16px;font-weight:700;padding:12px 0;cursor:pointer;transition:all .1s}
    .rank-btn:active{transform:scale(.95);background:#1565c0}
    /* [10] Post-move check flash */
    @keyframes check-pop{0%{opacity:0;transform:translate(-50%,-50%) scale(.5)}35%{opacity:1;transform:translate(-50%,-50%) scale(1.15)}65%{transform:translate(-50%,-50%) scale(1)}100%{opacity:0;transform:translate(-50%,-50%) scale(1)}}
    #chkflash{position:fixed;top:45%;left:50%;font-size:72px;z-index:200;pointer-events:none;animation:check-pop 0.9s ease forwards}
    /* [8] Mini card tiles (Euchre upcard) */
    .mini-card{background:#fff;border-radius:7px;padding:3px 8px;font-size:15px;font-weight:800;display:inline-block;line-height:1.2;vertical-align:middle}
    .mini-card.red{color:#c62828}
    .mini-card.dark{color:#111}
    /* [21] Landscape compact hand */
    @media (orientation:landscape){
      .hgrid{grid-template-columns:repeat(auto-fill,minmax(46px,1fr))}
      .hcard{min-height:56px}
      .rank{font-size:10px;padding:3px 4px 0}
      .suit-big{font-size:17px}
      .rank-bot{font-size:10px;padding:0 4px 3px}
      /* [79] Landscape layout improvements */
      .hdr{padding:8px 12px 2px}
      .hdr-title{font-size:18px}
      .card{margin:4px 8px;padding:10px 12px}
      .score-row{padding:2px 8px 3px}
      .score-val{font-size:14px}
      .score-cell{padding:4px 3px}
      .turn-card{padding:10px 12px;margin:4px 8px}
      .turn-title{font-size:17px}
      .btn{padding:11px 10px;font-size:15px;margin:4px 0}
      body{display:flex;flex-direction:column}
      #app{flex:1;overflow-y:auto}
      .seat-strip{padding:4px 12px}
      .status-bar{padding:3px 12px 1px}
    }
    /* [22] Party game writing area */
    .party-input{width:100%;padding:13px;border:none;border-radius:12px;font-size:16px;background:rgba(255,255,255,.1);color:#fff;margin:8px 0 4px;outline:none;resize:none;min-height:76px;font-family:inherit;line-height:1.4}
    .party-input:focus{background:rgba(255,255,255,.15);box-shadow:0 0 0 2.5px rgba(100,181,246,.5)}
    .party-progress{display:flex;align-items:center;justify-content:space-between;margin-bottom:8px}
    .party-label{font-size:11px;color:rgba(255,255,255,.38);text-transform:uppercase;letter-spacing:1px}
    .vote-btn{display:block;width:100%;padding:13px 14px;border:1.5px solid rgba(255,255,255,.13);border-radius:12px;font-size:15px;font-weight:500;margin:5px 0;cursor:pointer;background:rgba(255,255,255,.07);color:#e8eaf0;transition:all .12s;text-align:left;line-height:1.4}
    .vote-btn:active{transform:scale(.98);background:rgba(21,101,192,.35);border-color:#64b5f6}
    .reveal-item{padding:10px 12px;border-radius:12px;margin:5px 0;border:1.5px solid rgba(255,255,255,.1);background:rgba(255,255,255,.055)}
    .reveal-item.real{background:rgba(46,125,50,.18);border-color:rgba(100,220,100,.32)}
    .reveal-votes{font-size:11px;color:rgba(255,255,255,.42);margin-top:3px}
    .bluff-word{font-size:26px;font-weight:900;text-align:center;padding:12px 0 2px;letter-spacing:-.5px}
    .screw-row{display:flex;flex-wrap:wrap;gap:5px;justify-content:center;margin-top:7px}
    .screw-btn{background:rgba(183,28,28,.22);border:1px solid rgba(239,83,80,.3);border-radius:9px;color:#ef9a9a;font-size:13px;font-weight:600;padding:8px 11px;cursor:pointer;transition:all .1s}
    .screw-btn:active{background:rgba(183,28,28,.5);transform:scale(.96)}
    /* [23] Hearts danger cards */
    .hcard{position:relative}
    .hcard.danger{box-shadow:0 0 0 2.5px rgba(239,83,80,.55) inset,0 0 8px rgba(239,83,80,.2)}
    .hcard.danger.legal{box-shadow:0 0 0 2.5px rgba(239,83,80,.65) inset,0 0 8px rgba(239,83,80,.25),0 0 8px rgba(255,213,79,.18)}
    /* [24] Latency badge */
    #latbadge{font-size:9px;color:rgba(255,255,255,.28);margin-left:4px;font-variant-numeric:tabular-nums;min-width:30px}
    /* [31] Euchre bidding hand peek */
    .hcard.peek{opacity:0.42;cursor:default;pointer-events:none}
    /* [37] Hearts round history */
    .hist-panel{background:rgba(255,255,255,.04);border-radius:12px;margin:3px 10px;border:1px solid rgba(255,255,255,.08);overflow:hidden}
    .hist-header{display:flex;align-items:center;justify-content:space-between;padding:7px 12px;cursor:pointer;font-size:12px;color:rgba(255,255,255,.45)}
    .hist-body{padding:4px 12px 8px;display:none}
    .hist-body.open{display:block}
    .hist-row{display:grid;gap:4px;font-size:11px;padding:3px 0;border-bottom:1px solid rgba(255,255,255,.06);align-items:center}
    /* [38] Long-press card zoom */
    #card-zoom{position:fixed;top:50%;left:50%;transform:translate(-50%,-50%);z-index:400;pointer-events:none;background:#fff;border-radius:22px;padding:18px 26px;text-align:center;min-width:100px;box-shadow:0 24px 64px rgba(0,0,0,.7);animation:zoom-in .13s ease}
    #card-zoom .zr{font-size:22px;font-weight:900;text-align:left;line-height:1}
    #card-zoom .zs{font-size:58px;line-height:1;margin:4px 0}
    #card-zoom .zrb{font-size:22px;font-weight:900;text-align:right;line-height:1;transform:rotate(180deg);display:block}
    #card-zoom.red{color:#c62828}
    #card-zoom.dark{color:#111}
    @keyframes zoom-in{from{opacity:0;transform:translate(-50%,-50%) scale(.65)}to{opacity:1;transform:translate(-50%,-50%) scale(1)}}
    /* [40] Scroll-to-hand FAB */
    #fab{position:fixed;bottom:calc(env(safe-area-inset-bottom)+18px);right:16px;width:46px;height:46px;border-radius:23px;background:rgba(21,101,192,.88);border:1px solid rgba(100,181,246,.38);color:#fff;font-size:18px;display:none;align-items:center;justify-content:center;box-shadow:0 4px 16px rgba(0,0,0,.4);cursor:pointer;backdrop-filter:blur(6px);z-index:100;user-select:none}
    /* [49] Turn background pulse */
    #turnbg{position:fixed;inset:0;pointer-events:none;z-index:0;opacity:0;background:radial-gradient(ellipse at 50% 0%,rgba(25,120,200,.09),transparent 70%);transition:opacity 1.2s ease}
    #turnbg.on{opacity:1;animation:tbp 2.8s ease-in-out infinite}
    @keyframes tbp{0%,100%{opacity:.35}55%{opacity:1}}
    /* [46] Confetti */
    .cft{position:fixed;top:0;left:0;width:9px;height:9px;border-radius:2px;pointer-events:none;z-index:500;animation:cfall var(--cd,1.6s) ease-out var(--cdy,0s) forwards}
    @keyframes cfall{0%{opacity:1;transform:translate(var(--cx0),var(--cy0)) rotate(0deg)}100%{opacity:0;transform:translate(var(--cx1),var(--cy1)) rotate(var(--cr,720deg))}}
    /* [41] Star Party board */
    .sp-board{display:flex;flex-wrap:wrap;gap:3px;padding:6px 8px;justify-content:center}
    .sp-space{width:30px;height:30px;border-radius:7px;display:flex;align-items:center;justify-content:center;font-size:13px;position:relative;flex-shrink:0;box-sizing:border-box}
    .sp-space.sp-start{background:rgba(255,255,255,.14)}
    .sp-space.sp-blue{background:rgba(33,150,243,.25);border:1px solid rgba(33,150,243,.4)}
    .sp-space.sp-red{background:rgba(244,67,54,.22);border:1px solid rgba(244,67,54,.35)}
    .sp-space.sp-lucky{background:rgba(255,235,59,.22);border:1px solid rgba(255,235,59,.4)}
    .sp-space.sp-item{background:rgba(76,175,80,.2);border:1px solid rgba(76,175,80,.32)}
    .sp-space.sp-bowser{background:rgba(120,30,200,.22);border:1px solid rgba(120,30,200,.38)}
    .sp-space.sp-event{background:rgba(255,152,0,.2);border:1px solid rgba(255,152,0,.3)}
    .sp-space.sp-star{box-shadow:0 0 10px 2px rgba(255,230,40,.45)}
    .sp-tokens{position:absolute;top:-4px;right:-4px;display:flex;flex-wrap:wrap;gap:1px;max-width:18px}
    .sp-tok{width:8px;height:8px;border-radius:50%;border:1px solid rgba(0,0,0,.4);flex-shrink:0}
    /* [47] Euchre team tricks */
    .euch-tricks{display:flex;gap:6px;padding:6px 10px}
    .euch-team{flex:1;background:rgba(255,255,255,.06);border-radius:10px;padding:6px 10px;text-align:center;border:1px solid rgba(255,255,255,.1)}
    .euch-team.maker{background:rgba(33,150,243,.14);border-color:rgba(33,150,243,.3)}
    .euch-team-name{font-size:9px;text-transform:uppercase;letter-spacing:.7px;color:rgba(255,255,255,.4);margin-bottom:2px}
    .euch-team-count{font-size:22px;font-weight:800;line-height:1}
    .euch-star{color:#ffd54f}
    /* [50] Klondike solitaire */
    .kl-row{display:flex;gap:4px;padding:4px 8px}
    .kl-pile{flex:1;min-width:0}
    .kl-lbl{font-size:9px;color:rgba(255,255,255,.32);text-align:center;margin-top:2px}
    .kl-btn{background:rgba(255,255,255,.07);border:1px solid rgba(255,255,255,.14);border-radius:8px;color:#e8eaf0;font-size:11px;padding:4px 2px;cursor:pointer;transition:all .1s;text-align:center;width:100%;margin-top:3px;display:block}
    .kl-btn.found{background:rgba(80,180,80,.15);border-color:rgba(100,200,100,.35);color:#a5d6a7}
    .kl-btn.draw-btn{background:rgba(100,181,246,.12);border-color:rgba(100,181,246,.3);color:#81d4fa}
    .kl-btn:active{transform:scale(.95)}
    /* [56] Hearts pass tray */
    .pass-tray{display:flex;gap:8px;justify-content:center;padding:6px 16px 8px}
    .pass-slot{width:40px;height:52px;border:2px dashed rgba(255,255,255,.18);border-radius:9px;display:flex;align-items:center;justify-content:center;font-size:10px;color:rgba(255,255,255,.25);transition:all .18s ease;flex-shrink:0}
    .pass-slot.filled{border-color:rgba(255,183,77,.55);background:rgba(255,183,77,.08);color:#fff;font-size:12px;font-weight:800}
    /* [57] Opponent hand fan */
    .opp-fans{display:flex;gap:8px;padding:4px 10px 6px;justify-content:center;flex-wrap:wrap}
    .opp-fan{display:flex;flex-direction:column;align-items:center;gap:3px}
    .opp-fan-cards{position:relative;height:28px;width:44px}
    .opp-fc{position:absolute;width:16px;height:24px;border-radius:3px;background:rgba(25,50,120,.85);border:1px solid rgba(255,255,255,.18);top:0}
    .opp-fan-name{font-size:9px;color:rgba(255,255,255,.38);text-align:center;max-width:48px;overflow:hidden;white-space:nowrap;text-overflow:ellipsis}
    .opp-fan-count{font-size:11px;font-weight:700;color:rgba(255,255,255,.65)}
    /* [58] Euchre upcard big CTA */
    .euch-upcard-cta{text-align:center;padding:8px 10px 4px}
    .euch-upcard-big{display:inline-flex;flex-direction:column;align-items:center;justify-content:center;width:52px;height:70px;border-radius:11px;font-size:17px;font-weight:900;border:2px solid rgba(255,255,255,.25);box-shadow:0 6px 22px rgba(0,0,0,.5);margin:0 auto}
    .euch-upcard-big.red{background:#b71c1c;color:#fff}
    .euch-upcard-big.dark{background:#1a1a2e;color:#e8eaf0}
    /* [60] Game-over local rank spotlight */
    .go-you-banner{background:linear-gradient(135deg,rgba(33,150,243,.2),rgba(21,101,192,.15));border:1px solid rgba(100,181,246,.35);border-radius:14px;padding:12px 16px;text-align:center;margin:10px 0}
    .go-you-rank{font-size:32px;line-height:1;margin-bottom:4px}
    .go-you-label{font-size:14px;font-weight:700;color:#81d4fa}
    /* [61] Bridge vulnerability chip */
    .vul-chip{border-radius:7px;padding:2px 8px;font-size:10px;font-weight:800;letter-spacing:.5px}
    .vul-chip.danger{background:rgba(183,28,28,.25);color:#ef9a9a;border:1px solid rgba(239,83,80,.3)}
    .vul-chip.safe{background:rgba(46,125,50,.2);color:#a5d6a7;border:1px solid rgba(100,200,100,.25)}
    /* [63] Hand sort toggle */
    .sort-toggle{float:right;font-size:10px;background:rgba(255,255,255,.08);border:1px solid rgba(255,255,255,.14);border-radius:6px;color:rgba(255,255,255,.5);padding:2px 7px;cursor:pointer;margin-top:-1px}
    .sort-toggle:active{background:rgba(255,255,255,.14)}
    /* [64] JackAttack timer ring */
    .ja-timer-wrap{display:flex;justify-content:center;align-items:center;padding:4px 0}
    /* [65] MarioParty minigame numpad */
    .mg-numpad{display:grid;grid-template-columns:repeat(5,1fr);gap:5px;padding:4px 10px}
    .mg-numpad-btn{background:rgba(255,255,255,.08);border:1px solid rgba(255,255,255,.14);border-radius:9px;color:#e8eaf0;font-size:14px;font-weight:700;padding:10px 4px;cursor:pointer;text-align:center;transition:all .1s}
    .mg-numpad-btn:active{background:rgba(255,255,255,.18);transform:scale(.93)}
    .mg-numpad-btn.sel{background:rgba(33,150,243,.3);border-color:rgba(100,181,246,.5);color:#81d4fa}
    /* [62] Bomberman HUD */
    .bomber-hud{display:grid;grid-template-columns:repeat(3,1fr);gap:6px;padding:4px 10px 6px}
    .bomber-stat{text-align:center;background:rgba(255,255,255,.05);border-radius:10px;padding:8px 4px;border:1px solid rgba(255,255,255,.09)}
    .bomber-stat-val{font-size:22px;font-weight:800;line-height:1}
    .bomber-stat-lbl{font-size:9px;color:rgba(255,255,255,.38);text-transform:uppercase;letter-spacing:.6px;margin-top:2px}
    /* [70] Score bar chart */
    .score-chart{padding:6px 10px}
    .score-bar-row{display:flex;align-items:center;gap:6px;margin-bottom:5px}
    .score-bar-name{font-size:11px;color:rgba(255,255,255,.55);width:56px;text-align:right;flex-shrink:0;overflow:hidden;white-space:nowrap;text-overflow:ellipsis}
    .score-bar-track{flex:1;height:16px;background:rgba(255,255,255,.06);border-radius:4px;overflow:hidden}
    .score-bar-fill{height:100%;border-radius:4px;transition:width .5s ease;display:flex;align-items:center;justify-content:flex-end;padding-right:4px}
    .score-bar-val{font-size:10px;font-weight:700;color:rgba(255,255,255,.85);white-space:nowrap}
    /* [68] Klondike multi-card column stack */
    .kl-stack{display:flex;flex-direction:column;gap:-2px}
    .kl-mini{height:22px;border-radius:4px;font-size:11px;font-weight:700;display:flex;align-items:center;justify-content:center;border:1px solid rgba(255,255,255,.15);overflow:hidden;white-space:nowrap}
    .kl-mini.red{background:#7f1010;color:#ffcdd2}
    .kl-mini.drk{background:#1a2040;color:#e8eaf0}
    /* [66] Moon banner */
    @keyframes moonpulse{0%,100%{opacity:.85}50%{opacity:1;box-shadow:0 0 20px rgba(160,80,255,.35)}}
    .moon-warn{margin:3px 10px;padding:8px 12px;background:rgba(80,30,150,.3);border:1px solid rgba(180,100,255,.35);border-radius:12px;text-align:center;font-size:13px;font-weight:700;color:#ce93d8;animation:moonpulse 2s ease-in-out infinite}
    /* [69] Waiting screen live pulse */
    @keyframes wlive{0%,100%{opacity:.4;transform:scale(.92)}50%{opacity:1;transform:scale(1)}}
    .wait-live-dot{width:8px;height:8px;border-radius:50%;background:#69f0ae;display:inline-block;animation:wlive 1.4s ease-in-out infinite;margin-right:5px;vertical-align:middle}
    /* [77] Latency sparkline */
    #spark{display:inline-block;vertical-align:middle;margin-left:3px;opacity:.65}
    /* [82] Tricks progress bar */
    .tricks-bar{height:4px;background:rgba(255,255,255,.07);border-radius:2px;margin:2px 10px 5px;overflow:hidden}
    .tricks-fill{height:100%;border-radius:2px;background:linear-gradient(90deg,#1976d2,#42a5f5);transition:width .5s}
    /* [84] Chess check indicator */
    .check-banner{margin:3px 10px;padding:7px 12px;background:rgba(183,28,28,.28);border:1px solid rgba(239,83,80,.4);border-radius:11px;text-align:center;font-size:13px;font-weight:800;color:#ef9a9a}
    /* [85] Checkers move desc chip */
    .move-desc-chip{margin:2px 10px 4px;padding:5px 12px;background:rgba(255,255,255,.05);border:1px solid rgba(255,255,255,.1);border-radius:9px;font-size:12px;color:rgba(255,255,255,.55);text-align:center}
    /* [87] Hearts danger score highlight */
    .score-cell.hearts-danger{background:rgba(183,28,28,.18);border-color:rgba(239,83,80,.3)}
    .score-cell.hearts-ok{background:rgba(46,125,50,.12);border-color:rgba(100,200,100,.22)}
    /* [91] Tetris clear label badge */
    .clear-badge{display:inline-block;background:rgba(255,213,79,.18);color:#ffd54f;border-radius:8px;padding:2px 10px;font-size:12px;font-weight:800;margin:2px 0;letter-spacing:.5px;animation:clearPop .5s ease}
    @keyframes clearPop{0%{opacity:0;transform:scale(.7)}60%{transform:scale(1.08)}100%{opacity:1;transform:scale(1)}}
    /* [95] Euchre streak pip strip */
    .streak-pips{display:flex;gap:3px;justify-content:center;margin-top:3px}
    .streak-pip{width:6px;height:6px;border-radius:50%;background:#ffd54f;opacity:.85}
    /* [96] Status bar 2-line support */
    .status-bar{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:100%}
    /* [97] Swipe-up-to-dismiss trick flash */
    /* (handled in JS with touch events on the flash element) */
    /* [98] Score trend arrows */
    .score-trend{font-size:9px;font-weight:800;margin-left:2px}
    .score-trend.up{color:#ef9a9a}
    .score-trend.down{color:#a5d6a7}
    /* [100] Loading skeleton */
    .skel{background:linear-gradient(90deg,rgba(255,255,255,.04) 25%,rgba(255,255,255,.09) 50%,rgba(255,255,255,.04) 75%);background-size:200% 100%;animation:skelAnim 1.6s infinite;border-radius:10px;height:16px;margin:6px 0}
    @keyframes skelAnim{0%{background-position:200% 0}100%{background-position:-200% 0}}
    /* [71] Pull-to-refresh indicator */
    #ptr{position:fixed;top:0;left:0;right:0;height:44px;display:flex;align-items:center;justify-content:center;background:rgba(21,101,192,.72);font-size:13px;font-weight:600;color:#fff;transform:translateY(-44px);transition:transform .22s ease;z-index:300;pointer-events:none;backdrop-filter:blur(6px)}
    #ptr.visible{transform:translateY(0)}
    /* [73-75] Arcade spectator HUD */
    .arcade-hud{display:grid;grid-template-columns:repeat(3,1fr);gap:6px;padding:6px 10px}
    .arcade-stat{text-align:center;background:rgba(255,255,255,.05);border-radius:10px;padding:8px 4px;border:1px solid rgba(255,255,255,.09)}
    .arcade-val{font-size:24px;font-weight:900;line-height:1;color:#81d4fa}
    .arcade-lbl{font-size:9px;color:rgba(255,255,255,.38);text-transform:uppercase;letter-spacing:.7px;margin-top:3px}
    /* [72] Hearts round-points chip */
    .rpt-chip{font-size:10px;font-weight:700;border-radius:5px;padding:1px 5px;margin-top:2px;display:block}
    .rpt-chip.warn{background:rgba(239,83,80,.22);color:#ef9a9a}
    .rpt-chip.ok{background:rgba(46,125,50,.18);color:#a5d6a7}
    </style>
    </head>
    <body>
    <div id="ptr">&#8635; Refreshing&hellip;</div>
    <div class="hdr">
      <div class="hdr-title">&#127924; <span>Parlor</span></div>
      <div style="display:flex;align-items:center"><div class="conn" id="cdot"></div><span id="latbadge"></span><svg id="spark" width="32" height="14" viewBox="0 0 32 14"></svg></div>
    </div>
    <p id="gname">Loading&hellip;</p>
    <div id="turnbg"></div>
    <div id="app"></div>
    <div id="fab" onclick="fabTapped()">&#9660;</div>
    <script>
    // ── State ─────────────────────────────────────────────────────────────────
    var sid=null,mySeat=null,myName=null,pollTimer=null,passSelected=[],lastState=null;
    var pendingEight=null,pendingUnoId=null,submitting=false,errCount=0;
    var lastTrickSeen=null;
    var prevScores=null,prevTeamScores=null;  // [6] score delta tracking
    var scoreTrends=null;                      // [98] score trend direction
    var notifGranted=false,lastMyTurn=false;  // [2] notifications
    var lastRecvKey='';                        // [3] received cards seen key
    var pollStartMs=0;                         // [28] latency tracking
    var lastEuchreResult='';                   // [42] euchre round result flash
    var lastBookEvent='';                      // [45] gofish book flash
    var reconnCountdown=0,reconnTimer=null;    // [43] auto-reconnect countdown
    var latSamples=[];                         // [51] rolling latency samples
    var handSortMode='suit';                   // [63] 'suit' | 'rank'
    var mgScore=50;                            // [65] minigame score picker state
    var ptrStartY=0,ptrActive=false;           // [71] pull-to-refresh state
    var lastSpadesSummary='';                  // [81] spades round summary flash
    var lastCheckersMoveDesc='';               // [85] checkers move desc flash

    // ── Helpers ───────────────────────────────────────────────────────────────
    var app=function(){return document.getElementById('app')};
    var sub=function(t){document.getElementById('gname').textContent=t};
    var render=function(h){app().innerHTML=h};
    var esc=function(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;')};
    var rankOf=function(lbl){var m=lbl.match(/(\\d+|[AKQJ]|10)([\\u2660\\u2665\\u2666\\u2663])/);return m?m[1]:'?'};
    var suitOf=function(lbl){var m=lbl.match(/([\\u2660\\u2665\\u2666\\u2663])/);return m?m[1]:''};
    var rankVal=function(r){return({A:14,K:13,Q:12,J:11,'10':10,9:9,8:8,7:7,6:6,5:5,4:4,3:3,2:2})[r]||0};
    var suitOrder=function(s){return({'\\u2660':0,'\\u2665':1,'\\u2666':2,'\\u2663':3})[s]||4};
    function haptic(ms){try{if(navigator.vibrate)navigator.vibrate(ms||15);}catch(e){}}
    function setConn(ok){var d=document.getElementById('cdot');if(d)d.className='conn'+(ok?'':' bad');}
    // [51] Color conn dot + badge by rolling avg latency
    function setConnQuality(avgMs){
      var dot=document.getElementById('cdot'),lb=document.getElementById('latbadge');
      var col=avgMs<100?'#69f0ae':(avgMs<300?'#ffd54f':'#ef9a9a');
      if(dot&&dot.className.indexOf('bad')<0){dot.style.background=col;dot.style.boxShadow='0 0 5px '+col;}
      if(lb){lb.style.color=col;}
      // [77] Update latency sparkline SVG
      var spark=document.getElementById('spark');
      if(spark&&latSamples.length>1){
        var W=32,H=14,n=latSamples.length;
        var maxV=Math.max.apply(null,latSamples),minV=Math.min.apply(null,latSamples);
        var range=Math.max(maxV-minV,1);
        var pts=latSamples.map(function(v,i){
          var x=Math.round((i/(n-1))*(W-2))+1;
          var y=Math.round((1-(v-minV)/range)*(H-4))+2;
          return x+','+y;
        }).join(' ');
        spark.innerHTML='<polyline points="'+pts+'" fill="none" stroke="'+col+'" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>';
      }
    }

    // ── [71] Pull-to-refresh gesture ─────────────────────────────────────────────
    document.addEventListener('touchstart',function(e){
      if(window.scrollY===0&&e.touches.length===1){ptrStartY=e.touches[0].clientY;ptrActive=true;}
    },{passive:true});
    document.addEventListener('touchmove',function(e){
      if(!ptrActive) return;
      var dy=e.touches[0].clientY-ptrStartY;
      var ptr=document.getElementById('ptr');
      if(dy>18&&ptr) ptr.classList.add('visible');
    },{passive:true});
    document.addEventListener('touchend',function(){
      if(!ptrActive) return;
      ptrActive=false;
      var ptr=document.getElementById('ptr');
      if(ptr&&ptr.classList.contains('visible')){
        ptr.classList.remove('visible');
        if(sid){clearTimeout(pollTimer);doPoll();}
      }
    },{passive:true});

    // ── [78] Orientation change re-render ─────────────────────────────────────────
    window.addEventListener('orientationchange',function(){
      setTimeout(function(){if(sid&&lastState){renderState(lastState);}},220);
    });

    // ── [80] Back-button prevention ───────────────────────────────────────────────
    window.addEventListener('load',function(){history.pushState({parlor:true},document.title);});
    window.addEventListener('popstate',function(e){
      if(e.state&&e.state.parlor) history.pushState({parlor:true},document.title);
    });
    window.addEventListener('beforeunload',function(e){
      if(sid&&lastState&&!lastState.isOver){e.preventDefault();e.returnValue='Leave game?';return 'Leave game?';}
    });

    // ── Session ────────────────────────────────────────────────────────────────
    function saveSession(s,n,seat){try{localStorage.setItem('parlor_sid',s);localStorage.setItem('parlor_name',n);localStorage.setItem('parlor_seat',seat);}catch(e){}}
    function loadSavedName(){try{return localStorage.getItem('parlor_name')||'';}catch(e){return '';}}
    function loadSavedSid(){try{return localStorage.getItem('parlor_sid')||'';}catch(e){return '';}}
    function clearSession(){try{localStorage.removeItem('parlor_sid');}catch(e){}}

    // ── Network ────────────────────────────────────────────────────────────────
    async function api(method,path,body){
      try{
        var r=await fetch(path,{method:method,headers:{'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});
        return r.json();
      }catch(e){return{error:'Network error'}}
    }

    // ── [100] Loading skeleton ─────────────────────────────────────────────────
    function showSkeleton(){
      render('<div class="card" style="padding:16px"><div class="skel" style="width:60%;height:14px"></div>'+
        '<div class="skel" style="width:90%;height:12px;margin-top:8px"></div>'+
        '<div style="display:flex;gap:6px;margin-top:14px">'+
          '<div class="skel" style="flex:1;height:50px;border-radius:10px"></div>'+
          '<div class="skel" style="flex:1;height:50px;border-radius:10px"></div>'+
          '<div class="skel" style="flex:1;height:50px;border-radius:10px"></div>'+
          '<div class="skel" style="flex:1;height:50px;border-radius:10px"></div>'+
        '</div>'+
        '<div class="skel" style="height:36px;margin-top:12px;border-radius:10px"></div></div>');
    }

    async function tryResumeSession(){
      var savedSid=loadSavedSid();
      if(!savedSid) return false;
      showSkeleton(); // [100] Show skeleton while checking session
      var d=await api('GET','/api/state?id='+savedSid);
      if(d.error) return false;
      sid=savedSid; mySeat=d.mySeat; myName=d.myName;
      return true;
    }

    async function showJoin(){
      requestNotifPermission();
      var resumed=await tryResumeSession();
      if(resumed){sub('Reconnected');startPoll();return;}
      var d=await api('GET','/api/lobby');
      if(d.error){render('<div class="card"><p class="err">'+esc(d.error)+'</p></div>');return}
      sub(d.gameName||'Parlor');
      var pct=Math.round((d.seatsFilled/d.seatsTotal)*100);
      var savedName=loadSavedName();
      render('<div class="card"><p style="text-align:center;margin-bottom:10px;color:rgba(255,255,255,.42);font-size:14px">'+d.seatsFilled+'/'+d.seatsTotal+' players joined</p>'+
        '<div class="pbar"><div class="pfill" style="width:'+pct+'%"></div></div>'+
        '<input type="text" id="pname" placeholder="Your name" maxlength="20" autocomplete="off" value="'+esc(savedName)+'">'+
        '<p class="err" id="jerr"></p>'+
        '<button class="btn primary" onclick="joinGame()">Join Game</button></div>');
      var el=document.getElementById('pname');
      if(el){el.focus();if(savedName)el.select();el.addEventListener('keydown',function(e){if(e.key==='Enter')joinGame();});}
    }

    async function joinGame(){
      var name=(document.getElementById('pname')||{}).value||'';
      name=name.trim();
      if(!name){document.getElementById('jerr').textContent='Enter your name';return}
      var d=await api('POST','/api/join',{name:name});
      if(d.error){document.getElementById('jerr').textContent=d.error;return}
      sid=d.sessionID; mySeat=d.seat; myName=d.name;
      saveSession(sid,myName,mySeat);
      sub(d.gameName);
      startPoll();
    }

    // ── [1] Adaptive polling (300ms on your turn, 1.5s waiting) ───────────────
    function startPoll(){if(pollTimer)clearTimeout(pollTimer);doPoll();}
    function schedulePoll(){
      if(pollTimer)clearTimeout(pollTimer);
      var delay=(lastState&&lastState.isMyTurn)?300:1500;
      pollTimer=setTimeout(doPoll,delay);
    }

    // ── [2] Web notifications when turn starts ─────────────────────────────────
    function requestNotifPermission(){
      if('Notification' in window&&Notification.permission==='default'){
        Notification.requestPermission().then(function(p){notifGranted=(p==='granted');});
      } else { notifGranted='Notification' in window&&Notification.permission==='granted'; }
    }
    function maybeSendTurnNotif(d){
      if(!lastMyTurn&&d.isMyTurn){
        document.title='\\u2B50 Your Turn! \\u2014 Parlor';
        playTurnSound();   // [39]
        if(notifGranted){
          try{new Notification('Your turn!',{body:d.statusText||'It\\'s your move',tag:'parlor-turn',renotify:true});}catch(e){}
        }
        // [25] Auto-scroll to action area when turn starts
        setTimeout(function(){
          var tc=document.querySelector('.turn-card');
          if(tc) tc.scrollIntoView({behavior:'smooth',block:'nearest'});
        },180);
      } else if(!d.isMyTurn){
        document.title='Parlor';
      }
      lastMyTurn=d.isMyTurn;
    }

    async function doPoll(){
      if(submitting){schedulePoll();return;}
      pollStartMs=Date.now();
      var d=await api('GET','/api/state?id='+sid);
      var latMs=Date.now()-pollStartMs;
      var lb=document.getElementById('latbadge');
      if(!d.error){
        // [51] Rolling latency quality indicator
        latSamples.push(latMs);if(latSamples.length>5)latSamples.shift();
        var avgLat=Math.round(latSamples.reduce(function(a,b){return a+b;},0)/latSamples.length);
        if(lb)lb.textContent=avgLat+'ms';
        setConnQuality(avgLat);
      }
      if(d.error){
        errCount++;setConn(false);
        if(errCount<3){schedulePoll();return;}
        // [43] Auto-reconnect countdown instead of static error
        if(d.error.indexOf('expired')>=0||d.error.indexOf('No session')>=0){
          clearSession();
          render('<div class="card"><p class="err">Session expired</p><button class="btn accent" onclick="showJoin()">Rejoin</button></div>');
        } else {
          if(reconnTimer) clearTimeout(reconnTimer);
          reconnCountdown=Math.min(15,3+errCount);
          doReconnTick();
        }
        return;
      }
      errCount=0;setConn(true);
      if(lastState&&lastState.isMyTurn&&!d.isMyTurn){pendingEight=null;pendingUnoId=null;}
      maybeSendTurnNotif(d);
      renderState(d);
      schedulePoll();
    }

    // ── [43] Auto-reconnect countdown ─────────────────────────────────────────
    function doReconnTick(){
      if(reconnCountdown<=0){errCount=0;doPoll();return;}
      render('<div class="card" style="text-align:center;padding:20px 16px">'+
        '<div class="conn bad" style="margin:0 auto 12px;width:12px;height:12px;border-radius:50%;background:#ef5350"></div>'+
        '<p class="err" style="margin-bottom:6px">Connection lost</p>'+
        '<p style="font-size:13px;color:rgba(255,255,255,.4);margin-bottom:14px">Reconnecting in '+reconnCountdown+'s…</p>'+
        '<button class="btn" style="max-width:180px;margin:0 auto" onclick="if(reconnTimer)clearTimeout(reconnTimer);errCount=0;doPoll()">Retry Now</button>'+
        '</div>');
      reconnCountdown--;
      reconnTimer=setTimeout(doReconnTick,1000);
    }

    // ── [10] Last trick flash banner ───────────────────────────────────────────
    var trickFlashTimer=null;
    function showTrickFlash(msg,moon){
      var existing=document.getElementById('tflash');
      if(existing) existing.remove();
      if(trickFlashTimer) clearTimeout(trickFlashTimer);
      var el=document.createElement('div');
      el.id='tflash';
      var bg=moon?'rgba(99,58,162,.85)':'rgba(30,60,40,.9)';
      el.style.cssText='position:fixed;bottom:calc(env(safe-area-inset-bottom)+14px);left:12px;right:12px;background:'+bg+
        ';border-radius:14px;padding:10px 14px;font-size:13px;font-weight:600;color:#fff;z-index:99;'+
        'border:1px solid rgba(255,255,255,.18);animation:fadein .2s ease;text-align:center;';
      el.textContent=msg;
      // [97] Swipe-up-to-dismiss trick flash
      var swipeY0=0;
      el.addEventListener('touchstart',function(e){swipeY0=e.touches[0].clientY;},{passive:true});
      el.addEventListener('touchend',function(e){
        if(swipeY0-e.changedTouches[0].clientY>30){
          if(trickFlashTimer) clearTimeout(trickFlashTimer);
          el.style.transition='transform .2s,opacity .2s';
          el.style.transform='translateY(40px)';el.style.opacity='0';
          setTimeout(function(){if(el.parentNode)el.remove();},220);
        }
      },{passive:true});
      document.body.appendChild(el);
      trickFlashTimer=setTimeout(function(){if(el.parentNode)el.remove();},3000);
    }
    // inject keyframe once
    (function(){var s=document.createElement('style');s.textContent='@keyframes fadein{from{opacity:0;transform:translateY(8px)}to{opacity:1;transform:none}}';document.head.appendChild(s);})();

    // ── [45] GoFish book flash ─────────────────────────────────────────────────
    var bookFlashTimer=null;
    function showBookFlash(msg){
      var existing=document.getElementById('bkflash');
      if(existing) existing.remove();
      if(bookFlashTimer) clearTimeout(bookFlashTimer);
      var el=document.createElement('div');
      el.id='bkflash';
      el.style.cssText='position:fixed;top:70px;left:12px;right:12px;background:rgba(180,130,0,.88);'+
        'border-radius:14px;padding:10px 14px;font-size:14px;font-weight:700;color:#fff;z-index:99;'+
        'border:1px solid rgba(255,220,60,.4);animation:fadein .2s ease;text-align:center;'+
        'box-shadow:0 4px 20px rgba(200,160,0,.4)';
      el.textContent='\\uD83D\\uDCDA '+msg;
      document.body.appendChild(el);
      bookFlashTimer=setTimeout(function(){if(el.parentNode)el.remove();},3200);
    }

    // ── [48] Keyboard shortcuts ────────────────────────────────────────────────
    document.addEventListener('keydown',function(e){
      if(e.target.tagName==='INPUT'||e.target.tagName==='TEXTAREA') return;
      var d=lastState; if(!d||!d.isMyTurn) return;
      var m=d.moves||[];
      // A/B/C/D for trivia/4-choice answers
      var lmap={a:0,b:1,c:2,d:3};
      if(e.key.toLowerCase() in lmap&&m.length===4&&m.every(function(x){return /^[ABCD]$/.test(String(x.label||'').trim())})){
        var idx=lmap[e.key.toLowerCase()];
        if(m[idx]){haptic();doMove(m[idx].index);}
        return;
      }
      // 0-9 for bid/number picking
      if(/^[0-9]$/.test(e.key)&&m.length>=2){
        var mv=m.find(function(x){return String(x.label||'').trim()===e.key;});
        if(mv){haptic();doMove(mv.index);}
        return;
      }
      // Space/Enter: single-action moves (draw, roll, next)
      if((e.key===' '||e.key==='Enter')&&m.length===1){
        haptic();doMove(m[0].index);e.preventDefault();
      }
    });

    // ── Main render ────────────────────────────────────────────────────────────
    function renderState(d){
      var ts=d.lastTrickSummary;
      if(ts&&ts!==lastTrickSeen){lastTrickSeen=ts;showTrickFlash(ts,ts.indexOf('moon')>=0||ts.indexOf('\\uD83C\\uDF19')>=0);}
      // [42] Euchre round result flash
      if(d.lastRoundResult&&d.lastRoundResult!==lastEuchreResult){lastEuchreResult=d.lastRoundResult;showTrickFlash(d.lastRoundResult,false);}
      // [45] GoFish book completion flash
      if(d.lastBookEvent&&d.lastBookEvent!==lastBookEvent){lastBookEvent=d.lastBookEvent;showBookFlash(d.lastBookEvent);}
      // [81] Spades round summary flash
      if(d.lastRoundSummary&&d.lastRoundSummary!==lastSpadesSummary){lastSpadesSummary=d.lastRoundSummary;showTrickFlash(d.lastRoundSummary,false);}
      // [85] Checkers last move desc flash
      if(d.lastMoveDesc&&d.lastMoveDesc!==lastCheckersMoveDesc){lastCheckersMoveDesc=d.lastMoveDesc;}
      // [49] Turn background pulse
      var tb=document.getElementById('turnbg');
      if(tb) tb.className=d.isMyTurn?'on':'';
      // [89] Theme-color update on turn change
      var tc=document.querySelector('meta[name=theme-color]');
      if(tc) tc.setAttribute('content',d.isMyTurn?'#0d2860':'#0d1220');
      lastState=d;
      var me=+(d.mySeat||0);
      var names=d.seatNames||[];

      // [69] Waiting screen with live activity pulse
      if(d.waiting){
        var pct=Math.round((d.seatsFilled/d.seatsTotal)*100);
        var joined=d.joinedNames||[];
        var rosterHtml=joined.length?
          ('<div style="display:flex;flex-wrap:wrap;gap:6px;justify-content:center;margin-top:10px">'+
            joined.map(function(n){
              var isMe=(n===(d.myName||''));
              return '<span style="background:rgba(100,181,246,'+(isMe?.18:.08)+');border:1px solid rgba(100,181,246,'+(isMe?.3:.12)+');border-radius:8px;padding:3px 10px;font-size:13px;font-weight:'+(isMe?700:500)+';color:'+(isMe?'#64b5f6':'rgba(255,255,255,.65)')+'">'+esc(n)+(isMe?' (you)':'')+'</span>';
            }).join('')+
          '</div>'):
          '<p style="text-align:center;font-size:12px;color:rgba(255,255,255,.3);margin-top:8px">Be the first to join!</p>';
        render('<div class="card">'+
          '<div style="text-align:center;font-size:20px;font-weight:800;color:rgba(255,255,255,.45);padding:8px 0 2px">'+
            '<span class="wait-live-dot"></span>Waiting for host</div>'+
          '<p style="text-align:center;font-size:13px;color:rgba(255,255,255,.35);margin-top:4px">'+d.seatsFilled+'/'+d.seatsTotal+' players joined</p>'+
          '<div class="pbar" style="margin-top:8px"><div class="pfill" style="width:'+pct+'%"></div></div>'+
          rosterHtml+'</div>');
        return;
      }

      // [9] Enhanced game-over with ranking podium
      if(d.isOver){
        clearInterval(poll_); clearSession();
        render(buildGameOver(d));
        return;
      }

      // [7] Save scroll position before re-render
      var savedScroll=window.scrollY;

      var html='';

      // Seat identity strip
      var partnerStr=d.partnerName?'<span class="partner-badge">&#129309; '+esc(d.partnerName)+'</span>':'';
      html+='<div class="seat-strip"><span class="my-badge">'+esc(d.myName||('Seat '+(me+1)))+'</span>'+partnerStr+'</div>';

      // [59] Status bar with contextual color + [88] long-press tooltip to expand
      var sbColor='rgba(255,255,255,.46)';
      if(d.isMyTurn) sbColor='rgba(129,212,250,.72)';
      else if(d.queenLurking||d.sandbagsWarning) sbColor='rgba(255,152,0,.7)';
      else if(d.isShootingMoon) sbColor='rgba(180,100,240,.7)';
      else if(d.gamePhase==='bidding'||d.gamePhase==='auction') sbColor='rgba(255,213,79,.6)';
      var statusFull=esc(d.statusText||'');
      // Truncate long status lines to 72 chars with tap-to-expand
      var rawStatus=d.statusText||'';
      var truncated=rawStatus.length>72;
      var displayStatus=truncated?rawStatus.substring(0,70)+'…':rawStatus;
      html+='<div class="status-bar" style="color:'+sbColor+';cursor:'+(truncated?'pointer':'default')+'"'+
        (truncated?' onclick="this.textContent=\\''+statusFull+'\\';this.style.whiteSpace=\\'normal\\'"':'')+
        '>'+esc(displayStatus)+'</div>';

      // [6] Scores with delta badges
      html+=buildScoreRow(d);

      // [37] Hearts round history panel
      if(d.roundHistory&&d.roundHistory.length) html+=buildRoundHistory(d,names);

      // Info chips + [66] persistent moon-shoot banner
      html+=buildInfoChips(d);
      if(d.isShootingMoon){
        var mn=names[+(d.moonShooterSeat||0)]||('Seat '+((+(d.moonShooterSeat||0))+1));
        var isMe=(+(d.moonShooterSeat||0)===me);
        html+='<div class="moon-warn">&#127769; '+esc(mn)+(isMe?' — you\'re shooting the moon!'
          :' is shooting the moon!<br><span style="font-size:11px;opacity:.75">Play a &#9829; or &#9824;Q to stop them!</span>')+'</div>';
      }

      // Trivia branch
      if(d.triviaQuestion){
        if(d.triviaCategory) html+='<p class="qcat">'+esc(d.triviaCategory)+'</p>';
        html+='<div class="qcard">'+esc(d.triviaQuestion)+'</div>';
        if(d.isMyTurn&&d.moves&&d.moves.length)
          html+='<div class="turn-card"><div class="turn-title">&#127775; Your Turn!</div><div style="margin-top:10px">'+buildMoves(d)+'</div></div>';
        else
          html+='<div class="wait-card"><p class="wait-txt">Waiting for <span class="wait-name">'+esc(d.currentPlayerName||'other player')+'</span></p></div>';
        render(html);window.scrollTo(0,savedScroll); return;
      }

      // [21-22-23] Party game branch (Prompt Party, Bluff!, Jack Attack)
      if(d.gameType){
        html+=buildPartyGameContent(d,names);
        render(html);
        window.scrollTo(0,Math.min(savedScroll,document.body.scrollHeight));
        return;
      }

      // Spades panels
      if(d.bids){
        if(d.gamePhase==='bidding') html+=buildSpadesBidPanel(d,me,names);
        else if(d.tricksWon) html+=buildSpadesPlayPanel(d,me,names);
      }

      // [82] Tricks-played progress bar (Hearts + Spades)
      if(d.tricksTotal!==undefined&&d.tricksTotal>0&&!d.isEuchre){
        var tTotal=+(d.tricksTotal||0),tMax=13;
        var tPct=Math.min(Math.round(tTotal/tMax*100),100);
        html+='<div class="tricks-bar"><div class="tricks-fill" style="width:'+tPct+'%"></div></div>';
      }
      // [84] Chess check indicator
      if(d.inCheck){
        var checkMe=(+(d.currentPlayer||0)===me);
        html+='<div class="check-banner">&#9888; CHECK!'+(checkMe?' — your king is in check!':'')+'</div>';
      }
      // [83] Chess material balance chip
      if(d.gameType==='chess'&&d.materialBalance!==undefined&&d.materialBalance!==0){
        var mb=+(d.materialBalance||0);
        var mySide=(me===0)?1:-1; // seat 0=white, seat 1=black
        var myAdv=mb*mySide;
        var mbStr=myAdv>0?('You +'+myAdv+' material'):('Opp +'+(Math.abs(myAdv))+' material');
        var mbCol=myAdv>0?'#a5d6a7':'#ef9a9a';
        html+='<div style="text-align:center;font-size:11px;color:'+mbCol+';padding:2px 10px 3px;font-weight:700">&#9812; '+esc(mbStr)+'</div>';
      }
      // [85] Checkers last move desc chip
      if(d.gameType==='checkers'){
        if(d.lastMoveDesc) html+='<div class="move-desc-chip">'+esc(d.lastMoveDesc)+'</div>';
        if(d.redPieces!==undefined&&d.blackPieces!==undefined){
          html+='<div style="display:flex;gap:6px;justify-content:center;padding:2px 10px 4px">'+
            '<span class="ichip" style="color:#ef9a9a">&#9898; Red: '+d.redPieces+'</span>'+
            '<span class="ichip" style="color:#e8eaf0">&#9899; Black: '+d.blackPieces+'</span>'+
            (d.movesWithoutCapture>30?'<span class="ichip" style="color:#ffd54f">'+d.movesWithoutCapture+' no-cap</span>':'')+'</div>';
        }
      }
      // [47][95] Euchre team tricks panel + streak pips
      if(d.isEuchre&&d.gamePhase==='playing'&&d.euchreTeamTricks){
        var me2=+(d.mySeat||0),myT=(me2%2),oppT=1-myT;
        var myTr=d.euchreTeamTricks[myT]||0,oppTr=d.euchreTeamTricks[oppT]||0;
        var isMaker=(d.makerTeam===myT);
        var myStreak=(d.euchreTeamStreak&&d.euchreTeamStreak[myT])||0;
        var oppStreak=(d.euchreTeamStreak&&d.euchreTeamStreak[oppT])||0;
        function streakHtml(n){if(n<2) return ''; var p='<div class="streak-pips">';for(var si=0;si<Math.min(n,5);si++)p+='<div class="streak-pip"></div>';return p+'</div>';}
        html+='<div class="euch-tricks">'+
          '<div class="euch-team'+(isMaker?' maker':'')+'">'+
          '<div class="euch-team-name">Your team'+(isMaker?' &#11088;':'')+'</div>'+
          '<div class="euch-team-count">'+myTr+'<span class="euch-star">'+ '&#9733;'.repeat(Math.max(0,myTr))+'&#9734;'.repeat(Math.max(0,3-myTr))+'</span></div>'+streakHtml(myStreak)+'</div>'+
          '<div class="euch-team'+((!isMaker)?' maker':'')+'">'+
          '<div class="euch-team-name">Opponents'+(isMaker?'':' &#11088;')+'</div>'+
          '<div class="euch-team-count">'+oppTr+'<span class="euch-star">'+ '&#9733;'.repeat(Math.max(0,oppTr))+'&#9734;'.repeat(Math.max(0,3-oppTr))+'</span></div>'+streakHtml(oppStreak)+'</div>'+
          '</div>';
      }

      // Compass trick view
      if(d.trick!==undefined) html+=buildCompassTrick(d);

      // [4] Bridge dummy hand
      if(d.dummyHand&&d.dummyHand.length) html+=buildDummyHand(d,names);

      // UNO active color + top card
      if(d.activeColor) html+=buildUnoColorBanner(d);
      if(d.topCard) html+=buildTopCard(d);

      // Turn or wait
      if(d.isMyTurn){
        if(!(d.moves&&d.moves.length)&&d.phase!=='passCards')
          html+='<div class="turn-card"><div class="turn-title">&#127775; Your Turn — tap a card</div></div>';
      } else {
        html+='<div class="wait-card"><p class="wait-txt">Waiting for <span class="wait-name">'+esc(d.currentPlayerName||'other player')+'</span></p></div>';
      }

      // Hearts pass direction banner
      if(d.phase==='passCards'){
        var dirLabel=d.passDirection||'';
        var dirArrow={left:'\\u2190',right:'\\u2192',across:'\\u2195','no passing':'\\u21BB'}[dirLabel]||'';
        html+='<div class="turn-card"><div class="turn-title">'+dirArrow+' Pass '+esc(dirLabel||'3 Cards')+'</div>'+
          '<div style="text-align:center;font-size:12px;color:rgba(255,255,255,.45);margin:4px 0 8px">Select 3 cards below</div>'+
          buildPass(d)+'</div>';
      } else if(d.isMyTurn&&d.moves&&d.moves.length){
        // [58] Euchre bidding: show large upcard visual above moves
        var euchBidHtml='';
        if(d.isEuchre&&d.gamePhase==='bidding'&&d.upcard){
          var er=rankOf(d.upcard),es=suitOf(d.upcard),eRed=d.upcardRed;
          euchBidHtml='<div class="euch-upcard-cta">'+
            '<p style="font-size:11px;color:rgba(255,255,255,.35);text-transform:uppercase;letter-spacing:.8px;margin-bottom:6px">Upcard</p>'+
            '<div class="euch-upcard-big '+(eRed?'red':'dark')+'">'+
              '<div style="font-size:14px;font-weight:900;line-height:1">'+esc(er)+'</div>'+
              '<div style="font-size:24px;line-height:1">'+esc(es)+'</div>'+
              '<div style="font-size:14px;font-weight:900;line-height:1;transform:rotate(180deg)">'+esc(er)+'</div>'+
            '</div></div>';
        }
        html+='<div class="turn-card">'+euchBidHtml+'<div style="margin-bottom:6px">'+buildMoves(d)+'</div></div>';
      }

      // Extra moves
      if(d.isMyTurn&&d.extraMoves&&d.extraMoves.length){
        html+='<div class="card">'+d.extraMoves.map(function(m){
          return '<button class="btn accent" onclick="haptic();doMove('+m.index+')">'+esc(m.label)+'</button>';
        }).join('')+'</div>';
      }

      // [3] Hearts received cards strip
      if(d.receivedCards&&d.receivedCards.length){
        var rk=d.receivedCards.map(function(c){return c.label;}).join(',');
        if(rk!==lastRecvKey){lastRecvKey=rk;}
        html+='<div class="recv-strip"><span class="recv-label">Received:</span>';
        d.receivedCards.forEach(function(c){
          var r=rankOf(c.label),s=suitOf(c.label);
          html+='<div class="recv-card'+(c.isRed?' red':'')+'">'+esc(r)+esc(s)+'</div>';
        });
        html+='</div>';
      }

      // Hand
      if(d.phase!=='passCards'){
        if(d.isUno) html+=buildUnoHand(d);
        else if(d.hand&&d.hand.length) html+=buildHand(d);
      }

      // [57] Opponent hand fan visualization
      if(!d.trick&&d.handSizes){
        var fanHtml='';
        d.handSizes.forEach(function(sz,i){
          if(i===me) return;
          var nm=(names[i]||'S'+(i+1)).substring(0,7);
          var spread=Math.min(sz,7),cardW=Math.max(8,Math.floor(36/Math.max(spread,1)));
          var fanW=Math.min(44,spread*cardW+6);
          var cards='';
          for(var ci=0;ci<spread;ci++){
            cards+='<div class="opp-fc" style="left:'+(ci*Math.floor((fanW-16)/Math.max(spread-1,1)))+'px;background:rgba('+(25+ci*5)+',50,120,.82);transform:rotate('+((-1*(spread-1)/2+ci)*3)+'deg);transform-origin:bottom center"></div>';
          }
          fanHtml+='<div class="opp-fan"><div class="opp-fan-cards" style="width:'+fanW+'px">'+cards+'</div>'+
            '<div class="opp-fan-count">'+sz+'</div>'+
            '<div class="opp-fan-name">'+esc(nm)+'</div></div>';
        });
        if(fanHtml) html+='<div class="opp-fans">'+fanHtml+'</div>';
      }

      if(d.books&&d.books.length)
        html+='<div class="ibar"><span class="ichip">Your books: '+esc(d.books.join(' '))+'</span></div>';

      // [34] GoFish: last event + opponent book counts
      if(d.lastEvent)
        html+='<div class="status-bar" style="color:rgba(129,212,250,.55);font-size:12px;padding:2px 16px 4px">'+esc(d.lastEvent)+'</div>';
      if(d.bookCounts&&d.bookCounts.length){
        var bcChips=[];
        d.bookCounts.forEach(function(cnt,i){
          if(i!==(+(d.mySeat||0))) bcChips.push('<span class="ichip">'+esc((names[i]||'S'+(i+1)).substring(0,7))+': &#128218;'+cnt+'</span>');
        });
        if(bcChips.length) html+='<div class="ibar">'+bcChips.join('')+'</div>';
      }
      // [76] GoFish pond fish visualization
      if(d.pondCount!==undefined){
        var pc=+(d.pondCount||0);
        var fishCount=Math.min(pc,12);
        var fishStr='';
        for(var fi=0;fi<fishCount;fi++) fishStr+='&#128032;';
        var pondPct=Math.round(pc/52*100);
        html+='<div style="text-align:center;padding:4px 10px 6px">'+
          '<span style="font-size:10px;color:rgba(255,255,255,.3);text-transform:uppercase;letter-spacing:.7px">Pond ('+pc+' cards / '+pondPct+'%)</span>'+
          '<div style="font-size:18px;line-height:1.4;letter-spacing:2px;margin-top:2px">'+(fishStr||'&#127932;')+'</div></div>';
      }

      render(html);
      // [7] Restore scroll position
      window.scrollTo(0,Math.min(savedScroll,document.body.scrollHeight));
    }

    // ── [9] Game-over ranking podium ───────────────────────────────────────────
    // [46] Confetti burst
    function launchConfetti(){
      var cols=['#ef5350','#42a5f5','#66bb6a','#ffca28','#ab47bc','#ff7043','#26c6da'];
      for(var i=0;i<38;i++){(function(i){setTimeout(function(){
        var el=document.createElement('div');
        el.className='cft';
        var ox=(Math.random()-.5)*window.innerWidth*.9;
        var oy=-100-Math.random()*window.innerHeight*.55;
        var cx=+(window.innerWidth*.3+Math.random()*window.innerWidth*.4).toFixed(0)+'px';
        var cy=+(window.innerHeight*.35+Math.random()*window.innerHeight*.2).toFixed(0)+'px';
        var dur=(1.1+Math.random()*.9).toFixed(2)+'s';
        var delay=(Math.random()*.45).toFixed(2)+'s';
        el.style.cssText='--cx0:'+cx+';--cy0:'+cy+';--cx1:'+(parseFloat(cx)+ox)+'px;--cy1:'+(parseFloat(cy)+Math.abs(oy))+'px;--cd:'+dur+';--cdy:'+delay+';--cr:'+(360+Math.random()*360).toFixed(0)+'deg;background:'+cols[i%cols.length];
        document.body.appendChild(el);
        setTimeout(function(){if(el.parentNode)el.remove();},2400);
      },i*35);})(i);}
    }

    function buildGameOver(d){
      playWinSound();   // [39]
      launchConfetti(); // [46]
      var names=d.seatNames||[];
      var me=+(d.mySeat||0);
      var medals=['\\uD83E\\uDD47','\\uD83E\\uDD48','\\uD83E\\uDD49'];
      // [60] Find local player's place
      var myPlace=-1,myMedal='';
      if(d.ranking&&d.ranking.length){
        d.ranking.forEach(function(group,place){
          if(group.indexOf(me)>=0){myPlace=place;myMedal=medals[place]||('#'+(place+1));}
        });
      }
      var rankHtml='';
      if(d.ranking&&d.ranking.length){
        d.ranking.forEach(function(group,place){
          var medal=medals[place]||('#'+(place+1));
          group.forEach(function(seat){
            var you=(seat===me);
            rankHtml+='<div style="display:flex;align-items:center;gap:10px;padding:7px 0;border-bottom:1px solid rgba(255,255,255,.07);'+(you?'background:rgba(100,181,246,.06);border-radius:8px;margin:-2px -4px;padding:7px 4px':'')+'">'+
              '<span style="font-size:20px">'+medal+'</span>'+
              '<span style="font-size:15px;font-weight:'+(you?'800':'600')+';color:'+(you?'#81d4fa':'#e8eaf0')+'">'+esc(names[seat]||('Seat '+(seat+1)))+(you?' \\u2190 You':'')+'</span>'+
              (you?'<span style="margin-left:auto;font-size:12px;color:#64b5f6;font-weight:700">You!</span>':'')+
              '</div>';
          });
        });
      }
      var resultParts=(d.resultText||'').split(' · ');
      var headline=esc(resultParts[0]||'Game Over');
      // [90] Richer stat pills: color-code bracket scores, highlight special achievements
      var statsHtml=resultParts.slice(1,7).map(function(p){
        var col='';
        // Detect bracketed score (e.g. "[100 80 70 50]")
        if(p.match(/^\\[[\\d\\s]+\\]$/)) col='color:#81d4fa';
        // Moon shot / achievements
        else if(p.indexOf('moon')>=0||p.indexOf('\\uD83C\\uDF19')>=0) col='color:#ce93d8';
        // Streaks
        else if(p.indexOf('streak')>=0||p.indexOf('\\uD83D\\uDD25')>=0) col='color:#ffb74d';
        // Perfect / shutout
        else if(p.indexOf('erfect')>=0||p.indexOf('hutout')>=0||p.indexOf('lean')>=0) col='color:#a5d6a7';
        return '<span class="ichip"'+(col?' style="'+col+'"':'')+'>'+esc(p)+'</span>';
      }).join('');
      // [60] Personal result spotlight banner
      var spotlightHtml='';
      if(myPlace>=0){
        var placeLabel=['1st Place','2nd Place','3rd Place'][myPlace]||('Place '+(myPlace+1));
        var isWin=myPlace===0;
        spotlightHtml='<div class="go-you-banner"><div class="go-you-rank">'+myMedal+'</div>'+
          '<div class="go-you-label">'+esc(placeLabel)+(isWin?' \\uD83C\\uDF89':'')+'</div></div>';
      }
      // [70] Score bar chart
      var chartHtml='';
      if(d.scores&&d.scores.length>1){
        var scoreArr=d.scores.map(function(s,i){return{s:+(s||0),i:i,nm:(names[i]||'P'+(i+1)).substring(0,7)};});
        var maxS=Math.max.apply(null,scoreArr.map(function(x){return Math.abs(x.s);}));
        var barColors=['#42a5f5','#ef5350','#66bb6a','#ffca28','#ab47bc','#ff7043'];
        chartHtml='<div class="score-chart"><p class="slabel" style="text-align:left;margin-bottom:6px">Final Scores</p>';
        scoreArr.forEach(function(x,ci){
          var frac=maxS>0?Math.abs(x.s)/maxS:0;
          var w=Math.round(Math.max(4,frac*100))+'%';
          var col=barColors[ci%barColors.length];
          chartHtml+='<div class="score-bar-row">'+
            '<div class="score-bar-name">'+esc(x.nm)+'</div>'+
            '<div class="score-bar-track"><div class="score-bar-fill" style="width:'+w+';background:'+col+'">'+
              '<div class="score-bar-val">'+x.s+'</div></div></div></div>';
        });
        chartHtml+='</div>';
      }
      return '<div class="card">'+
        '<div class="result-big">&#127881; Game Over!</div>'+
        spotlightHtml+
        '<div style="font-size:15px;font-weight:700;text-align:center;margin:6px 0 10px;color:#81d4fa">'+headline+'</div>'+
        (rankHtml?'<div style="padding:0 4px;margin-bottom:10px">'+rankHtml+'</div>':'')+
        chartHtml+
        (statsHtml?'<div class="ibar" style="margin-bottom:8px">'+statsHtml+'</div>':'')+
        '<button class="btn" onclick="clearSession();location.reload()">Play Again</button></div>';
    }

    // ── Info chips (trump, alone, [8] visual upcard, makers, bags, [33] contract) ──
    function buildInfoChips(d){
      var chips=[];
      if(d.trump) chips.push('<span class="chip trump">'+esc(d.trump)+' Trump</span>');
      if(d.goingAlone) chips.push('<span class="chip alone">&#9889; Going Alone</span>');
      // [8] Euchre upcard as visual mini playing card
      if(d.upcard){
        var r=rankOf(d.upcard),s=suitOf(d.upcard),isRed=d.upcardRed;
        chips.push('<span style="display:inline-flex;align-items:center;gap:5px"><span style="font-size:10px;color:rgba(255,255,255,.4);text-transform:uppercase;letter-spacing:.6px">Upcard</span>'+
          '<span class="mini-card'+(isRed?' red':' dark')+'">'+esc(r)+esc(s)+'</span></span>');
      }
      // Euchre makers
      if(d.makerTeam!==undefined&&d.trump&&d.gamePhase==='playing'){
        var me=+(d.mySeat||0),myTeam=(me%2);
        var makersLabel=(d.makerTeam===myTeam)?'Your team called':'Opponents called';
        chips.push('<span class="chip" style="background:rgba(100,181,246,.1);color:#90caf9;border-color:rgba(100,181,246,.22)">'+esc(makersLabel)+'</span>');
      }
      // Spades bags
      if(d.teamBags&&d.teamBags.length===2){
        var me2=+(d.mySeat||0),myT=(me2%2===0)?0:1;
        var myBags=d.teamBags[myT]%10,oppBags=d.teamBags[1-myT]%10;
        if(myBags>=7) chips.push('<span class="chip alone">&#127860; '+myBags+'/10 bags!</span>');
        else if(myBags>0) chips.push('<span class="chip" style="color:rgba(255,183,77,.8)">&#127860; '+myBags+' bags</span>');
        if(oppBags>=7) chips.push('<span class="chip" style="color:rgba(255,183,77,.65)">Opp '+oppBags+' bags</span>');
      }
      // [33] Bridge contract progress chip
      if(d.contractChip){
        var making=d.contractChip.indexOf('Making')>=0;
        var cColor=making?'#a5d6a7':'#ef9a9a';
        var cBg=making?'rgba(46,125,50,.18)':'rgba(183,28,28,.18)';
        chips.push('<span class="chip" style="background:'+cBg+';color:'+cColor+';border-color:'+cColor+'.3">'+esc(d.contractChip)+'</span>');
      }
      // [44] Hearts Q♠ lurking chip
      if(d.queenLurking) chips.push('<span class="chip alone" style="background:rgba(120,0,180,.16);color:#ce93d8;border-color:rgba(160,80,220,.3)">\\u2660 Q\\u2660 lurking!</span>');
      // [61] Bridge vulnerability chip
      if(d.vulLabel){
        var vd=(d.myVul?'danger':'safe');
        chips.push('<span class="vul-chip '+vd+'">'+esc(d.vulLabel)+'</span>');
      }
      return chips.length?'<div class="chip-row">'+chips.join('')+'</div>':'';
    }

    // ── Spades panels ───────────────────────────────────────────────────────────
    // [53] Spades hand suit breakdown — computed from d.hand
    function buildSpadesSuitStrip(hand){
      if(!hand||!hand.length) return '';
      var suits={'\\u2660':[],'\\u2665':[],'\\u2666':[],'\\u2663':[]};
      hand.forEach(function(c){var s=suitOf(c.label);if(suits[s])suits[s].push(rankOf(c.label));});
      var honorSet={'A':true,'K':true,'Q':true,'J':true};
      var html='<div style="display:grid;grid-template-columns:repeat(4,1fr);gap:4px;padding:4px 10px 6px">';
      ['\\u2660','\\u2665','\\u2666','\\u2663'].forEach(function(suit){
        var cards=suits[suit]||[],isRed=(suit==='\\u2665'||suit==='\\u2666');
        var honors=cards.filter(function(r){return honorSet[r];});
        var bg=isRed?'rgba(183,28,28,.14)':'rgba(30,30,60,.5)';
        html+='<div style="background:'+bg+';border-radius:8px;padding:5px 4px;text-align:center">'+
          '<div style="font-size:17px;color:'+(isRed?'#c62828':'#e8eaf0')+'">'+suit+'</div>'+
          '<div style="font-size:16px;font-weight:800;line-height:1">'+cards.length+'</div>'+
          (honors.length?'<div style="font-size:9px;color:#ffd54f;font-weight:700;letter-spacing:-.3px">'+esc(honors.join(''))+'</div>':'<div style="font-size:9px;color:rgba(255,255,255,.18)">—</div>')+
          '</div>';
      });
      return html+'</div>';
    }

    function buildSpadesBidPanel(d,me,names){
      var bids=d.bids||[],active=+(d.currentPlayer||0);
      var html='<div style="padding:0 10px 2px"><p class="slabel" style="margin-bottom:4px">Bidding</p><div class="bids-grid">';
      bids.forEach(function(b,i){
        var isMe=(i===me),isActive=(i===active&&b==='?');
        var isNil=(b==='Nil');
        var cls='bid-cell'+(isMe?' me':(isActive?' cur':''));
        var dispVal=isActive?'&#8943;':(isNil?'&#128737;':esc(String(b)));
        var dispColor=isNil?'#81d4fa':'';
        html+='<div class="'+cls+'"><div class="bid-name">'+esc((names[i]||'S'+(i+1)).substring(0,8))+'</div>'+
          '<div class="bid-val"'+(dispColor?' style="color:'+dispColor+'"':'')+'>'+dispVal+'</div></div>';
      });
      html+='</div>';
      // [53] My hand suit strength strip during bidding
      if(d.isMyTurn&&d.hand&&d.hand.length) html+=buildSpadesSuitStrip(d.hand);
      html+='</div>';
      return html;
    }

    function buildSpadesPlayPanel(d,me,names){
      var bids=d.bids||[],tricks=d.tricksWon||[];
      var html='<div style="padding:0 10px 2px"><p class="slabel" style="margin-bottom:4px">Tricks</p><div class="bids-grid">';
      bids.forEach(function(b,i){
        var isMe=(i===me),t=tricks[i]||0,bid=String(b);
        var isNil=(bid==='Nil'),nilBusted=(isNil&&t>0);
        var nilMade=(isNil&&t===0);
        var ok=(!isNil)&&(bid!=='?')&&(t>=parseInt(bid));
        var color=ok?'#a5d6a7':(nilBusted?'#ef9a9a':(nilMade?'#81d4fa':'#e8eaf0'));
        var bidDisp=isNil?'&#128737;':esc(bid);
        var flag=nilBusted?'<span style="font-size:9px;margin-left:2px">&#10060;</span>':'';
        html+='<div class="bid-cell'+(isMe?' me':'')+'"><div class="bid-name">'+esc((names[i]||'S'+(i+1)).substring(0,8))+'</div>'+
          '<div class="bid-val" style="color:'+color+'">'+t+'<span style="font-size:10px;color:rgba(255,255,255,.4)">/'+bidDisp+'</span>'+flag+'</div></div>';
      });
      html+='</div></div>';
      return html;
    }

    // ── [6] Score row with delta badges ────────────────────────────────────────
    function buildScoreRow(d){
      var me=+(d.mySeat||0),names=d.seatNames||[];
      var partnerSeat=(d.partnerSeat!=null)?+d.partnerSeat:-1,active=+(d.currentPlayer||0);
      var rpts=d.roundPoints;  // [72] Hearts round points array
      // [87] Hearts danger coloring: high points this round = bad
      var isHeartsScoring=!d.teamScores&&rpts&&rpts.length>0;
      var html='<div class="score-row">';
      if(d.teamScores&&d.teamScores.length===2){
        var myTeam=(me%2===0)?0:1,oppTeam=1-myTeam;
        var myLabel=d.partnerName?('You & '+d.partnerName.split(' ')[0]):'Your Team';
        var myDelta=prevTeamScores?(d.teamScores[myTeam]-prevTeamScores[myTeam]):0;
        var oppDelta=prevTeamScores?(d.teamScores[oppTeam]-prevTeamScores[oppTeam]):0;
        html+='<div class="score-cell me" style="flex:2"><div class="score-name">'+esc(myLabel)+'</div><div class="score-you">Your Team</div><div class="score-val">'+d.teamScores[myTeam]+deltaHtml(myDelta)+'</div></div>';
        html+='<div class="score-cell" style="flex:2"><div class="score-name">Opponents</div><div class="score-sub">&nbsp;</div><div class="score-val">'+d.teamScores[oppTeam]+deltaHtml(oppDelta)+'</div></div>';
        prevTeamScores=d.teamScores.slice();
      } else if(d.scores){
        d.scores.forEach(function(s,i){
          var baseRpt=rpts&&rpts[i]!==undefined?+(rpts[i]):null;
          // [87] Hearts danger coloring
          var dangerCls='';
          if(isHeartsScoring&&baseRpt!==null){
            if(baseRpt>=5) dangerCls=' hearts-danger';
            else if(baseRpt===0) dangerCls=' hearts-ok';
          }
          var cls='score-cell'+(i===me?' me':(i===partnerSeat?' partner':(i===active?' active':'')))+dangerCls;
          var delta=prevScores?(s-prevScores[i]):0;
          // [72] Round points chip: show how many pts this seat has taken this round
          var rptHtml='';
          if(baseRpt!==null){
            if(baseRpt>0) rptHtml='<span class="rpt-chip warn">+'+baseRpt+' this rnd</span>';
            else rptHtml='<span class="rpt-chip ok">0 pts</span>';
          }
          html+='<div class="'+cls+'"><div class="score-name">'+esc((names[i]||'S'+(i+1)).substring(0,7))+'</div>';
          if(i===me) html+='<div class="score-you">You</div>';
          else if(i===partnerSeat) html+='<div class="score-par">Partner</div>';
          else html+='<div class="score-sub">&nbsp;</div>';
          // [98] Score trend arrow (▲ = went up / worse for Hearts; ▼ = went down / better)
          var trendHtml='';
          if(scoreTrends&&scoreTrends[i]!==undefined&&scoreTrends[i]!==0){
            var isUp=scoreTrends[i]>0;
            // For Hearts (no teamScores, has roundPoints), higher=worse; otherwise higher=better
            var isBadGame=!!(d.roundHistory||d.roundPoints);
            var upClass=(isBadGame?'up':'down'),downClass=(isBadGame?'down':'up');
            trendHtml='<span class="score-trend '+(isUp?upClass:downClass)+'">'+(isUp?'▲':'▼')+'</span>';
          }
          html+='<div class="score-val">'+s+trendHtml+deltaHtml(delta)+'</div>'+rptHtml+'</div>';
        });
        // Update trend tracking from roundHistory if available
        if(d.roundHistory&&d.roundHistory.length>=1){
          var rh=d.roundHistory[0]||[];
          scoreTrends=rh.map(function(pts){return pts;});
        }
        prevScores=d.scores.slice();
      }
      html+='</div>';
      return html;
    }
    function deltaHtml(delta){
      if(!delta) return '';
      // [54] Larger delta with pop + rise animation (always recreated per poll so always fires)
      var cls=delta>0?'pos':'neg';
      var size=Math.abs(delta)>=10?'13px':'11px';
      return '<div class="s-delta '+cls+'" style="font-size:'+size+'">'+(delta>0?'+':'')+delta+'</div>';
    }

    // ── [4] Bridge dummy hand ───────────────────────────────────────────────────
    function buildDummyHand(d,names){
      var ds=+(d.dummySeat||0);
      var name=(names[ds]||'Dummy').split(' ')[0];
      var hand=d.dummyHand||[];
      // Group by suit
      var bySuit={'\\u2660':[],'\\u2665':[],'\\u2666':[],'\\u2663':[]};
      hand.forEach(function(c){var s=suitOf(c.label);if(bySuit[s])bySuit[s].push(c);});
      var html='<div class="card dummy-zone"><p class="slabel">'+esc(name)+' (Dummy)</p><div class="dummy-suits">';
      ['\\u2660','\\u2665','\\u2666','\\u2663'].forEach(function(suit){
        var cards=bySuit[suit]; if(!cards.length) return;
        var isRed=(suit==='\\u2665'||suit==='\\u2666');
        html+='<div class="dummy-suit-row"><span class="dummy-suit-sym" style="color:'+(isRed?'#c62828':'#e8eaf0')+'">'+suit+'</span>';
        cards.forEach(function(c){
          html+='<div class="dummy-c'+(isRed?' red':'')+'">'+esc(rankOf(c.label))+'</div>';
        });
        html+='</div>';
      });
      html+='</div></div>';
      return html;
    }

    // ── Compass trick view ──────────────────────────────────────────────────────
    function buildCompassTrick(d){
      var trick=d.trick||[],names=d.seatNames||[],n=names.length||4;
      var me=+(d.mySeat||0),partnerSeat=(d.partnerSeat!=null)?+d.partnerSeat:-1;
      var played={},tricksWon=d.tricksWon||[];
      trick.forEach(function(tp){played[tp.seat]=tp;});
      var slots=['compass-bottom','compass-left','compass-top','compass-right'];
      var html='<div class="card"><p class="slabel">Table</p><div class="compass">';
      for(var rel=0;rel<Math.min(n,4);rel++){
        var seat=(me+rel)%n;
        var tp=played[seat];
        var name=(names[seat]||('S'+(seat+1))).substring(0,9);
        var isMe=(seat===me),isPartner=(seat===partnerSeat);
        var nc='trick-name'+(isMe?' ml':(isPartner?' pl':''));
        var tally=tricksWon[seat];
        var tallyStr=(tally>0)?('<div class="trick-tally">'+tally+'&#10003;</div>'):'';
        var cardHtml=tp?
          '<div class="trick-card'+(tp.isRed?' red':'')+'" style="font-size:15px">'+esc(rankOf(tp.label))+esc(suitOf(tp.label))+'</div>':
          '<div class="trick-card empty"></div>';
        if(rel===0){
          html+='<div class="trick-zone '+slots[rel]+'">'+cardHtml+'<div class="'+nc+'">'+esc(name)+'</div>'+tallyStr+'</div>';
        } else {
          html+='<div class="trick-zone '+slots[rel]+'"><div class="'+nc+'">'+esc(name)+'</div>'+cardHtml+tallyStr+'</div>';
        }
      }
      html+='<div class="compass-center" style="background:rgba(255,255,255,.05);border-radius:8px;width:22px;height:22px;border:1px solid rgba(255,255,255,.12)"></div>';
      html+='</div></div>';
      return html;
    }

    // ── [6] UNO active color banner + [35] draw pile LOW! ─────────────────────
    function buildUnoColorBanner(d){
      var colors={red:'#c62828',yellow:'#e65100',green:'#2e7d32',blue:'#1565c0'};
      var emoji={red:'&#128308;',yellow:'&#129001;',green:'&#128994;',blue:'&#128309;'};
      var bg=colors[d.activeColor]||'#263238';
      var em=emoji[d.activeColor]||'';
      var drawInfo=d.pendingDraw?(' · +'+d.pendingDraw+' stacked'):'';
      var html='<div style="margin:4px 10px;padding:8px 12px;background:'+bg+
        ';border-radius:12px;display:flex;align-items:center;gap:8px;justify-content:center">'+
        '<span style="font-size:20px">'+em+'</span>'+
        '<span style="font-size:14px;font-weight:700;color:#fff">'+esc(d.activeColor||'')+(drawInfo?'<span style="opacity:.7;font-size:12px">'+esc(drawInfo)+'</span>':'')+'</span>'+
        '</div>';
      // [35] Draw pile count with LOW! warning
      if(d.drawPileCount!==undefined){
        var low=d.drawPileCount<=5;
        var pileColor=low?'#ef9a9a':'rgba(255,255,255,.35)';
        var pileText='&#127924; '+(low?'LOW! ':'')+'Draw: '+d.drawPileCount;
        html+='<div style="text-align:center;font-size:11px;color:'+pileColor+';font-weight:'+(low?700:400)+';padding:0 0 4px">'+pileText+'</div>';
      }
      return html;
    }

    // ── Top card ────────────────────────────────────────────────────────────────
    function buildTopCard(d){
      var bg=d.topCardColor?unoCSS(d.topCardColor):(d.topCardRed?'#b71c1c':'#1a2035');
      var info='';
      if(d.activeSuit) info='Suit: '+d.activeSuit;
      if(d.pendingDraw&&!d.activeColor) info+=(info?' · ':'')+'+'+d.pendingDraw+' stacked';
      return '<div class="card"><p class="slabel">Discard</p><div class="top-card-row">'+
        '<div class="hcard" style="background:'+bg+';border:none;min-width:50px;min-height:62px;pointer-events:none">'+
        '<div class="rank" style="color:#fff">'+esc(d.topCard)+'</div></div>'+
        (info?'<span style="font-size:14px;color:rgba(255,255,255,.55)">'+esc(info)+'</span>':'')+
        '</div></div>';
    }

    // ── [8] Hand with suit sorting ──────────────────────────────────────────────
    function sortHand(hand){
      return hand.slice().sort(function(a,b){
        // [63] Respect sort mode
        if(handSortMode==='rank'){
          var rv=rankVal(rankOf(b.label))-rankVal(rankOf(a.label));
          if(rv!==0) return rv;
          return suitOrder(suitOf(a.label))-suitOrder(suitOf(b.label));
        }
        var sa=suitOrder(suitOf(a.label)),sb=suitOrder(suitOf(b.label));
        if(sa!==sb) return sa-sb;
        return rankVal(rankOf(b.label))-rankVal(rankOf(a.label));
      });
    }

    function buildHand(d){
      var h=sortHand(d.hand||[]); if(!h.length) return '';
      // [63] Sort toggle
      var sortLabel=handSortMode==='suit'?'A-K':'Suit';
      var html='<div class="card"><p class="slabel">Your Hand ('+h.length+')'+
        '<button class="sort-toggle" onclick="handSortMode=handSortMode===\'suit\'?\'rank\':\'suit\';renderState(lastState)">'+sortLabel+'</button></p>';
      if(pendingEight!==null&&d.eightMoves){
        // find the card we tapped (by label since we sorted)
        var origH=d.hand||[]; var hc=null;
        if(origH[pendingEight]) hc=origH[pendingEight];
        var found=null;
        if(hc) d.eightMoves.forEach(function(em){if(em.card===hc.label)found=em;});
        if(!found){
          // try searching sorted hand
          var sh=sortHand(origH);
          hc=sh[pendingEight];
          if(hc) d.eightMoves.forEach(function(em){if(em.card===hc.label)found=em;});
        }
        if(found){
          html+='<div class="suit-row"><p style="font-size:13px;color:rgba(255,255,255,.5);margin-bottom:6px;width:100%;text-align:center">Pick suit for '+esc((hc||{}).label||'')+':</p>';
          (found.suits||[]).forEach(function(s){html+='<button class="sbtn" onclick="haptic();doMove('+s.index+');pendingEight=null">'+esc(s.suit)+'</button>';});
          html+='</div><button class="btn" style="margin:6px 0 0;font-size:14px" onclick="pendingEight=null;renderState(lastState)">Cancel</button></div>';
          return html;
        }
        pendingEight=null;
      }
      // Group by suit with dividers
      var lastSuit=null;
      html+='<div class="hgrid">';
      h.forEach(function(c,i){
        var s=suitOf(c.label);
        if(lastSuit!==null&&s!==lastSuit){
          // suit divider: close and reopen grid to create visual gap
          html+='</div><div style="height:5px"></div><div class="hgrid">';
        }
        lastSuit=s;
        var red=c.isRed,dim=!c.legal;
        // [26] Hearts danger indicators: Q♠ and J♥+
        var isDanger=false;
        if(d.scores&&!d.teamScores&&d.trick!==undefined){
          var dr=rankOf(c.label),ds=suitOf(c.label);
          isDanger=(ds==='\\u2660'&&dr==='Q')||(c.isRed&&ds==='\\u2665'&&rankVal(dr)>=11);
        }
        // [31] Euchre bidding: use .peek (visible but non-interactive) instead of .dim
        var isBidding=(d.gamePhase==='bidding');
        var cls='hcard'+(red?' red':'')+(isBidding?' peek':(dim?' dim':''))+((!isBidding&&c.legal)?' legal':'')+(isDanger?' danger':'');
        var r=rankOf(c.label);
        // [38] Long-press zoom: ontouchstart/ontouchend on every card
        var zoomAttrs='ontouchstart="startZoom(event,\\''+esc(r)+'\\',\\''+esc(s)+'\\','+red+')" ontouchend="cancelZoom()" ontouchmove="cancelZoom()"';
        var inner='<div class="rank">'+esc(r)+'</div><div class="suit-big">'+esc(s)+'</div><div class="rank-bot">'+esc(r)+'</div>';
        var ariaLbl='aria-label="'+esc(c.label)+'"';
        if(!isBidding&&c.legal&&c.moveIdx!==undefined)
          html+='<div class="'+cls+'" '+ariaLbl+' role="button" tabindex="0" '+zoomAttrs+' onclick="haptic();playCardSound();doMove('+c.moveIdx+')">'+inner+'</div>';
        else if(!isBidding&&c.legal&&c.isEight)
          html+='<div class="'+cls+'" '+ariaLbl+' role="button" tabindex="0" '+zoomAttrs+' onclick="haptic();playCardSound();pendingEight='+i+';renderState(lastState)">'+inner+'</div>';
        else
          html+='<div class="'+cls+'" '+ariaLbl+' '+zoomAttrs+'>'+inner+'</div>';
      });
      html+='</div></div>'; return html;
    }

    // ── UNO hand ────────────────────────────────────────────────────────────────
    function buildUnoHand(d){
      var h=d.hand||[]; if(!h.length) return '';
      var html='<div class="card"><p class="slabel">Your Hand ('+h.length+')</p>';
      if(pendingUnoId!==null){
        var found=null; h.forEach(function(c){if(c.id===pendingUnoId)found=c;});
        if(found&&found.colorChoices){
          // [52] Large 2×2 wild color picker
          var colorEmoji={red:'&#128308;',yellow:'&#129001;',green:'&#128994;',blue:'&#128309;'};
          html+='<p style="text-align:center;font-size:13px;color:rgba(255,255,255,.45);margin:2px 0 10px">Pick a color for your Wild:</p>';
          html+='<div style="display:grid;grid-template-columns:1fr 1fr;gap:10px;padding:0 6px">';
          found.colorChoices.forEach(function(ch){
            html+='<button style="background:'+unoCSS(ch.color)+';border:none;border-radius:16px;padding:20px 8px;cursor:pointer;font-size:26px;font-weight:800;color:#fff;box-shadow:0 4px 18px rgba(0,0,0,.35);transition:transform .1s;display:flex;flex-direction:column;align-items:center;gap:4px" '+
              'onclick="haptic(20);doMove('+ch.index+');pendingUnoId=null" onpointerdown="this.style.transform=\'scale(.94)\'" onpointerup="this.style.transform=\'\'">'+
              (colorEmoji[ch.color]||'')+'<span style="font-size:14px;text-transform:capitalize">'+esc(ch.color)+'</span></button>';
          });
          html+='</div>';
          html+='<button class="btn" style="margin:10px 0 0;font-size:14px" onclick="pendingUnoId=null;renderState(lastState)">Cancel</button></div>';
          return html;
        }
        pendingUnoId=null;
      }
      html+='<div class="hgrid">';
      h.forEach(function(c){
        var bg=unoCSS(c.color),dim=!c.legal;
        var cls='uno-ctile'+(dim?' dim':'')+(c.legal?' legal':'');
        if(c.legal&&c.moveIdx!==undefined)
          html+='<div class="'+cls+'" style="background:'+bg+'" onclick="haptic();doMove('+c.moveIdx+')">'+esc(c.label)+'</div>';
        else if(c.legal&&c.colorChoices)
          html+='<div class="'+cls+'" style="background:'+bg+'" onclick="haptic();pendingUnoId='+c.id+';renderState(lastState)">'+esc(c.label)+'</div>';
        else
          html+='<div class="'+cls+'" style="background:'+bg+'">'+esc(c.label)+'</div>';
      });
      html+='</div></div>'; return html;
    }

    function unoCSS(c){return{red:'#c62828',yellow:'#e65100',green:'#2e7d32',blue:'#1565c0'}[c]||'#37474f';}

    // ── [5] GoFish rank picker + [7] bridge auction + other moves ──────────────
    function bridgeSuitColor(label){
      if(label==='Pass') return 'rgba(255,255,255,.12)';
      if(label==='Dbl') return 'rgba(239,83,80,.3)';
      if(label==='Rdbl') return 'rgba(255,152,0,.3)';
      if(label.indexOf('\\u2663')>=0) return 'rgba(46,125,50,.35)';   // ♣ green
      if(label.indexOf('\\u2666')>=0) return 'rgba(21,101,192,.35)';  // ♦ blue
      if(label.indexOf('\\u2665')>=0) return 'rgba(183,28,28,.35)';   // ♥ red
      if(label.indexOf('\\u2660')>=0) return 'rgba(50,50,70,.5)';     // ♠ dark
      return 'rgba(80,80,100,.35)'; // NT silver
    }

    function buildMoves(d){
      var m=d.moves||[];
      // [55] GoFish: enhanced rank picker with "I have N" count badges
      if(m.length>0&&m.every(function(x){return x.label.indexOf('Ask for ')===0;})){
        var myRankCounts={};
        (d.hand||[]).forEach(function(c){var r=rankOf(c.label);myRankCounts[r]=(myRankCounts[r]||0)+1;});
        return '<p style="text-align:center;font-size:11px;color:rgba(255,255,255,.36);margin:0 0 6px">Ask your opponent for:</p>'+
          '<div class="rank-grid">'+m.map(function(x){
            var rank=x.label.replace('Ask for ','').replace(/s$/,'');
            var cnt=myRankCounts[rank]||0;
            var badge=cnt>0?'<span style="position:absolute;top:-4px;right:-4px;background:#ffd54f;color:#111;font-size:8px;font-weight:900;border-radius:50%;width:14px;height:14px;line-height:14px;text-align:center;display:block">'+cnt+'</span>':'';
            return '<button class="rank-btn" style="position:relative" onclick="haptic();doMove('+x.index+')">'+esc(rank)+badge+'</button>';
          }).join('')+'</div>';
      }
      // [7] Bridge auction: color-coded bid buttons
      if(d.gamePhase==='auction'&&m.length>3){
        var html='<div style="display:grid;grid-template-columns:repeat(4,1fr);gap:5px">';
        m.forEach(function(x){
          var bg=bridgeSuitColor(x.label);
          var textCol=x.label==='Pass'?'rgba(255,255,255,.55)':'#e8eaf0';
          html+='<button style="background:'+bg+';border:1px solid rgba(255,255,255,.15);border-radius:9px;color:'+textCol+
            ';font-size:14px;font-weight:700;padding:11px 2px;cursor:pointer;transition:opacity .1s" '+
            'onclick="haptic();doMove('+x.index+')" onactive="this.style.opacity=.6">'+esc(x.label)+'</button>';
        });
        html+='</div>';
        return html;
      }
      // Trivia A/B/C/D
      if(m.length===4&&m.every(function(x){return /^[A-D]$/.test(x.label)})){
        var html2='';
        if(d.triviaCategory) html2+='<p class="qcat">'+esc(d.triviaCategory)+'</p>';
        if(d.triviaQuestion) html2+='<div class="qcard" style="margin:0 0 10px">'+esc(d.triviaQuestion)+'</div>';
        html2+='<div class="agrid">'+m.map(function(x){
          var desc=x.desc?'<span class="adesc">'+esc(x.desc)+'</span>':'';
          return '<button class="abtn" onclick="haptic();doMove('+x.index+')"><span class="aletter">'+esc(x.label)+'</span>'+desc+'</button>';
        }).join('')+'</div>';
        return html2;
      }
      // [32] Numeric bid grid with recommended bid chip
      if(m.length>=4&&m.every(function(x){return !isNaN(parseInt(x.label))||x.label==='Nil'||x.label==='Pass'})){
        var rec=d.recommendedBid!==undefined?+(d.recommendedBid):-1;
        var recHtml=rec>=0?'<div style="text-align:center;margin-bottom:6px"><span style="background:rgba(0,172,193,.2);color:#4dd0e1;border:1px solid rgba(0,188,212,.3);border-radius:7px;padding:3px 10px;font-size:12px;font-weight:700">Rec: '+rec+'</span></div>':'';
        return recHtml+'<div class="bgrid">'+m.map(function(x){
          var isRec=(rec>=0&&String(rec)===x.label);
          return '<button class="bbtn" style="'+(isRec?'border-color:#4dd0e1;background:rgba(0,172,193,.2);color:#4dd0e1':'')
            +'" onclick="haptic();doMove('+x.index+')">'+esc(x.label)+'</button>';
        }).join('')+'</div>';
      }
      return m.map(function(x){return '<button class="btn" aria-label="'+esc(x.label)+'" onclick="haptic();doMove('+x.index+')">'+esc(x.label)+'</button>';}).join('');
    }

    // ── [2] Pass with direction banner ──────────────────────────────────────────
    function buildPass(d){
      passSelected=[];
      var hand=sortHand(d.hand||[]),count=d.passCount||3;
      // [56] Pass tray: 3 card slots showing selected cards
      var html='<div class="pass-tray" id="ptray">';
      for(var ti=0;ti<count;ti++) html+='<div class="pass-slot" id="pt'+ti+'">?</div>';
      html+='</div>';
      html+='<p id="pcnt" style="text-align:center;font-size:12px;color:rgba(255,255,255,.4);margin-bottom:8px">Tap '+count+' cards to pass</p>';
      html+='<div class="hgrid" id="pgrid">';
      hand.forEach(function(c,i){
        var red=c.isRed,r=rankOf(c.label),s=suitOf(c.label);
        html+='<div class="hcard legal'+(red?' red':'')+'" id="pc'+i+'" onclick="haptic(8);togglePass(\\''+esc(c.label)+'\\','+i+',\\''+esc(r+s)+'\\')">'+
          '<div class="rank">'+esc(r)+'</div><div class="suit-big">'+esc(s)+'</div><div class="rank-bot">'+esc(r)+'</div></div>';
      });
      html+='</div><button class="btn accent" id="passbtn" style="display:none;margin-top:8px" onclick="haptic();submitPass()">Pass Selected &#10140;</button>';
      return html;
    }

    function togglePass(label,idx,display){
      var el=document.getElementById('pc'+idx); if(!el) return;
      var pos=passSelected.indexOf(label);
      if(pos>=0){passSelected.splice(pos,1);el.classList.remove('sel');}
      else if(passSelected.length<3){passSelected.push(label);el.classList.add('sel');}
      // [56] Update tray
      for(var ti=0;ti<3;ti++){
        var slot=document.getElementById('pt'+ti);
        if(!slot) continue;
        var lbl=passSelected[ti]||'?';
        var filled=ti<passSelected.length;
        slot.className='pass-slot'+(filled?' filled':'');
        slot.textContent=lbl;
      }
      var btn=document.getElementById('passbtn'),cnt=document.getElementById('pcnt');
      if(btn){btn.style.display=passSelected.length===3?'block':'none';}
      if(cnt) cnt.textContent='Tap 3 cards ('+passSelected.length+'/3 selected)';
    }

    async function submitPass(){
      submitting=true;
      var d=await api('POST','/api/move',{id:sid,passLabels:passSelected});
      submitting=false;
      if(!d.error) doPoll();
      else {var e=document.createElement('p');e.className='err';e.textContent=d.error;var c=document.querySelector('.turn-card');if(c)c.appendChild(e);}
    }

    // ── [10] Post-move checkmark flash ─────────────────────────────────────────
    function showCheckFlash(){
      var old=document.getElementById('chkflash');if(old)old.remove();
      var el=document.createElement('div');el.id='chkflash';el.textContent='\\u2705';
      document.body.appendChild(el);
      setTimeout(function(){if(el.parentNode)el.remove();},900);
    }

    // ── Move submit with haptic + visual feedback ───────────────────────────────
    async function doMove(idx){
      if(submitting) return;
      submitting=true;
      pendingEight=null; pendingUnoId=null;
      document.querySelectorAll('.hcard.legal,.uno-ctile.legal,.bbtn,.abtn').forEach(function(b){b.style.opacity='0.32';b.style.pointerEvents='none';});
      var d=await api('POST','/api/move',{id:sid,moveIndex:idx});
      submitting=false;
      if(d.error){
        document.querySelectorAll('.hcard.legal,.uno-ctile.legal,.bbtn,.abtn').forEach(function(b){b.style.opacity='';b.style.pointerEvents='';});
        if(d.error.indexOf('expired')>=0){clearSession();showJoin();return;}
        var el=document.createElement('p');el.className='err';el.textContent=d.error;
        var c=document.querySelector('.turn-card,.card');if(c)c.appendChild(el);
      } else { showCheckFlash(); doPoll(); }
    }

    // ── [36] Re-poll immediately when tab/screen becomes visible ───────────────
    document.addEventListener('visibilitychange',function(){
      if(!document.hidden&&sid){clearTimeout(pollTimer);doPoll();}
    });

    // ── [39] Web Audio API — subtle sounds ────────────────────────────────────
    var audioCtx=null;
    function getAudioCtx(){
      if(!audioCtx) try{audioCtx=new(window.AudioContext||window.webkitAudioContext)();}catch(e){}
      return audioCtx;
    }
    function playTone(freq,dur,vol,type){
      var ctx=getAudioCtx(); if(!ctx) return;
      try{
        var o=ctx.createOscillator(),g=ctx.createGain();
        o.type=type||'sine'; o.frequency.value=freq;
        g.gain.setValueAtTime(vol||0.12,ctx.currentTime);
        g.gain.exponentialRampToValueAtTime(0.001,ctx.currentTime+dur);
        o.connect(g); g.connect(ctx.destination);
        o.start(); o.stop(ctx.currentTime+dur);
      }catch(e){}
    }
    function playCardSound(){playTone(660,0.07,0.1,'sine');}
    function playTurnSound(){playTone(880,0.09,0.12,'sine');setTimeout(function(){playTone(1100,0.09,0.10,'sine');},95);}
    function playWinSound(){[880,1100,1320].forEach(function(f,i){setTimeout(function(){playTone(f,0.18,0.14,'sine');},i*90);});}

    // ── [38] Long-press card zoom overlay ────────────────────────────────────
    var zoomTimer=null,zoomEl=null;
    function startZoom(evt,rank,suit,isRed){
      if(zoomTimer) clearTimeout(zoomTimer);
      zoomTimer=setTimeout(function(){
        haptic(30);
        var old=document.getElementById('card-zoom');if(old)old.remove();
        zoomEl=document.createElement('div');
        zoomEl.id='card-zoom';
        zoomEl.className=isRed?'red':'dark';
        zoomEl.innerHTML='<div class="zr">'+esc(rank)+'</div><div class="zs">'+esc(suit)+'</div><div class="zrb">'+esc(rank)+'</div>';
        document.body.appendChild(zoomEl);
      },360);
    }
    function cancelZoom(){
      if(zoomTimer){clearTimeout(zoomTimer);zoomTimer=null;}
      if(zoomEl){zoomEl.remove();zoomEl=null;}
    }

    // ── [40] Scroll-to-hand FAB ───────────────────────────────────────────────
    function fabTapped(){
      haptic();
      var hand=document.querySelector('#app .hgrid,.uno-ctile');
      if(hand) hand.closest('.card')
        ? hand.closest('.card').scrollIntoView({behavior:'smooth',block:'start'})
        : hand.scrollIntoView({behavior:'smooth',block:'start'});
    }
    window.addEventListener('scroll',function(){
      var fab=document.getElementById('fab'); if(!fab||!lastState||lastState.isOver) return;
      var hand=document.querySelector('#app .hgrid');
      if(!hand){fab.style.display='none';return;}
      var rect=hand.getBoundingClientRect();
      fab.style.display=rect.top>window.innerHeight+60?'flex':'none';
    },{passive:true});

    // ── [37] Hearts round history toggle ─────────────────────────────────────
    function toggleHist(){
      var b=document.getElementById('hist-body'); if(!b) return;
      b.classList.toggle('open');
      var h=document.getElementById('hist-head-arrow');
      if(h) h.textContent=b.classList.contains('open')?'▲':'▼';
    }
    function buildRoundHistory(d,names){
      var rh=d.roundHistory; if(!rh||!rh.length) return '';
      var sNames=names.slice(0,4);
      var cols='grid-template-columns:40px '+sNames.map(function(){return '1fr';}).join(' ');
      var headerCells=sNames.map(function(n){return '<span style="color:rgba(255,255,255,.5);text-align:right;padding:0 4px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">'+esc(n.substring(0,6))+'</span>';}).join('');
      var rows='<div class="hist-row" style="'+cols+'"><span style="color:rgba(255,255,255,.3)">Rnd</span>'+headerCells+'</div>';
      var base=+(d.roundNumber||rh.length);
      rh.forEach(function(round,i){
        var rnum=base-i;
        var cells=round.map(function(pts){
          var col=pts===0?'rgba(255,255,255,.3)':(pts>0?'#ef9a9a':'#a5d6a7');
          return '<span style="color:'+col+';text-align:right;font-weight:700;padding:0 4px">'+(pts>0?'+':'')+pts+'</span>';
        }).join('');
        rows+='<div class="hist-row" style="'+cols+'"><span style="color:rgba(255,255,255,.3)">'+rnum+'</span>'+cells+'</div>';
      });
      return '<div class="hist-panel">'+
        '<div class="hist-header" onclick="toggleHist()"><span>Score History ('+rh.length+' rounds)</span><span id="hist-head-arrow">▼</span></div>'+
        '<div class="hist-body" id="hist-body">'+rows+'</div></div>';
    }

    // ── [22] Party game content dispatcher ─────────────────────────────────────
    function buildPartyGameContent(d,names){
      var gt=d.gameType,phase=d.phase||'';
      if(gt==='promptParty') return buildPromptParty(d,names,phase);
      if(gt==='bluff') return buildBluffGame(d,names,phase);
      if(gt==='jackAttack') return buildJackAttack(d,names);
      if(gt==='starParty') return buildStarParty(d,names);
      if(gt==='klondike') return buildKlondike(d,names);
      if(gt==='bomberman') return buildBombermanHUD(d,names);
      // [73-75] Arcade spectator HUDs
      if(gt==='tetris'||gt==='snake'||gt==='capsules') return buildArcadeSpectator(d);
      // [94] FreeCell spectator HUD
      if(gt==='freecell') return buildFreeCellHUD(d);
      return '';
    }

    // ── [73-75][91-93] Arcade spectator HUD (Tetris / Snake / Capsules) ──────────
    function buildArcadeSpectator(d){
      var icons={tetris:'&#127911;',snake:'&#127822;',capsules:'&#128138;'};
      var titles={tetris:'Tetris',snake:'Snake',capsules:'Capsules'};
      var gt=d.gameType||'';
      var icon=icons[gt]||'&#127918;',title=titles[gt]||gt;
      var html='<div class="card"><p class="slabel">'+icon+' '+title+'</p>'+
        '<div class="arcade-hud">';
      html+='<div class="arcade-stat"><div class="arcade-val">'+esc(String(d.arcadeScore||0))+'</div><div class="arcade-lbl">Score</div></div>';
      html+='<div class="arcade-stat"><div class="arcade-val">'+esc(String(d.arcadeLevel||1))+'</div><div class="arcade-lbl">Level</div></div>';
      if(gt==='tetris'){
        // [91] Tetris: lines + stack height
        html+='<div class="arcade-stat"><div class="arcade-val">'+esc(String(d.arcadeLines||0))+'</div><div class="arcade-lbl">Lines</div></div>';
        html+='</div>';
        if(d.arcadeClearLabel) html+='<div style="text-align:center;margin:2px 0 4px"><span class="clear-badge">'+esc(d.arcadeClearLabel)+'</span></div>';
        if((d.arcadeCombo||0)>1) html+='<p style="text-align:center;font-size:13px;color:#ffd54f;font-weight:700;margin-bottom:4px">&#128293; COMBO \\u00D7'+(d.arcadeCombo||0)+'!</p>';
        if(d.arcadeStackHeight>0){
          var shPct=Math.round(d.arcadeStackHeight/20*100);
          var shCol=shPct>75?'#ef9a9a':(shPct>50?'#ffd54f':'#a5d6a7');
          html+='<div style="padding:0 10px 4px"><div style="display:flex;justify-content:space-between;font-size:9px;color:rgba(255,255,255,.35);margin-bottom:2px"><span>Stack</span><span style="color:'+shCol+'">'+d.arcadeStackHeight+'/20</span></div>'+
            '<div class="pbar"><div class="pfill" style="width:'+shPct+'%;background:'+shCol+'"></div></div></div>';
        }
      } else if(gt==='capsules'){
        html+='<div class="arcade-stat"><div class="arcade-val">'+esc(String(d.levelsCleared||0))+'</div><div class="arcade-lbl">Cleared</div></div>';
        html+='</div>';
        // [93] Capsules lives
        if(d.arcadeLives!==undefined){var lStr='';for(var li=0;li<3;li++)lStr+=(li<+(d.arcadeLives||0)?'&#128315;':'&#9673;');html+='<p style="text-align:center;font-size:16px;margin-bottom:3px">'+lStr+'</p>';}
        if((d.totalVirusesCleared||0)>0) html+='<p style="text-align:center;font-size:11px;color:rgba(255,255,255,.4);margin-bottom:3px">&#127783; '+d.totalVirusesCleared+' viruses cleared</p>';
        if((d.maxChain||0)>1) html+='<p style="text-align:center;font-size:11px;color:#ffd54f;font-weight:700;margin-bottom:4px">Max chain \\u00D7'+(d.maxChain||0)+'</p>';
      } else if(gt==='snake'){
        // [92] Snake: speed + bonus food
        html+='<div class="arcade-stat"><div class="arcade-val" style="font-size:14px">'+esc(d.arcadeSpeedLabel||'?')+'</div><div class="arcade-lbl">Speed</div></div>';
        html+='</div>';
        // [92] Lives
        if(d.arcadeLives!==undefined){var lStr2='';for(var li2=0;li2<3;li2++)lStr2+=(li2<+(d.arcadeLives||0)?'&#128150;':'&#9673;');html+='<p style="text-align:center;font-size:16px;margin-bottom:3px">'+lStr2+'</p>';}
        if(d.arcadeBonusActive) html+='<p style="text-align:center;font-size:13px;color:#ffd54f;font-weight:700;margin-bottom:4px">&#11088; Bonus food active!</p>';
      } else {
        html+='<div class="arcade-stat"><div class="arcade-val" style="font-size:16px">&#128994;</div><div class="arcade-lbl">Playing</div></div>';
        html+='</div>';
      }
      html+='</div>'+
        '<div class="wait-card"><p class="wait-txt" style="font-size:13px">&#127918; Watch on the big screen<br><span style="opacity:.5;font-size:11px">Cheer them on!</span></p></div>';
      return html;
    }

    // ── [94] FreeCell spectator HUD ────────────────────────────────────────────
    function buildFreeCellHUD(d){
      var fc=+(d.foundationCount||0),pct=Math.round(fc/52*100);
      var html='<div class="card"><p class="slabel">&#127183; FreeCell</p>'+
        '<div class="pbar"><div class="pfill" style="width:'+pct+'%"></div></div>'+
        '<p style="text-align:center;font-size:11px;color:rgba(255,255,255,.38);margin:3px 0 6px">'+fc+'/52 in foundations ('+pct+'%)</p>';
      if(d.autoFinishAvailable) html+='<p style="text-align:center;font-size:13px;color:#a5d6a7;font-weight:700;margin-bottom:4px">&#10003; Auto-finish available!</p>';
      if(d.isDeadlocked) html+='<div class="check-banner" style="background:rgba(100,0,0,.3)">&#128683; Game deadlocked</div>';
      html+='</div><div class="wait-card"><p class="wait-txt" style="font-size:13px">&#127183; Watch on the big screen<br><span style="opacity:.5;font-size:11px">Cheer them on!</span></p></div>';
      return html;
    }

    // ── [41] Star Party (Mario Party) board ────────────────────────────────────
    var SP_TYPES=['sp-start','sp-blue','sp-blue','sp-red','sp-blue','sp-item','sp-blue','sp-lucky',
                  'sp-blue','sp-red','sp-event','sp-blue','sp-blue','sp-bowser','sp-blue','sp-item',
                  'sp-red','sp-blue','sp-lucky','sp-blue','sp-event','sp-blue','sp-red','sp-blue'];
    var SP_EMOJI={'sp-start':'&#127968;','sp-blue':'&#128309;','sp-red':'&#128308;','sp-lucky':'&#11088;',
                  'sp-item':'&#127873;','sp-bowser':'&#128128;','sp-event':'&#127922;'};
    var SP_TCOLS=['#4fc3f7','#ffb74d','#81c784','#f48fb1'];
    function buildStarParty(d,names){
      var me=+(d.mySeat||0),pos=d.positions||[],coins=d.coins||[],stars=d.stars||[];
      var starSp=+(d.starSpace||0),html='';
      html+='<div class="card"><p class="slabel">Round '+d.roundNumber+'/'+d.totalRounds+'</p>'+
        '<div style="display:grid;grid-template-columns:repeat(4,1fr);gap:5px;margin-bottom:4px">';
      names.slice(0,4).forEach(function(nm,i){
        var isMe=(i===me);
        html+='<div style="text-align:center;padding:5px 3px;background:rgba(255,255,255,'+(isMe?.1:.04)+');border-radius:10px;border:1px solid rgba(255,255,255,'+(isMe?.18:.06)+')">';
        html+='<div style="font-size:9px;color:rgba(255,255,255,.4);overflow:hidden;white-space:nowrap;text-overflow:ellipsis">'+esc(nm.substring(0,5))+'</div>';
        html+='<div style="font-size:15px;font-weight:800">&#11088;'+(stars[i]||0)+'</div>';
        html+='<div style="font-size:11px;color:#ffd54f">&#x1fa99;'+(coins[i]||0)+'</div></div>';
      });
      html+='</div></div>';
      html+='<div class="card"><p class="slabel">Board</p><div class="sp-board">';
      SP_TYPES.forEach(function(type,idx){
        var isStar=(idx===starSp);
        var cls='sp-space '+type+(isStar?' sp-star':'');
        var em=isStar?'&#11088;':(SP_EMOJI[type]||'?');
        var toks=pos.map(function(p,s){return p===idx?s:-1;}).filter(function(s){return s>=0;});
        var tokHtml=toks.length?'<div class="sp-tokens">'+toks.map(function(s){
          return '<div class="sp-tok" style="background:'+SP_TCOLS[s%4]+'">'+(s===me?'Y':'')+'</div>';
        }).join('')+'</div>':'';
        html+='<div class="'+cls+'">'+em+tokHtml+'</div>';
      });
      html+='</div>';
      if(d.lastRoll) html+='<p style="text-align:center;font-size:12px;color:rgba(255,255,255,.45);margin:4px 0 2px">Last roll: &#127922; '+d.lastRoll+'</p>';
      if(d.lastEvent) html+='<p style="text-align:center;font-size:12px;color:#81d4fa;padding-bottom:4px">'+esc(d.lastEvent)+'</p>';
      html+='</div>';
      if(d.isMinigame){
        if(d.isMyTurn&&d.moves&&d.moves.length){
          // [65] Minigame score numpad — find the playMinigame move
          var mgMoveFull=d.moves.find(function(m){return m.label&&m.label.indexOf('Score ')===0;});
          if(mgMoveFull){
            // Score picker: 0-10 in increments of 10
            html+='<div class="turn-card"><div class="turn-title">&#127917; '+esc(d.minigameName||'Minigame')+'</div>'+
              '<p style="text-align:center;font-size:12px;color:rgba(255,255,255,.45);margin:4px 0 8px">Enter your score (0=last, 100=first):</p>'+
              '<div class="mg-numpad">';
            [0,10,20,30,40,50,60,70,80,90,100].forEach(function(v){
              html+='<button class="mg-numpad-btn'+(mgScore===v?' sel':'')+'" onclick="mgScore='+v+';renderState(lastState)">'+v+'</button>';
            });
            // Find move matching selected score
            var targetMove=d.moves.find(function(m){return m.label==='Score '+mgScore;});
            html+='</div>'+
              '<button class="btn primary" style="margin-top:10px" onclick="haptic()'+
              (targetMove?';doMove('+targetMove.index+')'':'')+
              '">&#127917; Submit '+mgScore+' pts</button></div>';
          } else {
            html+='<div class="turn-card"><div class="turn-title">&#127917; Minigame: '+esc(d.minigameName||'Mini')+'</div>'+
              '<button class="btn primary" style="margin-top:8px" onclick="haptic();doMove('+d.moves[0].index+')">&#127917; Play!</button></div>';
          }
        } else {
          html+='<div class="wait-card"><div class="wait-txt">&#127917; Minigame: '+esc(d.minigameName||'Mini')+'</div></div>';
        }
      } else if(d.isMyTurn&&d.moves&&d.moves.length){
        html+='<div class="turn-card"><div class="turn-title">&#127922; Your Turn — Roll!</div>'+
          '<button class="btn primary" style="margin-top:10px;font-size:22px" onclick="haptic();doMove('+d.moves[0].index+')">&#127922; Roll Dice!</button></div>';
      } else {
        var cur=names[+(d.currentPlayer||0)]||'Someone';
        html+='<div class="wait-card"><p class="wait-txt"><span class="wait-name">'+esc(cur)+'</span> is rolling&#8230;</p></div>';
      }
      return html;
    }

    // ── [50] Klondike solitaire web controller ─────────────────────────────────
    function buildKlondike(d){
      var prog=+(d.foundationProgress||0),pct=Math.round(prog/52*100);
      var moves=d.moves||[];
      var html='<div class="card"><p class="slabel">Klondike Solitaire</p>'+
        '<div class="pbar"><div class="pfill" style="width:'+pct+'%"></div></div>'+
        '<p style="text-align:center;font-size:11px;color:rgba(255,255,255,.38);margin-top:3px">'+prog+'/52 in foundations ('+pct+'%)</p></div>';
      var drawMv=moves.find(function(m){return m.label==='Draw';});
      var resetMv=moves.find(function(m){return m.label==='Reset';});
      var wt=d.wasteTop;
      html+='<div class="card"><div class="kl-row">';
      // Stock
      var sc=+(d.stockCount||0);
      html+='<div class="kl-pile"><div class="hcard dark" style="min-height:54px;opacity:'+(sc>0?1:.3)+';pointer-events:none;justify-content:center;align-items:center;display:flex;flex-direction:column">'+
        '<div style="font-size:16px;font-weight:700;color:#546e7a">'+sc+'</div><div style="font-size:18px;color:#546e7a">&#128452;</div></div>'+
        (drawMv?'<button class="kl-btn draw-btn" onclick="haptic();doMove('+drawMv.index+')">Draw</button>':
         resetMv?'<button class="kl-btn draw-btn" onclick="haptic();doMove('+resetMv.index+')">Reset</button>':
         '<div class="kl-lbl">empty</div>')+'</div>';
      // Waste
      html+='<div class="kl-pile"><div class="hcard'+(wt?(wt.isRed?' red':' dark'):' dark')+'" style="min-height:54px;opacity:'+(wt?1:.25)+';pointer-events:none;display:flex;flex-direction:column;align-items:center;justify-content:center">'+
        (wt?'<div class="rank">'+esc(rankOf(wt.label))+'</div><div class="suit-big">'+esc(suitOf(wt.label))+'</div>':
            '<div style="font-size:18px;color:rgba(255,255,255,.18)">—</div>')+
        '</div><div class="kl-lbl">waste</div></div>';
      // Foundations
      var fTops=d.foundationTops||[];
      ['\\u2660','\\u2665','\\u2666','\\u2663'].forEach(function(suit,fi){
        var fc=fTops[fi],isEmpty=!fc||fc.empty;
        var isRed=(suit==='\\u2665'||suit==='\\u2666');
        html+='<div class="kl-pile"><div class="hcard '+(isRed?'red':'dark')+'" style="min-height:54px;opacity:'+(isEmpty?.28:1)+';pointer-events:none;display:flex;flex-direction:column;align-items:center;justify-content:center">'+
          (isEmpty?'<div style="font-size:20px;opacity:.5">'+suit+'</div>':
                   '<div class="rank">'+esc(rankOf(fc.label||''))+'</div><div class="suit-big">'+esc(suitOf(fc.label||suit))+'</div>')+
          '</div><div class="kl-lbl">'+(isEmpty?suit:(fc.count||''))+'</div></div>';
      });
      html+='</div>';
      // Foundation moves (high priority — green)
      var fndMoves=moves.filter(function(m){return m.label&&m.label.indexOf('Foundation')>=0;});
      if(fndMoves.length){
        html+='<p style="font-size:10px;color:#a5d6a7;text-transform:uppercase;letter-spacing:.7px;margin:8px 0 4px;padding:0 4px">Foundation moves</p>'+
          '<div style="display:flex;flex-wrap:wrap;gap:4px;padding:0 4px">'+fndMoves.map(function(m){
            return '<button class="kl-btn found" onclick="haptic();doMove('+m.index+')">'+esc(m.label||'')+'</button>';
          }).join('')+'</div>';
      }
      // [68] Tableau column mini-stacks
      var tab=d.tableau||[];
      if(tab.length){
        html+='<p style="font-size:10px;color:rgba(255,255,255,.32);text-transform:uppercase;letter-spacing:.7px;margin:8px 0 4px;padding:0 4px">Tableau columns</p>'+
          '<div style="display:grid;grid-template-columns:repeat(7,1fr);gap:3px;padding:0 4px">';
        tab.forEach(function(col){
          var fd=col.faceDown||0,topCards=col.topCards||[];
          html+='<div style="display:flex;flex-direction:column;gap:1px;align-items:stretch">';
          // Face-down count badge
          if(fd>0) html+='<div style="background:rgba(25,50,90,.8);border-radius:3px;font-size:8px;color:rgba(255,255,255,.35);text-align:center;padding:1px 0">'+fd+'&#128452;</div>';
          // Top face-up cards (oldest first, only up to 3)
          if(topCards.length===0){
            html+='<div class="kl-mini drk" style="opacity:.2;font-size:9px;color:rgba(255,255,255,.3)">—</div>';
          } else {
            topCards.forEach(function(tc){
              var tcRed=tc.isRed,tcR=rankOf(tc.label||''),tcS=suitOf(tc.label||'');
              html+='<div class="kl-mini '+(tcRed?'red':'drk')+'">'+esc(tcR)+esc(tcS)+'</div>';
            });
          }
          // Move button for this column
          var colMoves=moves.filter(function(m){var lbl=m.label||'';
            return lbl.indexOf('Col '+(+(col.col||0)+1))>=0;});
          if(colMoves.length){
            html+='<button class="kl-btn" style="font-size:8px;padding:2px 1px" onclick="haptic();doMove('+colMoves[0].index+')">&#10140;</button>';
          }
          html+='</div>';
        });
        html+='</div>';
      }
      // Foundation moves (high priority — green)
      var fndMoves=moves.filter(function(m){return m.label&&m.label.indexOf('Foundation')>=0;});
      if(fndMoves.length){
        html+='<p style="font-size:10px;color:#a5d6a7;text-transform:uppercase;letter-spacing:.7px;margin:8px 0 4px;padding:0 4px">Foundation moves &#127381;</p>'+
          '<div style="display:flex;flex-wrap:wrap;gap:4px;padding:0 4px">'+fndMoves.map(function(m){
            return '<button class="kl-btn found" onclick="haptic();doMove('+m.index+')">'+esc(m.label||'')+'</button>';
          }).join('')+'</div>';
      }
      html+='</div>';
      return html;
    }

    // ── [62] Bomberman live HUD ────────────────────────────────────────────────
    function buildBombermanHUD(d,names){
      var html='<div class="card"><p class="slabel">Bomberman</p><div class="bomber-hud">';
      var lives=+(d.bomberLives||0);
      var lifeStr='';
      for(var li=0;li<3;li++) lifeStr+=(li<lives?'&#128142;':'&#9899;');
      html+='<div class="bomber-stat"><div class="bomber-stat-val">'+esc(String(d.bomberScore||0))+'</div><div class="bomber-stat-lbl">Score</div></div>';
      html+='<div class="bomber-stat"><div class="bomber-stat-val" style="font-size:18px">'+lifeStr+'</div><div class="bomber-stat-lbl">Lives</div></div>';
      html+='<div class="bomber-stat"><div class="bomber-stat-val">'+esc(String(d.bomberLevel||1))+'</div><div class="bomber-stat-lbl">Level</div></div>';
      html+='</div>';
      if(d.levelsCleared>0) html+='<p style="text-align:center;font-size:11px;color:rgba(255,255,255,.35);margin-bottom:4px">&#128293; '+d.levelsCleared+' level'+(d.levelsCleared===1?'':'s')+' cleared</p>';
      html+='</div>';
      html+='<div class="wait-card"><p class="wait-txt" style="font-size:13px">&#127918; Playing on the big screen<br><span style="opacity:.5;font-size:11px">Watch and cheer them on!</span></p></div>';
      return html;
    }

    function buildPromptParty(d,names,phase){
      var html='';
      var total=d.totalPrompts||8,num=d.promptNumber||1;
      html+='<div class="card"><div class="party-progress"><span class="party-label">Prompt '+num+'/'+total+'</span>'+
        '<div class="pbar" style="width:80px;margin:0"><div class="pfill" style="width:'+Math.round(num/total*100)+'%"></div></div></div>';
      if(d.promptText) html+='<div class="qcard">'+esc(d.promptText)+'</div>';
      html+='</div>';
      if(phase==='writing'){
        if(d.isMyTurn){
          html+='<div class="turn-card"><div class="turn-title">&#128394;&#65039; Write Your Answer</div>'+
            '<textarea id="party-ans" class="party-input" placeholder="Your funniest answer...">'+(d.myAnswer?esc(d.myAnswer):'')+'</textarea>'+
            '<button class="btn primary" onclick="haptic();doPartyText()">Submit Answer</button></div>';
        } else {
          html+='<div class="wait-card"><p class="wait-txt">&#128394;&#65039; <span class="wait-name">'+esc(names[+(d.currentPlayer||0)]||'Someone')+'</span> is writing...</p></div>';
        }
      } else if(phase==='voting'){
        if(d.isMyTurn&&d.voteOptions&&d.voteOptions.length){
          html+='<div class="turn-card"><div class="turn-title">&#128221; Vote for Your Favorite</div><div style="margin-top:8px">';
          d.voteOptions.forEach(function(opt){
            html+='<button class="vote-btn" onclick="haptic();doMove('+opt.moveIndex+')">'+esc(opt.text)+'</button>';
          });
          html+='</div></div>';
        } else {
          html+='<div class="wait-card"><p class="wait-txt">&#128221; <span class="wait-name">'+esc(names[+(d.currentPlayer||0)]||'Someone')+'</span> is voting...</p></div>';
        }
      } else if(phase==='revealing'&&d.revealItems){
        html+='<div class="card">';
        d.revealItems.forEach(function(item){
          html+='<div style="padding:8px 0;border-bottom:1px solid rgba(255,255,255,.07)">'+
            '<div style="font-size:15px;font-weight:600;line-height:1.4">'+esc(item.text)+'</div>'+
            '<div style="font-size:11px;color:rgba(255,255,255,.42);margin-top:3px">'+esc(item.seatName||'')+
            (item.votes?' &nbsp;&#128077; '+item.votes:' &nbsp;no votes')+'</div></div>';
        });
        if(d.isMyTurn&&d.moves&&d.moves.length){
          html+='<button class="btn primary" style="margin-top:10px" onclick="haptic();doMove('+d.moves[0].index+')">'+esc(d.moves[0].label)+'</button>';
        } else {
          html+='<p style="text-align:center;font-size:12px;color:rgba(255,255,255,.3);margin-top:8px">Waiting for host to advance...</p>';
        }
        html+='</div>';
      }
      return html;
    }

    function buildBluffGame(d,names,phase){
      var html='';
      var total=d.totalRounds||8,num=d.roundNumber||1;
      html+='<div class="card"><div class="party-progress"><span class="party-label">Round '+num+'/'+total+'</span>'+
        '<div class="pbar" style="width:80px;margin:0"><div class="pfill" style="width:'+Math.round(num/total*100)+'%"></div></div></div>';
      if(d.bluffWord) html+='<div class="bluff-word">'+esc(d.bluffWord)+'</div>';
      html+='</div>';
      if(phase==='defining'){
        if(d.isMyTurn){
          html+='<div class="turn-card"><div class="turn-title">&#128221; Write a Fake Definition</div>'+
            '<textarea id="party-ans" class="party-input" placeholder="Make it convincing...">'+(d.myDefinition?esc(d.myDefinition):'')+'</textarea>'+
            '<button class="btn primary" onclick="haptic();doPartyText()">Submit Definition</button></div>';
        } else {
          html+='<div class="wait-card"><p class="wait-txt">&#128221; <span class="wait-name">'+esc(names[+(d.currentPlayer||0)]||'Someone')+'</span> is writing...</p></div>';
        }
      } else if(phase==='voting'){
        if(d.isMyTurn&&d.voteOptions&&d.voteOptions.length){
          html+='<div class="turn-card"><div class="turn-title">&#127915; Which is REAL?</div><div style="margin-top:8px">';
          d.voteOptions.forEach(function(opt){
            html+='<button class="vote-btn" onclick="haptic();doMove('+opt.moveIndex+')"><b style="color:#64b5f6">'+esc(opt.label)+'.</b> '+esc(opt.text)+'</button>';
          });
          html+='</div></div>';
        } else {
          html+='<div class="wait-card"><p class="wait-txt">&#127915; <span class="wait-name">'+esc(names[+(d.currentPlayer||0)]||'Someone')+'</span> is voting...</p></div>';
        }
      } else if(phase==='revealing'&&d.revealItems){
        html+='<div class="card">';
        d.revealItems.forEach(function(item){
          var realCls=item.isReal?' real':'';
          html+='<div class="reveal-item'+realCls+'">'+
            '<div style="font-size:15px;line-height:1.4"><b style="color:#81d4fa">'+esc(item.label)+'.</b> '+esc(item.text)+
            (item.isReal?' <span style="font-size:11px;color:#81c784;font-weight:700">&#10003; Real</span>':'')+'</div>'+
            '<div class="reveal-votes">'+item.votes+' vote'+(item.votes!==1?'s':'')+(item.isReal?'':' fooled')+'</div></div>';
        });
        if(d.isMyTurn&&d.moves&&d.moves.length){
          html+='<button class="btn primary" style="margin-top:10px" onclick="haptic();doMove('+d.moves[0].index+')">'+esc(d.moves[0].label)+'</button>';
        } else {
          html+='<p style="text-align:center;font-size:12px;color:rgba(255,255,255,.3);margin-top:8px">Waiting for host to advance...</p>';
        }
        html+='</div>';
      }
      return html;
    }

    function buildJackAttack(d,names){
      var html='';
      var qnum=d.questionNumber||1,total=d.totalQuestions||20,me=+(d.mySeat||0);
      html+='<div class="card"><div class="party-progress"><span class="party-label">Q'+qnum+'/'+total+'</span>'+
        '<div class="pbar" style="width:80px;margin:0"><div class="pfill" style="width:'+Math.round(qnum/total*100)+'%"></div></div></div>';
      // [64] SVG countdown ring (visual timer atmosphere — resets per question)
      if(d.isMyTurn){
        var r=22,circ=Math.round(2*Math.PI*r);
        html+='<div class="ja-timer-wrap"><svg width="56" height="56" style="transform:rotate(-90deg)">'+
          '<circle cx="28" cy="28" r="'+r+'" fill="none" stroke="rgba(255,255,255,.1)" stroke-width="4"/>'+
          '<circle cx="28" cy="28" r="'+r+'" fill="none" stroke="#ef5350" stroke-width="4" stroke-dasharray="'+circ+'" stroke-dashoffset="0" stroke-linecap="round">'+
            '<animate attributeName="stroke-dashoffset" from="0" to="'+circ+'" dur="15s" fill="freeze"/>'+
          '</circle></svg>'+
          '<div style="position:absolute;font-size:13px;font-weight:800;color:#ef9a9a">&#9889;</div></div>';
      }
      if(d.screwedSeat!==undefined&&d.screwedBy!==undefined){
        html+='<div style="text-align:center;background:rgba(183,28,28,.2);border-radius:10px;padding:6px 10px;margin-bottom:7px;font-size:13px;font-weight:700;color:#ef9a9a">'+
          '&#128299; '+esc(names[+(d.screwedBy||0)]||'?')+' SCREWED '+esc(names[+(d.screwedSeat||0)]||'?')+'!</div>';
      }
      if(d.questionText) html+='<div class="qcard">'+esc(d.questionText)+'</div>';
      // Live score mini-leaderboard
      if(d.scores&&d.scores.length){
        var sorted=d.scores.map(function(s,i){return{s:s,i:i};}).sort(function(a,b){return b.s-a.s;});
        html+='<div style="display:flex;gap:4px;justify-content:center;flex-wrap:wrap;padding:0 4px 4px">'+sorted.map(function(x,rank){
          var isMe=(x.i===me),medal=['&#129351;','&#129352;','&#129353;'][rank]||'';
          return '<span style="font-size:11px;font-weight:'+(isMe?800:500)+';color:'+(isMe?'#ffd54f':'rgba(255,255,255,.5)')+';background:rgba(255,255,255,'+(isMe?.1:.04)+');border-radius:6px;padding:2px 7px">'+
            medal+esc((names[x.i]||'P'+(x.i+1)).substring(0,5))+' '+x.s+'</span>';
        }).join('')+'</div>';
      }
      html+='</div>';
      if(d.isMyTurn&&d.moves&&d.moves.length){
        html+='<div class="turn-card"><div class="turn-title">&#9889; ANSWER NOW!</div>'+
          '<div class="agrid" style="margin-top:8px">'+d.moves.map(function(m){
            return '<button class="abtn" onclick="haptic();doMove('+m.index+')"><span class="aletter">'+esc(m.label)+'</span><span class="adesc">'+esc(m.desc||'')+'</span></button>';
          }).join('')+'</div>';
        if(d.screwMoves&&d.screwMoves.length&&d.screwedSeat===undefined&&d.screwsLeft>0){
          html+='<div style="margin-top:8px"><p style="font-size:10px;color:rgba(255,255,255,.3);margin-bottom:5px;text-align:center;text-transform:uppercase;letter-spacing:.7px">Use your screw ('+d.screwsLeft+' left)</p>'+
            '<div class="screw-row">'+d.screwMoves.map(function(m){
              return '<button class="screw-btn" onclick="haptic();doMove('+m.index+')">&#128299; '+esc(m.label)+'</button>';
            }).join('')+'</div></div>';
        }
        html+='</div>';
      } else {
        html+='<div class="wait-card"><p class="wait-txt">&#9889; <span class="wait-name">'+esc(names[+(d.currentPlayer||0)]||'Someone')+'</span> is answering!</p></div>';
      }
      return html;
    }

    // ── [22] Text-based move for Quiplash / Bluff typing phases ────────────────
    async function doPartyText(){
      var el=document.getElementById('party-ans'); if(!el) return;
      var text=el.value.trim(); if(!text){el.focus();return;}
      if(submitting) return;
      submitting=true; el.disabled=true;
      var d=await api('POST','/api/move',{id:sid,moveText:text});
      submitting=false; el.disabled=false;
      if(d.error){
        var e=document.createElement('p');e.className='err';e.textContent=d.error;
        var c=document.querySelector('.turn-card');if(c)c.appendChild(e);
      } else { showCheckFlash(); doPoll(); }
    }

    showJoin();
    </script>
    </body>
    </html>
    """
}
