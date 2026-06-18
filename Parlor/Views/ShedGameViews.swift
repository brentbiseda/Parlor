import SwiftUI

// MARK: - Wildcard (UNO-style)

struct UnoCardView: View {
    let card: UnoCard
    var width: CGFloat = 52

    static func color(_ color: UnoColor?) -> Color {
        switch color {
        case .red: return Color(red: 0.85, green: 0.2, blue: 0.2)
        case .yellow: return Color(red: 0.95, green: 0.75, blue: 0.1)
        case .green: return Color(red: 0.25, green: 0.65, blue: 0.25)
        case .blue: return Color(red: 0.2, green: 0.4, blue: 0.85)
        case nil: return Color(white: 0.15)
        }
    }

    var glyph: String {
        switch card.value {
        case .number(let n): return n >= 0 ? "\(n)" : "?"
        case .skip: return "⃠"
        case .reverse: return "⇄"
        case .drawTwo: return "+2"
        case .wild: return "★"
        case .wildDrawFour: return "+4"
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: width * 0.16)
            .fill(LinearGradient(colors: [Self.color(card.color),
                                          Self.color(card.color).opacity(0.75)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                Ellipse()
                    .fill(.white.opacity(0.18))
                    .rotationEffect(.degrees(35))
                    .padding(width * 0.1)
            )
            .overlay(
                Text(glyph)
                    .font(.system(size: width * 0.42, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: width * 0.16)
                    .strokeBorder(.white.opacity(0.7), lineWidth: 1.5)
            )
            .frame(width: width, height: width * 1.5)
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1.5)
    }
}

/// Inline color picker overlay for wild card plays in Wildcard (UNO-style).
struct UnoColorPicker: View {
    @Binding var pendingWild: UnoCard?
    var session: GameSession
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 14) {
            Text("Pick a Color")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            HStack(spacing: 14) {
                ForEach(Array(UnoColor.allCases.enumerated()), id: \.element) { index, color in
                    Button {
                        if let card = pendingWild {
                            session.submit(.uno(.play(card, declared: color)))
                        }
                        pendingWild = nil
                    } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(UnoCardView.color(color))
                                .frame(width: 44, height: 44)
                                .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 2))
                            Text(color.rawValue.capitalized)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(PressableTileStyle())
                    .scaleEffect(appeared ? 1.0 : 0.5)
                    .animation(.spring(response: 0.35, dampingFraction: 0.6).delay(Double(index) * 0.06),
                               value: appeared)
                }
            }
        }
        .onAppear { appeared = true }
    }
}

/// Wildcard table: opponents around the top, discard + draw in the middle,
/// your hand fanned along the bottom. Wilds ask for a color via inline overlay.
struct UnoView: View {
    @ObservedObject var session: GameSession
    @State private var pendingWild: UnoCard? = nil

    var game: UnoGame? { session.game?.engine as? UnoGame }

    var body: some View {
        if let game {
            let perspective = session.perspectiveSeat
            let acting = session.actionableSeat != nil
            ZStack {
                VStack(spacing: 6) {
                    opponentRow(game, perspective: perspective)

                    Spacer(minLength: 0)

                    handSizeStrip(game, perspective: perspective)

                    HStack(spacing: 24) {
                        // Draw pile — red pulse when ≤5 cards remaining
                        let drawLow = game.drawPile.count <= 5
                        Button {
                            guard acting else { return }
                            session.submit(.uno(game.drewThisTurn ? .pass : .draw))
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(drawLow ? Color(red: 0.5, green: 0.05, blue: 0.05) : Color(white: 0.18))
                                    .frame(width: 56, height: 84)
                                    .overlay(RoundedRectangle(cornerRadius: 9)
                                        .strokeBorder(drawLow ? Color.red.opacity(0.8) : .white.opacity(0.5), lineWidth: drawLow ? 2 : 1.5))
                                VStack(spacing: 2) {
                                    Text(game.drewThisTurn ? "PASS" : "DRAW")
                                        .font(.caption.weight(.black))
                                    Text("\(game.drawPile.count)")
                                        .font(.caption2)
                                        .opacity(0.7)
                                    if drawLow {
                                        Text("LOW!")
                                            .font(.system(size: 7, weight: .black))
                                            .foregroundStyle(.red.opacity(0.9))
                                    }
                                }
                                .foregroundStyle(.white)
                            }
                        }
                        .disabled(!acting)

                        // Discard with active color chip
                        if let top = game.topCard {
                            UnoCardView(card: top, width: 60)
                                .overlay(alignment: .bottom) {
                                    Text(game.activeColor.rawValue.capitalized)
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(UnoCardView.color(game.activeColor), in: Capsule())
                                        .foregroundStyle(.white)
                                        .offset(y: 14)
                                }
                        }

                        VStack(spacing: 4) {
                            // Play direction indicator
                            Image(systemName: game.clockwise
                                  ? "arrow.clockwise.circle.fill"
                                  : "arrow.counterclockwise.circle.fill")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white.opacity(0.7))
                                .symbolEffect(.bounce, value: game.clockwise)
                            // Discard pile count
                            Text("🃏 \(game.discard.count)")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }

                    Spacer(minLength: 0)

                    myHand(game, perspective: perspective, acting: acting)
                    SeatBadge(name: session.playerName(seat: perspective) + " (you)",
                              isCurrent: !game.isOver && game.currentPlayer == perspective)
                        .padding(.bottom, 4)
                }
                .padding(.top, 4)

                // Inline wild color picker overlay
                if pendingWild != nil {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                        .onTapGesture { pendingWild = nil }
                    UnoColorPicker(pendingWild: $pendingWild, session: session)
                        .padding(24)
                        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(.white.opacity(0.15), lineWidth: 1))
                        .transition(.scale(scale: 0.88).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3), value: pendingWild != nil)
        }
    }

    /// Compact bar showing each player's card count with a color-coded threat indicator.
    func handSizeStrip(_ game: UnoGame, perspective: Int) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { seat in
                let count = game.hands[seat].count
                let isMe = seat == perspective
                let isCurrent = !game.isOver && game.currentPlayer == seat
                let hasUno = game.calledUno.contains(seat) && count == 1
                let exposed = count == 1 && !game.calledUno.contains(seat)
                VStack(spacing: 2) {
                    Text("\(count)")
                        .font(.caption.weight(.black))
                        .foregroundStyle(count <= 1 ? (hasUno ? .yellow : .red) : count <= 3 ? .orange : .white)
                    GeometryReader { geo in
                        let maxCards = 14.0
                        let fraction = min(1.0, Double(count) / maxCards)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.white.opacity(0.12))
                            .overlay(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(count <= 1 ? (hasUno ? Color.yellow : Color.red)
                                          : count <= 3 ? Color.orange : Color.white.opacity(0.6))
                                    .frame(height: geo.size.height * fraction)
                            }
                    }
                    .frame(height: 20)
                    Text(isMe ? "you" : "S\(seat+1)")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(isCurrent ? Color.yellow : .white.opacity(0.5))
                    // Color distribution pips for local player's hand
                    if isMe {
                        let colorCounts = Dictionary(grouping: game.hands[seat].compactMap(\.color), by: { $0 })
                        HStack(spacing: 2) {
                            ForEach([UnoColor.red, .yellow, .green, .blue], id: \.self) { c in
                                let n = colorCounts[c]?.count ?? 0
                                if n > 0 {
                                    Text("\(n)")
                                        .font(.system(size: 6, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 10, height: 10)
                                        .background(UnoCardView.color(c), in: Circle())
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .overlay(alignment: .top) {
                    if exposed {
                        Text("!")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(.red)
                            .offset(x: 8, y: -2)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 4)
    }

    func opponentRow(_ game: UnoGame, perspective: Int) -> some View {
        HStack(spacing: 12) {
            ForEach(1..<4, id: \.self) { offset in
                let seat = (perspective + offset) % 4
                let hasUno = game.calledUno.contains(seat) && game.hands[seat].count == 1
                let exposed = game.hands[seat].count == 1 && !game.calledUno.contains(seat)
                VStack(spacing: 4) {
                    SeatBadge(name: session.playerName(seat: seat),
                              isCurrent: !game.isOver && game.currentPlayer == seat,
                              detail: "\(game.hands[seat].count) card\(game.hands[seat].count == 1 ? "" : "s")")
                    ZStack(alignment: .topTrailing) {
                        HStack(spacing: -14) {
                            ForEach(0..<min(game.hands[seat].count, 7), id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(white: 0.2))
                                    .overlay(RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(.white.opacity(0.4), lineWidth: 1))
                                    .frame(width: 20, height: 30)
                            }
                        }
                        if hasUno {
                            Text("UNO!")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.yellow, in: Capsule())
                                .offset(x: 4, y: -8)
                        } else if exposed {
                            Text("1 CARD!")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.red, in: Capsule())
                                .offset(x: 4, y: -8)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
    }

    func myHand(_ game: UnoGame, perspective: Int, acting: Bool) -> some View {
        let cards = game.hands[perspective]
        let legal = Set(game.legalCards(for: perspective).map(\.id))
        let myUno = game.calledUno.contains(perspective) && cards.count == 1
        return VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: -14) {
                    ForEach(cards) { card in
                        let playable = acting && legal.contains(card.id)
                        ZStack(alignment: .topTrailing) {
                            UnoCardView(card: card, width: 56)
                                .offset(y: playable ? -10 : 0)
                                .opacity(!acting || playable ? 1 : 0.6)
                                .onTapGesture {
                                    guard playable else { return }
                                    if card.color == nil {
                                        pendingWild = card
                                    } else {
                                        session.submit(.uno(.play(card, declared: nil)))
                                    }
                                }
                            if myUno {
                                Text("UNO!")
                                    .font(.caption2.weight(.black))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.yellow, in: Capsule())
                                    .offset(x: 4, y: cards.count == 1 ? -8 : 0)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .frame(height: 110)
            // UNO call button when the player is down to 2 cards (call before playing last).
            if acting && cards.count <= 2 && !myUno {
                Button {
                    session.submit(.uno(.callUno))
                } label: {
                    Text("UNO!")
                        .font(.headline.weight(.black))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 6)
                        .background(Color.yellow, in: Capsule())
                }
                .padding(.bottom, 4)
            }
        }
    }
}

// MARK: - Suit Overlay Picker

/// Spring-animated suit buttons for the Crazy Eights nomination overlay.
struct SuitOverlayPicker: View {
    @Binding var pendingEight: Card?
    var session: GameSession
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 14) {
            Text("Name a Suit")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            HStack(spacing: 16) {
                ForEach(Array(Suit.allCases.enumerated()), id: \.element) { index, suit in
                    Button {
                        if let card = pendingEight {
                            session.submit(.eights(.play(card, nominated: suit)))
                        }
                        pendingEight = nil
                    } label: {
                        VStack(spacing: 6) {
                            Text(suit.symbol)
                                .font(.system(size: 44))
                            Text(String(describing: suit).capitalized)
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(suit.isRed ? Color(red: 0.85, green: 0.15, blue: 0.15) : .black)
                        .frame(width: 68, height: 78)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(suit.isRed
                                          ? Color(red: 0.85, green: 0.15, blue: 0.15).opacity(0.5)
                                          : .black.opacity(0.25), lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                    }
                    .buttonStyle(PressableTileStyle())
                    .scaleEffect(appeared ? 1.0 : 0.5)
                    .animation(.spring(response: 0.35, dampingFraction: 0.6).delay(Double(index) * 0.06),
                               value: appeared)
                }
            }
        }
        .onAppear { appeared = true }
    }
}

// MARK: - Crazy Eights

/// Same table shape as Wildcard, but with the standard deck; playing an 8
/// asks for the suit to nominate via an inline overlay picker.
struct EightsView: View {
    @ObservedObject var session: GameSession
    @State private var pendingEight: Card? = nil
    @State private var drawBannerPulse = false

    var game: EightsGame? { session.game?.engine as? EightsGame }

    var body: some View {
        if let game {
            let perspective = session.perspectiveSeat
            let acting = session.actionableSeat != nil
            let myTurn = acting && game.currentPlayer == perspective
            ZStack {
                VStack(spacing: 6) {
                    HStack(spacing: 12) {
                        ForEach(1..<4, id: \.self) { offset in
                            let seat = (perspective + offset) % 4
                            VStack(spacing: 4) {
                                SeatBadge(name: session.playerName(seat: seat),
                                          isCurrent: !game.isOver && game.currentPlayer == seat,
                                          detail: "\(game.hands[seat].count) cards")
                                OpponentHandView(count: min(game.hands[seat].count, 8), width: 18)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 8)

                    Spacer(minLength: 0)

                    // Eights stats + draw chain indicator
                    HStack(spacing: 8) {
                        if game.eightPlays > 0 || game.suitChanges > 0 {
                            HStack(spacing: 6) {
                                if game.eightPlays > 0 {
                                    Label("\(game.eightPlays)", systemImage: "8.circle.fill")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.85))
                                }
                                if game.suitChanges > 0 {
                                    Text("\(game.suitChanges) suit\(game.suitChanges == 1 ? "" : "s")")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.3), in: Capsule())
                            .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.75))
                        }
                        // Show active draw chain when ≥2 twos are stacked
                        if game.currentDrawChain >= 2 {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                Text("Chain ×\(game.currentDrawChain) · DRAW \(game.pendingDraw)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.orange)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.orange.opacity(0.15), in: Capsule())
                            .overlay(Capsule().strokeBorder(.orange.opacity(0.5), lineWidth: 1))
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: game.currentDrawChain)

                    HStack(spacing: 24) {
                        Button {
                            guard acting else { return }
                            if game.drewThisTurn || game.stock.isEmpty {
                                session.submit(.eights(.pass))
                            } else {
                                session.submit(.eights(.draw))
                            }
                        } label: {
                            ZStack {
                                if game.stock.isEmpty {
                                    CardSlotView(width: 56, label: "—")
                                } else {
                                    FaceDownCardView(width: 56)
                                }
                                Text(game.drewThisTurn || game.stock.isEmpty ? "PASS" : "DRAW")
                                    .font(.caption.weight(.black))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black, radius: 2)
                            }
                        }
                        .disabled(!acting)

                        if let top = game.topCard {
                            CardView(card: top, width: 60)
                                .overlay(alignment: .bottom) {
                                    Text(game.activeSuit.symbol)
                                        .font(.headline)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 2)
                                        .background(.white, in: Capsule())
                                        .foregroundStyle(game.activeSuit.isRed ? .red : .black)
                                        .offset(y: 14)
                                }
                        }
                    }

                    Spacer(minLength: 0)

                    // Draw-two warning banner when penalty is pending.
                    if myTurn && game.pendingDraw > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.bold))
                            Text("DRAW \(game.pendingDraw) — play a 2 to stack or draw now")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            LinearGradient(colors: [Color(red: 1.0, green: 0.75, blue: 0.15),
                                                    Color(red: 1.0, green: 0.55, blue: 0.1)],
                                           startPoint: .leading, endPoint: .trailing),
                            in: Capsule())
                        .scaleEffect(drawBannerPulse ? 1.04 : 1.0)
                        .onAppear { withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { drawBannerPulse = true } }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    handView(game, perspective: perspective, acting: acting)
                    SeatBadge(name: session.playerName(seat: perspective) + " (you)",
                              isCurrent: !game.isOver && game.currentPlayer == perspective)
                        .padding(.bottom, 4)
                }
                .padding(.top, 4)
                .animation(.easeInOut(duration: 0.25), value: game.pendingDraw)

                // Inline suit picker overlay when an 8 is played.
                if pendingEight != nil {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                        .onTapGesture { pendingEight = nil }
                    SuitOverlayPicker(pendingEight: $pendingEight, session: session)
                    .padding(24)
                    .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 1))
                    .transition(.scale(scale: 0.88).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3), value: pendingEight != nil)
        }
    }

    func handView(_ game: EightsGame, perspective: Int, acting: Bool) -> some View {
        let cards = game.hands[perspective]
        let legal = Set(game.legalCards(for: perspective))
        return HandView(cards: cards, legal: legal, enabled: acting) { card in
            guard acting, legal.contains(card) else { return }
            if card.rank == .eight {
                pendingEight = card
            } else {
                session.submit(.eights(.play(card, nominated: nil)))
            }
        }
        .padding(.horizontal, 8)
    }
}
