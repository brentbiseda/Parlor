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
    @State private var pressedDirection: GridDirection? = nil
    // Popup upward drift (#7)
    @State private var popupOffset: CGFloat = 0
    // Speed chip flash (#8)
    @State private var speedFlash = false

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
                        // Upward drift animation (#7)
                        .offset(y: popupOffset)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                        .onChange(of: scorePopup) { _, newVal in
                            if newVal != nil {
                                popupOffset = 0
                                withAnimation(.easeOut(duration: 1.2)) { popupOffset = -20 }
                            }
                        }
                }
                // Tap-to-start overlay shown before the first move
                if let game, !game.started, !game.isOver {
                    tapToStartOverlay
                }
            }
            .animation(.easeOut(duration: 0.5), value: scorePopup)

            livesRow
            distanceChip
            controls
                .padding(.bottom, 6)
        }
        .padding(.top, 6)
        .task(id: session.sessionID) { await clock() }
    }

    /// Pulsing "tap to start" overlay shown before the first move.
    @ViewBuilder
    var tapToStartOverlay: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.up.arrow.down.arrow.left.arrow.right")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text("Swipe or tap arrows\nto start")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.22), lineWidth: 1))
        .transition(.opacity)
        .allowsHitTesting(false)
    }

    /// Lives shown as red hearts, lost lives as dim outlines.
    @ViewBuilder
    var livesRow: some View {
        if let game, !game.isOver {
            HStack(spacing: 8) {
                // Lives pill
                HStack(spacing: 3) {
                    ForEach(0..<SnakeGame.startingLives, id: \.self) { i in
                        Image(systemName: i < game.lives ? "heart.fill" : "heart")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(i < game.lives
                                ? Color(red: 0.95, green: 0.25, blue: 0.3)
                                : .white.opacity(0.2))
                            .shadow(color: i < game.lives ? Color.red.opacity(0.5) : .clear, radius: 4)
                            .animation(.spring(response: 0.3), value: game.lives)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06))
                        RoundedRectangle(cornerRadius: 8).strokeBorder(Color.red.opacity(0.2), lineWidth: 0.75)
                    }
                )

                Spacer()

                // Level + bite progress pill
                VStack(spacing: 3) {
                    Text("LVL \(game.level)")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .monospacedDigit()
                    let bitesDone = game.foodEaten % SnakeGame.bitesPerLevel
                    HStack(spacing: 2) {
                        ForEach(0..<SnakeGame.bitesPerLevel, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(i < bitesDone ? Color.green : Color.white.opacity(0.18))
                                .frame(width: 6, height: 3)
                                .animation(.easeOut(duration: 0.2), value: bitesDone)
                        }
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))

                Spacer()

                // Score pill
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8)).foregroundStyle(.yellow.opacity(0.8))
                    Text("\(game.score)")
                        .font(.system(size: 14, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06))
                        RoundedRectangle(cornerRadius: 8).strokeBorder(Color.yellow.opacity(0.18), lineWidth: 0.75)
                    }
                )
            }
            .padding(.horizontal, 14)
        }
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
                    // Color transitions: green when fresh, orange midway, red when expiring
                    let ringColor: Color
                    if frac > 0.6 { ringColor = Color(red: 0.3, green: 0.9, blue: 0.3) }
                    else if frac > 0.3 { ringColor = Color(red: 1.0, green: 0.65, blue: 0.1) }
                    else { ringColor = Color(red: 0.95, green: 0.2, blue: 0.2) }
                    let ring = r.insetBy(dx: -3, dy: -3)
                    var arc = Path()
                    arc.addArc(center: CGPoint(x: ring.midX, y: ring.midY),
                               radius: ring.width / 2,
                               startAngle: .degrees(-90),
                               endAngle: .degrees(-90 + 360 * Double(frac)),
                               clockwise: false)
                    context.stroke(arc, with: .color(ringColor), lineWidth: 2.5)
                    context.draw(Text("⭐").font(.system(size: min(cw, ch) * 0.85)), at: CGPoint(x: r.midX, y: r.midY))
                }
            }

            // Body, tail to head. t=0 is tail (dimmer), t=1 is head (bright).
            // Opacity fades from 0.6 at tail to 1.0 at head for a gradient effect (#6).
            for (i, segment) in game.body.enumerated().reversed() {
                let t = CGFloat(i) / CGFloat(max(game.body.count - 1, 1))
                let segOpacity = 0.6 + 0.4 * t
                let green = Color(red: 0.25 + 0.2 * t, green: 0.8 - 0.25 * t, blue: 0.3)
                context.fill(Path(roundedRect: cellRect(segment), cornerRadius: min(cw, ch) * 0.3),
                             with: .color(green.opacity(segOpacity)))
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
    /// Pulses green when the snake reaches a new speed level (#8).
    @ViewBuilder
    var speedChip: some View {
        if let game, !game.isOver, game.started {
            let level = game.level
            let bars = min(level, 6)
            let patternNames = ["open", "bar", "pillars", "cross", "corners", "diagonal"]
            let currentPattern = patternNames[(level - 1) % 6]
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 2) {
                    ForEach(0..<6, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(i < bars
                                  ? (speedFlash ? Color.white : Color.green.opacity(0.9))
                                  : Color.white.opacity(0.15))
                            .frame(width: 3, height: 4 + CGFloat(i) * 2)
                            .animation(.easeInOut(duration: 0.2), value: speedFlash)
                    }
                }
                if level > 1 {
                    Text(currentPattern)
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(speedFlash ? .white : .white.opacity(0.55))
                        .animation(.easeOut(duration: 0.4), value: speedFlash)
                }
            }
            .padding(6)
            .onChange(of: game.level) { _, _ in
                speedFlash = true
                Task { @MainActor in
                    do {
                        try await Task.sleep(nanoseconds: 600_000_000)
                        speedFlash = false
                    } catch { return }
                }
            }
        }
    }

    @ViewBuilder
    var distanceChip: some View {
        if let game, game.totalDistance > 0 || game.started {
            HStack(spacing: 8) {
                // Current snake length
                HStack(spacing: 2) {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                    Text("\(game.currentLength)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .monospacedDigit()
                }
                if game.totalDistance > 0 {
                    Divider().frame(height: 10).overlay(.white.opacity(0.2))
                    // Distance traveled
                    Text("🛣️\(game.totalDistance)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                    // Score/cell efficiency
                    let spc = game.scorePerCell
                    if spc > 0 {
                        let spcStr = String(format: "%.1f", spc)
                        let effColor: Color = spc >= 3 ? .green : spc >= 1.5 ? .yellow : .white.opacity(0.5)
                        Text("✦\(spcStr)/cell")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(effColor)
                    }
                }
                if game.bonusFoodEaten > 0 {
                    Divider().frame(height: 10).overlay(.white.opacity(0.2))
                    Text("⭐×\(game.bonusFoodEaten)")
                        .font(.caption2)
                        .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.2).opacity(0.9))
                    if game.bonusFoodMissed > 0 {
                        Text("✗\(game.bonusFoodMissed)")
                            .font(.caption2)
                            .foregroundStyle(.red.opacity(0.7))
                    }
                }
                // Speed label when past level 3
                if game.level > 3 {
                    Divider().frame(height: 10).overlay(.white.opacity(0.2))
                    let speedColor: Color = game.level >= 7 ? .red : game.level >= 5 ? .orange : .yellow
                    Text(game.speedLabel)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(speedColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                ZStack {
                    Capsule().fill(Color.black.opacity(0.4))
                    Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
                }
            )
            .shadow(color: .black.opacity(0.3), radius: 4)
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
        let isPressed = pressedDirection == direction
        return Button {
            turn(direction)
            pressedDirection = direction
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { pressedDirection = nil }
        } label: {
            Image(systemName: symbol)
                .font(.title3.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(isPressed ? .white.opacity(0.35) : .white.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(isPressed ? .yellow : .white)
                .scaleEffect(isPressed ? 0.92 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
    }
}
