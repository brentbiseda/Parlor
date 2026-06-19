import SwiftUI

/// Capsules: same controls as Blocks — swipe sideways to move, tap to
/// rotate, swipe down to drop — plus a virus count and next-pill preview.
struct CapsulesView: View {
    @ObservedObject var session: GameSession

    @State private var dragSteps: CGFloat = 0
    @State private var lastViruses = -1
    @State private var lastPills = 0
    @State private var paused = false
    @State private var showLevelClear = false
    @State private var chainBadge: String? = nil
    @State private var chainOpacity: Double = 0
    // Virus counter shrink animation (#17)
    @State private var virusCountScale: CGFloat = 1.0

    var game: CapsulesGame? { session.game?.engine as? CapsulesGame }

    static let cellColors: [Color] = [
        Color(red: 0.92, green: 0.3, blue: 0.35),
        Color(red: 0.95, green: 0.8, blue: 0.25),
        Color(red: 0.3, green: 0.6, blue: 0.95),
    ]

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                bottle
                sidebar
            }
            .padding(.horizontal, 12)

            controls
                .padding(.bottom, 6)
        }
        .padding(.top, 8)
        .task(id: session.sessionID) { await gravityLoop() }
    }

    private func gravityLoop() async {
        while true {
            let level = game?.level ?? 1
            let interval = max(0.16, 0.8 * pow(0.85, Double(level - 1)))
            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            } catch {
                break
            }
            guard !paused, let game, !game.isOver, !showLevelClear else { continue }
            submit(.tick)
        }
    }

    private func submit(_ move: TetrisMove) {
        guard !paused, let before = game, !before.isOver else { return }
        session.submit(.capsules(move))
        guard let after = game else { return }
        if after.cleared {
            SoundFX.shared.play(.win)
        } else if after.over {
            SoundFX.shared.play(.lose)
        } else if lastViruses >= 0 && after.virusesLeft < lastViruses {
            SoundFX.shared.play(.lineClear)
            // Virus counter shrink animation (#17)
            withAnimation(.interpolatingSpring(stiffness: 350, damping: 8)) { virusCountScale = 0.8 }
            Task { @MainActor in
                do {
                    try await Task.sleep(nanoseconds: 180_000_000)
                    withAnimation(.spring(response: 0.25)) { virusCountScale = 1.0 }
                } catch { return }
            }
        } else if after.pillsUsed > lastPills {
            SoundFX.shared.play(.lock)
        } else if move == .rotate {
            SoundFX.shared.play(.rotate)
        }
        lastViruses = after.virusesLeft
        lastPills = after.pillsUsed
        if after.cleared { showLevelClear = true }
    }

    var bottle: some View {
        Canvas { context, size in
            guard let game else { return }
            let cell = min(size.width / CGFloat(CapsulesGame.width),
                           size.height / CGFloat(CapsulesGame.height))
            let originX = (size.width - cell * CGFloat(CapsulesGame.width)) / 2

            func rect(_ x: Int, _ y: Int) -> CGRect {
                CGRect(x: originX + CGFloat(x) * cell, y: CGFloat(y) * cell,
                       width: cell - 1.5, height: cell - 1.5)
            }

            context.fill(
                Path(CGRect(x: originX, y: 0,
                            width: cell * CGFloat(CapsulesGame.width),
                            height: cell * CGFloat(CapsulesGame.height))),
                with: .color(.black.opacity(0.45)))

            for y in 0..<CapsulesGame.height {
                for x in 0..<CapsulesGame.width {
                    guard let c = game.cell(x, y) else { continue }
                    let color = Self.cellColors[c.color]
                    if c.isVirus {
                        // Viruses: dark-ringed circles with a scowl that
                        // pulse slowly so the targets stand out.
                        let r = rect(x, y).insetBy(dx: cell * 0.08, dy: cell * 0.08)
                        context.fill(Path(ellipseIn: r), with: .color(color))
                        context.stroke(Path(ellipseIn: r), with: .color(.black.opacity(0.5)), lineWidth: 2)
                        let eye = cell * 0.1
                        context.fill(Path(ellipseIn: CGRect(x: r.midX - eye * 1.6, y: r.midY - eye, width: eye, height: eye)), with: .color(.black))
                        context.fill(Path(ellipseIn: CGRect(x: r.midX + eye * 0.6, y: r.midY - eye, width: eye, height: eye)), with: .color(.black))
                        context.stroke(
                            Path { p in
                                p.move(to: CGPoint(x: r.midX - eye, y: r.midY + eye * 1.2))
                                p.addQuadCurve(to: CGPoint(x: r.midX + eye, y: r.midY + eye * 1.2),
                                               control: CGPoint(x: r.midX, y: r.midY + eye * 0.3))
                            },
                            with: .color(.black), lineWidth: 1.4)
                    } else {
                        let r = rect(x, y)
                        context.fill(Path(roundedRect: r, cornerRadius: cell * 0.3),
                                     with: .color(color))
                        var cap = r.insetBy(dx: cell * 0.14, dy: cell * 0.14)
                        cap.size.height *= 0.4
                        context.fill(Path(roundedRect: cap, cornerRadius: cell * 0.18),
                                     with: .color(.white.opacity(0.3)))
                    }
                }
            }

            if let ghost = game.ghostPill(), ghost != game.current {
                for (x, y, color) in ghost.cells where y >= 0 {
                    context.stroke(Path(roundedRect: rect(x, y), cornerRadius: cell * 0.3),
                                   with: .color(Self.cellColors[color].opacity(0.5)), lineWidth: 1.5)
                }
            }

            if let pill = game.current {
                for (x, y, color) in pill.cells where y >= 0 {
                    context.fill(Path(roundedRect: rect(x, y), cornerRadius: cell * 0.3),
                                 with: .color(Self.cellColors[color]))
                    context.stroke(Path(roundedRect: rect(x, y), cornerRadius: cell * 0.3),
                                   with: .color(.white.opacity(0.5)), lineWidth: 1)
                }
            }
        }
        .aspectRatio(CGFloat(CapsulesGame.width) / CGFloat(CapsulesGame.height), contentMode: .fit)
        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.25), lineWidth: 1.5))
        .overlay(alignment: .topTrailing) { ArcadePauseButton(paused: $paused) }
        .overlay { PausedCurtain(paused: $paused) }
        .overlay { levelClearOverlay }
        .overlay {
            if let badge = chainBadge {
                Text(badge)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(.yellow)
                    .shadow(color: .orange, radius: 6)
                    .opacity(chainOpacity)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.65), in: Capsule())
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .onChange(of: game?.lastChain ?? 0) { _, newChain in
            if newChain > 1 {
                chainBadge = "🔗 ×\(newChain) CHAIN!"
                withAnimation(.easeIn(duration: 0.15)) { chainOpacity = 1.0 }
                Task {
                    do {
                        try await Task.sleep(nanoseconds: 1_200_000_000)
                        withAnimation(.easeOut(duration: 0.35)) { chainOpacity = 0 }
                        try await Task.sleep(nanoseconds: 350_000_000)
                        chainBadge = nil
                    } catch { return }
                }
            }
        }
        .gesture(boardGesture)
    }

    var boardGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let steps = (value.translation.width / 26).rounded(.towardZero)
                while dragSteps < steps { submit(.right); dragSteps += 1 }
                while dragSteps > steps { submit(.left); dragSteps -= 1 }
            }
            .onEnded { value in
                defer { dragSteps = 0 }
                if value.translation.height > 60, abs(value.translation.width) < 50 {
                    submit(.hardDrop)
                } else if abs(value.translation.width) < 12, abs(value.translation.height) < 12 {
                    submit(.rotate)
                }
            }
    }

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.6))
                pillPreview(game?.nextColors, scale: 1.0)
            }
            // Upcoming pills queue (up to 3 shown).
            if let upcoming = game?.upcomingColors, !upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("QUEUE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.4))
                    VStack(spacing: 3) {
                        ForEach(Array(upcoming.prefix(3).enumerated()), id: \.offset) { _, colors in
                            pillPreview(colors, scale: 0.72)
                        }
                    }
                }
            }
            if let game {
                stat("SCORE", "\(game.score)")
                stat("LEVEL", "\(game.level)")
                // Per-color virus tally with progress bar
                VStack(alignment: .leading, spacing: 4) {
                    let cleared = game.virusesAtLevelStart - game.virusesLeft
                    let total = game.virusesAtLevelStart
                    HStack(spacing: 4) {
                        Text("VIRUSES")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.6))
                        // Shrinks on each virus clear (#17)
                        Text("\(cleared)/\(total)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(game.virusesLeft == 0 ? .green : .white.opacity(0.85))
                            .scaleEffect(virusCountScale)
                            .animation(.spring(response: 0.25), value: virusCountScale)
                    }
                    if total > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.15)).frame(height: 5)
                                Capsule()
                                    .fill(game.virusesLeft == 0 ? Color.green : Color(red: 0.95, green: 0.35, blue: 0.35))
                                    .frame(width: geo.size.width * CGFloat(cleared) / CGFloat(total), height: 5)
                                    // Smooth animation as viruses are cleared (#18)
                                    .animation(.easeOut(duration: 0.4), value: cleared)
                            }
                        }
                        .frame(height: 5)
                    }
                    let virusCounts = (0..<3).map { game.virusCount(color: $0) }
                    ForEach(0..<3, id: \.self) { color in
                        if virusCounts[color] > 0 {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(Self.cellColors[color])
                                    .frame(width: 8, height: 8)
                                Text("×\(virusCounts[color])")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                    }
                    if game.virusesLeft == 0 {
                        Text("✓ Clear!")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.green)
                    }
                }
                if game.maxChain > 1 {
                    stat("CHAIN", "×\(game.maxChain)")
                }
                if game.efficientClears > 0 {
                    stat("EFFICIENT", "×\(game.efficientClears)")
                }
            }
            Spacer()
        }
        .frame(width: 86)
    }

    func pillPreview(_ colors: [Int]?, scale: CGFloat) -> some View {
        HStack(spacing: 3 * scale) {
            if let colors {
                ForEach(0..<2, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 6 * scale)
                        .fill(Self.cellColors[colors[i]])
                        .overlay(
                            RoundedRectangle(cornerRadius: 6 * scale)
                                .strokeBorder(.white.opacity(0.45), lineWidth: 1.5 * scale)
                        )
                        .frame(width: 26 * scale, height: 26 * scale)
                }
            } else {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 6 * scale)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 26 * scale, height: 26 * scale)
                }
            }
        }
        .padding(6 * scale)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8 * scale))
        .overlay(RoundedRectangle(cornerRadius: 8 * scale).strokeBorder(.white.opacity(0.15), lineWidth: 1))
    }

    @ViewBuilder
    var levelClearOverlay: some View {
        if showLevelClear, let game {
            ZStack {
                Color.black.opacity(0.65)
                VStack(spacing: 10) {
                    Text("LEVEL \(game.level) CLEAR!")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(.yellow)
                        .shadow(color: .orange.opacity(0.7), radius: 8)
                    Divider().overlay(Color.white.opacity(0.2))
                    VStack(spacing: 4) {
                        let pillsThisLevel = game.pillsUsed - game.pillsAtLevelStart
                        let viruses = game.virusesAtLevelStart
                        Text("Viruses cleared: \(viruses)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        HStack(spacing: 6) {
                            Text("Pills used: \(pillsThisLevel)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(pillsThisLevel < viruses ? .green : .white.opacity(0.85))
                            if viruses > 0 {
                                let ratio = Double(pillsThisLevel) / Double(viruses)
                                let rating = ratio < 1.2 ? "💎 Flawless!" : ratio < 1.5 ? "⭐ Efficient" : ratio < 2.0 ? "👍 Good" : "🔧 Keep grinding"
                                Text(rating)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(ratio < 1.2 ? .mint : ratio < 1.5 ? .yellow : ratio < 2.0 ? .green : .white.opacity(0.6))
                            }
                        }
                        if game.lastChain >= 2 {
                            Text("Best chain: ×\(game.maxChain) 🔗")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.cyan)
                        }
                    }
                    Text("\(game.score) pts total")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.7))
                    Button("Next Level →") {
                        showLevelClear = false
                        session.submit(.capsules(.tick))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.yellow)
                    .foregroundStyle(.black)
                    .font(.headline.weight(.bold))
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .transition(.scale(scale: 0.92).combined(with: .opacity))
            .animation(.spring(response: 0.3), value: showLevelClear)
        }
    }

    func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.6))
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }

    var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                control("arrowtriangle.left.fill") { submit(.left) }
                control("arrow.counterclockwise") { submit(.rotateLeft) }
                control("arrow.clockwise") { submit(.rotate) }
                control("arrowtriangle.right.fill") { submit(.right) }
            }
            HStack(spacing: 10) {
                control("arrowtriangle.down.fill") { submit(.softDrop) }
                control("arrow.down.to.line") { submit(.hardDrop) }
            }
        }
        .padding(.horizontal, 16)
    }

    func control(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}
