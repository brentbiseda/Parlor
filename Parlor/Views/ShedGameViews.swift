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

/// Wildcard table: opponents around the top, discard + draw in the middle,
/// your hand fanned along the bottom. Wilds ask for a color.
struct UnoView: View {
    @ObservedObject var session: GameSession
    @State private var pendingWild: UnoCard? = nil

    var game: UnoGame? { session.game?.engine as? UnoGame }

    var body: some View {
        if let game {
            let perspective = session.perspectiveSeat
            let acting = session.actionableSeat != nil
            VStack(spacing: 6) {
                opponentRow(game, perspective: perspective)

                Spacer(minLength: 0)

                HStack(spacing: 24) {
                    // Draw pile
                    Button {
                        guard acting else { return }
                        session.submit(.uno(game.drewThisTurn ? .pass : .draw))
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 9)
                                .fill(Color(white: 0.18))
                                .frame(width: 56, height: 84)
                                .overlay(RoundedRectangle(cornerRadius: 9)
                                    .strokeBorder(.white.opacity(0.5), lineWidth: 1.5))
                            VStack(spacing: 2) {
                                Text(game.drewThisTurn ? "PASS" : "DRAW")
                                    .font(.caption.weight(.black))
                                Text("\(game.drawPile.count)")
                                    .font(.caption2)
                                    .opacity(0.7)
                            }
                            .foregroundStyle(.white)
                        }
                    }
                    .disabled(!acting)

                    // Discard
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

                    // Play direction.
                    Image(systemName: game.clockwise
                          ? "arrow.clockwise.circle.fill"
                          : "arrow.counterclockwise.circle.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .symbolEffect(.bounce, value: game.clockwise)
                }

                Spacer(minLength: 0)

                myHand(game, perspective: perspective, acting: acting)
                SeatBadge(name: session.playerName(seat: perspective) + " (you)",
                          isCurrent: !game.isOver && game.currentPlayer == perspective)
                    .padding(.bottom, 4)
            }
            .padding(.top, 4)
            .confirmationDialog("Pick a color", isPresented: Binding(
                get: { pendingWild != nil },
                set: { if !$0 { pendingWild = nil } }
            ), titleVisibility: .visible) {
                ForEach(UnoColor.allCases, id: \.self) { color in
                    Button(color.rawValue.capitalized) {
                        if let card = pendingWild {
                            session.submit(.uno(.play(card, declared: color)))
                        }
                        pendingWild = nil
                    }
                }
            }
        }
    }

    func opponentRow(_ game: UnoGame, perspective: Int) -> some View {
        HStack(spacing: 12) {
            ForEach(1..<4, id: \.self) { offset in
                let seat = (perspective + offset) % 4
                VStack(spacing: 4) {
                    SeatBadge(name: session.playerName(seat: seat),
                              isCurrent: !game.isOver && game.currentPlayer == seat,
                              detail: "\(game.hands[seat].count) cards")
                    HStack(spacing: -14) {
                        ForEach(0..<min(game.hands[seat].count, 7), id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(white: 0.2))
                                .overlay(RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(.white.opacity(0.4), lineWidth: 1))
                                .frame(width: 20, height: 30)
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
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: -14) {
                ForEach(cards) { card in
                    let playable = acting && legal.contains(card.id)
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
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(height: 110)
    }
}

// MARK: - Crazy Eights

/// Same table shape as Wildcard, but with the standard deck; playing an 8
/// asks for the suit to nominate.
struct EightsView: View {
    @ObservedObject var session: GameSession
    @State private var pendingEight: Card? = nil

    var game: EightsGame? { session.game?.engine as? EightsGame }

    var body: some View {
        if let game {
            let perspective = session.perspectiveSeat
            let acting = session.actionableSeat != nil
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

                handView(game, perspective: perspective, acting: acting)
                SeatBadge(name: session.playerName(seat: perspective) + " (you)",
                          isCurrent: !game.isOver && game.currentPlayer == perspective)
                    .padding(.bottom, 4)
            }
            .padding(.top, 4)
            .confirmationDialog("Name a suit", isPresented: Binding(
                get: { pendingEight != nil },
                set: { if !$0 { pendingEight = nil } }
            ), titleVisibility: .visible) {
                ForEach(Suit.allCases, id: \.self) { suit in
                    Button("\(suit.symbol) \(String(describing: suit).capitalized)") {
                        if let card = pendingEight {
                            session.submit(.eights(.play(card, nominated: suit)))
                        }
                        pendingEight = nil
                    }
                }
            }
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
