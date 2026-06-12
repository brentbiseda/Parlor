import SwiftUI

/// Mahjongg solitaire: tap two matching free tiles to clear them.
struct MahjongView: View {
    @ObservedObject var session: GameSession
    @State private var selectedTileID: Int? = nil
    @State private var hint: (Int, Int)? = nil

    var game: MahjongGame? { session.game?.engine as? MahjongGame }

    var body: some View {
        GeometryReader { geo in
            if let game {
                // Layout spans x −2…28 half-units (15 tiles wide), y 0…16.
                let unit = min(geo.size.width / 32, geo.size.height / 20)
                let tileW = unit * 2, tileH = unit * 2.4
                let originX = (geo.size.width - unit * 30) / 2 + unit * 2
                let originY = (geo.size.height - unit * 18) / 2

                ZStack {
                    ForEach(game.tiles.filter { !$0.removed }.sorted {
                        ($0.z, $0.y, $0.x) < ($1.z, $1.y, $1.x)
                    }) { tile in
                        tileView(tile, game: game, tileW: tileW, tileH: tileH)
                            .position(
                                x: originX + CGFloat(tile.x) * unit + tileW / 2 - CGFloat(tile.z) * unit * 0.18,
                                y: originY + CGFloat(tile.y) * unit * 1.2 + tileH / 2 - CGFloat(tile.z) * unit * 0.22
                            )
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let game {
                HStack {
                    Button("Hint") {
                        hint = game.availableMatches().randomElement()
                    }
                    .buttonStyle(.bordered).tint(.white)
                    if game.isStuck {
                        Button("Shuffle") {
                            session.submit(.shuffleRemaining)
                            selectedTileID = nil
                            hint = nil
                        }
                        .buttonStyle(.borderedProminent).tint(.orange)
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }

    func tileView(_ tile: MahjongGame.Tile, game: MahjongGame, tileW: CGFloat, tileH: CGFloat) -> some View {
        let free = game.isFree(tile)
        let isSelected = selectedTileID == tile.id
        let isHinted = hint.map { $0.0 == tile.id || $0.1 == tile.id } ?? false
        return RoundedRectangle(cornerRadius: 4)
            .fill(free ? Color(red: 0.99, green: 0.97, blue: 0.9) : Color(red: 0.78, green: 0.75, blue: 0.66))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isSelected ? Color.blue : isHinted ? Color.orange : Color.black.opacity(0.35),
                                  lineWidth: isSelected || isHinted ? 2.5 : 1)
            )
            .overlay(
                TileFaceView(face: tile.face, height: tileH)
                    .opacity(free ? 1 : 0.55)
            )
            // A visible side gives the stacks real thickness.
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(red: 0.6, green: 0.5, blue: 0.35))
                    .offset(x: tileW * 0.07, y: tileH * 0.06)
            )
            .frame(width: tileW, height: tileH)
            .shadow(color: .black.opacity(0.35), radius: 1.5, x: 2, y: 2)
            .onTapGesture { tap(tile, game: game) }
    }

    func tap(_ tile: MahjongGame.Tile, game: MahjongGame) {
        guard game.isFree(tile) else { return }
        hint = nil
        guard let selected = selectedTileID, selected != tile.id else {
            selectedTileID = selectedTileID == tile.id ? nil : tile.id
            if selectedTileID != nil { SoundFX.shared.play(.tileSelect) }
            return
        }
        if let first = game.tiles.first(where: { $0.id == selected }), first.face.matches(tile.face) {
            session.submit(.matchTiles(selected, tile.id))
            selectedTileID = nil
        } else {
            selectedTileID = tile.id
            SoundFX.shared.play(.tileSelect)
        }
    }
}

/// High-contrast tile faces: bold colored rank + suit mark instead of the
/// tiny monochrome Unicode mahjong glyphs.
struct TileFaceView: View {
    let face: MahjongGame.TileFace
    let height: CGFloat

    var body: some View {
        switch face {
        case .dots(let n):
            numberFace(n, mark: "●", color: Color(red: 0.1, green: 0.35, blue: 0.75))
        case .bamboo(let n):
            numberFace(n, mark: "▮", color: Color(red: 0.1, green: 0.55, blue: 0.25))
        case .characters(let n):
            numberFace(n, mark: "万", color: Color(red: 0.75, green: 0.12, blue: 0.15))
        case .wind(let n):
            Text(["E", "S", "W", "N"][n])
                .font(.system(size: height * 0.55, weight: .heavy, design: .serif))
                .foregroundStyle(Color(red: 0.15, green: 0.2, blue: 0.45))
                .minimumScaleFactor(0.5)
        case .dragon(let n):
            Text(["中", "發", "白"][n])
                .font(.system(size: height * 0.5, weight: .heavy))
                .foregroundStyle([Color(red: 0.75, green: 0.12, blue: 0.15),
                                  Color(red: 0.1, green: 0.55, blue: 0.25),
                                  Color(red: 0.45, green: 0.45, blue: 0.5)][n])
                .minimumScaleFactor(0.5)
        case .flower(let n):
            Text(["🌸", "🌷", "🌼", "🌺"][n])
                .font(.system(size: height * 0.48))
                .minimumScaleFactor(0.5)
        case .season(let n):
            Text(["🌱", "☀️", "🍂", "❄️"][n])
                .font(.system(size: height * 0.48))
                .minimumScaleFactor(0.5)
        }
    }

    private func numberFace(_ n: Int, mark: String, color: Color) -> some View {
        VStack(spacing: -height * 0.06) {
            Text("\(n)")
                .font(.system(size: height * 0.42, weight: .heavy, design: .rounded))
            Text(mark)
                .font(.system(size: height * 0.26, weight: .bold))
        }
        .foregroundStyle(color)
        .minimumScaleFactor(0.5)
    }
}
