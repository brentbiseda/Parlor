import SwiftUI

/// Shared chess / checkers board: tap a piece, see its targets, tap to move.
struct GridBoardView: View {
    @ObservedObject var session: GameSession
    @State private var selected: Point? = nil
    @State private var promotionChoice: [BoardMove] = []

    var isChess: Bool { session.game?.kind == .chess }

    /// White/red at the bottom for seat 0's perspective; flipped for seat 1.
    var flipped: Bool { session.perspectiveSeat == 1 }

    var boardMoves: [BoardMove] {
        guard let game = session.game else { return [] }
        if let chess = game.engine as? ChessGame { return chess.legalBoardMoves(for: chess.currentPlayer) }
        if let checkers = game.engine as? CheckersGame { return checkers.legalBoardMoves(for: checkers.currentPlayer) }
        return []
    }

    var body: some View {
        VStack {
            Spacer()
            board
                .aspectRatio(1, contentMode: .fit)
                .padding(10)
            Spacer()
            if session.actionableSeat != nil, session.game?.isOver == false {
                Button("Resign", role: .destructive) { session.submit(.resign) }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .padding(.bottom, 6)
            }
        }
        .confirmationDialog("Promote to", isPresented: Binding(
            get: { !promotionChoice.isEmpty },
            set: { if !$0 { promotionChoice = [] } }
        ), titleVisibility: .visible) {
            ForEach(promotionChoice, id: \.self) { move in
                Button(move.promotion?.rawValue.capitalized ?? "Move") {
                    session.submit(.board(move))
                    promotionChoice = []
                    selected = nil
                }
            }
        }
    }

    var board: some View {
        GeometryReader { geo in
            let cell = geo.size.width / 8
            let targets = selected.map { sel in boardMoves.filter { $0.from == sel } } ?? []
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { col in
                            let point = pointFor(row: row, col: col)
                            cellView(point: point, cell: cell,
                                     isTarget: targets.contains { $0.to == point })
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.black.opacity(0.4), lineWidth: 2))
        }
    }

    func pointFor(row: Int, col: Int) -> Point {
        // Row 0 renders at the top; y increases toward white/red's side (y=0 bottom).
        let y = flipped ? row : 7 - row
        let x = flipped ? 7 - col : col
        return Point(x: x, y: y)
    }

    @ViewBuilder
    func cellView(point: Point, cell: CGFloat, isTarget: Bool) -> some View {
        let dark = (point.x + point.y) % 2 == 0
        let lastMove = lastMovePoints
        ZStack {
            Rectangle()
                .fill(dark ? Color(red: 0.45, green: 0.32, blue: 0.22) : Color(red: 0.93, green: 0.85, blue: 0.71))
            if lastMove.contains(point) {
                Rectangle().fill(Color.yellow.opacity(0.25))
            }
            if point == selected {
                Rectangle().fill(Color.blue.opacity(0.35))
            }
            if isTarget {
                Circle()
                    .fill(Color.blue.opacity(0.45))
                    .frame(width: cell * 0.32, height: cell * 0.32)
            }
            pieceView(at: point, cell: cell)
        }
        .frame(width: cell, height: cell)
        .contentShape(Rectangle())
        .onTapGesture { tap(point) }
    }

    var lastMovePoints: [Point] {
        if let chess = session.game?.engine as? ChessGame, let m = chess.lastMove { return [m.from, m.to] }
        if let checkers = session.game?.engine as? CheckersGame, let m = checkers.lastMove { return [m.from, m.to] }
        return []
    }

    @ViewBuilder
    func pieceView(at point: Point, cell: CGFloat) -> some View {
        if let chess = session.game?.engine as? ChessGame, let piece = chess[point] {
            Text(piece.glyph)
                .font(.system(size: cell * 0.78))
                .shadow(color: .white.opacity(piece.color == 1 ? 0 : 0.6), radius: 1)
        } else if let checkers = session.game?.engine as? CheckersGame, let piece = checkers[point] {
            ZStack {
                Circle()
                    .fill(piece.color == 0 ? Color(red: 0.8, green: 0.15, blue: 0.15) : Color(red: 0.15, green: 0.15, blue: 0.15))
                    .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1.5))
                    .padding(cell * 0.12)
                if piece.king {
                    Image(systemName: "crown.fill")
                        .font(.system(size: cell * 0.34))
                        .foregroundStyle(.yellow)
                }
            }
        }
    }

    func tap(_ point: Point) {
        guard session.actionableSeat != nil else { return }
        let moves = boardMoves
        if let sel = selected {
            let options = moves.filter { $0.from == sel && $0.to == point }
            if options.count > 1 {
                promotionChoice = options
                return
            }
            if let move = options.first {
                session.submit(.board(move))
                selected = nil
                return
            }
        }
        // Select a piece with at least one legal move.
        if moves.contains(where: { $0.from == point }) {
            selected = point
        } else {
            selected = nil
        }
    }
}

struct GoBoardView: View {
    @ObservedObject var session: GameSession

    var go: GoGame? { session.game?.engine as? GoGame }

    var body: some View {
        VStack {
            Spacer()
            if let go {
                boardView(go)
                    .aspectRatio(1, contentMode: .fit)
                    .padding(12)
            }
            Spacer()
            if session.actionableSeat != nil, session.game?.isOver == false {
                HStack {
                    Button("Pass") { session.submit(.pass) }
                        .buttonStyle(.borderedProminent)
                    Button("Resign", role: .destructive) { session.submit(.resign) }
                        .buttonStyle(.bordered).tint(.white)
                }
                .padding(.bottom, 6)
            }
        }
    }

    func boardView(_ go: GoGame) -> some View {
        GeometryReader { geo in
            let n = go.size
            let inset: CGFloat = 14
            let span = geo.size.width - inset * 2
            let step = span / CGFloat(n - 1)

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.85, green: 0.68, blue: 0.42))
                Path { path in
                    for i in 0..<n {
                        let offset = inset + CGFloat(i) * step
                        path.move(to: CGPoint(x: inset, y: offset))
                        path.addLine(to: CGPoint(x: inset + span, y: offset))
                        path.move(to: CGPoint(x: offset, y: inset))
                        path.addLine(to: CGPoint(x: offset, y: inset + span))
                    }
                }
                .stroke(.black.opacity(0.7), lineWidth: 1)

                ForEach(0..<(n * n), id: \.self) { i in
                    let p = Point(x: i % n, y: i / n)
                    let stone = go.stone(at: p)
                    let center = CGPoint(x: inset + CGFloat(p.x) * step, y: inset + CGFloat(p.y) * step)
                    if stone != 0 {
                        Circle()
                            .fill(stone == 1 ? Color.black : Color.white)
                            .overlay(Circle().strokeBorder(.black.opacity(0.4), lineWidth: 0.8))
                            .overlay(
                                Circle().fill(Color.red)
                                    .frame(width: step * 0.2)
                                    .opacity(go.lastPlaced == p ? 1 : 0)
                            )
                            .frame(width: step * 0.85, height: step * 0.85)
                            .position(center)
                            .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    } else {
                        Circle()
                            .fill(Color.clear)
                            .frame(width: step, height: step)
                            .contentShape(Circle())
                            .position(center)
                            .onTapGesture {
                                if session.actionableSeat != nil { session.submit(.place(p)) }
                            }
                    }
                }
            }
        }
    }
}
