import SwiftUI

/// FreeCell: tap a card (or run) to pick it up, tap a destination to drop it.
/// Tapping a selected top card again sends it to its foundation when possible.
struct FreeCellView: View {
    @ObservedObject var session: GameSession

    enum Selection: Equatable {
        case cascade(col: Int, index: Int)
        case free(Int)
    }

    @State private var selection: Selection? = nil

    var game: FreeCellGame? { session.game?.engine as? FreeCellGame }

    var body: some View {
        GeometryReader { geo in
            if let game {
                let cardWidth = min(50, (geo.size.width - 9 * 6) / 8)
                VStack(spacing: 10) {
                    topRow(game, cardWidth: cardWidth)
                    cascadeRow(game, cardWidth: cardWidth)
                    Spacer(minLength: 0)
                }
                .padding(6)
            }
        }
    }

    func submit(_ move: FreeCellMove) {
        session.submit(.freecell(move))
        selection = nil
    }

    func topRow(_ game: FreeCellGame, cardWidth: CGFloat) -> some View {
        HStack(spacing: 6) {
            // Free cells
            ForEach(0..<4, id: \.self) { cell in
                Group {
                    if let card = game.freeCells[cell] {
                        CardView(card: card, width: cardWidth)
                            .overlay(selectionHighlight(selection == .free(cell), width: cardWidth))
                    } else {
                        CardSlotView(width: cardWidth, label: "·")
                    }
                }
                .onTapGesture { tapFreeCell(cell, game: game) }
            }

            Spacer(minLength: 4)

            // Foundations
            ForEach(0..<4, id: \.self) { f in
                Group {
                    if let top = game.foundations[f].last {
                        CardView(card: top, width: cardWidth)
                    } else {
                        CardSlotView(width: cardWidth, label: Suit.allCases[f].symbol)
                    }
                }
                .onTapGesture { tapFoundation(f, game: game) }
            }
        }
    }

    func cascadeRow(_ game: FreeCellGame, cardWidth: CGFloat) -> some View {
        let overlap = cardWidth * 0.42
        return HStack(alignment: .top, spacing: 6) {
            ForEach(0..<8, id: \.self) { col in
                let pile = game.cascades[col]
                ZStack(alignment: .top) {
                    if pile.isEmpty {
                        CardSlotView(width: cardWidth)
                            .onTapGesture { dropOnCascade(col, game: game) }
                    }
                    ForEach(Array(pile.enumerated()), id: \.element) { index, card in
                        CardView(card: card, width: cardWidth)
                            .overlay(selectionHighlight(isSelected(col: col, index: index), width: cardWidth))
                            .offset(y: CGFloat(index) * overlap)
                            .onTapGesture { tapCard(col: col, index: index, game: game) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    func isSelected(col: Int, index: Int) -> Bool {
        if case .cascade(let c, let i) = selection { return c == col && index >= i }
        return false
    }

    func selectionHighlight(_ on: Bool, width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: width * 0.12)
            .strokeBorder(Color.yellow, lineWidth: on ? 2.5 : 0)
    }

    func tapFreeCell(_ cell: Int, game: FreeCellGame) {
        switch selection {
        case .free(cell):
            if let card = game.freeCells[cell], game.canPlaceOnFoundation(card) {
                submit(.freeToFoundation(cell: cell))
            } else { selection = nil }
        case .cascade(let col, let index):
            // Only a single top card fits in a free cell.
            if game.freeCells[cell] == nil, index == game.cascades[col].count - 1 {
                submit(.cascadeToFree(col: col, cell: cell))
            } else { selection = nil }
        case .free:
            selection = game.freeCells[cell] != nil ? .free(cell) : nil
        case .none:
            if game.freeCells[cell] != nil { selection = .free(cell) }
        }
    }

    /// Tapping any foundation slot routes the selected card to its own
    /// suit's pile — no need to hit the exact slot.
    func tapFoundation(_ f: Int, game: FreeCellGame) {
        switch selection {
        case .free(let cell):
            if let card = game.freeCells[cell], game.canPlaceOnFoundation(card) {
                submit(.freeToFoundation(cell: cell))
            } else { selection = nil }
        case .cascade(let col, let index):
            if index == game.cascades[col].count - 1, let top = game.cascades[col].last,
               game.canPlaceOnFoundation(top) {
                submit(.cascadeToFoundation(col: col))
            } else { selection = nil }
        case .none:
            break
        }
    }

    func tapCard(col: Int, index: Int, game: FreeCellGame) {
        switch selection {
        case .cascade(let c, let i) where c == col && i == index:
            // Second tap: try the foundation for a single top card.
            if index == game.cascades[col].count - 1, let top = game.cascades[col].last,
               game.canPlaceOnFoundation(top) {
                submit(.cascadeToFoundation(col: col))
            } else { selection = nil }
        case .some:
            dropOnCascade(col, game: game)
        case .none:
            // Only pick up a valid run.
            let run = game.cascades[col].suffix(from: index)
            if game.isRun(run) { selection = .cascade(col: col, index: index) }
        }
    }

    func dropOnCascade(_ col: Int, game: FreeCellGame) {
        switch selection {
        case .cascade(let from, let index):
            let count = game.cascades[from].count - index
            let run = game.cascades[from].suffix(count)
            if from != col, count >= 1, game.isRun(run), let head = run.first,
               game.canPlace(head, onCascade: col),
               count <= game.maxRunLength(toEmptyCascade: game.cascades[col].isEmpty) {
                submit(.cascadeToCascade(from: from, count: count, to: col))
            } else { selection = nil }
        case .free(let cell):
            if let card = game.freeCells[cell], game.canPlace(card, onCascade: col) {
                submit(.freeToCascade(cell: cell, to: col))
            } else { selection = nil }
        case .none:
            break
        }
    }
}
