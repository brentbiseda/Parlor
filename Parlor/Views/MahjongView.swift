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
            .fill(free ? Color(red: 0.98, green: 0.96, blue: 0.88) : Color(red: 0.8, green: 0.77, blue: 0.68))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isSelected ? Color.blue : isHinted ? Color.orange : Color.black.opacity(0.35),
                                  lineWidth: isSelected || isHinted ? 2.5 : 1)
            )
            .overlay(
                Text(tile.face.glyph)
                    .font(.system(size: tileH * 0.62))
                    .minimumScaleFactor(0.5)
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
            return
        }
        if let first = game.tiles.first(where: { $0.id == selected }), first.face.matches(tile.face) {
            session.submit(.matchTiles(selected, tile.id))
            selectedTileID = nil
        } else {
            selectedTileID = tile.id
        }
    }
}
