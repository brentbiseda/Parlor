import SwiftUI

/// Falling blocks: rendered with Canvas, gravity driven by a task whose
/// tick interval shrinks as the level climbs. Swipe sideways to move, tap
/// to rotate, swipe down to hard-drop — or use the buttons.
struct TetrisView: View {
    @ObservedObject var session: GameSession

    @State private var dragSteps: CGFloat = 0
    @State private var lastLines = 0
    @State private var lastPieces = 0

    var game: TetrisGame? { session.game?.engine as? TetrisGame }

    private let pieceColors: [Color] = [
        .clear,                                   // 0 = empty
        Color(red: 0.25, green: 0.85, blue: 0.9), // I
        Color(red: 0.95, green: 0.85, blue: 0.3), // O
        Color(red: 0.7, green: 0.4, blue: 0.9),   // T
        Color(red: 0.35, green: 0.85, blue: 0.4), // S
        Color(red: 0.92, green: 0.3, blue: 0.3),  // Z
        Color(red: 0.3, green: 0.5, blue: 0.95),  // J
        Color(red: 0.95, green: 0.6, blue: 0.2),  // L
    ]

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                board
                sidebar
            }
            .padding(.horizontal, 12)

            controls
                .padding(.bottom, 6)
        }
        .padding(.top, 8)
        .task(id: session.sessionID) { await gravityLoop() }
    }

    // MARK: - Gravity

    private func gravityLoop() async {
        while !Task.isCancelled {
            let level = game?.level ?? 1
            let interval = max(0.12, 0.85 * pow(0.82, Double(level - 1)))
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard let game, !game.isOver else { continue }
            submit(.tick)
        }
    }

    private func submit(_ move: TetrisMove) {
        guard let before = game, !before.isOver else { return }
        session.submit(.tetris(move))
        guard let after = game else { return }
        if after.isOver {
            SoundFX.shared.play(.lose)
        } else if after.lines > lastLines {
            SoundFX.shared.play(.lineClear)
        } else if after.piecesPlaced > lastPieces {
            SoundFX.shared.play(.lock)
        } else if move == .rotate {
            SoundFX.shared.play(.rotate)
        }
        lastLines = after.lines
        lastPieces = after.piecesPlaced
    }

    // MARK: - Board

    var board: some View {
        Canvas { context, size in
            guard let game else { return }
            let cell = min(size.width / CGFloat(TetrisGame.width),
                           size.height / CGFloat(TetrisGame.height))
            let originX = (size.width - cell * CGFloat(TetrisGame.width)) / 2

            func rect(_ x: Int, _ y: Int) -> CGRect {
                CGRect(x: originX + CGFloat(x) * cell, y: CGFloat(y) * cell,
                       width: cell - 1, height: cell - 1)
            }

            // Well background.
            context.fill(
                Path(CGRect(x: originX, y: 0,
                            width: cell * CGFloat(TetrisGame.width),
                            height: cell * CGFloat(TetrisGame.height))),
                with: .color(.black.opacity(0.45)))

            // Settled cells.
            for y in 0..<TetrisGame.height {
                for x in 0..<TetrisGame.width {
                    let value = game.cell(x, y)
                    guard value != 0 else { continue }
                    context.fill(Path(roundedRect: rect(x, y), cornerRadius: 2),
                                 with: .color(pieceColors[value]))
                }
            }

            // Ghost landing outline.
            if let ghost = game.ghostPiece(), ghost != game.current {
                for (x, y) in ghost.cells() where y >= 0 {
                    context.stroke(Path(roundedRect: rect(x, y), cornerRadius: 2),
                                   with: .color(.white.opacity(0.3)), lineWidth: 1.5)
                }
            }

            // Falling piece.
            if let piece = game.current {
                for (x, y) in piece.cells() where y >= 0 {
                    context.fill(Path(roundedRect: rect(x, y), cornerRadius: 2),
                                 with: .color(pieceColors[piece.kind.colorIndex]))
                }
            }
        }
        .aspectRatio(CGFloat(TetrisGame.width) / CGFloat(TetrisGame.height), contentMode: .fit)
        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.25), lineWidth: 1.5))
        .gesture(boardGesture)
    }

    /// Swipe horizontally to step the piece, swipe down to hard-drop,
    /// tap to rotate.
    var boardGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let stepWidth: CGFloat = 24
                let steps = (value.translation.width / stepWidth).rounded(.towardZero)
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

    // MARK: - Sidebar & controls

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.6))
                nextPreview
            }
            if let game {
                statBlock("SCORE", "\(game.score)")
                statBlock("LINES", "\(game.lines)")
                statBlock("LEVEL", "\(game.level)")
            }
            Spacer()
        }
        .frame(width: 86)
    }

    var nextPreview: some View {
        Canvas { context, size in
            guard let game else { return }
            let kind = game.nextKind
            let cell: CGFloat = size.width / 4.5
            let cells = TetrisGame.Piece(kind: kind, rotation: 0, x: 0, y: 0).cells()
            let minX = cells.map(\.x).min() ?? 0
            let minY = cells.map(\.y).min() ?? 0
            for (x, y) in cells {
                let rect = CGRect(x: CGFloat(x - minX) * cell + 4,
                                  y: CGFloat(y - minY) * cell + 4,
                                  width: cell - 1, height: cell - 1)
                context.fill(Path(roundedRect: rect, cornerRadius: 2),
                             with: .color(pieceColors[kind.colorIndex]))
            }
        }
        .frame(width: 86, height: 48)
        .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
    }

    func statBlock(_ label: String, _ value: String) -> some View {
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
        HStack(spacing: 10) {
            controlButton("arrowtriangle.left.fill") { submit(.left) }
            controlButton("arrow.clockwise") { submit(.rotate) }
            controlButton("arrowtriangle.down.fill") { submit(.softDrop) }
            controlButton("arrow.down.to.line") { submit(.hardDrop) }
            controlButton("arrowtriangle.right.fill") { submit(.right) }
        }
        .padding(.horizontal, 16)
    }

    func controlButton(_ symbol: String, action: @escaping () -> Void) -> some View {
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
