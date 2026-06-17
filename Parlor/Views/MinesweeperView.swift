import SwiftUI

/// Minesweeper: tap to reveal, long-press (or toggle dig/flag mode) to flag.
struct MinesweeperView: View {
    @ObservedObject var session: GameSession
    @State private var flagMode = false
    @State private var startedAt: Date? = nil
    @State private var finalTime: TimeInterval? = nil

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
        .onChange(of: game?.minesPlaced ?? false) { _, placed in
            if placed && startedAt == nil { startedAt = Date() }
        }
        .onChange(of: game?.isOver ?? false) { _, over in
            if over, let start = startedAt, finalTime == nil {
                finalTime = Date().timeIntervalSince(start)
            }
        }
    }

    func speedTierLabel(game: MinesweeperGame, elapsed: TimeInterval) -> (String, Color)? {
        if game.difficulty == .easy && elapsed < 30 { return ("⚡ Lightning", .yellow) }
        if game.difficulty == .easy && elapsed < 60 { return ("🏃 Quick", .green) }
        if game.difficulty == .medium && elapsed < 90 { return ("🏃 Quick", .green) }
        return nil
    }

    @ViewBuilder
    func speedTierBadge(game: MinesweeperGame, elapsed: TimeInterval) -> some View {
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
                HStack(spacing: 3) {
                    Text("💣")
                        .font(.caption)
                    Text("\(minesLeft)")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(minesLeft == 0 ? Color.yellow : .white)
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
        let isMine = game.mines.contains(index)
        let showMine = game.isOver && isMine

        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(revealed
                      ? Color(white: 0.88)
                      : ((x + y).isMultiple(of: 2)
                         ? Color(red: 0.3, green: 0.55, blue: 0.35)
                         : Color(red: 0.26, green: 0.49, blue: 0.31)))
                .overlay(alignment: .top) {
                    if !revealed {
                        // Raised-tile highlight for tactile depth.
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
                }
            if revealed {
                if isMine {
                    Text("💥").font(.system(size: size * 0.6))
                } else {
                    let count = game.adjacentMines(index)
                    if count > 0 {
                        Text("\(count)")
                            .font(.system(size: size * 0.55, weight: .bold, design: .rounded))
                            .foregroundStyle(numberColors[count])
                    }
                }
            } else if showMine {
                Text("💣").font(.system(size: size * 0.55))
            } else if flagged {
                Text("🚩").font(.system(size: size * 0.55))
            }
        }
        .frame(width: size, height: size)
        .onTapGesture { tap(x: x, y: y, game: game) }
        .onLongPressGesture(minimumDuration: 0.3) {
            guard !game.isOver, !revealed else { return }
            SoundFX.shared.play(.tileSelect)
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
