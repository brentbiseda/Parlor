import SwiftUI

/// Minesweeper: tap to reveal, long-press (or toggle dig/flag mode) to flag.
struct MinesweeperView: View {
    @ObservedObject var session: GameSession
    @State private var flagMode = false
    @State private var startedAt: Date? = nil
    @State private var finalTime: TimeInterval? = nil

    var game: MinesweeperGame? { session.game?.engine as? MinesweeperGame }

    private let numberColors: [Color] = [
        .clear, .blue, .green, .red, .purple, .orange, .cyan, .pink, .black,
    ]

    var body: some View {
        VStack(spacing: 14) {
            if let game {
                timerChip(game)
                grid(game)
                    .padding(.horizontal, 12)

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

    /// Stopwatch from the first dig until the board resolves.
    func timerChip(_ game: MinesweeperGame) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let elapsed = finalTime
                ?? startedAt.map { timeline.date.timeIntervalSince($0) }
                ?? 0
            Label(String(format: "%d:%02d", Int(elapsed) / 60, Int(elapsed) % 60),
                  systemImage: "stopwatch.fill")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.black.opacity(0.35), in: Capsule())
        }
    }

    func grid(_ game: MinesweeperGame) -> some View {
        GeometryReader { geo in
            let cols = MinesweeperGame.width
            let rows = MinesweeperGame.height
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
        .aspectRatio(CGFloat(MinesweeperGame.width) / CGFloat(MinesweeperGame.height),
                     contentMode: .fit)
    }

    @ViewBuilder
    func cellView(x: Int, y: Int, game: MinesweeperGame, size: CGFloat) -> some View {
        let index = MinesweeperGame.index(x, y)
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
        let index = MinesweeperGame.index(x, y)
        if game.revealed.contains(index) {
            // Chord: only submit when the number is satisfied and has work to do.
            let neighbors = MinesweeperGame.neighbors(index)
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
