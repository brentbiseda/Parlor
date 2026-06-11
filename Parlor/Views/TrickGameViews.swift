import SwiftUI

enum TrickPanel {
    case none
    case heartsPassing(direction: String)
    case spadesBidding
    case euchreOrdering(upcard: Card)
    case euchreCalling(excluded: Suit, mustCall: Bool)
    case euchreDiscard
    case bridgeAuction
}

/// View-layer adapter giving the shared table UI a uniform window into the
/// four trick-taking engines.
protocol TrickGameAdapter {
    var hands: [[Card]] { get }
    var trick: [TrickPlay] { get }
    var lastTrickSummary: String? { get }
    var panel: TrickPanel { get }
    /// Hand shown face-up to everyone (bridge dummy).
    var faceUpSeat: Int? { get }
    func seatDetail(_ seat: Int) -> String?
    var scoreLines: [String] { get }
    /// Legal cards for the seat currently to act (empty outside play phases).
    var legalCardSet: Set<Card> { get }
}

extension HeartsGame: TrickGameAdapter {
    var panel: TrickPanel {
        phase == .passing ? .heartsPassing(direction: passDirection.label) : .none
    }
    var faceUpSeat: Int? { nil }
    func seatDetail(_ seat: Int) -> String? {
        if phase == .passing { return passSelections[seat] != nil ? "passed" : "choosing…" }
        return "round \(roundPoints[seat]) · total \(scores[seat])"
    }
    var scoreLines: [String] {
        (0..<4).map { "Seat \($0 + 1): \(scores[$0]) (this round: \(roundPoints[$0]))" }
    }
    var legalCardSet: Set<Card> { phase == .playing ? Set(legalCards()) : [] }
}

extension SpadesGame: TrickGameAdapter {
    var panel: TrickPanel { phase == .bidding ? .spadesBidding : .none }
    var faceUpSeat: Int? { nil }
    func seatDetail(_ seat: Int) -> String? {
        guard let bid = bids[seat] else { return phase == .bidding ? "bidding…" : nil }
        return "bid \(bid == 0 ? "nil" : String(bid)) · took \(tricksWon[seat])"
    }
    var scoreLines: [String] {
        [0, 1].map { "\(teamLabel($0)): \(teamScores[$0]) pts, \(teamBags[$0]) bags" }
    }
    var legalCardSet: Set<Card> { phase == .playing ? Set(legalCards()) : [] }
}

extension EuchreGame: TrickGameAdapter {
    var panel: TrickPanel {
        switch phase {
        case .orderingUp:
            if let upcard { return .euchreOrdering(upcard: upcard) }
            return .none
        case .callingTrump:
            if let upcard { return .euchreCalling(excluded: upcard.suit, mustCall: currentPlayer == dealer) }
            return .none
        case .dealerDiscard:
            return .euchreDiscard
        default:
            return .none
        }
    }
    var faceUpSeat: Int? { nil }
    func seatDetail(_ seat: Int) -> String? {
        if seat == sittingOut { return "sitting out" }
        var parts: [String] = []
        if seat == dealer { parts.append("dealer") }
        if phase == .playing { parts.append("took \(trickCounts[seat])") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    var scoreLines: [String] {
        [0, 1].map { "\(teamLabel($0)): \(teamScores[$0]) of 10" }
    }
    var legalCardSet: Set<Card> {
        switch phase {
        case .playing: return Set(legalCards())
        case .dealerDiscard: return Set(hands[dealer])
        default: return []
        }
    }
}

extension BridgeGame: TrickGameAdapter {
    var panel: TrickPanel { phase == .auction ? .bridgeAuction : .none }
    var faceUpSeat: Int? { dummyRevealed ? dummySeat : nil }
    func seatDetail(_ seat: Int) -> String? {
        var parts: [String] = []
        if seat == dealer && phase == .auction { parts.append("dealer") }
        if let contract {
            if seat == contract.declarer { parts.append("declarer") }
            if seat == dummySeat { parts.append("dummy") }
        }
        if isVulnerable(side: side(of: seat)) { parts.append("vul") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    var scoreLines: [String] {
        [sideLabel(0) + ": \(teamScores[0])", sideLabel(1) + ": \(teamScores[1])"] + history.map(\.summary)
    }
    var legalCardSet: Set<Card> { phase == .playing ? Set(legalCards()) : [] }
}

// MARK: - Table

struct TrickTableView: View {
    @ObservedObject var session: GameSession
    @State private var passSelection: Set<Card> = []
    @State private var showScores = false

    var adapter: TrickGameAdapter? { session.game?.engine as? TrickGameAdapter }

    var body: some View {
        GeometryReader { geo in
            if let game = session.game, let adapter {
                let perspective = session.perspectiveSeat
                let acting = session.actionableSeat != nil

                VStack(spacing: 4) {
                    opponentBadge(offset: 2, adapter: adapter, game: game)
                    HStack(alignment: .center) {
                        opponentBadge(offset: 1, adapter: adapter, game: game)
                        Spacer()
                        opponentBadge(offset: 3, adapter: adapter, game: game)
                    }
                    .padding(.horizontal, 6)

                    Spacer(minLength: 0)
                    trickArea(adapter: adapter, perspective: perspective)
                    Spacer(minLength: 0)

                    if let summary = adapter.lastTrickSummary, adapter.trick.isEmpty {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }

                    if acting {
                        panelView(adapter.panel, game: game)
                            .padding(.horizontal)
                    }

                    myHand(adapter: adapter, game: game, acting: acting, width: geo.size.width)
                    myBadge(adapter: adapter, game: game, perspective: perspective)
                        .padding(.bottom, 4)
                }
                .padding(.top, 4)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Scores", systemImage: "list.number") { showScores = true }
            }
        }
        .alert("Scores", isPresented: $showScores) {
            Button("Done", role: .cancel) {}
        } message: {
            Text(adapter?.scoreLines.joined(separator: "\n") ?? "")
        }
    }

    func seatName(_ seat: Int) -> String { session.playerName(seat: seat) }

    func opponentBadge(offset: Int, adapter: TrickGameAdapter, game: AnyGame) -> some View {
        let seat = (session.perspectiveSeat + offset) % 4
        let count = adapter.hands[seat].isEmpty
            ? adapter.hands[session.perspectiveSeat].count
            : adapter.hands[seat].count
        return VStack(spacing: 4) {
            SeatBadge(name: seatName(seat),
                      isCurrent: !game.isOver && game.currentPlayer == seat,
                      detail: adapter.seatDetail(seat))
            if adapter.faceUpSeat == seat {
                dummyCards(seat: seat, adapter: adapter, game: game)
            } else {
                OpponentHandView(count: min(count, 13), width: 20)
            }
        }
    }

    func myBadge(adapter: TrickGameAdapter, game: AnyGame, perspective: Int) -> some View {
        SeatBadge(name: seatName(perspective) + " (you)",
                  isCurrent: !game.isOver && game.currentPlayer == perspective,
                  detail: adapter.seatDetail(perspective))
    }

    /// Dummy's exposed hand; tappable when the local declarer must play from it.
    func dummyCards(seat: Int, adapter: TrickGameAdapter, game: AnyGame) -> some View {
        let playableFromDummy = session.actionableSeat != nil && game.currentPlayer == seat
        let legal = adapter.legalCardSet
        return FlowCards(cards: adapter.hands[seat]) { card in
            let ok = playableFromDummy && legal.contains(card)
            CardView(card: card, width: 30)
                .opacity(!playableFromDummy || ok ? 1 : 0.5)
                .onTapGesture {
                    if ok { session.submit(.playCard(card)) }
                }
        }
        .frame(maxWidth: 320)
    }

    func trickArea(adapter: TrickGameAdapter, perspective: Int) -> some View {
        ZStack {
            ForEach(adapter.trick, id: \.seat) { play in
                let relative = (play.seat - perspective + 4) % 4
                CardView(card: play.card, width: 46)
                    .offset(trickOffset(relative))
            }
        }
        .frame(height: 130)
    }

    func trickOffset(_ relative: Int) -> CGSize {
        switch relative {
        case 0: return CGSize(width: 0, height: 34)
        case 1: return CGSize(width: -52, height: 0)
        case 2: return CGSize(width: 0, height: -34)
        default: return CGSize(width: 52, height: 0)
        }
    }

    func myHand(adapter: TrickGameAdapter, game: AnyGame, acting: Bool, width: CGFloat) -> some View {
        // When acting for another seat (bridge dummy control plays from the
        // dummy badge instead), show the hand of the seat that must act.
        let handSeat: Int
        if acting, game.currentPlayer != adapter.faceUpSeat {
            handSeat = game.controller(of: game.currentPlayer) == game.currentPlayer
                ? game.currentPlayer
                : session.perspectiveSeat
        } else {
            handSeat = session.perspectiveSeat
        }
        let cards = adapter.hands[handSeat]
        let isPassing: Bool
        if case .heartsPassing = adapter.panel { isPassing = true } else { isPassing = false }
        let legal = isPassing ? Set(cards) : adapter.legalCardSet

        return HandView(cards: cards,
                        legal: legal,
                        enabled: acting,
                        selected: isPassing ? passSelection : []) { card in
            guard acting else { return }
            if isPassing {
                if passSelection.contains(card) {
                    passSelection.remove(card)
                } else if passSelection.count < 3 {
                    passSelection.insert(card)
                }
            } else if legal.contains(card) {
                session.submit(.playCard(card))
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Phase panels

    @ViewBuilder
    func panelView(_ panel: TrickPanel, game: AnyGame) -> some View {
        switch panel {
        case .none:
            EmptyView()
        case .heartsPassing(let direction):
            VStack(spacing: 6) {
                Text("Select 3 cards to pass \(direction)")
                    .font(.callout).foregroundStyle(.white)
                Button("Pass \(passSelection.count)/3") {
                    session.submit(.passCards(Array(passSelection).displaySorted()))
                    passSelection = []
                }
                .buttonStyle(.borderedProminent)
                .disabled(passSelection.count != 3)
            }
        case .spadesBidding:
            VStack(spacing: 6) {
                Text("Your bid").font(.callout).foregroundStyle(.white)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(0...13, id: \.self) { n in
                            Button(n == 0 ? "Nil" : "\(n)") { session.submit(.bid(n)) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
        case .euchreOrdering(let upcard):
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text("Order up").foregroundStyle(.white)
                    CardView(card: upcard, width: 34)
                    Text("?").foregroundStyle(.white)
                }
                HStack {
                    Button("Pass") { session.submit(.euchreCall(.pass)) }
                        .buttonStyle(.bordered).tint(.white)
                    Button("Order up") { session.submit(.euchreCall(.orderUp(alone: false))) }
                        .buttonStyle(.borderedProminent)
                    Button("Alone!") { session.submit(.euchreCall(.orderUp(alone: true))) }
                        .buttonStyle(.borderedProminent).tint(.orange)
                }
            }
        case .euchreCalling(let excluded, let mustCall):
            VStack(spacing: 6) {
                Text(mustCall ? "Dealer must name trump" : "Name trump?")
                    .font(.callout).foregroundStyle(.white)
                HStack {
                    if !mustCall {
                        Button("Pass") { session.submit(.euchreCall(.pass)) }
                            .buttonStyle(.bordered).tint(.white)
                    }
                    ForEach(Suit.allCases.filter { $0 != excluded }, id: \.self) { suit in
                        Button(suit.symbol) { session.submit(.euchreCall(.callTrump(suit, alone: false))) }
                            .buttonStyle(.borderedProminent)
                            .tint(suit.isRed ? .red : .black)
                    }
                }
            }
        case .euchreDiscard:
            Text("Tap a card to discard")
                .font(.callout).foregroundStyle(.white)
        case .bridgeAuction:
            BridgeAuctionPanel(session: session)
        }
    }
}

/// Simple wrapping layout for the dummy's cards.
struct FlowCards<Content: View>: View {
    let cards: [Card]
    @ViewBuilder let content: (Card) -> Content

    var body: some View {
        let rows = stride(from: 0, to: cards.count, by: 9).map { Array(cards[$0..<min($0 + 9, cards.count)]) }
        VStack(spacing: 2) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: -12) {
                    ForEach(row) { card in content(card) }
                }
            }
        }
    }
}

struct BridgeAuctionPanel: View {
    @ObservedObject var session: GameSession
    @State private var level = 1

    var bridge: BridgeGame? { session.game?.engine as? BridgeGame }

    var body: some View {
        let legal = bridge?.legalCalls() ?? []
        VStack(spacing: 6) {
            if let calls = bridge?.calls, !calls.isEmpty {
                Text("Auction: " + calls.map(\.label).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                Picker("Level", selection: $level) {
                    ForEach(1...7, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.menu)
                .tint(.white)
                ForEach(BridgeStrain.allCases, id: \.self) { strain in
                    let call = BridgeCall.bid(level: level, strain: strain)
                    Button(strain.label) { session.submit(.bridgeCall(call)) }
                        .buttonStyle(.borderedProminent)
                        .tint(strain.suit?.isRed == true ? .red : .indigo)
                        .disabled(!legal.contains(call))
                }
            }
            HStack {
                Button("Pass") { session.submit(.bridgeCall(.pass)) }
                    .buttonStyle(.bordered).tint(.white)
                Button("Double") { session.submit(.bridgeCall(.double)) }
                    .buttonStyle(.bordered).tint(.orange)
                    .disabled(!legal.contains(.double))
                Button("Redouble") { session.submit(.bridgeCall(.redouble)) }
                    .buttonStyle(.bordered).tint(.orange)
                    .disabled(!legal.contains(.redouble))
            }
        }
        .padding(8)
        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
    }
}
