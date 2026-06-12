import SwiftUI
import SpriteKit

/// Centipede: drag to glide the blaster (it autofires), blast the centipede
/// before it reaches the bottom. Hit segments leave mushrooms; clearing a
/// wave brings a longer, faster one.
struct CentipedeView: View {
    @ObservedObject var session: GameSession

    final class SceneHolder: ObservableObject {
        let scene = CentipedeScene(size: CGSize(width: 390, height: 700))
        init() { scene.scaleMode = .aspectFit }
    }

    @StateObject private var holder = SceneHolder()

    var body: some View {
        VStack(spacing: 6) {
            SpriteView(scene: holder.scene, options: [.allowsTransparency])
                .aspectRatio(390.0 / 700.0, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.15), lineWidth: 1))
                .padding(.horizontal, 10)

            Label("Drag to move — the blaster fires itself", systemImage: "hand.draw.fill")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
                .padding(.bottom, 4)
        }
        .onAppear {
            let scene = holder.scene
            scene.onEvent = { [weak session] event in
                MainActor.assumeIsolated { session?.submit(.arcade(event)) }
            }
            scene.shouldContinue = { [weak session] in
                MainActor.assumeIsolated {
                    (session?.game?.engine as? CentipedeGame)?.isOver == false
                }
            }
        }
    }
}

final class CentipedeScene: SKScene {
    var onEvent: ((ArcadeEvent) -> Void)?
    var shouldContinue: (() -> Bool)?

    private let cols = 13
    private let rows = 22
    private var cell: CGFloat { size.width / CGFloat(cols) }

    private var mushrooms: [Int: Int] = [:]          // grid index → hits left
    private var mushroomNodes: [Int: SKShapeNode] = [:]
    private var segments: [(col: Int, row: Int)] = []
    private var segmentNodes: [SKShapeNode] = []
    private var segmentDirection = 1
    private var player: SKShapeNode!
    private var bullets: [SKShapeNode] = []
    private var wave = 1
    private var moveAccumulator: TimeInterval = 0
    private var fireAccumulator: TimeInterval = 0
    private var lastUpdate: TimeInterval = 0
    private var respawning = false
    private var built = false
    private var spider: SKLabelNode?
    private var spiderTimer: TimeInterval = 0
    private var spiderPhase: CGFloat = 0

    private var stepInterval: TimeInterval { max(0.32 - Double(wave - 1) * 0.035, 0.14) }

    override func didMove(to view: SKView) {
        guard !built else { return }
        built = true
        backgroundColor = SKColor(red: 0.03, green: 0.06, blue: 0.04, alpha: 1)

        player = SKShapeNode(path: blasterPath())
        player.fillColor = SKColor(red: 0.4, green: 0.9, blue: 0.5, alpha: 1)
        player.strokeColor = SKColor(white: 1, alpha: 0.7)
        player.position = CGPoint(x: size.width / 2, y: 50)
        addChild(player)

        seedMushrooms()
        spawnCentipede()
    }

    private func blasterPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 14))
        path.addLine(to: CGPoint(x: 11, y: -8))
        path.addLine(to: CGPoint(x: -11, y: -8))
        path.closeSubpath()
        return path
    }

    private func gridPoint(col: Int, row: Int) -> CGPoint {
        CGPoint(x: (CGFloat(col) + 0.5) * cell, y: size.height - (CGFloat(row) + 0.5) * cell)
    }

    private func seedMushrooms() {
        for _ in 0..<26 {
            let col = Int.random(in: 0..<cols)
            let row = Int.random(in: 2..<(rows - 5))
            addMushroom(col: col, row: row)
        }
    }

    private func addMushroom(col: Int, row: Int) {
        let index = row * cols + col
        guard mushrooms[index] == nil else { return }
        mushrooms[index] = 2
        let node = SKShapeNode(circleOfRadius: cell * 0.32)
        node.position = gridPoint(col: col, row: row)
        node.fillColor = SKColor(red: 0.85, green: 0.45, blue: 0.55, alpha: 1)
        node.strokeColor = SKColor(white: 1, alpha: 0.5)
        addChild(node)
        mushroomNodes[index] = node
    }

    private func spawnCentipede() {
        segments.removeAll()
        segmentNodes.forEach { $0.removeFromParent() }
        segmentNodes.removeAll()
        let length = min(8 + wave, 14)
        for i in 0..<length {
            segments.append((col: -i, row: 0))
            let node = SKShapeNode(circleOfRadius: cell * 0.38)
            node.fillColor = i == 0
                ? SKColor(red: 0.95, green: 0.75, blue: 0.2, alpha: 1)
                : SKColor(red: 0.45, green: 0.8, blue: 0.3, alpha: 1)
            node.strokeColor = SKColor(white: 0, alpha: 0.4)
            node.position = gridPoint(col: -i, row: 0)
            addChild(node)
            segmentNodes.append(node)
        }
        segmentDirection = 1
    }

    // MARK: - Controls

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { steer(touches) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { steer(touches) }

    private func steer(_ touches: Set<UITouch>) {
        guard let touch = touches.first, !respawning else { return }
        let location = touch.location(in: self)
        player.position.x = min(max(location.x, 16), size.width - 16)
        player.position.y = min(max(location.y, 30), size.height * 0.3)
    }

    // MARK: - Frame loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 0 : min(currentTime - lastUpdate, 0.05)
        lastUpdate = currentTime
        guard shouldContinue?() != false, !respawning else { return }

        fireAccumulator += dt
        if fireAccumulator >= 0.32 {
            fireAccumulator = 0
            fire()
        }

        moveBullets(dt)

        moveAccumulator += dt
        if moveAccumulator >= stepInterval {
            moveAccumulator = 0
            stepCentipede()
        }

        updateSpider(dt)
    }

    // MARK: - Spider

    /// A bonus spider zigzags through the player's zone every so often:
    /// 300 points if you hit it, a life if it hits you.
    private func updateSpider(_ dt: TimeInterval) {
        if let spider {
            spiderPhase += CGFloat(dt) * 6
            spider.position.x += CGFloat(dt) * 150 * (spider.xScale > 0 ? 1 : -1)
            spider.position.y = spider.userData?["baseY"] as? CGFloat ?? 120
            spider.position.y += sin(spiderPhase) * 55
            if spider.position.x < -30 || spider.position.x > size.width + 30 {
                spider.removeFromParent()
                self.spider = nil
            } else if !respawning,
                      abs(spider.position.x - player.position.x) < 22,
                      abs(spider.position.y - player.position.y) < 22 {
                spider.removeFromParent()
                self.spider = nil
                playerCaught()
            }
        } else {
            spiderTimer += dt
            if spiderTimer > 8 {
                spiderTimer = 0
                spawnSpider()
            }
        }
    }

    private func spawnSpider() {
        let fromLeft = Bool.random()
        let node = SKLabelNode(text: "🕷")
        node.fontSize = 26
        node.verticalAlignmentMode = .center
        let baseY = CGFloat.random(in: 90...190)
        node.position = CGPoint(x: fromLeft ? -20 : size.width + 20, y: baseY)
        node.xScale = fromLeft ? 1 : -1
        node.userData = ["baseY": baseY]
        addChild(node)
        spider = node
    }

    private func fire() {
        let bullet = SKShapeNode(rectOf: CGSize(width: 3, height: 12), cornerRadius: 1.5)
        bullet.fillColor = .white
        bullet.strokeColor = .clear
        bullet.position = CGPoint(x: player.position.x, y: player.position.y + 16)
        addChild(bullet)
        bullets.append(bullet)
    }

    private func moveBullets(_ dt: TimeInterval) {
        var remaining: [SKShapeNode] = []
        for bullet in bullets {
            bullet.position.y += CGFloat(dt) * 620
            if bullet.position.y > size.height {
                bullet.removeFromParent()
                continue
            }
            if let hit = bulletHit(bullet) {
                bullet.removeFromParent()
                handleHit(hit)
                continue
            }
            remaining.append(bullet)
        }
        bullets = remaining
    }

    private enum Hit {
        case mushroom(Int)
        case segment(Int)
        case spider
    }

    private func bulletHit(_ bullet: SKShapeNode) -> Hit? {
        if let spider,
           abs(spider.position.x - bullet.position.x) < 18,
           abs(spider.position.y - bullet.position.y) < 18 {
            return .spider
        }
        for (i, segment) in segments.enumerated() where segment.col >= 0 {
            let p = gridPoint(col: segment.col, row: segment.row)
            if abs(p.x - bullet.position.x) < cell * 0.45,
               abs(p.y - bullet.position.y) < cell * 0.45 {
                return .segment(i)
            }
        }
        for (index, _) in mushrooms {
            let p = gridPoint(col: index % cols, row: index / cols)
            if abs(p.x - bullet.position.x) < cell * 0.35,
               abs(p.y - bullet.position.y) < cell * 0.4 {
                return .mushroom(index)
            }
        }
        return nil
    }

    private func handleHit(_ hit: Hit) {
        switch hit {
        case .spider:
            guard let spider else { return }
            SoundFX.shared.play(.jackpot)
            onEvent?(.score(300))
            let label = SKLabelNode(text: "+300")
            label.fontName = "AvenirNext-Bold"
            label.fontSize = 16
            label.fontColor = .yellow
            label.position = spider.position
            addChild(label)
            label.run(.sequence([
                .group([.moveBy(x: 0, y: 24, duration: 0.5), .fadeOut(withDuration: 0.5)]),
                .removeFromParent(),
            ]))
            spider.removeFromParent()
            self.spider = nil
        case .mushroom(let index):
            guard var hits = mushrooms[index] else { return }
            hits -= 1
            SoundFX.shared.play(.click)
            if hits <= 0 {
                mushroomNodes[index]?.removeFromParent()
                mushroomNodes[index] = nil
                mushrooms[index] = nil
                onEvent?(.score(5))
            } else {
                mushrooms[index] = hits
                mushroomNodes[index]?.alpha = 0.55
            }
        case .segment(let i):
            SoundFX.shared.play(.brick)
            let segment = segments[i]
            onEvent?(.score(i == 0 ? 100 : 10))
            addMushroom(col: max(segment.col, 0), row: segment.row)
            segments.remove(at: i)
            segmentNodes[i].removeFromParent()
            segmentNodes.remove(at: i)
            if segments.isEmpty {
                wave += 1
                onEvent?(.levelUp)
                SoundFX.shared.play(.levelUp)
                run(.sequence([.wait(forDuration: 1.0), .run { [weak self] in self?.spawnCentipede() }]))
            }
        }
    }

    private func stepCentipede() {
        guard !segments.isEmpty else { return }
        // The head leads; each body segment takes its predecessor's old cell.
        var head = segments[0]
        let nextCol = head.col + segmentDirection
        let blocked = nextCol < 0 && head.col >= 0 || nextCol >= cols
            || (nextCol >= 0 && mushrooms[head.row * cols + nextCol] != nil)
        if blocked {
            segmentDirection *= -1
            head.row += 1
            if head.row >= rows - 1 {
                playerCaught()
                return
            }
        } else {
            head.col = nextCol
        }
        var previous = segments[0]
        segments[0] = head
        for i in 1..<segments.count {
            let temp = segments[i]
            segments[i] = previous
            previous = temp
        }
        for (i, segment) in segments.enumerated() {
            segmentNodes[i].position = gridPoint(col: segment.col, row: segment.row)
        }
        // Reaching the player's zone costs a life.
        let headPoint = gridPoint(col: max(segments[0].col, 0), row: segments[0].row)
        if abs(headPoint.x - player.position.x) < cell * 0.6,
           abs(headPoint.y - player.position.y) < cell * 0.6 {
            playerCaught()
        }
    }

    private func playerCaught() {
        guard !respawning else { return }
        respawning = true
        SoundFX.shared.play(.lifeLost)
        onEvent?(.lifeLost)
        player.run(.sequence([.fadeAlpha(to: 0.2, duration: 0.15), .fadeAlpha(to: 1, duration: 0.15),
                              .fadeAlpha(to: 0.2, duration: 0.15), .fadeAlpha(to: 1, duration: 0.15)]))
        run(.sequence([.wait(forDuration: 0.8), .run { [weak self] in
            guard let self else { return }
            self.respawning = false
            self.player.position = CGPoint(x: self.size.width / 2, y: 50)
            self.spawnCentipede()
        }]))
    }
}
