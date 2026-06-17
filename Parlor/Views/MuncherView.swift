import SwiftUI

/// Muncher: swipe anywhere to steer; the timer drives the maze.
struct MuncherView: View {
    @ObservedObject var session: GameSession
    @State private var lastScore = 0
    @State private var lastLives = 3
    @State private var paused = false
    @State private var ghostComboPopup: String? = nil

    var game: MuncherGame? { session.game?.engine as? MuncherGame }

    /// Ghost colors keyed by GhostType raw value: Blinky/red, Pinky/pink, Inky/cyan, Clyde/orange.
    private let ghostColors: [Color] = [
        Color(red: 0.95, green: 0.2,  blue: 0.2),   // Blinky
        Color(red: 0.98, green: 0.55, blue: 0.82),   // Pinky
        Color(red: 0.25, green: 0.82, blue: 0.92),   // Inky
        Color(red: 0.95, green: 0.62, blue: 0.18),   // Clyde
    ]

    var body: some View {
        VStack(spacing: 6) {
            if let game, game.frightened {
                powerTimer(game: game)
                    .padding(.horizontal, 12)
            }
            ZStack {
                maze
                    .padding(.horizontal, 8)
                if let popup = ghostComboPopup {
                    Text(popup)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.yellow)
                        .shadow(color: .orange, radius: 4)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.4), value: ghostComboPopup)
            HStack(spacing: 8) {
                Label("Swipe to steer", systemImage: "hand.draw.fill")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
                if let game, game.isScatterPhase {
                    Text("SCATTER")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.cyan.opacity(0.12), in: Capsule())
                }
                Spacer(minLength: 0)
                if let game {
                    let activeGhosts = game.ghosts.filter { !$0.inBox }.count
                    if activeGhosts > 0 {
                        Text("\(activeGhosts)👻")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(activeGhosts == 4 ? Color(red: 1.0, green: 0.65, blue: 0.0) : .white.opacity(0.75))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.4), in: Capsule())
                    }
                    if game.totalGhostsEaten > 0 {
                        Text("👻×\(game.totalGhostsEaten)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.purple.opacity(0.9))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.purple.opacity(0.15), in: Capsule())
                    }
                }
            }
            .padding(.bottom, 4)
        }
        .padding(.top, 6)
        .task(id: session.sessionID) { await clock() }
    }

    func powerTimer(game: MuncherGame) -> some View {
        let maxTicks = max(60 - game.level * 6, 24)
        let fraction = Double(game.frightenedTicks) / Double(maxTicks)
        let warning = fraction < 0.35
        return HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(warning ? .red : .yellow)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(warning ? Color.red : Color.yellow)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 6)
            Text("POWER")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func clock() async {
        while true {
            let level = game?.level ?? 1
            let interval = max(0.11, 0.2 * pow(0.93, Double(level - 1)))
            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            } catch {
                break
            }
            guard !paused, let before = game, !before.isOver else { continue }
            session.submit(.maze(.tick))
            guard let after = game else { continue }
            if after.lives < lastLives {
                SoundFX.shared.play(after.isOver ? .lose : .lifeLost)
            } else if after.score >= lastScore + 200 {
                SoundFX.shared.play(.jackpot)
                let combo = after.ghostsEatenThisPower
                let pts = 200 * (1 << min(combo - 1, 3))
                ghostComboPopup = combo > 1 ? "×\(combo) 👻 +\(pts)!" : "👻 +\(pts)!"
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    ghostComboPopup = nil
                }
            } else if after.score >= lastScore + 50 {
                SoundFX.shared.play(.target)
            }
            lastScore = after.score
            lastLives = after.lives
        }
    }

    var maze: some View {
        Canvas { context, size in
            guard let game else { return }
            let cw = size.width / CGFloat(MuncherGame.width)
            let ch = size.height / CGFloat(MuncherGame.height)

            func center(_ index: Int) -> CGPoint {
                CGPoint(x: (CGFloat(MuncherGame.x(index)) + 0.5) * cw,
                        y: (CGFloat(MuncherGame.y(index)) + 0.5) * ch)
            }

            // Walls: dark fill with a neon edge.
            for index in game.walls {
                let rect = CGRect(x: CGFloat(MuncherGame.x(index)) * cw + 0.5,
                                  y: CGFloat(MuncherGame.y(index)) * ch + 0.5,
                                  width: cw - 1, height: ch - 1)
                context.fill(Path(roundedRect: rect, cornerRadius: 2),
                             with: .color(Color(red: 0.07, green: 0.1, blue: 0.32)))
                context.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 2),
                               with: .color(Color(red: 0.25, green: 0.4, blue: 0.95).opacity(0.8)),
                               lineWidth: 1)
            }

            // Bonus fruit.
            if let fruit = game.fruit {
                let c = center(fruit)
                context.draw(Text("🍒").font(.system(size: min(cw, ch) * 0.95)), at: c)
            }

            // Pellets
            for index in game.pellets {
                let c = center(index)
                context.fill(Path(ellipseIn: CGRect(x: c.x - 1.5, y: c.y - 1.5, width: 3, height: 3)),
                             with: .color(.white.opacity(0.85)))
            }
            for index in game.powerPellets {
                let c = center(index)
                let r: CGFloat = game.ticks % 6 < 3 ? 5 : 4
                context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                             with: .color(.white))
            }

            // Muncher: a wedge-mouthed disc facing its direction.
            let pc = center(game.pac)
            let radius = min(cw, ch) * 0.46
            var mouth = Path()
            let facing: Double
            switch game.pacDir {
            case .right: facing = 0
            case .down: facing = 90
            case .left: facing = 180
            case .up: facing = 270
            }
            let open = game.ticks % 4 < 2 ? 38.0 : 12.0
            mouth.move(to: pc)
            mouth.addArc(center: pc, radius: radius,
                         startAngle: .degrees(facing + open),
                         endAngle: .degrees(facing - open + 360),
                         clockwise: false)
            mouth.closeSubpath()
            context.fill(mouth, with: .color(Color(red: 1.0, green: 0.85, blue: 0.2)))

            // Ghosts: personality-colored normally, blue/flashing when frightened.
            for ghost in game.ghosts {
                let gc = center(ghost.pos)
                let isFrightened = game.frightened && !ghost.inBox
                let isWarning = game.frightenedTicks <= 20 && game.frightenedTicks % 4 < 2
                let frightenedColor: Color = isWarning
                    ? Color(white: 0.95)
                    : Color(red: 0.25, green: 0.3, blue: 0.92)
                let color = isFrightened
                    ? frightenedColor
                    : ghostColors[ghost.type.rawValue % ghostColors.count]
                let r = min(cw, ch) * 0.44
                var body = Path()
                body.addArc(center: CGPoint(x: gc.x, y: gc.y - r * 0.1), radius: r,
                            startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                body.addLine(to: CGPoint(x: gc.x + r, y: gc.y + r * 0.8))
                for k in 0..<3 {
                    let step = r * 2 / 3
                    body.addLine(to: CGPoint(x: gc.x + r - step * (CGFloat(k) + 0.5), y: gc.y + r * 0.5))
                    body.addLine(to: CGPoint(x: gc.x + r - step * CGFloat(k + 1), y: gc.y + r * 0.8))
                }
                body.closeSubpath()
                context.fill(body, with: .color(color))
                if isFrightened {
                    // Scared face: wavy mouth + white dot eyes.
                    let ew = r * 0.18
                    for dx: CGFloat in [-r * 0.28, r * 0.12] {
                        context.fill(Path(ellipseIn: CGRect(x: gc.x + dx, y: gc.y - r * 0.4,
                                                            width: ew, height: ew)),
                                     with: .color(.white))
                    }
                    var mouth = Path()
                    mouth.move(to: CGPoint(x: gc.x - r * 0.4, y: gc.y + r * 0.2))
                    mouth.addCurve(to: CGPoint(x: gc.x + r * 0.4, y: gc.y + r * 0.2),
                                   control1: CGPoint(x: gc.x - r * 0.15, y: gc.y + r * 0.45),
                                   control2: CGPoint(x: gc.x + r * 0.15, y: gc.y))
                    context.stroke(mouth, with: .color(.white.opacity(0.85)), lineWidth: 1.5)
                } else {
                    // Normal face: eyes with colored irises tracking movement direction.
                    let eye = r * 0.28
                    let labels = ["B", "P", "I", "C"]
                    for (di, dx) in [(-r * 0.4, 0), (r * 0.15, 1)] as [(CGFloat, Int)] {
                        let eyeRect = CGRect(x: gc.x + dx, y: gc.y - r * 0.5, width: eye, height: eye * 1.2)
                        context.fill(Path(ellipseIn: eyeRect), with: .color(.white))
                        context.fill(Path(ellipseIn: eyeRect.insetBy(dx: eye * 0.2, dy: eye * 0.2)),
                                     with: .color(Color(red: 0.1, green: 0.2, blue: 0.9)))
                    }
                    // Ghost name initial (tiny, in-body label for clarity at small sizes).
                    let label = labels[ghost.type.rawValue % labels.count]
                    context.draw(Text(label).font(.system(size: r * 0.45, weight: .black, design: .rounded))
                                    .foregroundColor(.white.opacity(0.55)),
                                 at: CGPoint(x: gc.x, y: gc.y + r * 0.35))
                }
            }
        }
        .aspectRatio(CGFloat(MuncherGame.width) / CGFloat(MuncherGame.height), contentMode: .fit)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.2), lineWidth: 1.5))
        .overlay(alignment: .topTrailing) { ArcadePauseButton(paused: $paused) }
        .overlay { PausedCurtain(paused: $paused) }
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    let direction: GridDirection = abs(dx) > abs(dy)
                        ? (dx > 0 ? .right : .left)
                        : (dy > 0 ? .down : .up)
                    session.submit(.maze(.go(direction)))
                }
        )
    }
}
