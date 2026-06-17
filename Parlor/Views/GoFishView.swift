import SwiftUI

/// Go Fish: pick a rank from your hand, then tap who to ask. Books pile up
/// next to each player's badge.
struct GoFishView: View {
    @ObservedObject var session: GameSession
    @State private var selectedRank: Rank? = nil
    @State private var bookFlash: String? = nil
    @State private var hotStreakVisible = false

    var game: GoFishGame? { session.game?.engine as? GoFishGame }

    var body: some View {
        if let game {
            let perspective = session.perspectiveSeat
            let acting = session.actionableSeat != nil
            ZStack {
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        ForEach(1..<4, id: \.self) { offset in
                            let seat = (perspective + offset) % 4
                            opponentCard(game, seat: seat, acting: acting)
                        }
                    }
                    .padding(.horizontal, 8)

                    Spacer(minLength: 0)

                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            if game.stock.isEmpty {
                                CardSlotView(width: 44, label: "—")
                            } else {
                                FaceDownCardView(width: 44)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                let totalBooks = game.books.map(\.count).reduce(0, +)
                                HStack(spacing: 6) {
                                    Text("Pond: \(game.stock.count) · Books: \(totalBooks)/13")
                                        .font(.subheadline.weight(.semibold))
                                    // Ask streak badge
                                    if game.askStreak >= 3 {
                                        Text("🔥\(game.askStreak)")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.orange)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(.orange.opacity(0.15), in: Capsule())
                                    }
                                }
                                if let event = game.lastEvent {
                                    Text(event)
                                        .font(.caption)
                                        .opacity(0.8)
                                }
                            }
                            .foregroundStyle(.white)
                        }
                        if acting {
                            Text(selectedRank == nil
                                 ? "Tap a rank below, then a player above"
                                 : "Asking for \(selectedRank!.label)s — tap a player")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.yellow)
                        }
                    }

                    Spacer(minLength: 0)

                    myBooks(game, perspective: perspective)
                    rankPicker(game, perspective: perspective, acting: acting)
                    SeatBadge(name: session.playerName(seat: perspective) + " (you)",
                              isCurrent: !game.isOver && game.currentPlayer == perspective,
                              detail: "\(game.books[perspective].count) books")
                        .padding(.bottom, 4)
                }
                .padding(.top, 4)

                // Hot streak toast — shown when bestAskStreak surpasses 3.
                if hotStreakVisible {
                    Text("🔥 Hot streak!")
                        .font(.title3.weight(.black))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(colors: [Color(red: 1.0, green: 0.78, blue: 0.1),
                                                    Color(red: 1.0, green: 0.55, blue: 0.0)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: Capsule())
                        .shadow(color: .orange.opacity(0.5), radius: 8, y: 3)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                        .padding(.top, 60)
                }

                // Book completion flash banner.
                if let flash = bookFlash {
                    Text(flash)
                        .font(.title3.weight(.black))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(colors: [Color(red: 1.0, green: 0.85, blue: 0.2),
                                                    Color(red: 1.0, green: 0.65, blue: 0.1)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: Capsule())
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .animation(.spring(response: 0.35), value: bookFlash)
            .onChange(of: game.currentPlayer) { _, _ in selectedRank = nil }
            .onChange(of: game.bestAskStreak) { oldVal, newVal in
                guard newVal > 3 && newVal > oldVal else { return }
                withAnimation(.spring(response: 0.35)) { hotStreakVisible = true }
                Task {
                    do { try await Task.sleep(nanoseconds: 1_500_000_000) } catch { return }
                    withAnimation { hotStreakVisible = false }
                }
            }
            .onChange(of: game.lastBookEvent) { _, event in
                guard let event else { return }
                SoundFX.shared.play(.jackpot)
                bookFlash = "📚 \(event)"
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    bookFlash = nil
                }
            }
        }
    }

    func opponentCard(_ game: GoFishGame, seat: Int, acting: Bool) -> some View {
        let askable = acting && selectedRank != nil && !game.hands[seat].isEmpty
        let topBooks = game.books.map(\.count).max() ?? 0
        let isLeader = topBooks > 0 && game.books[seat].count == topBooks
            && game.books.filter({ $0.count == topBooks }).count == 1
        return VStack(spacing: 4) {
            SeatBadge(name: (isLeader ? "👑 " : "") + session.playerName(seat: seat),
                      isCurrent: !game.isOver && game.currentPlayer == seat,
                      detail: "\(game.hands[seat].count) cards · \(game.books[seat].count) books")
            OpponentHandView(count: min(game.hands[seat].count, 8), width: 16)
            if !game.books[seat].isEmpty {
                bookRow(game.books[seat])
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.white.opacity(askable ? 0.18 : 0), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.yellow, lineWidth: askable ? 2 : 0)
        )
        .onTapGesture {
            guard askable, let rank = selectedRank else { return }
            session.submit(.fish(.ask(seat: seat, rank: rank)))
            selectedRank = nil
        }
    }

    func bookRow(_ books: [Rank]) -> some View {
        HStack(spacing: 2) {
            ForEach(books, id: \.self) { rank in
                VStack(spacing: 0) {
                    Text(rank.label)
                        .font(.system(size: 9, weight: .black))
                    Text("♠♥")
                        .font(.system(size: 6))
                        .opacity(0.7)
                }
                .foregroundStyle(.black)
                .frame(width: 20, height: 22)
                .background(
                    LinearGradient(colors: [Color(red: 1.0, green: 0.92, blue: 0.4),
                                            Color(red: 0.98, green: 0.78, blue: 0.15)],
                                   startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(.black.opacity(0.2), lineWidth: 0.5))
            }
        }
    }

    func myBooks(_ game: GoFishGame, perspective: Int) -> some View {
        Group {
            if !game.books[perspective].isEmpty {
                bookRow(game.books[perspective])
            }
        }
    }

    /// Your hand grouped by rank — tap a group to choose what to ask for.
    func rankPicker(_ game: GoFishGame, perspective: Int, acting: Bool) -> some View {
        let groups = Dictionary(grouping: game.hands[perspective], by: \.rank)
            .sorted { $0.key < $1.key }
        if groups.isEmpty {
            return AnyView(
                Text(game.stock.isEmpty ? "No cards left" : "Waiting to draw…")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(height: 96)
            )
        }
        return AnyView(ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(groups, id: \.key) { rank, cards in
                    VStack(spacing: 3) {
                        ZStack {
                            ForEach(Array(cards.enumerated()), id: \.element) { index, card in
                                CardView(card: card, width: 40)
                                    .offset(x: CGFloat(index) * 9)
                            }
                        }
                        .frame(width: 40 + CGFloat(cards.count - 1) * 9, height: 58)
                        Text("\(cards.count)× \(rank.label)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(6)
                    .background(.white.opacity(selectedRank == rank ? 0.25 : 0.06),
                                in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.yellow, lineWidth: selectedRank == rank ? 2 : 0)
                    )
                    .onTapGesture {
                        guard acting else { return }
                        SoundFX.shared.play(.tileSelect)
                        selectedRank = selectedRank == rank ? nil : rank
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .frame(height: 96))
    }
}
