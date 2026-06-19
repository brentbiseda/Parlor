import SwiftUI
import UIKit

/// Container for an active session: lobby, the game itself, the pass-and-play
/// curtain, results, and errors.
struct TableView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session: GameSession
    @State private var trophyPulse = false
    // 2. Turn indicator glow state.
    @State private var turnPulse = false
    // 3. Medal chip appear animation state.
    @State private var medalsAppeared = false
    // 5. Game-over confetti dot positions (static colored dots near result banner).
    private let confettiDots: [(CGFloat, CGFloat, Color)] = [
        (-55, -18, Color(red: 1.0, green: 0.84, blue: 0.0)),
        (50, -12, Color(red: 0.3, green: 0.9, blue: 0.45)),
        (-30, 14, Color(red: 0.2, green: 0.7, blue: 1.0)),
        (65, 20, Color(red: 1.0, green: 0.35, blue: 0.7)),
        (-70, 5, Color(red: 0.65, green: 0.3, blue: 1.0)),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                switch session.lobby.gameKind.section {
                case .arcade, .sports:
                    ArcadeBackground()
                case .puzzles where session.lobby.gameKind != .solitaire
                    && session.lobby.gameKind != .freecell && session.lobby.gameKind != .mahjong:
                    ArcadeBackground()
                default:
                    FeltBackground(inlay: session.lobby.gameKind.section == .cards)
                }
                if session.game == nil {
                    LobbyWaitView(session: session)
                } else {
                    gameBody
                }

                if session.needsHandoff {
                    handoffCurtain
                }

                if let result = session.game?.resultText {
                    if localOutcome != false {
                        ConfettiView()
                            .allowsHitTesting(false)
                    }
                    resultBanner(result)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.spring(response: 0.55, dampingFraction: 0.72), value: result)
                }
            }
            .navigationTitle(session.lobby.gameKind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // 4. Haptic feedback on leave — consequential action deserves tactile confirmation.
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        model.endSession()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                            Text("Leave")
                                .font(.callout.weight(.medium))
                        }
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.12), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 0.75))
                    }
                    .buttonStyle(.plain)
                }
                if session.supportsUndo {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            session.undo()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white.opacity(session.canUndo ? 0.9 : 0.3))
                                .frame(width: 34, height: 34)
                                .background(.white.opacity(session.canUndo ? 0.12 : 0.06), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!session.canUndo)
                    }
                }
                if model.activeMatch != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 5) {
                            Image(systemName: "trophy.fill")
                                .foregroundStyle(.yellow)
                            Text("Match")
                                .foregroundStyle(.yellow)
                        }
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(.yellow.opacity(0.15), in: Capsule())
                        .overlay(Capsule().strokeBorder(.yellow.opacity(0.35), lineWidth: 0.75))
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let game = session.game, game.resultText == nil {
                    VStack(spacing: 4) {
                        // Player turn strip for multiplayer games.
                        if game.playerCount > 1 {
                            HStack(spacing: 0) {
                                ForEach(0..<game.playerCount, id: \.self) { seat in
                                    let isCurrent = seat == game.controller(of: game.currentPlayer)
                                    let isYou = session.localHumanSeats.contains(seat)
                                    let isBot = session.lobby.players[safe: seat]?.isBot == true
                                    PlayerAvatarCell(
                                        name: session.playerName(seat: seat),
                                        isCurrent: isCurrent,
                                        isYou: isYou,
                                        isBot: isBot
                                    )
                                    .frame(maxWidth: .infinity)
                                    .accessibilityLabel("\(session.playerName(seat: seat))\(isCurrent ? ", current turn" : "")\(isYou ? ", you" : "")\(isBot ? ", bot" : "")")
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                        }

                        HStack(spacing: 6) {
                            if session.actionableSeat != nil {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                    .accessibilityHidden(true)
                            }
                            // 1. Capsule background wrapping status text for better readability.
                            // 6. lineLimit(2) + minimumScaleFactor(0.78) for long Chess/Go strings.
                            Text(statusLine(game))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .minimumScaleFactor(0.78)
                                .multilineTextAlignment(.center)
                                .accessibilityLabel(statusLine(game))
                                .padding(.horizontal, 10)
                                .background(Capsule().fill(Color.primary.opacity(0.06)))
                        }
                        .accessibilityElement(children: .combine)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 5)
                        .background {
                            ZStack {
                                Color.black.opacity(0.45)
                                LinearGradient(colors: [.white.opacity(0.07), .clear],
                                               startPoint: .top, endPoint: .bottom)
                            }
                            .clipShape(Capsule())
                        }
                        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.75))
                        // 2. Animated green glow when it's the local human's turn.
                        .shadow(color: session.actionableSeat != nil
                                    ? .green.opacity(turnPulse ? 0.4 : 0.15)
                                    : .black.opacity(0.3),
                                radius: session.actionableSeat != nil ? 8 : 6, y: 2)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                                turnPulse = true
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 5)
                    }
                    .background {
                        ZStack {
                            Color.black.opacity(0.25)
                            LinearGradient(colors: [Color.black.opacity(0.3), .clear],
                                           startPoint: .top, endPoint: .bottom)
                        }
                        .ignoresSafeArea()
                    }
                }
            }
            .alert("Oops", isPresented: Binding(
                get: { session.toast != nil },
                set: { if !$0 { session.toast = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(session.toast ?? "")
            }
            .onChange(of: session.ended) { _, ended in
                if ended { model.session = nil }
            }
        }
    }

    func statusLine(_ game: AnyGame) -> String {
        var line = game.statusText
        if !game.isOver, game.playerCount > 1 {
            let seat = game.currentPlayer
            if session.actionableSeat != nil {
                line += " — your move"
            } else {
                line += " — \(session.playerName(seat: game.controller(of: seat)))"
            }
        }
        return line
    }

    @ViewBuilder
    var gameBody: some View {
        switch session.lobby.gameKind {
        case .hearts, .spades, .euchre, .bridge:
            TrickTableView(session: session)
        case .chess, .checkers:
            GridBoardView(session: session)
        case .go:
            GoBoardView(session: session)
        case .solitaire:
            KlondikeView(session: session)
        case .freecell:
            FreeCellView(session: session)
        case .mahjong:
            MahjongView(session: session)
        case .uno:
            UnoView(session: session)
        case .eights:
            EightsView(session: session)
        case .gofish:
            GoFishView(session: session)
        case .minesweeper:
            MinesweeperView(session: session)
        // Arcade & sports tables get a fresh scene per session (play again).
        case .pinball:
            PinballView(session: session)
                .id(ObjectIdentifier(session))
        case .breakout:
            BreakoutView(session: session)
                .id(ObjectIdentifier(session))
        case .tetris:
            TetrisView(session: session)
                .id(ObjectIdentifier(session))
        case .capsules:
            CapsulesView(session: session)
                .id(ObjectIdentifier(session))
        case .muncher:
            MuncherView(session: session)
                .id(ObjectIdentifier(session))
        case .hopper:
            HopperView(session: session)
                .id(ObjectIdentifier(session))
        case .centipede:
            CentipedeView(session: session)
                .id(ObjectIdentifier(session))
        case .snake:
            SnakeView(session: session)
                .id(ObjectIdentifier(session))
        case .bomberman:
            BombermanView(session: session)
                .id(ObjectIdentifier(session))
        case .football:
            FootballView(session: session)
                .id(ObjectIdentifier(session))
        case .baseball:
            BaseballView(session: session)
                .id(ObjectIdentifier(session))
        case .soccer:
            SoccerView(session: session)
                .id(ObjectIdentifier(session))
        case .hockey:
            HockeyView(session: session)
                .id(ObjectIdentifier(session))
        }
    }

    var handoffCurtain: some View {
        let seat = session.game.map { $0.controller(of: $0.currentPlayer) } ?? 0
        let name = session.playerName(seat: seat)
        return ZStack {
            Color.black.opacity(0.88)
                .ignoresSafeArea()
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(colors: [Color.teal.opacity(0.3), .clear],
                                           center: .center, startRadius: 0, endRadius: 60))
                        .frame(width: 120, height: 120)
                    Circle()
                        .strokeBorder(.white.opacity(0.15), lineWidth: 1.5)
                        .frame(width: 100, height: 100)
                    Image(systemName: "hand.point.right.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.white)
                }
                VStack(spacing: 8) {
                    Text("Pass the device")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .textCase(.uppercase)
                        .kerning(1.2)
                    Text("to \(name)")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)
                }
                Button {
                    session.revealForHandoff()
                } label: {
                    Label("I'm \(name) — show my cards", systemImage: "eye.fill")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(colors: [Color.teal, Color(red: 0.05, green: 0.4, blue: 0.45)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
            }
            .environment(\.colorScheme, .dark)
        }
    }

    /// Whether the single local player won: true/false, or nil when there's
    /// no meaningful verdict (draws, pass-and-play, score-attack arcade).
    var localOutcome: Bool? {
        guard let game = session.game, game.isOver,
              session.localHumanSeats.count == 1,
              let seat = session.localHumanSeats.first else { return nil }
        if game.playerCount > 1 {
            let ranking = game.ranking()
            guard let top = ranking.first, ranking.count > 1 else { return nil }
            return top.contains(seat)
        }
        switch game.engine {
        case let g as CapsulesGame: return g.cleared
        case let g as MinesweeperGame: return g.won
        case let g as SoccerGame: return g.yourGoals == g.botGoals ? nil : g.won
        case let g as HockeyGame: return g.won
        case is KlondikeGame, is FreeCellGame, is MahjongGame: return true
        default: return nil
        }
    }

    func resultBanner(_ result: String) -> some View {
        let isLoss = localOutcome == false
        let accentColor: Color = isLoss ? Color(red: 0.85, green: 0.22, blue: 0.22) : Color(red: 1.0, green: 0.82, blue: 0.2)
        let bannerGradient: [Color] = isLoss
            ? [Color(red: 0.35, green: 0.08, blue: 0.08), Color(red: 0.18, green: 0.04, blue: 0.04)]
            : [Color(red: 0.38, green: 0.28, blue: 0.0), Color(red: 0.18, green: 0.13, blue: 0.0)]
        let ranking = session.game?.ranking() ?? []
        let isMultiplayer = (session.game?.playerCount ?? 1) > 1

        return VStack(spacing: 0) {
            LinearGradient(colors: bannerGradient, startPoint: .leading, endPoint: .trailing)
                .frame(height: 4)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.18))
                        .frame(width: 80, height: 80)
                    Circle()
                        .strokeBorder(accentColor.opacity(0.35), lineWidth: 1.5)
                        .frame(width: 80, height: 80)
                    if isLoss {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white.opacity(0.8))
                    } else {
                        Circle()
                            .stroke(accentColor.opacity(0.5), lineWidth: 2)
                            .frame(width: 80, height: 80)
                            .scaleEffect(trophyPulse ? 1.25 : 1.0)
                            .opacity(trophyPulse ? 0 : 0.7)
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(accentColor)
                            .shadow(color: accentColor.opacity(0.8), radius: 16)
                            .scaleEffect(trophyPulse ? 1.08 : 1.0)
                    }
                }
                .onAppear {
                    guard !isLoss else { return }
                    withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                        trophyPulse = true
                    }
                }

                VStack(spacing: 5) {
                    if model.lastResultWasPersonalBest {
                        Label("New Personal Best!", systemImage: "star.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.yellow)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.yellow.opacity(0.18), in: Capsule())
                            .overlay(Capsule().strokeBorder(.yellow.opacity(0.4), lineWidth: 1))
                            .transition(.scale.combined(with: .opacity))
                    }
                    Text(isLoss ? "Better luck next time" : "Well played!")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accentColor)
                        .textCase(.uppercase)
                        .kerning(1.2)
                    resultTextView(result)
                }

                // 3. Per-player finish table with spring-animated medal chips.
                if isMultiplayer && !ranking.isEmpty {
                    let medals = ["🥇", "🥈", "🥉"]
                    VStack(spacing: 4) {
                        ForEach(ranking.indices, id: \.self) { groupIdx in
                            let group = ranking[groupIdx]
                            ForEach(group, id: \.self) { seat in
                                HStack(spacing: 10) {
                                    // Medal chip with scale animation on appear.
                                    Text(groupIdx < medals.count ? medals[groupIdx] : "·")
                                        .font(.body)
                                        .frame(width: 24)
                                        .scaleEffect(medalsAppeared ? 1.0 : 0.5)
                                        .animation(
                                            .spring(response: 0.45, dampingFraction: 0.55)
                                            .delay(Double(groupIdx) * 0.12 + Double(group.firstIndex(of: seat) ?? 0) * 0.06),
                                            value: medalsAppeared
                                        )
                                    Text(session.playerName(seat: seat))
                                        .font(.subheadline.weight(groupIdx == 0 ? .semibold : .regular))
                                        .foregroundStyle(groupIdx == 0 ? accentColor : .white.opacity(0.75))
                                    Spacer()
                                    if groupIdx == 0 {
                                        Text("winner")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(accentColor.opacity(0.8))
                                            .textCase(.uppercase)
                                            .kerning(0.8)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(.white.opacity(groupIdx == 0 ? 0.1 : 0.04),
                                            in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .onAppear { medalsAppeared = true }
                    .onDisappear { medalsAppeared = false }
                }

                if model.activeMatch != nil {
                    Label("Result recorded when you leave", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }

                HStack(spacing: 12) {
                    if session.role == .local {
                        Button("Play again") { model.playAgain() }
                            .buttonStyle(.borderedProminent)
                            .tint(isLoss ? Color(red: 0.55, green: 0.12, blue: 0.12) : Color(red: 0.15, green: 0.5, blue: 0.25))
                    }
                    Button(model.activeMatch != nil ? "Back to standings" : "Leave table") {
                        model.endSession()
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    ShareLink(item: result) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.1), in: Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 0.75))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
        .foregroundStyle(.white)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 24).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 24).fill(
                    LinearGradient(
                        colors: isLoss
                            ? [Color(red: 0.22, green: 0.06, blue: 0.06).opacity(0.6), .clear]
                            : [Color(red: 0.25, green: 0.20, blue: 0.0).opacity(0.55), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                // 5. Small static colored dots near the banner for a festive look (win only).
                if !isLoss {
                    ForEach(confettiDots.indices, id: \.self) { idx in
                        let dot = confettiDots[idx]
                        Circle()
                            .fill(dot.2)
                            .frame(width: 6 + CGFloat(idx % 2) * 3, height: 6 + CGFloat(idx % 2) * 3)
                            .offset(x: dot.0, y: dot.1)
                            .opacity(0.72)
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(accentColor.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 24)
        .environment(\.colorScheme, .dark)
        .padding(24)
    }

    /// Breaks "Title · stat1 · stat2" resultText into a bold headline + smaller stat pills.
    @ViewBuilder
    func resultTextView(_ text: String) -> some View {
        let parts = text.components(separatedBy: " · ")
        let isWin: Bool = {
            guard session.localHumanSeats.count == 1,
                  let seat = session.localHumanSeats.first,
                  let ranking = session.game?.ranking(),
                  !ranking.isEmpty else { return false }
            return ranking.first?.contains(seat) ?? false
        }()
        let headline = parts.first.map { isWin ? "🏆 \($0)" : $0 } ?? text
        if parts.count > 1 {
            VStack(spacing: 6) {
                Text(headline)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(parts.dropFirst().prefix(5), id: \.self) { stat in
                            Text(stat)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.82))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.white.opacity(0.1), in: Capsule())
                                .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        } else {
            Text(headline)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
        }
    }
}

struct LobbyWaitView: View {
    @ObservedObject var session: GameSession
    @State private var scanPulse: CGFloat = 0
    @State private var waitDots: Int = 0
    let waitTimer = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()

    var waitingText: String {
        let dots = String(repeating: ".", count: waitDots + 1)
        return "Waiting\(dots)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Game icon with animated ring for the host-searching state.
                ZStack {
                    Circle()
                        .strokeBorder(Color.teal.opacity(0.18 * (1 - scanPulse)), lineWidth: 2)
                        .frame(width: 90, height: 90)
                        .scaleEffect(1 + scanPulse * 0.5)
                    Circle()
                        .fill(Color.teal.opacity(0.12))
                        .frame(width: 72, height: 72)
                    Image(systemName: session.lobby.gameKind.symbolName)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .shadow(color: Color.teal.opacity(0.4), radius: 16)

                VStack(spacing: 6) {
                    Text(session.lobby.gameKind.title)
                        .font(.title.weight(.bold))
                    Text(session.role == .host
                         ? "Waiting for players nearby…"
                         : "Waiting for the host to start…")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }

                // Seat roster.
                VStack(spacing: 8) {
                    ForEach(0..<session.seatsTotal, id: \.self) { seat in
                        let filled = seat < session.seatsFilled
                        let isMe = session.lobby.players[safe: seat]?.id == session.myID
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(filled
                                        ? LinearGradient(colors: [Color.teal, Color.teal.opacity(0.6)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing)
                                        : LinearGradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 38, height: 38)
                                Image(systemName: filled ? "person.fill" : "person")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.white.opacity(filled ? 1 : 0.4))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.lobby.players[safe: seat]?.name ?? "Open seat")
                                    .font(.body.weight(filled ? .semibold : .regular))
                                    .foregroundStyle(.white.opacity(filled ? 1 : 0.45))
                                if !filled && session.role == .host {
                                    Text("Will become a bot")
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.35))
                                }
                            }
                            Spacer()
                            if isMe {
                                Text("you")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.teal)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.teal.opacity(0.18), in: Capsule())
                            } else if !filled && session.role == .host {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.35))
                                    .symbolEffect(.variableColor.iterative, options: .repeating)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            filled
                                ? AnyShapeStyle(LinearGradient(colors: [.white.opacity(0.15), .white.opacity(0.08)],
                                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                                : AnyShapeStyle(.white.opacity(0.05)),
                            in: RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(.white.opacity(filled ? 0.18 : 0.07), lineWidth: 1)
                        )
                        .shadow(color: filled ? Color.teal.opacity(0.15) : .clear, radius: 8, y: 2)
                        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: filled)
                    }
                }
                .frame(maxWidth: 360)

                if session.role == .host {
                    Button {
                        session.startHostedGame()
                    } label: {
                        Label(session.seatsFilled > 1 ? "Start game" : "Start with bots",
                              systemImage: "play.fill")
                            .font(.headline)
                            .frame(minWidth: 220)
                            .padding(.vertical, 15)
                            .background(
                                LinearGradient(colors: [Color.teal, Color(red: 0.05, green: 0.42, blue: 0.46)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.25), lineWidth: 1))
                            .shadow(color: Color.teal.opacity(0.5), radius: 12, y: 5)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                } else {
                    HStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text(waitingText)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.65))
                            .animation(.easeInOut(duration: 0.3), value: waitDots)
                    }
                }
            }
            .padding(24)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .onAppear {
            withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
                scanPulse = 1.0
            }
        }
        .onReceive(waitTimer) { _ in
            waitDots = (waitDots + 1) % 3
        }
    }
}
