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
        var lines = (0..<4).map { s in
            let total = scores[s]
            let thisRound = roundPoints[s]
            let moonCount = roundHistory.filter { $0[s] == 26 }.count
            let moonStr = moonCount > 0 ? " 🌙×\(moonCount)" : ""
            return "S\(s+1): \(total)\(thisRound > 0 ? " (+\(thisRound) this round)" : "")\(moonStr)"
        }
        if !roundHistory.isEmpty {
            lines.append("")
            lines.append("Round history (newest first):")
            for (i, deltas) in roundHistory.prefix(8).enumerated() {
                let parts = (0..<4).map { s in
                    deltas[s] == 26 ? "🌙" : deltas[s] == 0 ? "–" : "+\(deltas[s])"
                }
                lines.append("R\(roundHistory.count - i): " + parts.joined(separator: "  "))
            }
        }
        return lines
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
        var lines = [0, 1].map { t in
            let nilRecord: String = {
                let m = nilsMade[t]; let b = nilsBusted[t]
                guard m + b > 0 else { return "" }
                return m > 0 && b > 0 ? " · nil \(m)✓\(b)✗" : m > 0 ? " · nil \(m)✓" : " · nil \(b)✗"
            }()
            return "\(teamLabel(t)): \(teamScores[t]) pts · \(teamBags[t]) bags\(nilRecord)"
        }
        if let summary = lastRoundSummary {
            lines.append("")
            lines.append("Last round: \(summary)")
        }
        return lines
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
        [0, 1].map { t in
            var line = "\(teamLabel(t)): \(teamScores[t]) of 10"
            if teamEuchres[t] > 0 { line += " · \(teamEuchres[t]) euchre\(teamEuchres[t] == 1 ? "" : "s")" }
            if lonersAttempted[t] > 0 { line += " · ⚡\(teamLoneMarches[t])/\(lonersAttempted[t]) loner" }
            if teamBestStreak[t] >= 3 { line += " · 🔥\(teamBestStreak[t]) streak" }
            return line
        }
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
    @State private var moonPulse = false
    // Improvement 14: round-summary pop scale
    @State private var summaryScale: CGFloat = 1.0

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
                    // Improvement 13: trick count progress bar beneath the trick pile
                    if let hearts = game.engine as? HeartsGame, hearts.phase == .playing {
                        let taken = hearts.tricksPlayed
                        let total = 13
                        GeometryReader { barGeo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.10))
                                    .frame(height: 4)
                                Capsule()
                                    .fill(Color.green.opacity(0.75))
                                    .frame(width: total > 0 ? barGeo.size.width * CGFloat(taken) / CGFloat(total) : 0, height: 4)
                                    .animation(.easeOut(duration: 0.3), value: taken)
                            }
                        }
                        .frame(height: 4)
                        .padding(.horizontal, 12)
                        .overlay(alignment: .trailing) {
                            Text("\(taken)/\(total)")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.45))
                                .padding(.trailing, 4)
                        }
                    } else if let spades = game.engine as? SpadesGame, spades.phase == .playing {
                        let taken = (0..<4).reduce(0) { $0 + spades.tricksWon[$1] }
                        GeometryReader { barGeo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.10))
                                    .frame(height: 4)
                                Capsule()
                                    .fill(Color.blue.opacity(0.7))
                                    .frame(width: barGeo.size.width * CGFloat(taken) / 13.0, height: 4)
                                    .animation(.easeOut(duration: 0.3), value: taken)
                            }
                        }
                        .frame(height: 4)
                        .padding(.horizontal, 12)
                        .overlay(alignment: .trailing) {
                            Text("\(taken)/13")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.45))
                                .padding(.trailing, 4)
                        }
                    }
                    ZStack(alignment: .topLeading) {
                        trickArea(adapter: adapter, perspective: perspective)
                        // Trump suit badge shown during playing phase
                        if let trump = activeTrump(game: game) {
                            VStack(spacing: 2) {
                                Text(trump.symbol)
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(trump.isRed ? .red : .primary)
                                // For Euchre: show maker team and streak
                                if let euchre = game.engine as? EuchreGame,
                                   let makerTeam = euchre.makerTeam {
                                    let streakTeam = makerTeam
                                    let streak = euchre.teamRoundStreak[streakTeam]
                                    let makerLabel = "T\(makerTeam + 1) made"
                                    HStack(spacing: 2) {
                                        Text(makerLabel)
                                            .font(.system(size: 8, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.7))
                                        if streak >= 2 {
                                            Text("🔥\(streak)")
                                                .font(.system(size: 8, weight: .bold))
                                        }
                                    }
                                }
                            }
                            .padding(6)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder((trump.isRed ? Color.red : Color.white).opacity(0.35), lineWidth: 1))
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
                    // Hearts received-cards strip (shown at start of play after passing).
                    if let hearts = game.engine as? HeartsGame, hearts.phase == .playing,
                       hearts.tricksPlayed == 0, !hearts.receivedCards[perspective].isEmpty {
                        let received = hearts.receivedCards[perspective]
                        let hasDanger = received.contains {
                            ($0.suit == .spades && $0.rank == .queen) ||
                            ($0.suit == .hearts && $0.rank >= .king)
                        }
                        HStack(spacing: 4) {
                            Text("Received:")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.white.opacity(0.55))
                            ForEach(received, id: \.self) { card in
                                let isQueen = card.suit == .spades && card.rank == .queen
                                Text(card.label)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(isQueen ? .red : card.suit.isRed ? .pink : .white.opacity(0.85))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(isQueen ? Color.red.opacity(0.18) : .white.opacity(0.07), in: Capsule())
                            }
                            if hasDanger {
                                Text("⚠️")
                                    .font(.system(size: 9))
                            }
                        }
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
                        // Improvement 14: spring pop scale on round summary capsule
                        .scaleEffect(summaryScale)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        .animation(.easeInOut(duration: 0.25), value: summary)
                        .onChange(of: summary) { _, _ in
                            summaryScale = 1.0
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                                summaryScale = 1.1
                            }
                            Task { @MainActor in
                                do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }
                                withAnimation(.spring(response: 0.2)) { summaryScale = 1.0 }
                            }
                        }
                    }

                    // Spades last-round summary pill (shown during bidding after a round ends).
                    if let spades = game.engine as? SpadesGame, spades.phase == .bidding,
                       let summary = spades.lastRoundSummary {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2)
                                .foregroundStyle(.cyan.opacity(0.85))
                            Text(summary)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.cyan.opacity(0.10), in: Capsule())
                        .overlay(Capsule().strokeBorder(.cyan.opacity(0.25), lineWidth: 0.75))
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        .padding(.bottom, 2)
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
            // Alone indicator with march progress
            if euchre.aloneSeat != nil {
                let marchLeft = max(0, 5 - makerTricks)
                let aloneText = marchLeft == 0 ? "⚡MARCH!" : "⚡ALONE \(makerTricks)/5"
                let aloneColor: Color = marchLeft == 0 ? .green : .yellow
                Text(aloneText)
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(aloneColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(aloneColor.opacity(0.2), in: Capsule())
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
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(ourTricks)/\(ourContract) · \(theirTricks)/\(theirContract)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .monospacedDigit()
                // Bag penalty imminent: bags >= 8 this round will trigger the -100 penalty
                let usBagNow = spades.teamBags[us]
                let usOverTricks = ourTricks > ourContract ? ourTricks - ourContract : 0
                let projBags = usBagNow + usOverTricks
                if projBags >= 8 && usBagNow < 10 {
                    Text("🎒 PENALTY!")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(Color.red.opacity(0.15), in: Capsule())
                }
                // Nil bid status chips: show for any seat with a nil bid
                let nilSeats = (0..<4).filter { spades.bids[$0] == 0 }
                if !nilSeats.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(nilSeats, id: \.self) { seat in
                            let tricks = spades.tricksWon[seat]
                            let busted = tricks > 0
                            let atRisk = !busted && spades.phase == .playing
                            HStack(spacing: 2) {
                                Image(systemName: busted ? "xmark.circle.fill" : "shield.fill")
                                    .font(.system(size: 7))
                                    .foregroundStyle(busted ? .red : .green)
                                Text("S\(seat+1) NIL\(busted ? " ✗(\(tricks))" : " ✓")")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(busted ? .red : atRisk ? .green : .green)
                            }
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(busted ? Color.red.opacity(0.18) : Color.green.opacity(0.15), in: Capsule())
                            .overlay(Capsule().strokeBorder(busted ? Color.red.opacity(0.4) : Color.green.opacity(0.3), lineWidth: 0.5))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Hearts round score chips

    @ViewBuilder
    func heartsRoundChips(hearts: HeartsGame, perspective: Int) -> some View {
        let moonAttempt = (0..<4).first { seat in hearts.roundPoints[seat] >= 12 && (1..<4).allSatisfy({ i in i == seat || hearts.roundPoints[i] == 0 }) }
        // Identify who holds the Queen of Spades point (13 pts in this round, among those with pts ≥ 13)
        let queenHolder: Int? = hearts.queenPlayed ? (0..<4).first(where: { hearts.roundPoints[$0] >= 13 }) : nil
        HStack(spacing: 5) {
            ForEach(0..<4, id: \.self) { seat in
                let pts = hearts.roundPoints[seat]
                let isMoonCandidate = moonAttempt == seat
                let isMe = seat == perspective
                let hasQueen = queenHolder == seat
                let _ = { if isMoonCandidate && !moonPulse { DispatchQueue.main.async { moonPulse = true } } }()
                HStack(spacing: 2) {
                    if hasQueen {
                        Text("♛")
                            .font(.system(size: 8))
                            .foregroundStyle(.red)
                    }
                    Text(String(session.playerName(seat: seat).prefix(4)))
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    let heartOnly = hearts.roundHeartsTaken[seat]
                    if pts > 0 {
                        Text("+\(pts)")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(isMoonCandidate ? .yellow : pts >= 13 ? .red : pts > 0 ? .orange : .white.opacity(0.5))
                        // Show breakdown: ♥N if hearts>0 and queen was also taken
                        if hasQueen && heartOnly > 0 {
                            Text("♥\(heartOnly)")
                                .font(.system(size: 7))
                                .foregroundStyle(.pink.opacity(0.85))
                        }
                    } else {
                        Text("–")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(isMoonCandidate ? Color.yellow.opacity(moonPulse ? 0.25 : 0.12) : hasQueen ? Color.red.opacity(0.12) : isMe ? .white.opacity(0.1) : .clear,
                            in: Capsule())
                .overlay(isMoonCandidate ? Capsule().strokeBorder(.yellow.opacity(moonPulse ? 0.8 : 0.4), lineWidth: 1.5)
                         : hasQueen ? Capsule().strokeBorder(.red.opacity(0.4), lineWidth: 1) : nil)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: moonPulse)
            }
            if let moon = moonAttempt {
                let moonPts = hearts.roundPoints[moon]
                let queenIn = hearts.queenPlayed && (hearts.roundPoints[moon] >= 13)
                let needed = 26 - moonPts
                VStack(alignment: .leading, spacing: 2) {
                    Text("🌙 \(moonPts)/26")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.yellow)
                    if needed > 0 && !queenIn {
                        Text("♛ not yet")
                            .font(.system(size: 7))
                            .foregroundStyle(.orange.opacity(0.8))
                    }
                }
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
            let theirTricks = g.tricksWon[1 - us] + g.tricksWon[(1 - us) + 2]
            let ourContract = g.teamContract(us)
            let theirContract = g.teamContract(1 - us)
            let projBag = g.phase == .playing && ourContract > 0 && ourTricks > ourContract
                ? " +\(ourTricks - ourContract)🎒" : ""
            let projNote = g.phase == .playing && ourContract > 0
                ? (ourTricks >= ourContract ? "✓" : "\(ourTricks)/\(ourContract)") : nil
            // Projected round score for each team if current state persists
            let ourProjScore: Int? = g.phase == .playing && ourContract > 0 ? {
                if ourTricks >= ourContract { return 10 * ourContract + (ourTricks - ourContract) }
                return -10 * ourContract
            }() : nil
            let theirProjScore: Int? = g.phase == .playing && theirContract > 0 ? {
                if theirTricks >= theirContract { return 10 * theirContract + (theirTricks - theirContract) }
                return -10 * theirContract
            }() : nil
            HStack(spacing: 8) {
                let usNilDetail: String? = {
                    let m = g.nilsMade[us]; let b = g.nilsBusted[us]
                    guard m + b > 0 else { return nil }
                    return m > 0 && b > 0 ? "nil \(m)✓\(b)✗" : m > 0 ? "nil \(m)✓" : "nil \(b)✗"
                }()
                let themNilDetail: String? = {
                    let m = g.nilsMade[1 - us]; let b = g.nilsBusted[1 - us]
                    guard m + b > 0 else { return nil }
                    return m > 0 && b > 0 ? "nil \(m)✓\(b)✗" : m > 0 ? "nil \(m)✓" : "nil \(b)✗"
                }()
                let usPerfect = g.perfectBids[us]
                let themPerfect = g.perfectBids[1 - us]
                let usPerfectStr = usPerfect >= 2 ? " · 🎯×\(usPerfect)" : ""
                let themPerfectStr = themPerfect >= 2 ? " · 🎯×\(themPerfect)" : ""
                let usDetail = (usNilDetail.map { "\(usBags)🎒\(projBag) · \($0)" } ?? "\(usBags)🎒\(projBag)") + usPerfectStr
                let themDetail = (themNilDetail.map { "\(themBags)🎒 · \($0)" } ?? "\(themBags)🎒") + themPerfectStr
                scoreChip("Us", "\(g.teamScores[us])", detail: usDetail,
                          highlight: true, bagWarning: usBags >= 7)
                    .scaleEffect(usBags >= 7 && bagPulse ? 1.06 : 1.0)
                VStack(spacing: 1) {
                    Text("to 500").font(.caption2).foregroundStyle(.white.opacity(0.5))
                    if let note = projNote {
                        Text(note)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(note == "✓" ? .green : .white.opacity(0.6))
                    }
                    if let us = ourProjScore, let them = theirProjScore {
                        let usPlusMinus = us >= 0 ? "+\(us)" : "\(us)"
                        let themPlusMinus = them >= 0 ? "+\(them)" : "\(them)"
                        Text("\(usPlusMinus)/\(themPlusMinus)")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(us < 0 ? .red : them < 0 ? .green : .white.opacity(0.5))
                    }
                }
                scoreChip("Them", "\(g.teamScores[1 - us])", detail: themDetail,
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
            let usLonerDetail: String? = {
                let att = g.lonersAttempted[us]; let won = g.teamLoneMarches[us]
                guard att > 0 else { return nil }
                return "⚡\(won)/\(att)"
            }()
            let themLonerDetail: String? = {
                let att = g.lonersAttempted[1 - us]; let won = g.teamLoneMarches[1 - us]
                guard att > 0 else { return nil }
                return "⚡\(won)/\(att)"
            }()
            let usChipDetail = [usStreak >= 2 ? "🔥\(usStreak)" : nil, usLonerDetail]
                .compactMap { $0 }.joined(separator: " ")
            let themChipDetail = [themStreak >= 2 ? "🔥\(themStreak)" : nil, themLonerDetail]
                .compactMap { $0 }.joined(separator: " ")
            HStack(spacing: 8) {
                scoreChip("Us", "\(g.teamScores[us])",
                          detail: usChipDetail.isEmpty ? nil : usChipDetail, highlight: true)
                Text("to 10").font(.caption2).foregroundStyle(.white.opacity(0.5))
                scoreChip("Them", "\(g.teamScores[1 - us])",
                          detail: themChipDetail.isEmpty ? nil : themChipDetail, highlight: false)
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
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { seat in
                        let isLeading = g.scores[seat] == g.scores.min()!
                        let isDanger = g.scores[seat] >= 85
                        scoreChip(String(seatName(seat).prefix(4)),
                                  "\(g.scores[seat])",
                                  detail: isLeading && g.scores.min()! > 0 ? "★" : (isDanger ? "⚠️" : nil),
                                  highlight: seat == perspective,
                                  bagWarning: isDanger)
                    }
                    if g.heartsBroken && g.phase == .playing {
                        Image(systemName: "heart.slash.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(5)
                            .background(.black.opacity(0.3), in: Circle())
                    }
                }
                // Show spread and round history
                if g.phase == .playing {
                    let spread = (g.scores.max() ?? 0) - (g.scores.min() ?? 0)
                    HStack(spacing: 6) {
                        if spread > 0 {
                            Text("spread \(spread)")
                                .font(.system(size: 8))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        // Last 3 rounds mini history for the perspective seat
                        let recent = g.roundHistory.prefix(3)
                        if !recent.isEmpty {
                            HStack(spacing: 3) {
                                ForEach(Array(recent.reversed().enumerated()), id: \.offset) { _, deltas in
                                    let pts = deltas[perspective]
                                    Text(pts == 0 ? "–" : "+\(pts)")
                                        .font(.system(size: 7, weight: .semibold))
                                        .foregroundStyle(pts == 0 ? .green.opacity(0.7) : pts >= 13 ? .red : .white.opacity(0.5))
                                        .padding(.horizontal, 3)
                                        .padding(.vertical, 1)
                                        .background(pts >= 13 ? Color.red.opacity(0.15) : .white.opacity(0.04), in: Capsule())
                                }
                            }
                        }
                    }
                }
            }
        default:
            EmptyView()
        }
    }

    /// Cards from `hand` that are risky to keep in Hearts: Q♠, high hearts (A/K/Q), high spades (A/K).
    func heartsDangerCards(_ hand: [Card]) -> [Card] {
        hand.filter { card in
            let isQueenSpades = card.suit == .spades && card.rank == .queen
            let isHighHeart = card.suit == .hearts && card.rank >= .queen
            let isHighSpade = card.suit == .spades && card.rank >= .king && card.rank != .queen
            return isQueenSpades || isHighHeart || isHighSpade
        }.sorted { lhs, rhs in
            let score: (Card) -> Int = { c in
                if c.suit == .spades && c.rank == .queen { return 100 }
                if c.suit == .hearts { return c.rank.rawValue + 20 }
                return c.rank.rawValue
            }
            return score(lhs) > score(rhs)
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
        // During passing: highlight cards the player can still pick (not yet in selection,
        // slot still open). Once 3 are chosen, no more yellow borders. Selected cards get
        // the green checkmark via the `selected:` parameter.
        let legalCards = adapter.legalCardSet
        let legal: Set<Card>
        if isPassing {
            legal = passSelection.count < 3
                ? Set(adapter.hands[handSeat]).subtracting(passSelection)
                : []
        } else {
            legal = legalCards
        }

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
                // Suit distribution + risk indicator during passing
                if let hearts = game.engine as? HeartsGame, direction != "hold" {
                    let hand = hearts.hands[session.perspectiveSeat]
                    let bySuit = Dictionary(grouping: hand, by: \.suit)
                    let keeping = hand.filter { !passSelection.contains($0) }
                    let dangerous = heartsDangerCards(keeping)
                    // Suit count pips: show how many cards per suit remain after selection
                    let keepBySuit = Dictionary(grouping: keeping, by: \.suit)
                    HStack(spacing: 6) {
                        ForEach(Suit.allCases, id: \.self) { suit in
                            let total = (bySuit[suit] ?? []).count
                            let kept = (keepBySuit[suit] ?? []).count
                            let isDanger = suit == .hearts || suit == .spades
                            HStack(spacing: 2) {
                                Text(suit.symbol)
                                    .font(.system(size: 9))
                                    .foregroundStyle(suit.isRed ? .red : .white.opacity(0.8))
                                Text("\(kept)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(isDanger && kept >= 4 ? .orange : .white.opacity(0.7))
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(total != kept ? Color.yellow.opacity(0.08) : Color.white.opacity(0.05),
                                        in: Capsule())
                        }
                    }
                    if !dangerous.isEmpty {
                        HStack(spacing: 4) {
                            Text("Keep risk:")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.white.opacity(0.55))
                            ForEach(dangerous, id: \.self) { card in
                                let isQueen = card.suit == .spades && card.rank == .queen
                                Text(card.label)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(isQueen ? .red : card.suit.isRed ? .pink : .orange)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(isQueen ? Color.red.opacity(0.2) : Color.pink.opacity(0.15),
                                                in: Capsule())
                            }
                        }
                    }
                }
                Button {
                    session.submit(.passCards(Array(passSelection).displaySorted()))
                    passSelection = []
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "paperplane.fill")
                        // Improvement 15: show pass direction arrow in the button label
                        let dirArrow: String = switch direction {
                        case "left": "←"
                        case "right": "→"
                        case "across": "↕"
                        default: "⟳"
                        }
                        Text("\(dirArrow) Pass \(passSelection.count)/3")
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
                // Show trump strength if player orders up this suit
                if let euchre = game.engine as? EuchreGame {
                    let seat = euchre.currentPlayer
                    let hand = euchre.hands[seat]
                    let partner = euchre.sittingOut == nil ? (seat + 2) % 4 : -1
                    // Count trump cards including the upcard (right/left bower + regular trump)
                    let trumpSuit = upcard.suit
                    let partnerSuit = trumpSuit.sameColorPartner
                    let trumpCards = hand.filter { card in
                        card.suit == trumpSuit || (card.rank == .jack && card.suit == partnerSuit)
                    }
                    let hasRightBower = hand.contains { $0.rank == .jack && $0.suit == trumpSuit }
                    let hasLeftBower = hand.contains { $0.rank == .jack && $0.suit == partnerSuit }
                    let trumpCount = trumpCards.count + (euchre.dealer == seat ? 1 : 0)
                    let strength = trumpCount >= 4 ? "Strong" : trumpCount >= 3 ? "Good" : "Weak"
                    let strengthColor: Color = trumpCount >= 4 ? .green : trumpCount >= 3 ? .yellow : .orange
                    HStack(spacing: 6) {
                        Text("\(trumpSuit.symbol) strength: \(strength) (\(trumpCount) trump)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(strengthColor)
                        if hasRightBower { Text("R♖").font(.system(size: 9, weight: .black)).foregroundStyle(.yellow) }
                        if hasLeftBower  { Text("L♖").font(.system(size: 9, weight: .black)).foregroundStyle(.yellow.opacity(0.8)) }
                    }
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
                // Show suit strength for each option
                if let euchre = game.engine as? EuchreGame {
                    let seat = euchre.currentPlayer
                    let hand = euchre.hands[seat]
                    HStack(spacing: 8) {
                        ForEach(Suit.allCases.filter { $0 != excluded }, id: \.self) { suit in
                            let partnerSuit = suit.sameColorPartner
                            let trumpCount = hand.filter { $0.suit == suit || ($0.rank == .jack && $0.suit == partnerSuit) }.count
                            VStack(spacing: 1) {
                                Text(suit.symbol)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(suit.isRed ? .red : .white)
                                Text("\(trumpCount)")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(trumpCount >= 3 ? .yellow : .white.opacity(0.6))
                            }
                        }
                    }
                }
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
            // HCP display for the local player during auction
            if let bridge, !bridge.isOver, bridge.contract == nil {
                let seat = session.perspectiveSeat
                let hand = bridge.hands[seat]
                let hcp = TrickTaking.highCardPoints(hand: hand)
                let bySuit = Dictionary(grouping: hand, by: \.suit)
                let suitLengths = Suit.allCases.map { (bySuit[$0] ?? []).count }.sorted(by: >)
                let hasVoid = suitLengths.contains(0)
                let hasSingleton = suitLengths.contains(1)
                let handShape: String = {
                    if suitLengths[0] >= 6 { return "Long (\(suitLengths[0]))" }
                    if suitLengths[0] >= 5 { return "Semi-Bal" }
                    if hasVoid || hasSingleton { return "Unbal" }
                    return "Balanced"
                }()
                let shapeColor: Color = hasVoid || suitLengths[0] >= 6 ? .yellow : hasSingleton ? .orange : .green
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Text("HCP:")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("\(hcp)")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(hcp >= 15 ? .yellow : hcp >= 12 ? .white : .white.opacity(0.7))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(hcp >= 12 ? Color.white.opacity(0.12) : Color.white.opacity(0.06),
                                in: Capsule())
                    Text(handShape)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(shapeColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(shapeColor.opacity(0.12), in: Capsule())
                    ForEach(Suit.allCases, id: \.self) { suit in
                        let cards = (bySuit[suit] ?? []).sorted { $0.rank.rawValue > $1.rank.rawValue }
                        if !cards.isEmpty {
                            Text("\(suit.symbol)\(cards.count)" + (cards.first.map { $0.rank >= .ace ? "A" : $0.rank >= .king ? "K" : "" } ?? ""))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(suit.isRed ? .red : .white.opacity(0.85))
                        }
                    }
                }
            }
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
