import SwiftUI

/// Container for an active session: lobby, the game itself, the pass-and-play
/// curtain, results, and errors.
struct TableView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session: GameSession

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
                }
            }
            .navigationTitle(session.lobby.gameKind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Leave") { model.endSession() }
                        .tint(.white)
                }
                if session.supportsUndo {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            session.undo()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .tint(.white)
                        .disabled(!session.canUndo)
                    }
                }
                if model.activeMatch != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Label("Match", systemImage: "trophy.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.yellow)
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let game = session.game, game.resultText == nil {
                    Text(statusLine(game))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.35), in: Capsule())
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
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
        return VStack(spacing: 16) {
            Image(systemName: "hand.point.right.fill")
                .font(.system(size: 44))
            Text("Pass the device to \(session.playerName(seat: seat))")
                .font(.title3.weight(.semibold))
            Button("I'm \(session.playerName(seat: seat)) — show my cards") {
                session.revealForHandoff()
            }
            .buttonStyle(.borderedProminent)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.92))
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
        VStack(spacing: 16) {
            if localOutcome == false {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.yellow)
                    .shadow(color: .yellow.opacity(0.5), radius: 10)
            }
            Text(result)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            if model.activeMatch != nil {
                Text("Result recorded when you leave the table.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            HStack {
                if session.role == .local {
                    Button("Play again") { model.playAgain() }
                        .buttonStyle(.borderedProminent)
                }
                Button(model.activeMatch != nil ? "Back to standings" : "Leave table") {
                    model.endSession()
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
        }
        .foregroundStyle(.white)
        .padding(28)
        .background(.ultraThinMaterial.shadow(.drop(color: .black.opacity(0.4), radius: 16)),
                    in: RoundedRectangle(cornerRadius: 20))
        .environment(\.colorScheme, .dark)
        .padding(30)
    }
}

struct LobbyWaitView: View {
    @ObservedObject var session: GameSession

    var body: some View {
        VStack(spacing: 18) {
            Text(session.lobby.gameKind.title)
                .font(.largeTitle.weight(.bold))
            Text(session.role == .host
                 ? "Waiting for players nearby… seats fill in join order. Empty seats become bots when you start."
                 : "Waiting for the host to start the game…")
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            VStack(spacing: 8) {
                ForEach(0..<session.seatsTotal, id: \.self) { seat in
                    HStack {
                        Image(systemName: seat < session.seatsFilled ? "person.fill" : "person")
                        Text(session.lobby.players[safe: seat]?.name ?? "Open seat")
                        Spacer()
                        if session.lobby.players[safe: seat]?.id == session.myID {
                            Text("you").font(.caption).opacity(0.7)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.white.opacity(seat < session.seatsFilled ? 0.18 : 0.07),
                                in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .frame(maxWidth: 320)

            if session.role == .host {
                Button(session.seatsFilled > 1 ? "Start game" : "Start with bots") {
                    session.startHostedGame()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                ProgressView().tint(.white)
            }
        }
        .foregroundStyle(.white)
    }
}
