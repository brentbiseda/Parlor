import SwiftUI

/// Klondike: tap a card to pick it up, tap a destination to drop it.
/// Tapping a selected card again sends it to its foundation when possible.
struct KlondikeView: View {
    @ObservedObject var session: GameSession

    enum Selection: Equatable {
        case waste
        case tableau(col: Int, index: Int)
        case foundation(Int)
    }

    @State private var selection: Selection? = nil

    var game: KlondikeGame? { session.game?.engine as? KlondikeGame }

    var body: some View {
        GeometryReader { geo in
            if let game {
                let cardWidth = min(54, (geo.size.width - 8 * 8) / 7)
                VStack(spacing: 10) {
                    topRow(game, cardWidth: cardWidth)
                    tableauRow(game, cardWidth: cardWidth)
                    Spacer(minLength: 0)
                }
                .padding(8)
            }
        }
    }

    func submit(_ move: KlondikeMove) {
        session.submit(.klondike(move))
        selection = nil
    }

    func topRow(_ game: KlondikeGame, cardWidth: CGFloat) -> some View {
        HStack(spacing: 8) {
            // Stock
            Group {
                if game.stock.isEmpty {
                    CardSlotView(width: cardWidth, label: "↻")
                } else {
                    FaceDownCardView(width: cardWidth)
                }
            }
            .onTapGesture {
                submit(game.stock.isEmpty ? .resetStock : .draw)
            }

            // Waste
            Group {
                if let top = game.waste.last {
                    CardView(card: top, width: cardWidth)
                        .overlay(selectionHighlight(selection == .waste, width: cardWidth))
                } else {
                    CardSlotView(width: cardWidth)
                }
            }
            .onTapGesture {
                guard !game.waste.isEmpty else { return }
                if selection == .waste {
                    if game.canPlaceOnFoundation(game.waste.last!) { submit(.wasteToFoundation) }
                    else { selection = nil }
                } else {
                    selection = .waste
                }
            }

            Spacer()

            // Foundations
            ForEach(0..<4, id: \.self) { f in
                Group {
                    if let top = game.foundations[f].last {
                        CardView(card: top, width: cardWidth)
                    } else {
                        CardSlotView(width: cardWidth, label: Suit.allCases[f].symbol)
                    }
                }
                .overlay(selectionHighlight(selection == .foundation(f), width: cardWidth))
                .onTapGesture { tapFoundation(f, game: game) }
            }
        }
    }

    func tapFoundation(_ f: Int, game: KlondikeGame) {
        switch selection {
        case .waste:
            if let top = game.waste.last, top.suit == Suit.allCases[f], game.canPlaceOnFoundation(top) {
                submit(.wasteToFoundation)
            } else { selection = nil }
        case .tableau(let col, let index):
            let ups = game.tableau[col].faceUp
            if index == ups.count - 1, let top = ups.last,
               top.suit == Suit.allCases[f], game.canPlaceOnFoundation(top) {
                submit(.tableauToFoundation(col))
            } else { selection = nil }
        case .foundation(f):
            selection = nil
        default:
            if !game.foundations[f].isEmpty { selection = .foundation(f) }
        }
    }

    func tableauRow(_ game: KlondikeGame, cardWidth: CGFloat) -> some View {
        let overlap = cardWidth * 0.4
        return HStack(alignment: .top, spacing: 8) {
            ForEach(0..<7, id: \.self) { col in
                let pile = game.tableau[col]
                ZStack(alignment: .top) {
                    if pile.faceDown.isEmpty && pile.faceUp.isEmpty {
                        CardSlotView(width: cardWidth, label: "K")
                            .onTapGesture { tapColumn(col, game: game) }
                    }
                    ForEach(0..<pile.faceDown.count, id: \.self) { i in
                        FaceDownCardView(width: cardWidth)
                            .offset(y: CGFloat(i) * overlap * 0.5)
                    }
                    ForEach(Array(pile.faceUp.enumerated()), id: \.element) { index, card in
                        CardView(card: card, width: cardWidth)
                            .overlay(selectionHighlight(isSelected(col: col, index: index), width: cardWidth))
                            .offset(y: CGFloat(pile.faceDown.count) * overlap * 0.5 + CGFloat(index) * overlap)
                            .onTapGesture { tapCard(col: col, index: index, game: game) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    func isSelected(col: Int, index: Int) -> Bool {
        if case .tableau(let c, let i) = selection { return c == col && index >= i }
        return false
    }

    func selectionHighlight(_ on: Bool, width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: width * 0.12)
            .strokeBorder(Color.yellow, lineWidth: on ? 2.5 : 0)
    }

    func tapCard(col: Int, index: Int, game: KlondikeGame) {
        switch selection {
        case .tableau(let c, let i) where c == col && i == index:
            // Second tap: try the foundation for a single top card.
            let ups = game.tableau[col].faceUp
            if index == ups.count - 1, let top = ups.last, game.canPlaceOnFoundation(top) {
                submit(.tableauToFoundation(col))
            } else { selection = nil }
        case .some:
            dropOnColumn(col, game: game)
        case .none:
            selection = .tableau(col: col, index: index)
        }
    }

    func tapColumn(_ col: Int, game: KlondikeGame) {
        if selection != nil { dropOnColumn(col, game: game) }
    }

    func dropOnColumn(_ col: Int, game: KlondikeGame) {
        switch selection {
        case .waste:
            if let top = game.waste.last, game.canPlaceOnTableau(top, column: col) {
                submit(.wasteToTableau(col))
            } else { selection = nil }
        case .tableau(let from, let index):
            let ups = game.tableau[from].faceUp
            if index < ups.count, game.canPlaceOnTableau(ups[index], column: col), from != col {
                submit(.tableauToTableau(from: from, index: index, to: col))
            } else { selection = nil }
        case .foundation(let f):
            if let top = game.foundations[f].last, game.canPlaceOnTableau(top, column: col) {
                submit(.foundationToTableau(foundation: f, to: col))
            } else { selection = nil }
        case .none:
            break
        }
    }
}
