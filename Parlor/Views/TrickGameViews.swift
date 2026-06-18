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
    @State private var bagPulse = false

    var adapter: TrickGameAdapter? { session.game?.engine as? TrickGameAdapter }

    var body: some View {
        GeometryReader { geo in
            if let game = session.game, let adapter {
                let perspective = session.perspectiveSeat
                let acting = session.actionableSeat != nil

                VStack(spacing: 4) {
                    scoreStrip(game: game, perspective: perspective)
                    opponentBadge(offset: 2, adapter: adapter, game: game)
                    HStack(alignment: .center) {
                        opponentBadge(offset: 1, adapter: adapter, game: game)
                        Spacer()
                        opponentBadge(offset: 3, adapter: adapter, game: game)
                    }
                    .padding(.horizontal, 6)

                    Spacer(minLength: 0)
                    ZStack(alignment: .topLeading) {
                        trickArea(adapter: adapter, perspective: perspective)
                        // Trump suit badge shown during playing phase
                        if let trump = activeTrump(game: game) {
                            Text(trump.symbol)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(trump.isRed ? .red : .primary)
                                .padding(6)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.2), lineWidth: 1))
                                .padding(.leading, 4)
                                .padding(.top, 4)
                        }
                    }
                    Spacer(minLength: 0)

                    // Euchre tricks progress indicator (5 dots).
                    if let euchre = game.engine as? EuchreGame, euchre.phase == .playing,
                       let makerTeam = euchre.makerTeam {
                        euchreTricksBar(euchre: euchre, makerTeam: makerTeam, perspective: perspective)
                            .padding(.bottom, 2)
                    }

                    // Spades tricks-vs-contract progress bar (13 dots).
                    if let spades = game.engine as? SpadesGame, spades.phase == .playing {
                        spadesTricksBar(spades: spades, perspective: perspective)
                            .padding(.bottom, 2)
                    }

                    // Hearts per-seat round score when any seat has scored this round.
                    if let hearts = game.engine as? HeartsGame, hearts.phase == .playing,
                       hearts.roundPoints.contains(where: { $0 > 0 }) {
                        heartsRoundChips(hearts: hearts, perspective: perspective)
                            .padding(.bottom, 2)
                    }

                    // Bridge: contract progress bar during playing phase.
                    if let bridge = game.engine as? BridgeGame, bridge.phase == .playing {
                        bridgeContractBar(bridge: bridge, perspective: perspective)
                            .padding(.bottom, 2)
                    }

                    if let summary = adapter.lastTrickSummary, adapter.trick.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.green.opacity(0.85))
                            Text(summary)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.08), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.75))
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        .animation(.easeInOut(duration: 0.25), value: summary)
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

    // MARK: - Euchre tricks progress

    @ViewBuilder
    func euchreTricksBar(euchre: EuchreGame, makerTeam: Int, perspective: Int) -> some View {
        let perspTeam = perspective % 2
        let makerTricks = euchre.trickCounts[makerTeam] + euchre.trickCounts[makerTeam + 2]
        let defenderTricks = euchre.trickCounts[1 - makerTeam] + euchre.trickCounts[(1 - makerTeam) + 2]
        let totalPlayed = makerTricks + defenderTricks
        let makerIsUs = makerTeam == perspTeam
        return HStack(spacing: 5) {
            ForEach(0..<5, id: \.self) { i in
                let filledByMaker = i < makerTricks
                let filledByDefender = i < defenderTricks && !filledByMaker
                let played = i < totalPlayed
                let dotColor: Color = filledByMaker
                    ? (makerIsUs ? .blue : .red)
                    : filledByDefender
                        ? (makerIsUs ? .red : .blue)
                        : .clear
                Circle()
                    .fill(dotColor)
                    .overlay(Circle().strokeBorder(played ? .white.opacity(0.5) : .white.opacity(0.25), lineWidth: 1))
                    .frame(width: 10, height: 10)
            }
            // Alone indicator
            if euchre.aloneSeat != nil {
                Text("⚡ALONE")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.yellow)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.yellow.opacity(0.2), in: Capsule())
            }
            Spacer(minLength: 4)
            Text("\(makerIsUs ? makerTricks : defenderTricks)/3")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .monospacedDigit()
        }
    }

    // MARK: - Spades contract progress

    /// 13-dot bar showing each trick as Us/Them/unplayed. Contract thresholds
    /// are marked with a subtle white line so you can see "need 4 more" at a glance.
    @ViewBuilder
    func spadesTricksBar(spades: SpadesGame, perspective: Int) -> some View {
        let us = perspective % 2
        let them = 1 - us
        let ourTricks = spades.tricksWon[us] + spades.tricksWon[us + 2]
        let theirTricks = spades.tricksWon[them] + spades.tricksWon[them + 2]
        let ourContract = spades.teamContract(us)
        let theirContract = spades.teamContract(them)
        let played = ourTricks + theirTricks

        HStack(spacing: 3) {
            ForEach(0..<13, id: \.self) { i in
                let ours = i < ourTricks
                let theirs = !ours && i < played
                let atOurContract = ourContract > 0 && i == ourContract - 1
                let atTheirContract = theirContract > 0 && i == 13 - theirContract
                RoundedRectangle(cornerRadius: 2)
                    .fill(ours ? Color.blue : theirs ? Color.red : Color.white.opacity(0.12))
                    .frame(width: 14, height: 10)
                    .overlay(alignment: .trailing) {
                        if atOurContract {
                            Rectangle()
                                .fill(Color.white.opacity(0.6))
                                .frame(width: 1.5)
                        }
                    }
                    .overlay(alignment: .leading) {
                        if atTheirContract && !atOurContract {
                            Rectangle()
                                .fill(Color.white.opacity(0.4))
                                .frame(width: 1.5)
                        }
                    }
            }
            Spacer(minLength: 4)
            Text("\(ourTricks)/\(ourContract) · \(theirTricks)/\(theirContract)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Hearts round score chips

    @ViewBuilder
    func heartsRoundChips(hearts: HeartsGame, perspective: Int) -> some View {
        let moonAttempt = (0..<4).first { seat in hearts.roundPoints[seat] >= 12 && (1..<4).allSatisfy({ i in i == seat || hearts.roundPoints[i] == 0 }) }
        HStack(spacing: 5) {
            ForEach(0..<4, id: \.self) { seat in
                let pts = hearts.roundPoints[seat]
                let isMoonCandidate = moonAttempt == seat
                let isMe = seat == perspective
                HStack(spacing: 2) {
                    Text(String(session.playerName(seat: seat).prefix(4)))
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("+\(pts)")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(isMoonCandidate ? .yellow : pts >= 13 ? .red : pts > 0 ? .orange : .white.opacity(0.5))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(isMoonCandidate ? Color.yellow.opacity(0.15) : isMe ? .white.opacity(0.1) : .clear,
                            in: Capsule())
                .overlay(isMoonCandidate ? Capsule().strokeBorder(.yellow.opacity(0.5), lineWidth: 1) : nil)
            }
            if let moon = moonAttempt {
                Text("🌙 S\(moon+1) going for moon!")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.yellow)
            }
        }
    }

    // MARK: - Bridge contract bar

    /// 13-dot bar + contract label showing declarer's trick progress.
    @ViewBuilder
    func bridgeContractBar(bridge: BridgeGame, perspective: Int) -> some View {
        if let contract = bridge.contract, let bidLabel = bridge.currentBidLabel {
            let declarerSide = contract.declarer % 2
            let perspSide = perspective % 2
            let dTricks = bridge.declarerTricks
            let defTricks = bridge.defenderTricks
            let needed = contract.level + 6
            let madeIt = dTricks >= needed
            // From perspective: are we the declaring side?
            let weAreDeclarer = declarerSide == perspSide
            let ourTricks = weAreDeclarer ? dTricks : defTricks
            let theirTricks = weAreDeclarer ? defTricks : dTricks

            HStack(spacing: 3) {
                Text(bidLabel)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(madeIt ? .green : .white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(madeIt ? Color.green.opacity(0.2) : .white.opacity(0.1), in: Capsule())

                ForEach(0..<13, id: \.self) { i in
                    let ours = i < ourTricks
                    let theirs = !ours && i < ourTricks + theirTricks
                    // Contract threshold always shown from declarer's perspective
                    let atContract = weAreDeclarer && i == needed - 1
                    RoundedRectangle(cornerRadius: 2)
                        .fill(ours ? Color.blue : theirs ? Color.red : Color.white.opacity(0.12))
                        .frame(width: 14, height: 10)
                        .overlay(alignment: .trailing) {
                            if atContract {
                                Rectangle()
                                    .fill(Color.white.opacity(0.55))
                                    .frame(width: 1.5)
                            }
                        }
                }
                Spacer(minLength: 4)
                Text(madeIt ? "+\(dTricks - needed)" : "\(dTricks)/\(needed)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(madeIt ? .green : .white.opacity(0.7))
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)
        }
    }

    // MARK: - Always-visible scores

    /// Compact scoreboard pinned above the table, so nobody has to open the
    /// Scores sheet to know where the game stands.
    @ViewBuilder
    func scoreStrip(game: AnyGame, perspective: Int) -> some View {
        switch game.engine {
        case let g as SpadesGame:
            let us = perspective % 2
            let usBags = g.teamBags[us]
            let themBags = g.teamBags[1 - us]
            // Projected round delta: tricks won vs contract so far
            let ourTricks = g.tricksWon[us] + g.tricksWon[us + 2]
            let ourContract = g.teamContract(us)
            let projBag = g.phase == .playing && ourContract > 0 && ourTricks > ourContract
                ? " +\(ourTricks - ourContract)🎒" : ""
            let projNote = g.phase == .playing && ourContract > 0
                ? (ourTricks >= ourContract ? "✓" : "\(ourTricks)/\(ourContract)") : nil
            HStack(spacing: 8) {
                scoreChip("Us", "\(g.teamScores[us])", detail: "\(usBags)🎒\(projBag)",
                          highlight: true, bagWarning: usBags >= 7)
                    .scaleEffect(usBags >= 7 && bagPulse ? 1.06 : 1.0)
                VStack(spacing: 1) {
                    Text("to 500").font(.caption2).foregroundStyle(.white.opacity(0.5))
                    if let note = projNote {
                        Text(note)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(note == "✓" ? .green : .white.opacity(0.6))
                    }
                }
                scoreChip("Them", "\(g.teamScores[1 - us])", detail: "\(themBags)🎒",
                          highlight: false, bagWarning: themBags >= 7)
                    .scaleEffect(themBags >= 7 && bagPulse ? 1.06 : 1.0)
            }
            .onAppear {
                if usBags >= 7 || themBags >= 7 {
                    withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) { bagPulse = true }
                }
            }
            .onChange(of: max(usBags, themBags)) { _, bags in
                if bags >= 7 {
                    withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) { bagPulse = true }
                } else {
                    bagPulse = false
                }
            }
        case let g as EuchreGame:
            let us = perspective % 2
            let usStreak = g.teamRoundStreak[us]
            let themStreak = g.teamRoundStreak[1 - us]
            HStack(spacing: 8) {
                scoreChip("Us", "\(g.teamScores[us])",
                          detail: usStreak >= 2 ? "🔥\(usStreak)" : nil, highlight: true)
                Text("to 10").font(.caption2).foregroundStyle(.white.opacity(0.5))
                scoreChip("Them", "\(g.teamScores[1 - us])",
                          detail: themStreak >= 2 ? "🔥\(themStreak)" : nil, highlight: false)
            }
        case let g as BridgeGame:
            let us = perspective % 2
            let usVul = g.isVulnerable(side: us)
            let themVul = g.isVulnerable(side: 1 - us)
            HStack(spacing: 8) {
                scoreChip("Us", "\(g.teamScores[us])", detail: usVul ? "VUL" : nil, highlight: true,
                          bagWarning: usVul)
                Text("deal \(min(g.dealNumber, 4))/4").font(.caption2).foregroundStyle(.white.opacity(0.5))
                scoreChip("Them", "\(g.teamScores[1 - us])", detail: themVul ? "VUL" : nil, highlight: false,
                          bagWarning: themVul)
            }
        case let g as HeartsGame:
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { seat in
                    scoreChip(String(seatName(seat).prefix(6)), "\(g.scores[seat])",
                              detail: nil, highlight: seat == perspective)
                }
                if g.heartsBroken && g.phase == .playing {
                    Image(systemName: "heart.slash.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(5)
                        .background(.black.opacity(0.3), in: Circle())
                }
            }
        default:
            EmptyView()
        }
    }

    func scoreChip(_ label: String, _ value: String, detail: String?, highlight: Bool,
                   bagWarning: Bool = false) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))
            Text(value)
                .font(.callout.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(highlight ? .yellow : .white)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(bagWarning ? Color.orange : .white.opacity(0.6))
                    .fontWeight(bagWarning ? .bold : .regular)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(bagWarning ? Color.orange.opacity(0.22) : .black.opacity(highlight ? 0.4 : 0.25), in: Capsule())
        .overlay(Capsule().strokeBorder(bagWarning ? .orange.opacity(0.6) : .white.opacity(highlight ? 0.3 : 0.12), lineWidth: bagWarning ? 1.5 : 1))
    }

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

    /// Returns the trump suit for the current game, if in playing phase.
    func activeTrump(game: AnyGame) -> Suit? {
        if let g = game.engine as? EuchreGame, g.phase == .playing { return g.trump }
        if let g = game.engine as? SpadesGame, g.phase == .playing { return .spades }
        if let g = game.engine as? BridgeGame, g.phase == .playing { return g.contract?.strain.suit }
        return nil  // Hearts: no trump
    }

    /// Played cards spring in from their seat's side of the table.
    func trickArea(adapter: TrickGameAdapter, perspective: Int) -> some View {
        ZStack {
            ForEach(adapter.trick, id: \.seat) { play in
                let relative = (play.seat - perspective + 4) % 4
                CardView(card: play.card, width: 46)
                    .offset(trickOffset(relative))
                    .transition(
                        .offset(entryOffset(relative))
                        .combined(with: .scale(scale: 1.25))
                        .combined(with: .opacity)
                    )
            }
        }
        .frame(height: 130)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: adapter.trick.count)
    }

    /// Where a card flies in from, by relative seat (0 = you, going clockwise).
    func entryOffset(_ relative: Int) -> CGSize {
        switch relative {
        case 0: return CGSize(width: 0, height: 160)
        case 1: return CGSize(width: -180, height: 0)
        case 2: return CGSize(width: 0, height: -160)
        default: return CGSize(width: 180, height: 0)
        }
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
        // During Hearts passing every card is selectable, so legal = [] avoids
        // painting all 13 with a yellow border.  Only the selected cards are highlighted.
        let legalCards = adapter.legalCardSet
        let legal: Set<Card> = isPassing ? [] : legalCards

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
                HStack(spacing: 8) {
                    // Directional arrow glyphs
                    let arrow: String = switch direction {
                    case "left": "← Pass left"
                    case "right": "Pass right →"
                    case "across": "↑ Pass across"
                    default: "⊘ No passing"
                    }
                    Text(arrow)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                    HStack(spacing: 5) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .frame(width: 12, height: 12)
                                .foregroundStyle(i < passSelection.count ? Color.yellow : Color.white.opacity(0.25))
                                .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
                        }
                    }
                }
                Button {
                    session.submit(.passCards(Array(passSelection).displaySorted()))
                    passSelection = []
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "paperplane.fill")
                        Text("Pass \(passSelection.count)/3")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(passSelection.count != 3)
            }
        case .spadesBidding:
            if let spades = game.engine as? SpadesGame {
                let seat = spades.currentPlayer
                let hand = spades.hands[seat]
                let bySuit = Dictionary(grouping: hand, by: \.suit)
                let suggested = Bot.estimateSpadesBid(hand: hand)
                VStack(spacing: 6) {
                    // Per-suit hand strength strip
                    HStack(spacing: 8) {
                        ForEach(Suit.allCases, id: \.self) { suit in
                            let cards = (bySuit[suit] ?? []).sorted { $0.rank.rawValue > $1.rank.rawValue }
                            let highCards = cards.filter { $0.rank >= .queen }
                            VStack(spacing: 2) {
                                Text(suit.symbol)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(suit.isRed ? .red : (suit == .spades ? .white : .white.opacity(0.8)))
                                Text("\(cards.count)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(suit == .spades ? .yellow : .white)
                                if !highCards.isEmpty {
                                    Text(highCards.map { String($0.rank.label.prefix(1)) }.joined())
                                        .font(.system(size: 8))
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(suit == .spades ? Color.white.opacity(0.12) : Color.white.opacity(0.06),
                                        in: RoundedRectangle(cornerRadius: 6))
                        }
                        Spacer()
                        // Suggested bid chip
                        VStack(spacing: 0) {
                            Text("Rec.")
                                .font(.system(size: 7, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.5))
                            Text(suggested == 0 ? "Nil" : "\(suggested)")
                                .font(.system(size: 15, weight: .black))
                                .foregroundStyle(.cyan)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.cyan.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                    }
                    Text("Your bid").font(.caption).foregroundStyle(.white.opacity(0.7))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(0...13, id: \.self) { n in
                                Button(n == 0 ? "Nil" : "\(n)") { session.submit(.bid(n)) }
                                    .buttonStyle(.borderedProminent)
                                    .tint(n == suggested ? .cyan : .blue)
                            }
                        }
                    }
                }
            } else {
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

    func strainColor(_ strain: BridgeStrain) -> Color {
        switch strain {
        case .clubs: return Color(red: 0.2, green: 0.62, blue: 0.3)
        case .diamonds: return Color(red: 0.88, green: 0.3, blue: 0.2)
        case .hearts: return Color(red: 0.88, green: 0.2, blue: 0.3)
        case .spades: return Color(white: 0.15)
        case .notrump: return Color(red: 0.2, green: 0.45, blue: 0.85)
        }
    }

    var body: some View {
        let legal = bridge?.legalCalls() ?? []
        VStack(spacing: 6) {
            if let bridge, !bridge.calls.isEmpty {
                // Auction grid: 4 columns (seats), rows fill from dealer onward
                let dealer = bridge.dealer
                let calls = bridge.calls
                let total = dealer + calls.count
                let rows = Int(ceil(Double(total) / 4.0))
                VStack(spacing: 2) {
                    // Header: seat labels
                    HStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { col in
                            let seat = col
                            Text(session.playerName(seat: seat).prefix(4))
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(seat == bridge.currentPlayer ? .yellow : .white.opacity(0.5))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<4, id: \.self) { col in
                                let callIndex = row * 4 + col - dealer
                                Group {
                                    if callIndex < 0 {
                                        Text("—").font(.system(size: 9)).foregroundStyle(.white.opacity(0.2))
                                    } else if callIndex < calls.count {
                                        let call = calls[callIndex]
                                        if case .bid(let lvl, let strain) = call {
                                            Text("\(lvl)\(strain.label)")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 3)
                                                .padding(.vertical, 1)
                                                .background(strainColor(strain), in: RoundedRectangle(cornerRadius: 3))
                                        } else {
                                            Text(call.label)
                                                .font(.system(size: 9))
                                                .foregroundStyle(.white.opacity(0.55))
                                        }
                                    } else {
                                        Text("").font(.system(size: 9))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
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
