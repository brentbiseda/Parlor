import SwiftUI

/// Nibbles: swipe (or use the arrows) to steer; the clock speeds up with
/// every level. The snake is drawn as a rounded chain with a proper head.
struct SnakeView: View {
    @ObservedObject var session: GameSession
    @State private var paused = false
    @State private var lastScore = 0
    @State private var lastLives = 3
    @State private var lastLevel = 1

    var game: SnakeGame? { session.game?.engine as? SnakeGame }

    var body: some View {
        VStack(spacing: 8) {
            board
                .padding(.horizontal, 10)
            controls
                .padding(.bottom, 6)
        }
        .padding(.top, 6)
        .task(id: session.sessionID) { await clock() }
    }

    private func clock() async {
        while !Task.isCancelled {
            let level = game?.level ?? 1
            let interval = max(0.09, 0.24 * pow(0.88, Double(level - 1)))
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !paused, let before = game, !before.isOver else { continue }
            session.submit(.snake(.tick))
            guard let after = game else { continue }
            if after.isOver {
                SoundFX.shared.play(.lose)
            } else if after.lives < lastLives {
                SoundFX.shared.play(.lifeLost)
            } else if after.level > lastLevel {
                SoundFX.shared.play(.levelUp)
            } else if after.score > lastScore {
                SoundFX.shared.play(.target)
            }
            lastScore = after.score
            lastLives = after.lives
            lastLevel = after.level
        }
    }

    private func turn(_ direction: GridDirection) {
        guard !paused, let game, !game.isOver else { return }
        session.submit(.snake(.turn(direction)))
    }

    var board: some View {
        Canvas { context, size in
            guard let game else { return }
            let cw = size.width / CGFloat(SnakeGame.width)
            let ch = size.height / CGFloat(SnakeGame.height)

            func cellRect(_ index: Int) -> CGRect {
                CGRect(x: CGFloat(SnakeGame.x(index)) * cw + 1,
                       y: CGFloat(SnakeGame.y(index)) * ch + 1,
                       width: cw - 2, height: ch - 2)
            }

            // Subtle checker for depth.
            for y in 0..<SnakeGame.height {
                for x in 0..<SnakeGame.width where (x + y).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(x) * cw, y: CGFloat(y) * ch,
                                             width: cw, height: ch)),
                                 with: .color(.white.opacity(0.025)))
                }
            }

            // Level walls.
            for wall in game.walls {
                context.fill(Path(roundedRect: cellRect(wall), cornerRadius: 2),
                             with: .color(Color(red: 0.5, green: 0.42, blue: 0.3)))
                context.stroke(Path(roundedRect: cellRect(wall), cornerRadius: 2),
                               with: .color(.white.opacity(0.25)), lineWidth: 1)
            }

            // Food.
            context.draw(Text("🍎").font(.system(size: min(cw, ch) * 0.9)),
                         at: CGPoint(x: cellRect(game.food).midX, y: cellRect(game.food).midY))

            // Body, tail to head, fading toward the tail.
            for (i, segment) in game.body.enumerated().reversed() {
                let t = CGFloat(i) / CGFloat(max(game.body.count - 1, 1))
                let green = Color(red: 0.25 + 0.2 * t, green: 0.8 - 0.25 * t, blue: 0.3)
                context.fill(Path(roundedRect: cellRect(segment), cornerRadius: min(cw, ch) * 0.3),
                             with: .color(green))
            }

            // Head: brighter, with eyes set by travel direction.
            if let head = game.body.first {
                let r = cellRect(head)
                context.fill(Path(roundedRect: r, cornerRadius: min(cw, ch) * 0.34),
                             with: .color(Color(red: 0.3, green: 0.95, blue: 0.4)))
                let eye = min(cw, ch) * 0.16
                let along: (CGFloat, CGFloat) = (CGFloat(game.direction.dx), CGFloat(game.direction.dy))
                let side: (CGFloat, CGFloat) = (-along.1, along.0)
                for s in [CGFloat(-1), 1] {
                    let ex = r.midX + along.0 * r.width * 0.18 + side.0 * s * r.width * 0.2
                    let ey = r.midY + along.1 * r.height * 0.18 + side.1 * s * r.height * 0.2
                    context.fill(Path(ellipseIn: CGRect(x: ex - eye / 2, y: ey - eye / 2,
                                                        width: eye, height: eye)),
                                 with: .color(.black))
                }
            }
        }
        .aspectRatio(CGFloat(SnakeGame.width) / CGFloat(SnakeGame.height), contentMode: .fit)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
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
                    turn(direction)
                }
        )
    }

    var controls: some View {
        HStack(spacing: 10) {
            arrow("arrowtriangle.left.fill", .left)
            VStack(spacing: 8) {
                arrow("arrowtriangle.up.fill", .up)
                arrow("arrowtriangle.down.fill", .down)
            }
            arrow("arrowtriangle.right.fill", .right)
        }
        .padding(.horizontal, 60)
    }

    func arrow(_ symbol: String, _ direction: GridDirection) -> some View {
        Button { turn(direction) } label: {
            Image(systemName: symbol)
                .font(.title3.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}
