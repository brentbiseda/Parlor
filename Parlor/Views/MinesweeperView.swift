import SwiftUI

/// Minesweeper: tap to reveal, long-press (or toggle dig/flag mode) to flag.
struct MinesweeperView: View {
    @ObservedObject var session: GameSession
    @State private var flagMode = false
    @State private var startedAt: Date? = nil
    @State private var finalTime: TimeInterval? = nil
    @State private var chordPulse = false
    // Flag plant bounce (#10)
    @State private var flaggedCell: (Int, Int)? = nil
    @State private var flagScale: CGFloat = 1.0
    // Win celebration banner (#11)
    @State private var wonBanner = false

    var game: MinesweeperGame? { session.game?.engine as? MinesweeperGame }

    // Tuned for readability on the light cell background.
    private let numberColors: [Color] = [
        .clear,
        Color(red: 0.10, green: 0.18, blue: 0.85),   // 1 — blue
        Color(red: 0.05, green: 0.58, blue: 0.18),   // 2 — green
        Color(red: 0.82, green: 0.10, blue: 0.10),   // 3 — red
        Color(red: 0.48, green: 0.05, blue: 0.65),   // 4 — purple
        Color(red: 0.72, green: 0.10, blue: 0.10),   // 5 — maroon
        Color(red: 0.05, green: 0.58, blue: 0.72),   // 6 — teal
        Color(red: 0.08, green: 0.08, blue: 0.08),   // 7 — near-black
        Color(red: 0.48, green: 0.48, blue: 0.48),   // 8 — gray
    ]

    var body: some View {
        VStack(spacing: 14) {
            if let game {
                timerChip(game)
                if game.minesPlaced && !game.isOver {
                    progressBar(game)
                }
                grid(game)
                    .padding(.horizontal, 12)

                if game.won, let elapsed = finalTime {
                    speedTierBadge(game: game, elapsed: elapsed)
                }

                Picker("Mode", selection: $flagMode) {
                    Label("Dig", systemImage: "hand.tap.fill").tag(false)
                    Label("Flag", systemImage: "flag.fill").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
                .colorScheme(.dark)

                Text("Long-press any square to flag it")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.top, 10)
        // Win celebration banner overlay (#11)
        .overlay(alignment: .top) {
            if wonBanner {
                Text("🎉 You Win!")
                    .font(.title2.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.green.opacity(0.9), in: Capsule())
                    .shadow(color: .green.opacity(0.5), radius: 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.5), value: wonBanner)
                    .padding(.top, 4)
            }
        }
        .onChange(of: game?.minesPlaced ?? false) { _, placed in
            if placed && startedAt == nil { startedAt = Date() }
        }
        .onChange(of: game?.isOver ?? false) { _, over in
            if over, let start = startedAt, finalTime == nil {
                finalTime = Date().timeIntervalSince(start)
            }
        }
        .onChange(of: game?.won ?? false) { _, won in
            if won {
                withAnimation(.spring(response: 0.5)) { wonBanner = true }
                Task { @MainActor in
                    do {
                        try await Task.sleep(nanoseconds: 3_000_000_000)
                        withAnimation(.easeOut(duration: 0.5)) { wonBanner = false }
                    } catch { return }
                }
            }
        }
    }

    func speedTierLabel(game: MinesweeperGame, elapsed: TimeInterval) -> (String, Color)? {
        switch game.difficulty {
        case .easy:
            if elapsed < 20 { return ("⚡ Lightning", .yellow) }
            if elapsed < 40 { return ("🏃 Quick", .green) }
        case .medium:
            if elapsed < 60 { return ("⚡ Lightning", .yellow) }
            if elapsed < 120 { return ("🏃 Quick", .green) }
        case .hard:
            if elapsed < 200 { return ("⚡ Lightning", .yellow) }
            if elapsed < 360 { return ("🏃 Quick", .green) }
        }
        return nil
    }

    @ViewBuilder
    func speedTierBadge(game: MinesweeperGame, elapsed: TimeInterval) -> some View {
        HStack(spacing: 8) {
            if let (label, color) = speedTierLabel(game: game, elapsed: elapsed) {
                Text(label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(color.opacity(0.15), in: Capsule())
                    .overlay(Capsule().strokeBorder(color.opacity(0.5), lineWidth: 1))
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(response: 0.35), value: elapsed)
            }
            // 3BV/s efficiency: board complexity relative to time taken.
            if game.threeBV > 0 && elapsed > 0 {
                let bvs = Double(game.threeBV) / elapsed
                let bvsStr = String(format: "%.2f", bvs)
                Text("3BV/s \(bvsStr)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.cyan)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.cyan.opacity(0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder(.cyan.opacity(0.4), lineWidth: 1))
            }
        }
    }

    /// Horizontal progress bar showing percentage of safe cells revealed.
    func progressBar(_ game: MinesweeperGame) -> some View {
        let pct = min(1.0, Double(game.revealed.count) / Double(max(1, game.difficulty.safeCells)))
        let remaining = game.difficulty.safeCells - game.revealed.count
        let barColor: Color = pct >= 0.9 ? .green : pct >= 0.6 ? .cyan : .white.opacity(0.7)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.1))
                    .frame(height: 6)
                Capsule()
                    .fill(barColor)
                    .frame(width: geo.size.width * CGFloat(pct), height: 6)
                    .animation(.easeInOut(duration: 0.3), value: pct)
            }
            .overlay(alignment: .trailing) {
                Text("\(remaining) left")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .offset(x: -4, y: -10)
            }
        }
        .frame(height: 6)
        .padding(.horizontal, 20)
    }

    /// Difficulty badge + stopwatch from the first dig until the board resolves.
    func timerChip(_ game: MinesweeperGame) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let elapsed = finalTime
                ?? startedAt.map { timeline.date.timeIntervalSince($0) }
                ?? 0
            HStack(spacing: 10) {
                // Difficulty badge.
                Text(game.difficulty.label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.7))
                Divider()
                    .frame(height: 14)
                    .overlay(.white.opacity(0.3))
                // Mine counter: remaining unflagged mines.
                let minesLeft = max(0, game.difficulty.mines - game.flagCount)
                let mineCountColor: Color = minesLeft == 0 ? .yellow : (minesLeft <= 3 ? .orange : .white)
                HStack(spacing: 3) {
                    Text("💣")
                        .font(.caption)
                    Text("\(minesLeft)")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(mineCountColor)
                        .animation(.easeInOut(duration: 0.3), value: mineCountColor == .orange)
                }
                Divider()
                    .frame(height: 14)
                    .overlay(.white.opacity(0.3))
                // Stopwatch.
                HStack(spacing: 3) {
                    Image(systemName: "stopwatch.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(String(format: "%d:%02d", Int(elapsed) / 60, Int(elapsed) % 60))
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.black.opacity(0.35), in: Capsule())
            .overlay(Capsule().strokeBorder(
                game.won ? Color.green.opacity(0.5) : (game.lost ? Color.red.opacity(0.5) : .clear),
                lineWidth: 1.5))
        }
    }

    func grid(_ game: MinesweeperGame) -> some View {
        GeometryReader { geo in
            let cols = game.difficulty.width
            let rows = game.difficulty.height
            let cell = min(geo.size.width / CGFloat(cols), geo.size.height / CGFloat(rows))
            let originX = (geo.size.width - cell * CGFloat(cols)) / 2

            VStack(spacing: 2) {
                ForEach(0..<rows, id: \.self) { y in
                    HStack(spacing: 2) {
                        ForEach(0..<cols, id: \.self) { x in
                            cellView(x: x, y: y, game: game, size: cell - 2)
                        }
                    }
                }
            }
            .offset(x: originX)
        }
        .aspectRatio(CGFloat(game.difficulty.width) / CGFloat(game.difficulty.height),
                     contentMode: .fit)
    }

    @ViewBuilder
    func cellView(x: Int, y: Int, game: MinesweeperGame, size: CGFloat) -> some View {
        let index = game.index(x, y)
        let revealed = game.revealed.contains(index)
        let flagged = game.flagged.contains(index)
        let questioned = game.questioned.contains(index)
        let isMine = game.mines.contains(index)
        let showMine = game.isOver && isMine
        // Chord-ready: revealed number with exactly matching flag count among hidden neighbors.
        let count = revealed && !isMine ? game.adjacentMines(index) : 0
        let isChordReady: Bool = revealed && count > 0 && !game.isOver && {
            let nbrs = game.neighbors(index)
            let flagCount = nbrs.filter { game.flagged.contains($0) }.count
            return flagCount == count && nbrs.contains { !game.flagged.contains($0) && !game.revealed.contains($0) }
        }()

        let isFlagAnimating = flaggedCell.map { $0.0 == x && $0.1 == y } ?? false
        ZStack {
            // Chord-ready cells get a subtle cyan tint (#12)
            RoundedRectangle(cornerRadius: 3)
                .fill(revealed
                      ? (isChordReady ? Color(red: 0.82, green: 0.96, blue: 0.98) : Color(white: 0.88))
                      : ((x + y).isMultiple(of: 2)
                         ? Color(red: 0.3, green: 0.55, blue: 0.35)
                         : Color(red: 0.26, green: 0.49, blue: 0.31)))
                .overlay(alignment: .top) {
                    if !revealed {
                        LinearGradient(colors: [.white.opacity(0.22), .clear],
                                       startPoint: .top, endPoint: .center)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .allowsHitTesting(false)
                    }
                }
                .overlay {
                    if showMine && !revealed {
                        RoundedRectangle(cornerRadius: 3).fill(Color.red.opacity(0.25))
                    }
                    if isChordReady {
                        // Pulsing cyan glow around chord-ready numbers.
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Color.cyan.opacity(chordPulse ? 0.9 : 0.4), lineWidth: chordPulse ? 2 : 1.5)
                            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: chordPulse)
                            .onAppear { chordPulse = true }
                    }
                }
            if revealed {
                if isMine {
                    Text("💥").font(.system(size: size * 0.6))
                } else if count > 0 {
                    Text("\(count)")
                        .font(.system(size: size * 0.55, weight: .bold, design: .rounded))
                        .foregroundStyle(numberColors[count])
                }
            } else if showMine {
                Text("💣").font(.system(size: size * 0.55))
            } else if flagged {
                // Flag with bounce scale animation when just planted (#10)
                Text("🚩").font(.system(size: size * 0.55))
                    .scaleEffect(isFlagAnimating ? flagScale : 1.0)
            } else if questioned {
                Text("?")
                    .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.orange.opacity(0.9))
            }
        }
        .frame(width: size, height: size)
        .onTapGesture { tap(x: x, y: y, game: game) }
        .onLongPressGesture(minimumDuration: 0.3) {
            guard !game.isOver, !revealed else { return }
            SoundFX.shared.play(.tileSelect)
            // Trigger flag bounce animation (#10)
            flaggedCell = (x, y)
            flagScale = 1.0
            withAnimation(.interpolatingSpring(stiffness: 400, damping: 8)) { flagScale = 1.4 }
            Task { @MainActor in
                do {
                    try await Task.sleep(nanoseconds: 200_000_000)
                    withAnimation(.spring(response: 0.2)) { flagScale = 1.0 }
                    try await Task.sleep(nanoseconds: 300_000_000)
                    flaggedCell = nil
                } catch { return }
            }
            session.submit(.minesweeper(.flag(x: x, y: y)))
        }
    }

    func tap(x: Int, y: Int, game: MinesweeperGame) {
        guard !game.isOver else { return }
        let index = game.index(x, y)
        if game.revealed.contains(index) {
            // Chord: only submit when the number is satisfied and has work to do.
            let neighbors = game.neighbors(index)
            let count = game.adjacentMines(index)
            let flags = neighbors.filter { game.flagged.contains($0) }.count
            let hidden = neighbors.contains { !game.flagged.contains($0) && !game.revealed.contains($0) }
            guard count > 0, flags == count, hidden else { return }
            session.submit(.minesweeper(.reveal(x: x, y: y)))
            SoundFX.shared.play(self.game?.lost == true ? .lose : .click)
            return
        }
        if flagMode {
            SoundFX.shared.play(.tileSelect)
            session.submit(.minesweeper(.flag(x: x, y: y)))
        } else {
            guard !game.flagged.contains(index) else { return }
            session.submit(.minesweeper(.reveal(x: x, y: y)))
            if let after = self.game, after.lost {
                SoundFX.shared.play(.lose)
            } else {
                SoundFX.shared.play(.click)
            }
        }
    }
}
