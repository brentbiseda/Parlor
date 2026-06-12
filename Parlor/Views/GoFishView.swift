import SwiftUI

/// Go Fish: pick a rank from your hand, then tap who to ask. Books pile up
/// next to each player's badge.
struct GoFishView: View {
    @ObservedObject var session: GameSession
    @State private var selectedRank: Rank? = nil

    var game: GoFishGame? { session.game?.engine as? GoFishGame }

    var body: some View {
        if let game {
            let perspective = session.perspectiveSeat
            let acting = session.actionableSeat != nil
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
                            Text("Pond: \(game.stock.count) cards")
                                .font(.subheadline.weight(.semibold))
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
            .onChange(of: game.currentPlayer) { _, _ in selectedRank = nil }
        }
    }

    func opponentCard(_ game: GoFishGame, seat: Int, acting: Bool) -> some View {
        let askable = acting && selectedRank != nil && !game.hands[seat].isEmpty
        return VStack(spacing: 4) {
            SeatBadge(name: session.playerName(seat: seat),
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
        HStack(spacing: 3) {
            ForEach(books, id: \.self) { rank in
                Text(rank.label)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.yellow.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.black)
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
        return ScrollView(.horizontal, showsIndicators: false) {
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
        .frame(height: 96)
    }
}
