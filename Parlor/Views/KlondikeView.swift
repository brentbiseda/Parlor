import SwiftUI

/// Klondike with two ways to move cards:
/// - **Drag & drop** — pick up a card (or run) and drop it on a column or
///   any foundation slot; foundation drops route to the right suit pile.
/// - **Tap** — tap to pick up, tap a destination to drop; double-tap a top
///   card to send it straight to its foundation.
struct KlondikeView: View {
    @ObservedObject var session: GameSession

    enum Selection: Equatable {
        case waste
        case tableau(col: Int, index: Int)
        case foundation(Int)
    }

    @State private var selection: Selection? = nil
    @State private var dragSource: Selection? = nil
    @State private var dragLocation: CGPoint = .zero
    @State private var dropFrames: [String: CGRect] = [:]
    @State private var autoFinishing = false

    var game: KlondikeGame? { session.game?.engine as? KlondikeGame }

    /// Everything face up with the stock gone — the win is just busywork.
    var canAutoFinish: Bool {
        guard let game, !game.isOver else { return false }
        return game.stock.isEmpty && game.waste.isEmpty
            && game.tableau.allSatisfy { $0.faceDown.isEmpty }
    }

    var body: some View {
        GeometryReader { geo in
            if let game {
                let cardWidth = min(54, (geo.size.width - 8 * 8) / 7)
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 10) {
                        topRow(game, cardWidth: cardWidth)
                        tableauRow(game, cardWidth: cardWidth)
                        Spacer(minLength: 0)
                    }
                    .padding(8)

                    dragOverlay(game, cardWidth: cardWidth)
                }
                .coordinateSpace(name: "klondike")
                .onPreferenceChange(DropFrameKey.self) { dropFrames = $0 }
                .overlay(alignment: .bottom) {
                    if canAutoFinish && !autoFinishing {
                        Button {
                            autoFinish()
                        } label: {
                            Label("Auto-finish", systemImage: "wand.and.stars")
                                .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
    }

    /// Feed every remaining card to the foundations with a little cadence.
    private func autoFinish() {
        autoFinishing = true
        Task { @MainActor in
            defer { autoFinishing = false }
            while let game = self.game, !game.isOver {
                guard let col = (0..<7).first(where: { c in
                    game.tableau[c].faceUp.last.map(game.canPlaceOnFoundation) == true
                }) else { break }
                session.submit(.klondike(.tableauToFoundation(col)))
                try? await Task.sleep(nanoseconds: 90_000_000)
            }
        }
    }

    func submit(_ move: KlondikeMove) {
        session.submit(.klondike(move))
        selection = nil
    }

    // MARK: - Drag & drop

    /// The cards travelling with the current drag.
    func draggedCards(_ source: Selection, game: KlondikeGame) -> [Card] {
        switch source {
        case .waste:
            return game.waste.last.map { [$0] } ?? []
        case .tableau(let col, let index):
            let ups = game.tableau[col].faceUp
            guard ups.indices.contains(index) else { return [] }
            return Array(ups[index...])
        case .foundation(let f):
            return game.foundations[f].last.map { [$0] } ?? []
        }
    }

    func isBeingDragged(col: Int, index: Int) -> Bool {
        if case .tableau(let c, let i) = dragSource { return c == col && index >= i }
        return false
    }

    func dragGesture(source: Selection, game: KlondikeGame) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named("klondike"))
            .onChanged { value in
                dragSource = source
                dragLocation = value.location
                selection = nil
            }
            .onEnded { value in
                defer { dragSource = nil }
                drop(at: value.location, source: source, game: game)
            }
    }

    func drop(at point: CGPoint, source: Selection, game: KlondikeGame) {
        // Foundations accept a single card; the engine routes it by suit, so
        // dropping on any of the four slots works.
        let inFoundations = dropFrames.contains {
            $0.key.hasPrefix("f") && $0.value.insetBy(dx: -8, dy: -8).contains(point)
        }
        if inFoundations {
            dropOnFoundation(source, game: game)
            return
        }
        if let column = dropFrames
            .first(where: { $0.key.hasPrefix("col") && $0.value.insetBy(dx: -3, dy: 0).contains(point) })
            .flatMap({ Int($0.key.dropFirst(3)) }) {
            dropOnColumn(column, source: source, game: game)
        }
    }

    func dropOnFoundation(_ source: Selection, game: KlondikeGame) {
        switch source {
        case .waste:
            if let top = game.waste.last, game.canPlaceOnFoundation(top) {
                submit(.wasteToFoundation)
            }
        case .tableau(let col, let index):
            let ups = game.tableau[col].faceUp
            if index == ups.count - 1, let top = ups.last, game.canPlaceOnFoundation(top) {
                submit(.tableauToFoundation(col))
            }
        case .foundation:
            break
        }
    }

    func dropOnColumn(_ col: Int, source: Selection, game: KlondikeGame) {
        switch source {
        case .waste:
            if let top = game.waste.last, game.canPlaceOnTableau(top, column: col) {
                submit(.wasteToTableau(col))
            }
        case .tableau(let from, let index):
            let ups = game.tableau[from].faceUp
            if index < ups.count, from != col, game.canPlaceOnTableau(ups[index], column: col) {
                submit(.tableauToTableau(from: from, index: index, to: col))
            }
        case .foundation(let f):
            if let top = game.foundations[f].last, game.canPlaceOnTableau(top, column: col) {
                submit(.foundationToTableau(foundation: f, to: col))
            }
        }
    }

    @ViewBuilder
    func dragOverlay(_ game: KlondikeGame, cardWidth: CGFloat) -> some View {
        if let source = dragSource {
            let cards = draggedCards(source, game: game)
            let overlap = cardWidth * 0.4
            ZStack(alignment: .top) {
                ForEach(Array(cards.enumerated()), id: \.element) { index, card in
                    CardView(card: card, width: cardWidth)
                        .offset(y: CGFloat(index) * overlap)
                }
            }
            .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
            .position(x: dragLocation.x,
                      y: dragLocation.y + cardWidth * 0.5)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Top row (stock, waste, foundations)

    func topRow(_ game: KlondikeGame, cardWidth: CGFloat) -> some View {
        HStack(spacing: 8) {
            // Stock
            Group {
                if game.stock.isEmpty {
                    CardSlotView(width: cardWidth, label: game.canResetStock ? "↻" : "✕")
                } else {
                    FaceDownCardView(width: cardWidth)
                }
            }
            .onTapGesture {
                if game.stock.isEmpty {
                    if game.canResetStock { submit(.resetStock) } else { SoundFX.shared.play(.error) }
                } else {
                    submit(.draw)
                }
            }

            // Waste: draw-3 fans the last three, only the top is live.
            Group {
                if game.waste.isEmpty {
                    CardSlotView(width: cardWidth)
                } else {
                    let visible = Array(game.waste.suffix(game.drawThree ? 3 : 1))
                    ZStack(alignment: .leading) {
                        ForEach(Array(visible.enumerated()), id: \.element) { i, card in
                            let isTop = i == visible.count - 1
                            CardView(card: card, width: cardWidth)
                                .offset(x: CGFloat(i) * cardWidth * 0.3)
                                .opacity(isTop && dragSource == .waste ? 0.35 : 1)
                                .overlay(
                                    selectionHighlight(isTop && selection == .waste, width: cardWidth)
                                        .offset(x: CGFloat(i) * cardWidth * 0.3)
                                )
                        }
                    }
                    .frame(width: cardWidth + (game.drawThree ? cardWidth * 0.6 : 0), alignment: .leading)
                    .gesture(dragGesture(source: .waste, game: game))
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

            // Foundations: the matching pile glows when a pickup can land.
            ForEach(0..<4, id: \.self) { f in
                Group {
                    if let top = game.foundations[f].last {
                        CardView(card: top, width: cardWidth)
                            .opacity(dragSource == .foundation(f) ? 0.35 : 1)
                            .gesture(dragGesture(source: .foundation(f), game: game))
                    } else {
                        CardSlotView(width: cardWidth, label: Suit.allCases[f].symbol)
                    }
                }
                .overlay(selectionHighlight(selection == .foundation(f), width: cardWidth))
                .overlay(
                    RoundedRectangle(cornerRadius: cardWidth * 0.12)
                        .strokeBorder(Color.yellow.opacity(0.85),
                                      lineWidth: foundationHintSuit(game) == Suit.allCases[f] ? 2.5 : 0)
                )
                .recordDropFrame("f\(f)")
                .onTapGesture { tapFoundation(f, game: game) }
            }
        }
    }

    /// Suit pile that would accept the currently picked-up card, if any.
    func foundationHintSuit(_ game: KlondikeGame) -> Suit? {
        let active = dragSource ?? selection
        let card: Card?
        switch active {
        case .waste:
            card = game.waste.last
        case .tableau(let col, let index):
            let ups = game.tableau[col].faceUp
            card = index == ups.count - 1 ? ups.last : nil
        default:
            card = nil
        }
        guard let card, game.canPlaceOnFoundation(card) else { return nil }
        return card.suit
    }

    /// Tapping any foundation slot with a placeable card selected sends the
    /// card to its own suit's pile — no need to hit the exact slot.
    func tapFoundation(_ f: Int, game: KlondikeGame) {
        switch selection {
        case .waste:
            if let top = game.waste.last, game.canPlaceOnFoundation(top) {
                submit(.wasteToFoundation)
            } else { selection = nil }
        case .tableau(let col, let index):
            let ups = game.tableau[col].faceUp
            if index == ups.count - 1, let top = ups.last, game.canPlaceOnFoundation(top) {
                submit(.tableauToFoundation(col))
            } else { selection = nil }
        case .foundation:
            selection = nil
        case .none:
            if !game.foundations[f].isEmpty { selection = .foundation(f) }
        }
    }

    // MARK: - Tableau

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
                            .opacity(isBeingDragged(col: col, index: index) ? 0.35 : 1)
                            .overlay(selectionHighlight(isSelected(col: col, index: index), width: cardWidth))
                            .offset(y: CGFloat(pile.faceDown.count) * overlap * 0.5 + CGFloat(index) * overlap)
                            .gesture(dragGesture(source: .tableau(col: col, index: index), game: game))
                            .onTapGesture { tapCard(col: col, index: index, game: game) }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .recordDropFrame("col\(col)")
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
            tapDropOnColumn(col, game: game)
        case .none:
            selection = .tableau(col: col, index: index)
        }
    }

    func tapColumn(_ col: Int, game: KlondikeGame) {
        if selection != nil { tapDropOnColumn(col, game: game) }
    }

    func tapDropOnColumn(_ col: Int, game: KlondikeGame) {
        guard let source = selection else { return }
        switch source {
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
        }
    }
}

// MARK: - Drop-target frame plumbing

struct DropFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Publish this view's frame (in the "klondike" space) as a drop target.
    func recordDropFrame(_ key: String) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: DropFrameKey.self,
                                       value: [key: proxy.frame(in: .named("klondike"))])
            }
        )
    }
}
