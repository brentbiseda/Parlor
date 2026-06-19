import SwiftUI

/// Hopper: swipe (or use the arrows) to hop; traffic runs on the clock.
struct HopperView: View {
    @ObservedObject var session: GameSession
    @State private var lastLives = 3
    @State private var lastPads = 0
    @State private var paused = false
    @State private var scorePopup: String? = nil
    @State private var timerBarPulse = false
    // Zone label chip (#13)
    @State private var zoneLabelText = ""
    @State private var zoneLabelVisible = false

    var game: HopperGame? { session.game?.engine as? HopperGame }

    var body: some View {
        VStack(spacing: 8) {
            if let game {
                // Life hearts row (#15)
                lifeHeartsRow(game: game)
                    .padding(.horizontal, 12)
                statsStrip(game: game)
                    .padding(.horizontal, 12)
                timerBar(game: game)
                    .padding(.horizontal, 12)
            }
            ZStack {
                board
                    .padding(.horizontal, 8)
                if let popup = scorePopup {
                    Text(popup)
                        .font(.title.weight(.black))
                        .foregroundStyle(.yellow)
                        .shadow(color: .black, radius: 3)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                // Zone label chip (#13)
                if zoneLabelVisible {
                    VStack {
                        Spacer()
                        Text(zoneLabelText)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.7), in: Capsule())
                            .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1))
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .padding(.bottom, 8)
                    }
                }
            }
            .animation(.easeOut(duration: 0.4), value: scorePopup)
            .animation(.spring(response: 0.35), value: zoneLabelVisible)
            controls
                .padding(.bottom, 6)
        }
        .padding(.top, 6)
        .task(id: session.sessionID) { await clock() }
        .onChange(of: game?.frogY) { _, _ in
            guard let game else { return }
            let label = game.zoneLabel
            if label != zoneLabelText {
                zoneLabelText = label
                withAnimation(.spring(response: 0.35)) { zoneLabelVisible = true }
                Task { @MainActor in
                    do {
                        try await Task.sleep(nanoseconds: 1_800_000_000)
                        withAnimation(.easeOut(duration: 0.4)) { zoneLabelVisible = false }
                    } catch { return }
                }
            }
        }
    }

    /// Life hearts display (#15): filled hearts for lives, empty for lost lives.
    @ViewBuilder
    func lifeHeartsRow(game: HopperGame) -> some View {
        if !game.isOver {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Text(i < game.lives ? "❤️" : "🤍")
                        .font(.system(size: 18))
                        .opacity(i < game.lives ? 1.0 : 0.5)
                        .animation(.spring(response: 0.3), value: game.lives)
                }
                Spacer()
            }
        }
    }

    /// Returns how many road-obstacle cells are within `window` cells of `frogX` on `row`.
    func laneDanger(game: HopperGame, row: Int, window: Int = 2) -> Int {
        guard let lane = game.lane(atRow: row) else { return 0 }
        return lane.cells.filter { abs($0 - game.frogX) <= window || abs($0 - game.frogX - HopperGame.width) <= window || abs($0 - game.frogX + HopperGame.width) <= window }.count
    }

    /// Danger in the row directly ahead of the frog (in the direction of progress).
    var nextRowDanger: Int {
        guard let game else { return 0 }
        let nextRow = game.frogY - 1   // rows count down toward row 0 (goal)
        guard (7...11).contains(nextRow) else { return 0 }
        return laneDanger(game: game, row: nextRow)
    }

    func statsStrip(game: HopperGame) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                // Lives as frog hearts
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in
                        Text(i < game.lives ? "🐸" : "💀")
                            .font(.system(size: 14))
                            .opacity(i < game.lives ? 1.0 : 0.3)
                    }
                }
                // Road danger chip: shown when about to cross into or through a traffic lane
                let danger = nextRowDanger
                if danger > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                        Text("CAR!")
                            .font(.caption2.weight(.black))
                    }
                    .foregroundStyle(.red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.red.opacity(0.2), in: Capsule())
                    .overlay(Capsule().strokeBorder(.red.opacity(0.5), lineWidth: 1))
                }
                // River zone indicator: show when frog is on a moving platform
                if (1...5).contains(game.frogY) {
                    let onLog = game.isSolid(row: game.frogY, x: game.frogX)
                    HStack(spacing: 3) {
                        Text(onLog ? "🪵" : "💧")
                            .font(.system(size: 10))
                        Text(onLog ? "RIDING" : "DANGER")
                            .font(.caption2.weight(.black))
                    }
                    .foregroundStyle(onLog ? .green : .red)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(onLog ? Color.green.opacity(0.15) : Color.red.opacity(0.2), in: Capsule())
                }
                Spacer()
                // Level and crossings
                HStack(spacing: 6) {
                    Text("Lv\(game.level)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.7))
                    if game.perfectCrossings > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.yellow)
                            Text("×\(game.perfectCrossings)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.yellow)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.yellow.opacity(0.12), in: Capsule())
                    }
                }
                Spacer()
                // Score
                Text("\(game.score)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            // Lily pad progress: 5 pads shown as icons
            HStack(spacing: 8) {
                Text("Pads:")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                ForEach(HopperGame.padXs, id: \.self) { padX in
                    let filled = game.homePads.contains(padX)
                    Text(filled ? "🐸" : "○")
                        .font(.system(size: 11))
                        .foregroundStyle(filled ? .green : .white.opacity(0.3))
                }
                let remaining = HopperGame.padXs.count - game.homePads.count
                if remaining > 0 {
                    Text("\(remaining) left")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
    }

    func timerBar(game: HopperGame) -> some View {
        let budget = HopperGame.timeBonusBudget
        let remaining = max(0, budget - game.crossingTicks)
        let fraction = Double(remaining) / Double(budget)
        // Smooth hue blend: green(0.33) → yellow(0.17) → red(0.0) based on fraction (#14)
        let hue = fraction * 0.33
        let barColor = Color(hue: hue, saturation: 0.9, brightness: 0.95)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("TIME BONUS")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text("+\(max(0, remaining * 50 / budget))")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(barColor)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(width: geo.size.width * CGFloat(fraction))
                        .animation(.linear(duration: 0.24), value: fraction)
                        .scaleEffect(x: 1, y: fraction < 0.2 && timerBarPulse ? 1.5 : 1.0, anchor: .center)
                        .animation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true), value: timerBarPulse)
                }
            }
            .frame(height: 6)
            .onChange(of: fraction < 0.2) { _, isUrgent in
                timerBarPulse = isUrgent
            }
        }
    }

    private func clock() async {
        while true {
            do {
                try await Task.sleep(nanoseconds: 240_000_000)
            } catch {
                break
            }
            guard !paused, let before = game, !before.isOver else { continue }
            session.submit(.hopper(.tick))
            guard let after = game else { continue }
            if after.lives < lastLives {
                SoundFX.shared.play(after.isOver ? .lose : .lifeLost)
            } else if after.homePads.count != lastPads {
                SoundFX.shared.play(after.homePads.isEmpty ? .levelUp : .target)
            }
            lastLives = after.lives
            lastPads = after.homePads.count
        }
    }

    private func hop(_ direction: GridDirection) {
        guard !paused, let before = game, !before.isOver else { return }
        let prevScore = before.score
        session.submit(.hopper(.hop(direction)))
        guard let after = game else { return }
        if after.lives < lastLives {
            SoundFX.shared.play(after.isOver ? .lose : .lifeLost)
        } else if after.homePads.count > lastPads {
            SoundFX.shared.play(.target)
            let gained = after.score - prevScore
            if gained > 50 {
                scorePopup = "+\(gained)"
                Task {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    scorePopup = nil
                }
            }
        } else {
            SoundFX.shared.play(.click)
        }
        lastLives = after.lives
        lastPads = after.homePads.count
    }

    var board: some View {
        Canvas { context, size in
            guard let game else { return }
            let cw = size.width / CGFloat(HopperGame.width)
            let ch = size.height / CGFloat(HopperGame.height)

            func rowRect(_ row: Int) -> CGRect {
                CGRect(x: 0, y: CGFloat(row) * ch, width: size.width, height: ch)
            }
            func cellRect(_ x: Int, _ row: Int) -> CGRect {
                CGRect(x: CGFloat(x) * cw + 1, y: CGFloat(row) * ch + 2,
                       width: cw - 2, height: ch - 4)
            }

            // Backgrounds: pads, river, median, road, start.
            context.fill(Path(rowRect(0)), with: .color(Color(red: 0.1, green: 0.35, blue: 0.2)))
            for row in 1...5 {
                context.fill(Path(rowRect(row)), with: .color(Color(red: 0.1, green: 0.25, blue: 0.5)))
            }
            context.fill(Path(rowRect(6)), with: .color(Color(red: 0.25, green: 0.45, blue: 0.2)))
            for row in 7...11 {
                context.fill(Path(rowRect(row)), with: .color(Color(white: 0.18)))
            }
            context.fill(Path(rowRect(12)), with: .color(Color(red: 0.25, green: 0.45, blue: 0.2)))

            // Lane dashes on the road.
            for row in 8...11 {
                for x in stride(from: 0, to: HopperGame.width, by: 2) {
                    let dash = CGRect(x: CGFloat(x) * cw + cw * 0.2, y: CGFloat(row) * ch - 1,
                                      width: cw * 0.5, height: 2)
                    context.fill(Path(dash), with: .color(.white.opacity(0.25)))
                }
            }

            // Lily pads.
            for padX in HopperGame.padXs {
                let rect = cellRect(padX, 0).insetBy(dx: -1, dy: 0)
                context.fill(Path(ellipseIn: rect),
                             with: .color(game.homePads.contains(padX)
                                          ? Color(red: 0.4, green: 0.8, blue: 0.4)
                                          : Color(red: 0.15, green: 0.5, blue: 0.3)))
                if game.homePads.contains(padX) {
                    context.draw(Text("🐸").font(.system(size: ch * 0.6)), in: rect)
                }
            }

            // River traffic: logs with grain ends, turtles with shells.
            for row in 1...5 {
                guard let lane = game.lane(atRow: row) else { continue }
                let isTurtles = row == 2 || row == 4
                for x in lane.cells {
                    let rect = cellRect(x, row)
                    if isTurtles {
                        let shell = rect.insetBy(dx: 1, dy: 1)
                        context.fill(Path(ellipseIn: shell),
                                     with: .color(Color(red: 0.2, green: 0.6, blue: 0.45)))
                        context.stroke(Path(ellipseIn: shell.insetBy(dx: shell.width * 0.22,
                                                                     dy: shell.height * 0.22)),
                                       with: .color(.black.opacity(0.25)), lineWidth: 1.5)
                    } else {
                        context.fill(Path(roundedRect: rect, cornerRadius: 4),
                                     with: .color(Color(red: 0.55, green: 0.38, blue: 0.2)))
                        context.fill(Path(roundedRect: CGRect(x: rect.minX + 2, y: rect.minY + rect.height * 0.3,
                                                              width: rect.width - 4, height: 1.5),
                                          cornerRadius: 1),
                                     with: .color(.black.opacity(0.2)))
                        context.fill(Path(roundedRect: CGRect(x: rect.minX + 2, y: rect.minY + rect.height * 0.62,
                                                              width: rect.width - 4, height: 1.5),
                                          cornerRadius: 1),
                                     with: .color(.black.opacity(0.2)))
                    }
                }
            }
            // Road traffic: cars with windshields facing their direction.
            let carColors: [Color] = [.red, .yellow, .cyan, .orange, .purple]
            for row in 7...11 {
                guard let lane = game.lane(atRow: row) else { continue }
                for x in lane.cells {
                    let rect = cellRect(x, row)
                    context.fill(Path(roundedRect: rect, cornerRadius: 3),
                                 with: .color(carColors[(row - 7) % carColors.count]))
                    let windshieldX = lane.direction > 0
                        ? rect.maxX - rect.width * 0.32
                        : rect.minX + rect.width * 0.1
                    context.fill(Path(roundedRect: CGRect(x: windshieldX, y: rect.minY + 2,
                                                          width: rect.width * 0.22,
                                                          height: rect.height - 4),
                                      cornerRadius: 2),
                                 with: .color(.white.opacity(0.45)))
                }
            }

            // The frog — flashes white during respawn invincibility frames.
            let frogRect = cellRect(game.frogX, game.frogY)
            let isInvincible = game.invincibleTicks > 0
            let frogOpacity = isInvincible && game.invincibleTicks % 2 == 0 ? 0.4 : 1.0
            if isInvincible {
                // White halo during invincibility.
                context.fill(Path(ellipseIn: frogRect.insetBy(dx: -2, dy: -2)),
                             with: .color(.white.opacity(0.55)))
            }
            context.opacity = frogOpacity
            context.draw(Text("🐸").font(.system(size: min(cw, ch) * 0.8)), in: frogRect)
            context.opacity = 1.0
        }
        .aspectRatio(CGFloat(HopperGame.width) / CGFloat(HopperGame.height), contentMode: .fit)
        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
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
                    hop(direction)
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
        Button { hop(direction) } label: {
            Image(systemName: symbol)
                .font(.title3.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}
