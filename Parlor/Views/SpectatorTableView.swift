import SwiftUI

/// Display-only "big screen" table for hidden-hand games (Hearts, Spades,
/// Euchre, Bridge, Uno, Crazy Eights, Go Fish). It reads the host's full
/// authoritative game but renders **only public information** — face-down fans
/// sized to each player's real hand count, the cards already played to the
/// trick, scores/roles, and the live status line. No hand is ever drawn
/// face-up, so the shared screen never leaks anyone's cards.
struct SpectatorTableView: View {
    @ObservedObject var session: GameSession

    private let seatColors: [Color] = [
        Color(red: 0.95, green: 0.78, blue: 0.25),   // bottom
        Color(red: 0.30, green: 0.78, blue: 0.55),   // left
        Color(red: 0.45, green: 0.6, blue: 0.95),    // top
        Color(red: 0.92, green: 0.45, blue: 0.5),    // right
    ]

    var body: some View {
        GeometryReader { geo in
            if let game = session.game {
                let size = geo.size
                let turnSeat = game.isOver ? -1 : game.controller(of: game.currentPlayer)
                ZStack {
                    // Center: the played trick (or a felt emblem for pile games).
                    centerArea(game)
                        .frame(width: size.width * 0.5, height: size.height * 0.42)
                        .position(x: size.width / 2, y: size.height / 2)

                    // Four seats around the rail.
                    ForEach(0..<min(game.playerCount, 4), id: \.self) { seat in
                        seatView(game, seat: seat, isTurn: seat == turnSeat)
                            .position(seatPoint(seat, size: size))
                    }

                    bigScreenBadge
                        .position(x: size.width / 2, y: 22)
                }
                .frame(width: size.width, height: size.height)
            }
        }
    }

    // MARK: - Seats

    private func seatView(_ game: AnyGame, seat: Int, isTurn: Bool) -> some View {
        let color = seatColors[seat]
        return VStack(spacing: 4) {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 0.5))
                Text(session.playerName(seat: seat))
                    .font(.caption.weight(isTurn ? .bold : .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(isTurn ? AnyShapeStyle(color.opacity(0.32)) : AnyShapeStyle(.black.opacity(0.3)),
                        in: Capsule())
            .overlay(Capsule().strokeBorder(isTurn ? color : .white.opacity(0.12),
                                            lineWidth: isTurn ? 1.5 : 0.75))

            OpponentHandView(count: handCount(game, seat), width: 22)

            if let detail = seatDetail(game, seat) {
                Text(detail)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(8)
        .background(.black.opacity(isTurn ? 0.28 : 0.0), in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: isTurn ? color.opacity(0.5) : .clear, radius: 8)
        .animation(.easeInOut(duration: 0.25), value: isTurn)
        .frame(width: 150)
    }

    // MARK: - Center

    @ViewBuilder
    private func centerArea(_ game: AnyGame) -> some View {
        let plays = trickPlays(game)
        if !plays.isEmpty {
            ZStack {
                ForEach(plays, id: \.seat) { play in
                    CardView(card: play.card, width: 46)
                        .offset(trickOffset(play.seat))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.8), value: plays.count)
        } else {
            VStack(spacing: 8) {
                Image(systemName: session.lobby.gameKind.symbolName)
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.35))
                Text(centerHint(game))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var bigScreenBadge: some View {
        Label("BIG SCREEN", systemImage: "tv.fill")
            .font(.system(size: 10, weight: .black))
            .kerning(1.5)
            .foregroundStyle(.teal)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.black.opacity(0.35), in: Capsule())
            .overlay(Capsule().strokeBorder(.teal.opacity(0.4), lineWidth: 0.75))
    }

    // MARK: - Geometry

    /// Seat 0 bottom, 1 left, 2 top, 3 right — matching the trick-table layout.
    private func seatPoint(_ seat: Int, size: CGSize) -> CGPoint {
        let mx = size.width * 0.2, my: CGFloat = 78
        switch seat {
        case 0: return CGPoint(x: size.width / 2, y: size.height - my)
        case 1: return CGPoint(x: mx, y: size.height / 2)
        case 2: return CGPoint(x: size.width / 2, y: my + 8)
        default: return CGPoint(x: size.width - mx, y: size.height / 2)
        }
    }

    private func trickOffset(_ seat: Int) -> CGSize {
        switch seat {
        case 0: return CGSize(width: 0, height: 34)
        case 1: return CGSize(width: -52, height: 0)
        case 2: return CGSize(width: 0, height: -34)
        default: return CGSize(width: 52, height: 0)
        }
    }

    // MARK: - Public-info extraction (never reads card faces of a hand)

    private func handCount(_ game: AnyGame, _ seat: Int) -> Int {
        switch game.engine {
        case let g as HeartsGame: return g.hands[safe: seat]?.count ?? 0
        case let g as SpadesGame: return g.hands[safe: seat]?.count ?? 0
        case let g as EuchreGame: return g.hands[safe: seat]?.count ?? 0
        case let g as BridgeGame: return g.hands[safe: seat]?.count ?? 0
        case let g as UnoGame: return g.hands[safe: seat]?.count ?? 0
        case let g as EightsGame: return g.hands[safe: seat]?.count ?? 0
        case let g as GoFishGame: return g.hands[safe: seat]?.count ?? 0
        default: return 0
        }
    }

    private func seatDetail(_ game: AnyGame, _ seat: Int) -> String? {
        if let adapter = game.engine as? TrickGameAdapter { return adapter.seatDetail(seat) }
        switch game.engine {
        case let g as UnoGame:
            return "\(g.hands[safe: seat]?.count ?? 0) cards" + (g.calledUno.contains(seat) ? " · UNO!" : "")
        case let g as EightsGame:
            return "\(g.hands[safe: seat]?.count ?? 0) cards"
        case let g as GoFishGame:
            return "\(g.books[safe: seat]?.count ?? 0) books · \(g.hands[safe: seat]?.count ?? 0) cards"
        default:
            return nil
        }
    }

    private func trickPlays(_ game: AnyGame) -> [TrickPlay] {
        (game.engine as? TrickGameAdapter)?.trick ?? []
    }

    private func centerHint(_ game: AnyGame) -> String {
        game.isOver ? "Game over" : "Players act on their phones"
    }
}
