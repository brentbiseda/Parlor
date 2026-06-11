import SwiftUI

/// Container for an active session: lobby, the game itself, the pass-and-play
/// curtain, results, and errors.
struct TableView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session: GameSession

    var body: some View {
        NavigationStack {
            ZStack {
                FeltBackground()
                if session.game == nil {
                    LobbyWaitView(session: session)
                } else {
                    gameBody
                }

                if session.needsHandoff {
                    handoffCurtain
                }

                if let result = session.game?.resultText {
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
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let game = session.game, game.resultText == nil {
                    Text(statusLine(game))
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .background(.black.opacity(0.25))
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
        if !game.isOver {
            let seat = game.currentPlayer
            if session.actionableSeat != nil {
                line += " — your move"
            } else if game.playerCount > 1 {
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
        case .mahjong:
            MahjongView(session: session)
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

    func resultBanner(_ result: String) -> some View {
        VStack(spacing: 14) {
            Text(result)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            HStack {
                if session.role == .local {
                    Button("Play again") { model.playAgain() }
                        .buttonStyle(.borderedProminent)
                }
                Button("Leave table") { model.endSession() }
                    .buttonStyle(.bordered)
                    .tint(.white)
            }
        }
        .foregroundStyle(.white)
        .padding(24)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
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
