import SwiftUI

/// Nibbles: swipe (or use the arrows) to steer; the clock speeds up with
/// every level. The snake is drawn as a rounded chain with a proper head.
/// Bonus star food appears every 3rd bite for 3× points.
struct SnakeView: View {
    @ObservedObject var session: GameSession
    @State private var paused = false
    @State private var lastScore = 0
    @State private var lastLives = 3
    @State private var lastLevel = 1
    @State private var scorePopup: String? = nil
    @State private var levelFlash = false

    var game: SnakeGame? { session.game?.engine as? SnakeGame }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                board
                    .padding(.horizontal, 10)
                if let popup = scorePopup {
                    Text(popup)
                        .font(.title2.weight(.black))
                        .foregroundStyle(.yellow)
                        .shadow(color: .black, radius: 3)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.5), value: scorePopup)

            distanceChip
            controls
                .padding(.bottom, 6)
        }
        .padding(.top, 6)
        .task(id: session.sessionID) { await clock() }
    }

    private func clock() async {
        while true {
            let level = game?.level ?? 1
            let interval = max(0.09, 0.24 * pow(0.88, Double(level - 1)))
            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            } catch {
                break
            }
            guard !paused, let before = game, !before.isOver else { continue }
            let prevBonus = before.bonusFood
            session.submit(.snake(.tick))
            guard let after = game else { continue }
            if after.isOver {
                SoundFX.shared.play(.lose)
            } else if after.lives < lastLives {
                SoundFX.shared.play(.lifeLost)
                scorePopup = nil
            } else if after.level > lastLevel {
                SoundFX.shared.play(.levelUp)
                scorePopup = "Level \(after.level)! +\(SnakeGame.levelBonus)"
                levelFlash = true
                clearPopup()
            } else if after.score > lastScore {
                let gained = after.score - lastScore
                if gained >= SnakeGame.pointsPerBite * after.level * SnakeGame.bonusMultiplier {
                    SoundFX.shared.play(.jackpot)
                    scorePopup = "⭐ ×\(SnakeGame.bonusMultiplier) \(gained > 0 ? "+\(gained)" : "")"
                    clearPopup()
                } else if gained > SnakeGame.pointsPerBite * after.level {
                    SoundFX.shared.play(.lineClear)
                    scorePopup = "Combo! +\(gained)"
                    clearPopup()
                } else {
                    SoundFX.shared.play(.target)
                    if prevBonus == nil && after.bonusFood != nil {
                        scorePopup = "⭐ Bonus!"
                        clearPopup()
                    }
                }
            }
            lastScore = after.score
            lastLives = after.lives
            lastLevel = after.level
        }
    }

    private func clearPopup() {
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            scorePopup = nil
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

            // Regular food.
            context.draw(Text("🍎").font(.system(size: min(cw, ch) * 0.9)),
                         at: CGPoint(x: cellRect(game.food).midX, y: cellRect(game.food).midY))

            // Bonus star food — blinks as it runs out.
            if let bf = game.bonusFood {
                let blink = game.bonusTicks <= 8 && game.bonusTicks % 2 == 0
                if !blink {
                    let r = cellRect(bf)
                    // Gold shimmer background.
                    context.fill(Path(ellipseIn: r.insetBy(dx: -2, dy: -2)),
                                 with: .color(Color(red: 1.0, green: 0.85, blue: 0.2).opacity(0.35)))
                    // Countdown ring (shrinks as the bonus expires).
                    let frac = CGFloat(game.bonusTicks) / CGFloat(SnakeGame.bonusTTL)
                    let ring = r.insetBy(dx: -3, dy: -3)
                    var arc = Path()
                    arc.addArc(center: CGPoint(x: ring.midX, y: ring.midY),
                               radius: ring.width / 2,
                               startAngle: .degrees(-90),
                               endAngle: .degrees(-90 + 360 * Double(frac)),
                               clockwise: false)
                    context.stroke(arc, with: .color(Color(red: 1.0, green: 0.9, blue: 0.3)), lineWidth: 2)
                    context.draw(Text("⭐").font(.system(size: min(cw, ch) * 0.85)), at: CGPoint(x: r.midX, y: r.midY))
                }
            }

            // Body, tail to head, fading toward the tail.
            for (i, segment) in game.body.enumerated().reversed() {
                let t = CGFloat(i) / CGFloat(max(game.body.count - 1, 1))
                let green = Color(red: 0.25 + 0.2 * t, green: 0.8 - 0.25 * t, blue: 0.3)
                context.fill(Path(roundedRect: cellRect(segment), cornerRadius: min(cw, ch) * 0.3),
                             with: .color(green))
            }

            // Head: brighter, with eyes anticipating the pending steer direction.
            if let head = game.body.first {
                let r = cellRect(head)
                context.fill(Path(roundedRect: r, cornerRadius: min(cw, ch) * 0.34),
                             with: .color(Color(red: 0.3, green: 0.95, blue: 0.4)))
                let eye = min(cw, ch) * 0.16
                let facing = game.pendingDirection ?? game.direction
                let along: (CGFloat, CGFloat) = (CGFloat(facing.dx), CGFloat(facing.dy))
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
        .overlay(alignment: .topLeading) { nextWallChip }
        .overlay(alignment: .bottomLeading) { speedChip }
        .overlay(alignment: .bottomTrailing) { bestLengthChip }
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

    /// Shows what wall pattern is coming up when the player is 2 bites away from leveling.
    @ViewBuilder
    var nextWallChip: some View {
        if let game, !game.isOver {
            let bitesLeft = SnakeGame.bitesPerLevel - (game.foodEaten % SnakeGame.bitesPerLevel)
            if bitesLeft <= 2 {
                let nextPattern = game.level % 6
                let label: String = switch nextPattern {
                case 0: "open"
                case 1: "bar"
                case 2: "pillars"
                case 3: "cross"
                case 4: "corners"
                default: "diagonal"
                }
                Text("Next: \(label)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(6)
            }
        }
    }

    /// Best length indicator in the bottom-right corner.
    @ViewBuilder
    var bestLengthChip: some View {
        if let game, !game.isOver, game.bestLength > 3 {
            let currentLen = game.body.count + game.growth
            let isAtBest = currentLen >= game.bestLength
            HStack(spacing: 3) {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(isAtBest ? .yellow : .white.opacity(0.6))
                Text("\(game.bestLength)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isAtBest ? .yellow : .white.opacity(0.8))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.55), in: Capsule())
            .overlay(Capsule().strokeBorder(isAtBest ? .yellow.opacity(0.5) : .white.opacity(0.2), lineWidth: 1))
            .padding(6)
        }
    }

    /// Speed indicator in the bottom-left corner.
    @ViewBuilder
    var speedChip: some View {
        if let game, !game.isOver, game.started {
            let level = game.level
            let bars = min(level, 6)
            HStack(spacing: 2) {
                ForEach(0..<6, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(i < bars ? Color.green.opacity(0.9) : Color.white.opacity(0.15))
                        .frame(width: 3, height: 4 + CGFloat(i) * 2)
                }
            }
            .padding(6)
        }
    }

    @ViewBuilder
    var distanceChip: some View {
        if let game, game.totalDistance > 0 {
            HStack(spacing: 6) {
                Text("🛣️ \(game.totalDistance) cells")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
                if game.bonusFoodEaten > 0 {
                    Text("⭐ \(game.bonusFoodEaten) bonus")
                        .font(.caption2)
                        .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.2).opacity(0.9))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(.black.opacity(0.35), in: Capsule())
        }
    }

    /// Shows the buffered direction queue as small arrow chips above the controls.
    @ViewBuilder
    var queueChip: some View {
        if let game, !game.isOver, !game.directionQueue.isEmpty {
            HStack(spacing: 3) {
                Text("Queued:")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                ForEach(Array(game.directionQueue.enumerated()), id: \.offset) { _, dir in
                    let arrow: String = switch dir {
                    case .up: "↑"
                    case .down: "↓"
                    case .left: "←"
                    case .right: "→"
                    }
                    Text(arrow)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .transition(.opacity)
        }
    }

    var controls: some View {
        VStack(spacing: 4) {
            queueChip
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
