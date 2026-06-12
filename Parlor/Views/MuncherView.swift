import SwiftUI

/// Muncher: swipe anywhere to steer; the timer drives the maze.
struct MuncherView: View {
    @ObservedObject var session: GameSession
    @State private var lastScore = 0
    @State private var lastLives = 3
    @State private var paused = false

    var game: MuncherGame? { session.game?.engine as? MuncherGame }

    private let ghostColors: [Color] = [
        Color(red: 0.95, green: 0.25, blue: 0.25),
        Color(red: 0.95, green: 0.55, blue: 0.8),
        Color(red: 0.3, green: 0.85, blue: 0.9),
        Color(red: 0.95, green: 0.65, blue: 0.2),
    ]

    var body: some View {
        VStack(spacing: 8) {
            maze
                .padding(.horizontal, 8)
            Label("Swipe to steer", systemImage: "hand.draw.fill")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
                .padding(.bottom, 4)
        }
        .padding(.top, 6)
        .task(id: session.sessionID) { await clock() }
    }

    private func clock() async {
        while !Task.isCancelled {
            let level = game?.level ?? 1
            let interval = max(0.11, 0.2 * pow(0.93, Double(level - 1)))
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !paused, let before = game, !before.isOver else { continue }
            session.submit(.maze(.tick))
            guard let after = game else { continue }
            if after.lives < lastLives {
                SoundFX.shared.play(after.isOver ? .lose : .lifeLost)
            } else if after.score >= lastScore + 200 {
                SoundFX.shared.play(.jackpot)        // ate a ghost
            } else if after.score >= lastScore + 50 {
                SoundFX.shared.play(.target)         // power pellet
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

            // Ghosts (frightened ghosts flash white as the power runs out).
            for (i, ghost) in game.ghosts.enumerated() {
                let gc = center(ghost.pos)
                let frightenedColor = game.frightenedTicks <= 10 && game.frightenedTicks % 2 == 0
                    ? Color(white: 0.92)
                    : Color(red: 0.25, green: 0.3, blue: 0.9)
                let color = game.frightened && !ghost.inBox
                    ? frightenedColor
                    : ghostColors[i % ghostColors.count]
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
                // Eyes
                let eye = r * 0.28
                for dx in [-r * 0.4, r * 0.15] {
                    context.fill(Path(ellipseIn: CGRect(x: gc.x + dx, y: gc.y - r * 0.5,
                                                        width: eye, height: eye * 1.2)),
                                 with: .color(.white))
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
