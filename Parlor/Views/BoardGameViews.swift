import SwiftUI

/// Shared chess / checkers board: tap a piece, see its targets, tap to move.
struct GridBoardView: View {
    @ObservedObject var session: GameSession
    @State private var selected: Point? = nil
    @State private var promotionChoice: [BoardMove] = []
    // 8. Chess check: pulsing red overlay on the king square while in check.
    @State private var checkPulse = false
    // 12. Checkers promotion sparkle: briefly shows ✨ at the promotion square.
    @State private var promotionSparklePoint: Point? = nil
    @State private var promotionSparkleScale: CGFloat = 0
    @State private var promotionSparkleOpacity: Double = 0
    // Track previous king count to detect new promotions.
    @State private var prevKingCount: Int = 0

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
            capturedBar
                .padding(.horizontal, 12)
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
        .onAppear {
            // 8. Start the continuous check-pulse animation.
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                checkPulse = true
            }
            // Track initial king count for checkers.
            if let checkers = session.game?.engine as? CheckersGame {
                prevKingCount = checkers.kingCount(color: 0) + checkers.kingCount(color: 1)
            }
        }
        // 12. Detect new king promotions in checkers and show sparkle.
        .onChange(of: session.game?.statusText) { _, _ in
            if let checkers = session.game?.engine as? CheckersGame {
                let newKingCount = checkers.kingCount(color: 0) + checkers.kingCount(color: 1)
                if newKingCount > prevKingCount, let lastMove = checkers.lastMove {
                    promotionSparklePoint = lastMove.to
                    promotionSparkleScale = 0
                    promotionSparkleOpacity = 1
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                        promotionSparkleScale = 1.4
                    }
                    withAnimation(.easeOut(duration: 0.9).delay(0.4)) {
                        promotionSparkleScale = 0.0
                        promotionSparkleOpacity = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        promotionSparklePoint = nil
                    }
                }
                prevKingCount = newKingCount
            }
        }
    }

    /// Captured-piece display and move counter for chess/checkers.
    @ViewBuilder
    var capturedBar: some View {
        if let chess = session.game?.engine as? ChessGame {
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    capturedRow(chess: chess, capturedColor: 1, label: "White")
                    Spacer()
                    VStack(spacing: 1) {
                        Text("Move \(chess.moveNumber)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.45))
                        let legalCount = chess.isOver ? 0 : chess.legalBoardMoves(for: chess.currentPlayer).count
                        if legalCount > 0 {
                            Text("\(legalCount)▸")
                                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                                .foregroundStyle(legalCount <= 5 ? .orange.opacity(0.9) : .white.opacity(0.4))
                        }
                        let totalChecks = chess.checksDelivered[0] + chess.checksDelivered[1]
                        if totalChecks > 0 {
                            Text("⚡\(totalChecks) chk")
                                .font(.system(size: 9).monospacedDigit())
                                .foregroundStyle(.orange.opacity(0.8))
                        }
                        // Last move in algebraic notation
                        if let lm = chess.lastMove {
                            let fileOf = { (p: Point) in String(UnicodeScalar(97 + p.x)!) }
                            let rankOf = { (p: Point) in "\(p.y + 1)" }
                            Text("\(fileOf(lm.from))\(rankOf(lm.from))→\(fileOf(lm.to))\(rankOf(lm.to))")
                                .font(.system(size: 8).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        // Castle status: show O-O chip per side that castled
                        let castleLabels = [(0, "W"), (1, "B")].compactMap { (idx, letter) in
                            chess.castled[idx] ? "\(letter) O-O" : nil
                        }
                        if !castleLabels.isEmpty {
                            Text(castleLabels.joined(separator: " "))
                                .font(.system(size: 8).monospacedDigit())
                                .foregroundStyle(.cyan.opacity(0.75))
                        }
                        // 50-move clock warning chip
                        if chess.halfmoveClock >= 80 {
                            Text("⚠️\(chess.halfmoveClock / 2)/50")
                                .font(.system(size: 8).monospacedDigit())
                                .foregroundStyle(.yellow.opacity(0.85))
                        }
                    }
                    Spacer()
                    capturedRow(chess: chess, capturedColor: 0, label: "Black")
                }
                materialAdvantage(chess: chess)
            }
        } else if let checkers = session.game?.engine as? CheckersGame {
            let red = 12 - checkers.pieceCount(color: 0)
            let black = 12 - checkers.pieceCount(color: 1)
            let redKings = checkers.kingCount(color: 0)
            let blackKings = checkers.kingCount(color: 1)
            let redCount = checkers.pieceCount(color: 0)
            let blackCount = checkers.pieceCount(color: 1)
            let _ = (red, black) // suppress unused warning
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    HStack(spacing: 6) {
                        Text("🔴")
                        Text("\(redCount)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.9))
                            .monospacedDigit()
                        if redKings > 0 {
                            Text("\(redKings)♛")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color(red: 1.0, green: 0.8, blue: 0.2))
                        }
                    }
                    // Material advantage bar
                    GeometryReader { geo in
                        let total = max(1, redCount + blackCount)
                        let redFrac = CGFloat(redCount) / CGFloat(total)
                        HStack(spacing: 1) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(red: 0.85, green: 0.2, blue: 0.2))
                                .frame(width: (geo.size.width - 1) * redFrac)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(white: 0.25))
                                .frame(maxWidth: .infinity)
                        }
                        .frame(height: 6)
                        .animation(.easeInOut(duration: 0.35), value: redCount)
                    }
                    .frame(height: 6)
                    Spacer()
                    HStack(spacing: 6) {
                        if blackKings > 0 {
                            Text("\(blackKings)♛")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color(red: 1.0, green: 0.8, blue: 0.2))
                        }
                        Text("\(blackCount)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.9))
                            .monospacedDigit()
                        Text("⚫")
                    }
                }
                HStack(spacing: 6) {
                    Text("\(checkers.movesWithoutCapture) no-cap")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.45))
                    if let desc = checkers.lastMoveDesc {
                        Text(desc)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                HStack(spacing: 6) {
                    if checkers.longestMultiJump >= 3 {
                        Text("⛓ Best: \(checkers.longestMultiJump)-jump")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.white.opacity(0.1), in: Capsule())
                            .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
                    }
                    if checkers.kingToKingCaptures > 0 {
                        Text("♛×♛ \(checkers.kingToKingCaptures)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color(red: 1.0, green: 0.8, blue: 0.2))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(red: 1.0, green: 0.8, blue: 0.2).opacity(0.12), in: Capsule())
                    }
                }
            }
        }
    }

    /// Inline row of captured piece glyphs with repeat stacking.
    func capturedRow(chess: ChessGame, capturedColor: Int, label: String) -> some View {
        let remaining = chess.board.compactMap { $0 }.filter { $0.color == capturedColor }
        let counts: [ChessPieceKind: Int] = remaining.reduce(into: [:]) { $0[$1.kind, default: 0] += 1 }
        let full: [ChessPieceKind: Int] = [.pawn: 8, .rook: 2, .knight: 2, .bishop: 2, .queen: 1, .king: 1]
        let kinds: [ChessPieceKind] = [.queen, .rook, .bishop, .knight, .pawn]

        return HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
            ForEach(kinds, id: \.rawValue) { kind in
                let diff = (full[kind] ?? 0) - (counts[kind] ?? 0)
                if diff > 0 {
                    HStack(spacing: 0) {
                        ForEach(0..<diff, id: \.self) { _ in
                            Text(filledGlyph(kind))
                                .font(.system(size: 11))
                                .foregroundStyle(capturedColor == 1 ? Color.white.opacity(0.9) : Color(white: 0.25))
                        }
                    }
                }
            }
        }
    }

    /// Thin bar showing material advantage (positive = white ahead).
    @ViewBuilder
    func materialAdvantage(chess: ChessGame) -> some View {
        let values: [ChessPieceKind: Int] = [.queen: 9, .rook: 5, .bishop: 3, .knight: 3, .pawn: 1]
        let total: (Int) -> Int = { color in
            chess.board.compactMap { $0 }.filter { $0.color == color }
                .reduce(0) { $0 + (values[$1.kind] ?? 0) }
        }
        let whiteMat = total(1)
        let blackMat = total(0)
        let diff = whiteMat - blackMat
        if diff != 0 {
            let leader = diff > 0 ? "White" : "Black"
            let absDiff = abs(diff)
            Text("\(leader) +\(absDiff)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity)
        }
    }

    func capturedPieces(chess: ChessGame, byColor capturedColor: Int) -> String {
        let remaining = chess.board.compactMap { $0 }.filter { $0.color == capturedColor }
        let counts: [ChessPieceKind: Int] = remaining.reduce(into: [:]) { $0[$1.kind, default: 0] += 1 }
        let full: [ChessPieceKind: Int] = [.pawn: 8, .rook: 2, .knight: 2, .bishop: 2, .queen: 1, .king: 1]
        var lost: [String] = []
        for kind in [ChessPieceKind.queen, .rook, .bishop, .knight, .pawn] {
            let diff = (full[kind] ?? 0) - (counts[kind] ?? 0)
            if diff > 0 { lost.append("\(filledGlyph(kind))×\(diff)") }
        }
        return lost.joined(separator: " ")
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
            .overlay(coordinates(cell: cell))
            // 9. Multi-jump path overlay: thin orange lines connecting jump squares.
            .overlay(jumpPathOverlay(cell: cell))
            // 12. Promotion sparkle: animated ✨ emoji at the promotion square.
            .overlay(promotionSparkleOverlay(cell: cell))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 5)
        }
    }

    /// 9. Draw dashed orange lines from each jump origin to its target,
    ///    passing through the captured-piece midpoint square, so the capture
    ///    path is visible.  Each `BoardMove` for a jump has `from` one step and
    ///    `to` two steps away; the midpoint is the captured piece square.
    @ViewBuilder
    func jumpPathOverlay(cell: CGFloat) -> some View {
        if session.game?.kind == .checkers {
            let jumpMoves: [BoardMove] = {
                guard let sel = selected else { return [] }
                return boardMoves.filter { $0.from == sel }
                    .filter { abs($0.to.x - $0.from.x) == 2 }
            }()
            if !jumpMoves.isEmpty {
                Canvas { ctx, _ in
                    for move in jumpMoves {
                        // The captured square is the midpoint between from and to.
                        let midX = (move.from.x + move.to.x) / 2
                        let midY = (move.from.y + move.to.y) / 2
                        let mid = Point(x: midX, y: midY)
                        let waypoints = [move.from, mid, move.to]
                        let pts = waypoints.map { p -> CGPoint in
                            let screenCol = flipped ? 7 - p.x : p.x
                            let screenRow = flipped ? p.y : 7 - p.y
                            return CGPoint(
                                x: CGFloat(screenCol) * cell + cell * 0.5,
                                y: CGFloat(screenRow) * cell + cell * 0.5
                            )
                        }
                        var path = Path()
                        path.move(to: pts[0])
                        for pt in pts.dropFirst() { path.addLine(to: pt) }
                        ctx.stroke(path,
                                   with: .color(Color.orange.opacity(0.5)),
                                   style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [5, 3]))
                    }
                }
                .allowsHitTesting(false)
            }
        }
    }

    /// 12. Show ✨ emoji at promotion square with scale + fade animation.
    @ViewBuilder
    func promotionSparkleOverlay(cell: CGFloat) -> some View {
        if let pt = promotionSparklePoint {
            let screenCol = flipped ? 7 - pt.x : pt.x
            let screenRow = flipped ? pt.y : 7 - pt.y
            let cx = CGFloat(screenCol) * cell + cell * 0.5
            let cy = CGFloat(screenRow) * cell + cell * 0.5
            Text("✨")
                .font(.system(size: cell * 0.55))
                .scaleEffect(promotionSparkleScale)
                .opacity(promotionSparkleOpacity)
                .position(x: cx, y: cy)
                .allowsHitTesting(false)
        }
    }

    /// File letters and rank numbers tucked into the edge squares (chess only).
    @ViewBuilder
    func coordinates(cell: CGFloat) -> some View {
        if isChess {
            ZStack(alignment: .topLeading) {
                Color.clear
                ForEach(0..<8, id: \.self) { row in
                    let point = pointFor(row: row, col: 0)
                    Text("\(point.y + 1)")
                        .font(.system(size: cell * 0.18, weight: .bold))
                        .foregroundStyle(squareIsDark(point) ? Color.lightSquare : Color.darkSquare)
                        .offset(x: 2, y: CGFloat(row) * cell + 2)
                }
                ForEach(0..<8, id: \.self) { col in
                    let point = pointFor(row: 7, col: col)
                    Text(String(UnicodeScalar(97 + point.x)!))
                        .font(.system(size: cell * 0.18, weight: .bold))
                        .foregroundStyle(squareIsDark(point) ? Color.lightSquare : Color.darkSquare)
                        .offset(x: CGFloat(col) * cell + cell - cell * 0.18,
                                y: 8 * cell - cell * 0.26)
                }
            }
        }
    }

    func squareIsDark(_ point: Point) -> Bool { (point.x + point.y) % 2 == 0 }

    func pointFor(row: Int, col: Int) -> Point {
        // Row 0 renders at the top; y increases toward white/red's side (y=0 bottom).
        let y = flipped ? row : 7 - row
        let x = flipped ? 7 - col : col
        return Point(x: x, y: y)
    }

    @ViewBuilder
    func cellView(point: Point, cell: CGFloat, isTarget: Bool) -> some View {
        let dark = squareIsDark(point)
        let lastMove = lastMovePoints
        let occupied = pieceExists(at: point)
        ZStack {
            Rectangle()
                .fill(dark ? Color.darkSquare : Color.lightSquare)
            if lastMove.contains(point) {
                Rectangle().fill(Color.yellow.opacity(0.3))
            }
            if kingInCheck == point {
                // 8. The threatened king pulses red (opacity animates via checkPulse state).
                RadialGradient(colors: [.red.opacity(checkPulse ? 0.7 : 0.3), .red.opacity(0)],
                               center: .center, startRadius: 2, endRadius: cell * 0.62)
            }
            // Checkers: subtle crown-row tint so players can see where pieces promote.
            if session.game?.kind == .checkers && dark {
                if point.y == 7 {  // red moves +y, crowns at top row
                    Rectangle().fill(Color(red: 0.95, green: 0.45, blue: 0.1).opacity(0.14))
                } else if point.y == 0 {  // black moves -y, crowns at bottom row
                    Rectangle().fill(Color.white.opacity(0.10))
                }
            }
            // Chess: glow on the 7th rank (promotion approaching) if a pawn is there.
            if let chess = session.game?.engine as? ChessGame {
                let whitePawnOnSeven = point.y == 6 && chess[point]?.kind == .pawn && chess[point]?.color == 0
                let blackPawnOnTwo  = point.y == 1 && chess[point]?.kind == .pawn && chess[point]?.color == 1
                if whitePawnOnSeven || blackPawnOnTwo {
                    RadialGradient(colors: [Color(red: 1.0, green: 0.85, blue: 0.2).opacity(0.55), .clear],
                                   center: .center, startRadius: 2, endRadius: cell * 0.55)
                }
            }
            if point == selected {
                Rectangle().fill(Color.cyan.opacity(0.35))
            }
            if isTarget {
                if occupied {
                    // Capture: a ring around the victim.
                    Circle()
                        .strokeBorder(Color.cyan.opacity(0.85), lineWidth: cell * 0.07)
                        .padding(cell * 0.05)
                } else {
                    Circle()
                        .fill(Color.cyan.opacity(0.55))
                        .frame(width: cell * 0.3, height: cell * 0.3)
                }
            }
            pieceView(at: point, cell: cell)
        }
        .frame(width: cell, height: cell)
        .contentShape(Rectangle())
        .onTapGesture { tap(point) }
    }

    func pieceExists(at point: Point) -> Bool {
        if let chess = session.game?.engine as? ChessGame { return chess[point] != nil }
        if let checkers = session.game?.engine as? CheckersGame { return checkers[point] != nil }
        return false
    }

    var lastMovePoints: [Point] {
        if let chess = session.game?.engine as? ChessGame, let m = chess.lastMove { return [m.from, m.to] }
        if let checkers = session.game?.engine as? CheckersGame, let m = checkers.lastMove { return [m.from, m.to] }
        return []
    }

    /// The current player's king square while in check.
    var kingInCheck: Point? {
        guard let chess = session.game?.engine as? ChessGame,
              chess.inCheck(chess.currentPlayer) else { return nil }
        return chess.kingSquare(chess.currentPlayer)
    }

    /// Filled glyphs for both sides, tinted ivory/charcoal with a contrast
    /// shadow — far crisper than the hollow "white" Unicode set.
    @ViewBuilder
    func pieceView(at point: Point, cell: CGFloat) -> some View {
        if let chess = session.game?.engine as? ChessGame, let piece = chess[point] {
            Text(filledGlyph(piece.kind))
                .font(.system(size: cell * 0.8))
                .foregroundStyle(piece.color == 0
                                 ? Color(red: 0.98, green: 0.95, blue: 0.88)
                                 : Color(red: 0.12, green: 0.1, blue: 0.12))
                .shadow(color: piece.color == 0 ? .black.opacity(0.7) : .white.opacity(0.35),
                        radius: 1, y: 1)
        } else if let checkers = session.game?.engine as? CheckersGame, let piece = checkers[point] {
            // Crown-ready: non-king piece one step from promotion row
            let crownRow = piece.color == 0 ? 6 : 1
            let isCrownReady = !piece.king && point.y == crownRow
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: piece.color == 0
                            ? [Color(red: 0.95, green: 0.35, blue: 0.3), Color(red: 0.6, green: 0.08, blue: 0.08)]
                            : [Color(white: 0.35), Color(white: 0.05)],
                        center: .init(x: 0.35, y: 0.3), startRadius: 1, endRadius: cell * 0.5))
                    .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1.5))
                    .overlay(
                        Circle()
                            .strokeBorder(.black.opacity(0.3), lineWidth: cell * 0.05)
                            .padding(cell * 0.1)
                    )
                    .padding(cell * 0.1)
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 2)
                if piece.king {
                    Image(systemName: "crown.fill")
                        .font(.system(size: cell * 0.34))
                        .foregroundStyle(.yellow)
                        .shadow(color: .black.opacity(0.6), radius: 1)
                } else if isCrownReady {
                    // Small crown outline to signal promotion opportunity
                    Image(systemName: "crown")
                        .font(.system(size: cell * 0.28))
                        .foregroundStyle(Color(red: 1.0, green: 0.88, blue: 0.3).opacity(0.85))
                }
            }
            // Gold glow ring for crown-ready pieces
            .overlay(isCrownReady
                ? Circle().strokeBorder(Color(red: 1.0, green: 0.85, blue: 0.2).opacity(0.65), lineWidth: 2).padding(cell * 0.08)
                : nil)
        }
    }

    /// U+FE0E forces text presentation — without it iOS draws the pawn (and
    /// sometimes others) as an emoji that ignores the tint color.
    func filledGlyph(_ kind: ChessPieceKind) -> String {
        let glyph: String
        switch kind {
        case .king: glyph = "♚"
        case .queen: glyph = "♛"
        case .rook: glyph = "♜"
        case .bishop: glyph = "♝"
        case .knight: glyph = "♞"
        case .pawn: glyph = "♟"
        }
        return glyph + "\u{FE0E}"
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
                captureBar(go)
                    .padding(.horizontal, 20)
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

    func captureBar(_ go: GoGame) -> some View {
        let (bScore, wScore) = go.areaScores()
        let total = bScore + wScore
        let bFrac = total > 0 ? bScore / total : 0.5
        let margin = bScore - wScore
        let atari = go.atariPoints
        let bAtari = atari.filter { go.board[go.index($0)] == 1 }.count
        let wAtari = atari.filter { go.board[go.index($0)] == 2 }.count
        return VStack(spacing: 6) {
            HStack(spacing: 12) {
                let bStones = go.board.filter { $0 == 1 }.count
                let wStones = go.board.filter { $0 == 2 }.count
                HStack(spacing: 4) {
                    Circle()
                        .fill(RadialGradient(colors: [Color(white: 0.35), .black],
                                             center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 8))
                        .overlay(Circle().strokeBorder(.black.opacity(0.35), lineWidth: 0.8))
                        .frame(width: 14, height: 14)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 3) {
                            Text("B \(bStones) stones")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.75))
                            if bAtari > 0 {
                                Text("⚠️\(bAtari)")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(.red)
                            }
                        }
                        Text("cap \(go.captures[0])")
                            .font(.system(size: 7))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                Spacer()
                // Territory score + move count + komi
                VStack(spacing: 1) {
                    let leader = margin > 0.5 ? "B" : margin < -0.5 ? "W" : nil
                    if let leader {
                        Text("\(leader) +\(String(format: "%.1f", abs(margin)))")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(margin > 0 ? Color(white: 0.9) : .white)
                    } else {
                        Text("Even")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Text("move \(go.moveCount) · komi \(String(format: "%.1f", go.komi))")
                        .font(.system(size: 7))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
                HStack(spacing: 4) {
                    VStack(alignment: .trailing, spacing: 0) {
                        HStack(spacing: 3) {
                            if wAtari > 0 {
                                Text("⚠️\(wAtari)")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(.red)
                            }
                            Text("W \(wStones) stones")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        Text("cap \(go.captures[1])")
                            .font(.system(size: 7))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Circle()
                        .fill(RadialGradient(colors: [.white, Color(white: 0.78)],
                                             center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 8))
                        .overlay(Circle().strokeBorder(.black.opacity(0.35), lineWidth: 0.8))
                        .frame(width: 14, height: 14)
                }
            }
            // Split score bar: black territory | white territory (includes komi)
            GeometryReader { barGeo in
                HStack(spacing: 1) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(white: 0.22))
                        .frame(width: barGeo.size.width * CGFloat(bFrac) - 0.5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(white: 0.9))
                        .frame(maxWidth: .infinity)
                }
                .animation(.easeOut(duration: 0.4), value: bFrac)
                HStack {
                    Text("\(Int(bScore.rounded()))pts")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .offset(x: 4, y: 1)
                    Spacer()
                    Text("\(String(format: "%.1f", wScore))pts")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.6))
                        .offset(x: -4, y: 1)
                }
            }
            .frame(height: 12)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.1), lineWidth: 0.75))
    }

    func boardView(_ go: GoGame) -> some View {
        GeometryReader { geo in
            let n = go.size
            let inset: CGFloat = 14
            let span = geo.size.width - inset * 2
            let step = span / CGFloat(n - 1)

            ZStack {
                // Kaya-style wood with grain bands.
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [Color(red: 0.89, green: 0.72, blue: 0.45),
                                                  Color(red: 0.8, green: 0.62, blue: 0.36)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        VStack(spacing: geo.size.width / 14) {
                            ForEach(0..<8, id: \.self) { _ in
                                Rectangle()
                                    .fill(.black.opacity(0.03))
                                    .frame(height: 3)
                            }
                        }
                        .rotationEffect(.degrees(3))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    )
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 5)
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

                // Star points (hoshi).
                ForEach(starPoints(n), id: \.self) { p in
                    Circle()
                        .fill(.black.opacity(0.75))
                        .frame(width: 5, height: 5)
                        .position(x: inset + CGFloat(p.x) * step, y: inset + CGFloat(p.y) * step)
                }

                // Ko point: red X marker on the forbidden recapture point
                if let ko = go.koPoint {
                    let kCenter = CGPoint(x: inset + CGFloat(ko.x) * step, y: inset + CGFloat(ko.y) * step)
                    let kr = step * 0.3
                    Path { path in
                        path.move(to: CGPoint(x: kCenter.x - kr, y: kCenter.y - kr))
                        path.addLine(to: CGPoint(x: kCenter.x + kr, y: kCenter.y + kr))
                        path.move(to: CGPoint(x: kCenter.x + kr, y: kCenter.y - kr))
                        path.addLine(to: CGPoint(x: kCenter.x - kr, y: kCenter.y + kr))
                    }
                    .stroke(Color.red.opacity(0.75), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }

                let atariPts = go.atariPoints
                ForEach(0..<(n * n), id: \.self) { i in
                    let p = Point(x: i % n, y: i / n)
                    let stone = go.stone(at: p)
                    let center = CGPoint(x: inset + CGFloat(p.x) * step, y: inset + CGFloat(p.y) * step)
                    let inAtari = atariPts.contains(p)
                    if stone != 0 {
                        Circle()
                            .fill(RadialGradient(
                                colors: stone == 1
                                    ? [Color(white: 0.35), .black]
                                    : [.white, Color(white: 0.78)],
                                center: .init(x: 0.35, y: 0.3),
                                startRadius: 0, endRadius: step * 0.55))
                            .overlay(Circle().strokeBorder(.black.opacity(0.35), lineWidth: 0.8))
                            .overlay(
                                Circle()
                                    .strokeBorder(stone == 1 ? Color.white : Color.black, lineWidth: 1.6)
                                    .frame(width: step * 0.38)
                                    .opacity(go.lastPlaced == p ? 1 : 0)
                            )
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.red.opacity(0.75), lineWidth: 1.5)
                                    .opacity(inAtari ? 1 : 0)
                                    .padding(1)
                            )
                            .frame(width: step * 0.88, height: step * 0.88)
                            .position(center)
                            .shadow(color: .black.opacity(0.35), radius: 1.5, x: 1, y: 1.5)
                            .transition(.scale(scale: 1.6).combined(with: .opacity))
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

                // Coordinate labels: letters along bottom, numbers along left.
                let colLetters = "ABCDEFGHJKLMNOPQRST"
                ForEach(0..<n, id: \.self) { i in
                    let letterIdx = colLetters.index(colLetters.startIndex, offsetBy: i)
                    let letter = String(colLetters[letterIdx])
                    let x = inset + CGFloat(i) * step
                    Text(letter)
                        .font(.system(size: max(8, step * 0.32), weight: .medium, design: .monospaced))
                        .foregroundStyle(.black.opacity(0.5))
                        .position(x: x, y: inset + span + 8)
                }
                ForEach(0..<n, id: \.self) { i in
                    let y = inset + CGFloat(i) * step
                    Text("\(n - i)")
                        .font(.system(size: max(8, step * 0.32), weight: .medium, design: .monospaced))
                        .foregroundStyle(.black.opacity(0.5))
                        .position(x: inset - 9, y: y)
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: go.moveCount)
        }
    }

    /// Traditional hoshi positions for 9/13/19 boards.
    func starPoints(_ n: Int) -> [Point] {
        let edge = n >= 13 ? 3 : 2
        let mid = n / 2
        var points = [Point(x: mid, y: mid)]
        for x in [edge, n - 1 - edge] {
            for y in [edge, n - 1 - edge] {
                points.append(Point(x: x, y: y))
            }
        }
        if n >= 19 {
            for v in [edge, n - 1 - edge] {
                points.append(Point(x: mid, y: v))
                points.append(Point(x: v, y: mid))
            }
        }
        return points
    }
}

extension Color {
    static let darkSquare = Color(red: 0.42, green: 0.3, blue: 0.2)
    static let lightSquare = Color(red: 0.93, green: 0.86, blue: 0.71)
}
