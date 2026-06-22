import SwiftUI

/// Falling blocks: rendered with Canvas, gravity driven by a task whose
/// tick interval shrinks as the level climbs. Swipe sideways to move, tap
/// to rotate, swipe down to hard-drop — or use the buttons.
///
/// Color palette is designed for deuteranopia/protanopia (red-green) accessibility:
/// S and Z use visually distinct hues (bright lime vs magenta) rather than the
/// traditional green/red pair that many players cannot distinguish.
struct TetrisView: View {
    @ObservedObject var session: GameSession

    @State private var dragSteps: CGFloat = 0
    @State private var lastLines = 0
    @State private var lastPieces = 0
    @State private var lastLevel = 1
    @State private var lineFlash = false
    @State private var levelFlash = false
    @State private var paused = false
    @State private var clearBadge: String? = nil

    var game: TetrisGame? { session.game?.engine as? TetrisGame }

    private let pieceColors: [Color] = [
        .clear,                                    // 0 = empty
        Color(red: 0.22, green: 0.88, blue: 0.95), // I — cyan
        Color(red: 0.98, green: 0.88, blue: 0.22), // O — yellow
        Color(red: 0.72, green: 0.38, blue: 0.92), // T — purple
        Color(red: 0.55, green: 0.95, blue: 0.22), // S — lime  (colorblind-safe vs Z)
        Color(red: 0.95, green: 0.25, blue: 0.65), // Z — magenta (colorblind-safe vs S)
        Color(red: 0.28, green: 0.50, blue: 0.98), // J — blue
        Color(red: 0.98, green: 0.60, blue: 0.18), // L — orange
    ]

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                board
                sidebar
            }
            .padding(.horizontal, 12)

            controls
                .padding(.bottom, 6)
        }
        .padding(.top, 8)
        .task(id: session.sessionID) { await gravityLoop() }
    }

    // MARK: - Gravity

    private func gravityLoop() async {
        while !Task.isCancelled {
            let level = game?.level ?? 1
            let interval = max(0.12, 0.85 * pow(0.82, Double(level - 1)))
            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            } catch {
                break   // cancelled — exit cleanly
            }
            guard !paused, let game, !game.isOver else { continue }
            submit(.tick)
        }
    }

    private func submit(_ move: TetrisMove) {
        guard !paused, let before = game, !before.isOver else { return }
        session.submit(.tetris(move))
        guard let after = game else { return }
        if after.isOver {
            SoundFX.shared.play(.lose)
        } else if after.lines > lastLines {
            let cleared = after.lines - lastLines
            SoundFX.shared.play(cleared >= 4 ? .jackpot : .lineClear)
            lineFlash = true
            // Show clear label and combo in the sidebar badge.
            var badge = after.lastClearLabel ?? ""
            if after.combo > 1 { badge += " ×\(after.combo)" }
            if after.backToBack && cleared == 4 { badge = "B2B TETRIS!" }
            clearBadge = badge.isEmpty ? nil : badge
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 220_000_000)
                lineFlash = false
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                clearBadge = nil
            }
        } else if after.piecesPlaced > lastPieces {
            SoundFX.shared.play(.lock)
            if after.lines == lastLines { clearBadge = nil }
        } else if move == .rotate {
            SoundFX.shared.play(.rotate)
        }
        if after.level > lastLevel {
            levelFlash = true
            Task { @MainActor in
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    levelFlash = false
                } catch { return }
            }
        }
        lastLines = after.lines
        lastPieces = after.piecesPlaced
        lastLevel = after.level
    }

    // MARK: - Board

    var board: some View {
        Canvas { context, size in
            guard let game else { return }
            let cell = min(size.width / CGFloat(TetrisGame.width),
                           size.height / CGFloat(TetrisGame.height))
            let originX = (size.width - cell * CGFloat(TetrisGame.width)) / 2

            func rect(_ x: Int, _ y: Int) -> CGRect {
                CGRect(x: originX + CGFloat(x) * cell, y: CGFloat(y) * cell,
                       width: cell - 1, height: cell - 1)
            }

            // Well background.
            context.fill(
                Path(CGRect(x: originX, y: 0,
                            width: cell * CGFloat(TetrisGame.width),
                            height: cell * CGFloat(TetrisGame.height))),
                with: .color(.black.opacity(0.45)))

            // Beveled cells: light cap, dark base.
            func drawCell(_ r: CGRect, _ color: Color) {
                context.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(color))
                var cap = r
                cap.size.height *= 0.42
                context.fill(Path(roundedRect: cap, cornerRadius: 2),
                             with: .color(.white.opacity(0.22)))
                var base = r
                base.origin.y += r.height * 0.66
                base.size.height *= 0.34
                context.fill(Path(roundedRect: base, cornerRadius: 2),
                             with: .color(.black.opacity(0.2)))
            }

            // Settled cells.
            for y in 0..<TetrisGame.height {
                for x in 0..<TetrisGame.width {
                    let value = game.cell(x, y)
                    guard value != 0 else { continue }
                    drawCell(rect(x, y), pieceColors[value])
                }
            }

            // Ghost landing outline — opacity increases when ghost is close to active piece.
            // A top-lighter gradient gives depth to ghost cells.
            if let ghost = game.ghostPiece(), let piece = game.current, ghost != piece {
                let distance = ghost.y - piece.y
                let ghostOpacity = distance <= 3 ? 0.55 : distance <= 6 ? 0.40 : distance <= 10 ? 0.28 : 0.18
                for (x, y) in ghost.cells() where y >= 0 {
                    let r = rect(x, y)
                    // Subtle top-half lighter fill for depth.
                    var topHalf = r
                    topHalf.size.height *= 0.5
                    context.fill(Path(roundedRect: topHalf, cornerRadius: 2),
                                 with: .color(.white.opacity(ghostOpacity * 0.25)))
                    context.stroke(Path(roundedRect: r, cornerRadius: 2),
                                   with: .color(.white.opacity(ghostOpacity)), lineWidth: 1.5)
                }
            }

            // Falling piece.
            if let piece = game.current {
                for (x, y) in piece.cells() where y >= 0 {
                    drawCell(rect(x, y), pieceColors[piece.kind.colorIndex])
                }
            }
        }
        .aspectRatio(CGFloat(TetrisGame.width) / CGFloat(TetrisGame.height), contentMode: .fit)
        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.25), lineWidth: 1.5))
        // Line-clear flash: bright horizontal white stripe effect (#1)
        .overlay(
            Rectangle()
                .fill(.white.opacity(lineFlash ? 0.60 : 0))
                .animation(.easeOut(duration: 0.30), value: lineFlash)
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.red.opacity((game?.stackHeight ?? 0) >= 16 ? 0.85 : 0), lineWidth: 3)
                .animation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true), value: (game?.stackHeight ?? 0) >= 16)
        )
        .overlay(alignment: .bottom) { lockDelayBar }
        .overlay(alignment: .topTrailing) { ArcadePauseButton(paused: $paused) }
        .overlay { PausedCurtain(paused: $paused) }
        .gesture(boardGesture)
    }

    /// Swipe horizontally to step the piece, swipe down to hard-drop,
    /// swipe up to hold, tap to rotate.
    var boardGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let stepWidth: CGFloat = 24
                let steps = (value.translation.width / stepWidth).rounded(.towardZero)
                while dragSteps < steps { submit(.right); dragSteps += 1 }
                while dragSteps > steps { submit(.left); dragSteps -= 1 }
            }
            .onEnded { value in
                defer { dragSteps = 0 }
                let dx = abs(value.translation.width)
                let dy = value.translation.height
                if dy > 60, dx < 50 {
                    submit(.hardDrop)
                } else if dy < -40, dx < 50 {
                    // Swipe up = hold piece
                    if game?.canHold == true { submit(.hold) }
                } else if dx < 12, abs(dy) < 12 {
                    submit(.rotate)
                }
            }
    }

    /// Thin bar at the bottom of the well showing lock-delay countdown.
    /// Only visible when the current piece is on the ground and about to lock.
    @ViewBuilder
    var lockDelayBar: some View {
        if let game, game.current != nil, !game.isOver {
            let ticks = game.lockDelayTicks
            let maxTicks = TetrisGame.lockDelayMax
            let grounded = ticks > 0
            if grounded {
                let frac = CGFloat(ticks) / CGFloat(maxTicks)
                GeometryReader { geo in
                    Capsule()
                        .fill(Color.orange.opacity(0.85))
                        .frame(width: geo.size.width * frac, height: 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(.linear(duration: 0.12), value: frac)
                }
                .frame(height: 4)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            }
        }
    }

    // MARK: - Sidebar & controls

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Next-piece queue: primary + 2 queued
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.6))
                nextPreview
                if let game {
                    ForEach(Array(game.nextQueue.enumerated()), id: \.offset) { _, kind in
                        piecePreview(kind: kind, scale: 0.72)
                    }
                }
            }

            // Hold piece
            VStack(alignment: .leading, spacing: 4) {
                Text("HOLD")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.6))
                holdPreview
            }

            if let game {
                statBlock("SCORE", "\(game.score)")
                statBlock("LINES", "\(game.lines)")
                // Level chip flashes gold on level-up (#3)
                statBlock("LEVEL", "\(game.level)", tint: levelFlash ? Color(red: 1.0, green: 0.82, blue: 0.1) : .white)
                    .animation(.easeOut(duration: 0.4), value: levelFlash)
                // Lines to next level chip (#5)
                let toNext = 10 - (game.lines % 10)
                if !game.isOver {
                    let toNextCapped = toNext == 10 ? 0 : toNext
                    let levelColor: Color = toNextCapped <= 2 ? .yellow : .white.opacity(0.55)
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.to.line")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(levelColor)
                        Text("LV in \(toNextCapped)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(levelColor)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(levelColor.opacity(0.1), in: Capsule())
                    .overlay(Capsule().strokeBorder(levelColor.opacity(0.3), lineWidth: 0.75))
                }
                if let badge = clearBadge {
                    let isTSpin = badge.contains("T-SPIN") || badge.contains("I-SPIN")
                    let tSpinColor = Color(red: 0.72, green: 0.38, blue: 0.92)
                    let badgeColor: Color = isTSpin
                        ? tSpinColor
                        : badge.contains("PERFECT") ? .mint : .yellow
                    Text(badge)
                        .font(.caption2.weight(.black))
                        .foregroundStyle(badgeColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .background(badgeColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(badgeColor.opacity(0.4), lineWidth: 1))
                        // T-spin gets a pulsing purple glow shadow (#2)
                        .shadow(color: isTSpin ? tSpinColor.opacity(0.6) : .clear, radius: 8)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                        .animation(.spring(response: 0.25), value: badge)
                }
                if game.combo > 1 {
                    statBlock("COMBO", "×\(game.combo)")
                } else if game.maxCombo > 2 {
                    statBlock("B.CMBO", "×\(game.maxCombo)")
                }
                if let ppm = game.piecesPerMinute, !game.isOver {
                    statBlock("PPM", "\(ppm)")
                }
                // Stack height indicator
                if !game.isOver {
                    let sh = game.stackHeight
                    let shColor: Color = sh >= 16 ? .red : sh >= 12 ? .orange : sh >= 8 ? .yellow : .white
                    statBlock("STACK", "\(sh)", tint: shColor)
                }
                // Line-type breakdown
                let totalClears = game.singleCount + game.doubleCount + game.tripleCount + game.tetrisCount
                if totalClears > 0 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CLEARS")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.6))
                        if game.singleCount > 0 {
                            Text("1L×\(game.singleCount)")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        if game.doubleCount > 0 {
                            Text("2L×\(game.doubleCount)")
                                .font(.caption2)
                                .foregroundStyle(.cyan.opacity(0.9))
                        }
                        if game.tripleCount > 0 {
                            Text("3L×\(game.tripleCount)")
                                .font(.caption2)
                                .foregroundStyle(.mint.opacity(0.9))
                        }
                        if game.tetrisCount > 0 {
                            let totalClears = game.singleCount + game.doubleCount + game.tripleCount + game.tetrisCount
                            let tetrisPct = totalClears > 0 ? Int(Double(game.tetrisCount) / Double(totalClears) * 100) : 0
                            let effColor: Color = tetrisPct >= 50 ? .yellow : tetrisPct >= 25 ? Color(red: 1.0, green: 0.8, blue: 0.0) : .white.opacity(0.7)
                            Text("T×\(game.tetrisCount)(\(tetrisPct)%)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(effColor)
                        }
                        if game.tSpinCount > 0 {
                            Text("🌀×\(game.tSpinCount)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color(red: 0.72, green: 0.38, blue: 0.92))
                        }
                        if game.iSpinCount > 0 {
                            Text("🔵×\(game.iSpinCount)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.cyan)
                        }
                        if game.perfectClears > 0 {
                            Text("💎×\(game.perfectClears)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.mint)
                        }
                    }
                }
            }
            Spacer()
        }
        .frame(width: 86)
    }

    func piecePreview(kind: TetrisGame.PieceKind?, dimmed: Bool = false, scale: CGFloat = 1.0) -> some View {
        let h = 48 * scale
        return Canvas { context, size in
            guard let kind else { return }
            let cell: CGFloat = size.width / 4.5
            let cells = TetrisGame.Piece(kind: kind, rotation: 0, x: 0, y: 0).cells()
            let minX = cells.map(\.x).min() ?? 0
            let minY = cells.map(\.y).min() ?? 0
            for (x, y) in cells {
                let rect = CGRect(x: CGFloat(x - minX) * cell + 4,
                                  y: CGFloat(y - minY) * cell + 4,
                                  width: cell - 1, height: cell - 1)
                context.fill(Path(roundedRect: rect, cornerRadius: 2),
                             with: .color(pieceColors[kind.colorIndex].opacity(dimmed ? 0.45 : 1.0)))
                // Highlight cap
                var cap = rect; cap.size.height *= 0.4
                context.fill(Path(roundedRect: cap, cornerRadius: 2),
                             with: .color(.white.opacity(dimmed ? 0.08 : 0.2)))
            }
        }
        .frame(width: 86, height: h)
        .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.2), lineWidth: 1))
    }

    var nextPreview: some View { piecePreview(kind: game?.nextKind) }

    var holdPreview: some View {
        let held = game?.hold
        let dimmed = game?.holdUsed ?? false
        return piecePreview(kind: held, dimmed: dimmed)
            .overlay(alignment: .center) {
                if held == nil {
                    Text("—")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
    }

    func statBlock(_ label: String, _ value: String, tint: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .black)).kerning(0.5)
                .foregroundStyle(.white.opacity(0.45))
            Text(value)
                .font(.system(size: 20, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.3), value: tint == .red)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05))
                if tint != .white {
                    RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.06))
                    RoundedRectangle(cornerRadius: 8).strokeBorder(tint.opacity(0.3), lineWidth: 0.75)
                } else {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                }
            }
        )
        .shadow(color: tint != .white ? tint.opacity(0.18) : .clear, radius: 5)
    }

    var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                controlButton("arrowtriangle.left.fill") { submit(.left) }
                controlButton("arrow.counterclockwise") { submit(.rotateLeft) }
                controlButton("arrow.2.squarepath") { submit(.rotate180) }
                controlButton("arrow.clockwise") { submit(.rotate) }
                controlButton("arrowtriangle.right.fill") { submit(.right) }
            }
            HStack(spacing: 10) {
                controlButton("tray.and.arrow.down.fill",
                              tint: (game?.canHold ?? false) ? .cyan : .white.opacity(0.3)) {
                    submit(.hold)
                }
                controlButton("arrowtriangle.down.fill") { submit(.softDrop) }
                controlButton("arrow.down.to.line") { submit(.hardDrop) }
            }
        }
        .padding(.horizontal, 16)
    }

    func controlButton(_ symbol: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }
}
