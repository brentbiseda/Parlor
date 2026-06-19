import SwiftUI
import SpriteKit

/// Breakout with 10 new features: multi-ball, shield, fireball, extra-life,
/// score-doubler, explosive bricks, steel bricks, moving bricks, wall-bounce
/// tracking, and a brick-progress header bar.
struct BreakoutView: View {
    @ObservedObject var session: GameSession

    final class SceneHolder: ObservableObject {
        let scene: BreakoutScene
        init() {
            scene = BreakoutScene(size: CGSize(width: 390, height: 700))
            scene.scaleMode = .aspectFit
        }
    }

    @StateObject private var holder = SceneHolder()

    var game: BreakoutGame? { session.game?.engine as? BreakoutGame }

    var body: some View {
        VStack(spacing: 6) {
            if let game, !game.isOver {
                breakoutHeader(game)
            }
            SpriteView(scene: holder.scene, options: [.allowsTransparency])
                .aspectRatio(390.0 / 700.0, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.15), lineWidth: 1))
                .padding(.horizontal, 10)

            Label("Drag to move · tap to launch", systemImage: "hand.draw.fill")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
                .padding(.bottom, 4)
        }
        .onAppear {
            let scene = holder.scene
            scene.onEvent = { [weak session] event in
                MainActor.assumeIsolated { session?.submit(.breakout(event)) }
            }
            scene.shouldContinue = { [weak session] in
                MainActor.assumeIsolated {
                    (session?.game?.engine as? BreakoutGame)?.isOver == false
                }
            }
            scene.startIfNeeded()
        }
    }

    func breakoutHeader(_ game: BreakoutGame) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                // Level + speed chip
                HStack(spacing: 3) {
                    Text("Lv\(game.level)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.85))
                    let speed = game.level >= 7 ? "⚡⚡⚡" : game.level >= 5 ? "⚡⚡" : game.level >= 3 ? "⚡" : ""
                    if !speed.isEmpty { Text(speed).font(.system(size: 9)) }
                }
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(.white.opacity(0.12), in: Capsule())

                Text("\(game.score)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.85))

                if game.currentStreak >= 3 {
                    HStack(spacing: 2) {
                        Text("🔥").font(.system(size: 11))
                        Text("×\(game.currentStreak)")
                            .font(.caption2.weight(.bold)).foregroundStyle(.orange)
                    }
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.orange.opacity(0.15), in: Capsule())
                }

                Spacer()

                if game.perfectLevels > 0 {
                    Text("⭐×\(game.perfectLevels)")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.yellow)
                }

                // Lives
                HStack(spacing: 3) {
                    ForEach(0..<BreakoutGame.livesPerGame, id: \.self) { i in
                        Circle()
                            .fill(i < game.livesLeft
                                  ? Color(red: 0.35, green: 0.75, blue: 1.0)
                                  : Color.white.opacity(0.15))
                            .frame(width: 8, height: 8)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)

            // Brick progress bar
            if game.totalBricks > 0 {
                let fraction = max(0, Double(game.totalBricks - game.bricksRemaining) / Double(game.totalBricks))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.1))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(LinearGradient(
                                colors: [Color(red: 0.35, green: 0.75, blue: 1.0),
                                         Color(red: 0.6, green: 0.4, blue: 0.9)],
                                startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * fraction)
                            .animation(.easeOut(duration: 0.2), value: fraction)
                    }
                }
                .frame(height: 4)
                .padding(.horizontal, 14)
            }
        }
    }
}

// MARK: - SpriteKit Scene

final class BreakoutScene: SKScene, SKPhysicsContactDelegate {

    enum Category {
        static let ball:   UInt32 = 1 << 0
        static let paddle: UInt32 = 1 << 1
        static let brick:  UInt32 = 1 << 2
        static let wall:   UInt32 = 1 << 3
        static let floor:  UInt32 = 1 << 4
        static let shield: UInt32 = 1 << 5
    }

    // Scene-to-engine callbacks
    var onEvent: ((BreakoutEvent) -> Void)?
    var shouldContinue: (() -> Bool)?

    // Nodes
    private var paddle: SKShapeNode!
    private var balls: [SKShapeNode] = []
    private var ballGlued = true
    private var shieldNode: SKShapeNode?
    private var powerUpNodes: [(node: SKShapeNode, kind: BreakoutPowerUp)] = []

    // State
    private var level = 1
    private var built = false
    private var lastTime: TimeInterval = 0
    private var totalBricksThisLevel = 0

    // Power-up timers (scene-local; multiplied score sent to engine)
    private var wideUntil: TimeInterval = 0
    private var fireballUntil: TimeInterval = 0
    private var scoreDoubleUntil: TimeInterval = 0

    // Derived
    private let normalPaddleWidth: CGFloat = 92
    private let paddleHeight: CGFloat = 14
    private var currentPaddleWidth: CGFloat { wideUntil > lastTime ? 140 : normalPaddleWidth }
    private var isFireball: Bool { fireballUntil > lastTime }
    private var scoreMultiplier: Int { scoreDoubleUntil > lastTime ? 2 : 1 }
    private var ballSpeed: CGFloat { 430 + CGFloat(level - 1) * 45 }

    private var sparkTexture: SKTexture?

    private let rowColors: [SKColor] = [
        SKColor(red: 0.92, green: 0.3,  blue: 0.3,  alpha: 1),
        SKColor(red: 0.95, green: 0.6,  blue: 0.2,  alpha: 1),
        SKColor(red: 0.95, green: 0.85, blue: 0.25, alpha: 1),
        SKColor(red: 0.35, green: 0.8,  blue: 0.4,  alpha: 1),
        SKColor(red: 0.3,  green: 0.6,  blue: 0.95, alpha: 1),
        SKColor(red: 0.6,  green: 0.4,  blue: 0.9,  alpha: 1),
    ]

    func startIfNeeded() {
        guard built, balls.isEmpty else { return }
        spawnBall()
    }

    override func didMove(to view: SKView) {
        guard !built else { return }
        built = true
        backgroundColor = SKColor(red: 0.04, green: 0.05, blue: 0.12, alpha: 1)
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self

        // Walls (L, top, R) — include in contactTestBitMask so wall bounces fire.
        let walls = CGMutablePath()
        walls.move(to: CGPoint(x: 6, y: 0))
        walls.addLine(to: CGPoint(x: 6, y: 694))
        walls.addLine(to: CGPoint(x: 384, y: 694))
        walls.addLine(to: CGPoint(x: 384, y: 0))
        let wallNode = SKNode()
        wallNode.physicsBody = SKPhysicsBody(edgeChainFrom: walls)
        wallNode.physicsBody!.friction = 0
        wallNode.physicsBody!.restitution = 1
        wallNode.physicsBody!.categoryBitMask = Category.wall
        wallNode.physicsBody!.contactTestBitMask = Category.ball
        addChild(wallNode)
        let outline = SKShapeNode(path: walls)
        outline.strokeColor = SKColor(white: 1, alpha: 0.25)
        outline.lineWidth = 2
        addChild(outline)

        // Floor sensor
        let floor = SKNode()
        floor.position = CGPoint(x: size.width / 2, y: -16)
        floor.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 10))
        floor.physicsBody!.isDynamic = false
        floor.physicsBody!.categoryBitMask = Category.floor
        floor.physicsBody!.collisionBitMask = 0
        floor.physicsBody!.contactTestBitMask = Category.ball
        addChild(floor)

        // Paddle
        paddle = SKShapeNode(rectOf: CGSize(width: normalPaddleWidth, height: paddleHeight), cornerRadius: 7)
        paddle.position = CGPoint(x: size.width / 2, y: 64)
        paddle.fillColor = SKColor(red: 0.85, green: 0.88, blue: 0.95, alpha: 1)
        paddle.strokeColor = SKColor(white: 1, alpha: 0.7)
        paddle.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: normalPaddleWidth, height: paddleHeight))
        paddle.physicsBody!.isDynamic = false
        paddle.physicsBody!.friction = 0
        paddle.physicsBody!.restitution = 1
        paddle.physicsBody!.categoryBitMask = Category.paddle
        paddle.physicsBody!.contactTestBitMask = Category.ball
        addChild(paddle)

        buildBricks()
        spawnBall()
    }

    // MARK: - Brick building

    private func buildBricks() {
        let columns = 9
        let rows = min(4 + level, 8)
        let brickW = (size.width - 24 - CGFloat(columns - 1) * 4) / CGFloat(columns)
        let brickH: CGFloat = 18
        var count = 0

        for row in 0..<rows {
            for col in 0..<columns {
                // Checkerboard gap from level 3
                if level >= 3 && (row + col) % 5 == 0 { continue }

                let x = 12 + brickW / 2 + CGFloat(col) * (brickW + 4)
                let y = 660 - CGFloat(row) * (brickH + 6)

                // Steel brick (level 4+): every 4th in the bottom row
                if level >= 4 && row == rows - 1 && col % 4 == 2 {
                    let brick = makeBrick(width: brickW, height: brickH, x: x, y: y,
                                         color: SKColor(white: 0.55, alpha: 1),
                                         strokeColor: SKColor(white: 0.85, alpha: 0.6),
                                         hits: 999, points: 0, steel: true)
                    addChild(brick)
                    count += 1
                    continue
                }

                // Explosive brick (level 3+): star pattern
                let isExplosive = level >= 3 && (row + col * 2) % 9 == 4
                let armored = level >= 2 && row % 3 == 2 && !isExplosive
                let baseColor = rowColors[row % rowColors.count]
                let fillColor = isExplosive
                    ? SKColor(red: 0.95, green: 0.75, blue: 0.1, alpha: 1)
                    : armored ? SKColor(white: 0.45, alpha: 1) : baseColor

                let brick = makeBrick(width: brickW, height: brickH, x: x, y: y,
                                      color: fillColor,
                                      strokeColor: isExplosive
                                          ? SKColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 0.9)
                                          : SKColor(white: 1, alpha: 0.4),
                                      hits: armored ? 2 : 1,
                                      points: 50 + (rows - 1 - row) * 10,
                                      steel: false,
                                      explosive: isExplosive,
                                      originalColor: baseColor)

                // Moving brick (level 3+, every 6th)
                if level >= 3 && (row * columns + col) % 6 == 1 && !isExplosive {
                    brick.userData?["moving"] = true
                    let range: CGFloat = min(brickW * 2.5, 60)
                    let dur = Double.random(in: 1.2...2.0)
                    let sign: CGFloat = col < columns / 2 ? 1 : -1
                    brick.run(.repeatForever(.sequence([
                        .moveBy(x: range * sign, y: 0, duration: dur),
                        .moveBy(x: -range * sign, y: 0, duration: dur),
                    ])))
                }

                addChild(brick)
                count += 1
            }
        }
        totalBricksThisLevel = count
        // Report initial count, excluding steel (steel never clears the level)
        let nonSteel = children.filter { $0.name == "brick" && ($0.userData?["steel"] as? Bool) != true }.count
        onEvent?(.brickCount(remaining: nonSteel, total: nonSteel))
    }

    private func makeBrick(width: CGFloat, height: CGFloat, x: CGFloat, y: CGFloat,
                           color: SKColor, strokeColor: SKColor,
                           hits: Int, points: Int, steel: Bool,
                           explosive: Bool = false, originalColor: SKColor? = nil) -> SKShapeNode {
        let brick = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 3)
        brick.position = CGPoint(x: x, y: y)
        brick.fillColor = color
        brick.strokeColor = strokeColor
        brick.name = "brick"
        brick.userData = ["hits": hits, "points": points, "color": originalColor ?? color,
                          "steel": steel, "explosive": explosive]
        let body = SKPhysicsBody(rectangleOf: CGSize(width: width, height: height))
        body.isDynamic = false
        body.friction = 0
        body.restitution = 1
        body.categoryBitMask = Category.brick
        body.contactTestBitMask = Category.ball
        body.collisionBitMask = Category.ball
        brick.physicsBody = body
        return brick
    }

    // MARK: - Ball management

    private func makeBallNode() -> SKShapeNode {
        let b = SKShapeNode(circleOfRadius: 8)
        b.fillColor = SKColor(white: 0.95, alpha: 1)
        b.strokeColor = SKColor(white: 0.6, alpha: 1)
        let body = SKPhysicsBody(circleOfRadius: 8)
        body.friction = 0
        body.restitution = 1
        body.linearDamping = 0
        body.angularDamping = 0
        body.allowsRotation = false
        body.usesPreciseCollisionDetection = true
        body.categoryBitMask = Category.ball
        body.collisionBitMask = Category.wall | Category.paddle | Category.brick
        body.contactTestBitMask = Category.paddle | Category.brick | Category.floor | Category.wall | Category.shield
        b.physicsBody = body
        addChild(b)
        addTrail(to: b)
        return b
    }

    private func addTrail(to ball: SKShapeNode) {
        ensureSparkTexture()
        let trail = SKEmitterNode()
        trail.particleTexture = sparkTexture
        trail.particleBirthRate = 45
        trail.particleLifetime = 0.28
        trail.particleAlpha = 0.3
        trail.particleAlphaSpeed = -1.2
        trail.particleScale = 0.45
        trail.particleScaleSpeed = -1.2
        trail.particleColor = isFireball
            ? SKColor(red: 1.0, green: 0.55, blue: 0.1, alpha: 1)
            : SKColor(red: 0.5, green: 0.8, blue: 1.0, alpha: 1)
        trail.particleColorBlendFactor = 1
        trail.targetNode = self
        trail.zPosition = -0.5
        ball.addChild(trail)
    }

    private func spawnBall() {
        let b = makeBallNode()
        balls.append(b)
        ballGlued = true
        positionGluedBall(b)
    }

    private func positionGluedBall(_ ball: SKShapeNode) {
        ball.position = CGPoint(x: paddle.position.x, y: paddle.position.y + 18)
        ball.physicsBody?.velocity = .zero
    }

    private func applyFireballAppearance() {
        for b in balls {
            b.fillColor = isFireball
                ? SKColor(red: 1.0, green: 0.5, blue: 0.1, alpha: 1)
                : SKColor(white: 0.95, alpha: 1)
            b.strokeColor = isFireball
                ? SKColor(red: 1.0, green: 0.75, blue: 0.3, alpha: 1)
                : SKColor(white: 0.6, alpha: 1)
            b.physicsBody?.collisionBitMask = isFireball
                ? (Category.wall | Category.paddle)
                : (Category.wall | Category.paddle | Category.brick)
        }
    }

    // MARK: - Power-ups

    private func maybeDropPowerUp(at point: CGPoint) {
        guard Double.random(in: 0..<1) < 0.20 else { return }
        let kinds: [BreakoutPowerUp] = [.widePaddle, .multiball, .shield, .fireball, .scoreDouble, .extraLife]
        let weights: [Double]        = [    0.28,       0.18,     0.20,     0.14,       0.12,        0.08]
        var r = Double.random(in: 0..<1)
        var chosen = kinds[0]
        for (k, w) in zip(kinds, weights) { r -= w; if r <= 0 { chosen = k; break } }
        dropCapsule(kind: chosen, at: point)
    }

    private func dropCapsule(kind: BreakoutPowerUp, at point: CGPoint) {
        let capsule = SKShapeNode(rectOf: CGSize(width: 32, height: 13), cornerRadius: 6.5)
        let (fillColor, label): (SKColor, String) = {
            switch kind {
            case .widePaddle:   return (SKColor(red: 0.3, green: 0.85, blue: 0.55, alpha: 1), "⟷")
            case .multiball:    return (SKColor(red: 0.7, green: 0.3, blue: 0.9, alpha: 1),   "🔮")
            case .shield:       return (SKColor(red: 0.3, green: 0.6, blue: 0.95, alpha: 1),  "🛡")
            case .fireball:     return (SKColor(red: 0.95, green: 0.45, blue: 0.1, alpha: 1), "🔥")
            case .scoreDouble:  return (SKColor(red: 0.95, green: 0.85, blue: 0.2, alpha: 1), "×2")
            case .extraLife:    return (SKColor(red: 0.95, green: 0.25, blue: 0.35, alpha: 1), "❤️")
            }
        }()
        capsule.fillColor = fillColor
        capsule.strokeColor = SKColor(white: 1, alpha: 0.7)
        capsule.position = point
        capsule.userData = ["kind": kind.rawValue]
        let lbl = SKLabelNode(text: label)
        lbl.fontSize = 10
        lbl.fontName = "AvenirNext-Bold"
        lbl.verticalAlignmentMode = .center
        capsule.addChild(lbl)
        addChild(capsule)
        powerUpNodes.append((node: capsule, kind: kind))
    }

    private func activatePowerUp(_ kind: BreakoutPowerUp) {
        onEvent?(.powerUp(kind))
        SoundFX.shared.play(.levelUp)
        switch kind {
        case .widePaddle:
            wideUntil = lastTime + 10
            setPaddleWidth(140)
        case .multiball:
            spawnExtraBalls()
        case .shield:
            activateShield()
        case .fireball:
            fireballUntil = lastTime + 8
            applyFireballAppearance()
        case .scoreDouble:
            scoreDoubleUntil = lastTime + 12
        case .extraLife:
            break  // engine handles life restoration
        }
    }

    private func setPaddleWidth(_ width: CGFloat) {
        paddle.path = CGPath(roundedRect: CGRect(x: -width / 2, y: -paddleHeight / 2,
                                                 width: width, height: paddleHeight),
                             cornerWidth: 7, cornerHeight: 7, transform: nil)
        let body = SKPhysicsBody(rectangleOf: CGSize(width: width, height: paddleHeight))
        body.isDynamic = false; body.friction = 0; body.restitution = 1
        body.categoryBitMask = Category.paddle
        body.contactTestBitMask = Category.ball
        paddle.physicsBody = body
    }

    private func spawnExtraBalls() {
        guard let source = balls.first, !ballGlued else { return }
        let v = source.physicsBody?.velocity ?? CGVector(dx: 0, dy: ballSpeed)
        let b = makeBallNode()
        b.position = source.position
        b.physicsBody?.velocity = CGVector(dx: -v.dx * 0.9 + 40, dy: v.dy)
        if isFireball {
            b.fillColor = SKColor(red: 1, green: 0.5, blue: 0.1, alpha: 1)
            b.physicsBody?.collisionBitMask = Category.wall | Category.paddle
        }
        balls.append(b)
    }

    private func activateShield() {
        guard shieldNode == nil else { return }
        let w = size.width - 28
        let sh = SKShapeNode(rectOf: CGSize(width: w, height: 8), cornerRadius: 4)
        sh.position = CGPoint(x: size.width / 2, y: 24)
        sh.fillColor = SKColor(red: 0.3, green: 0.6, blue: 0.95, alpha: 0.85)
        sh.strokeColor = SKColor(white: 1, alpha: 0.8)
        sh.name = "shield"
        sh.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: w, height: 8))
        sh.physicsBody!.isDynamic = false
        sh.physicsBody!.friction = 0
        sh.physicsBody!.restitution = 1
        sh.physicsBody!.categoryBitMask = Category.shield
        sh.physicsBody!.collisionBitMask = Category.ball
        sh.physicsBody!.contactTestBitMask = Category.ball
        addChild(sh)
        shieldNode = sh
        for b in balls {
            b.physicsBody?.collisionBitMask |= Category.shield
        }
    }

    private func breakShield() {
        guard let sh = shieldNode else { return }
        onEvent?(.shieldHit)
        spark(at: sh.position, color: SKColor(red: 0.3, green: 0.6, blue: 0.95, alpha: 1))
        sh.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))
        shieldNode = nil
        for b in balls {
            b.physicsBody?.collisionBitMask &= ~Category.shield
        }
    }

    // MARK: - Hits & explosions

    private func hitBrick(_ brick: SKShapeNode?, at point: CGPoint) {
        guard let brick, brick.physicsBody != nil else { return }

        // Steel bricks: shake and skip
        if brick.userData?["steel"] as? Bool == true {
            brick.run(.sequence([
                .scale(to: 0.94, duration: 0.03),
                .scale(to: 1.06, duration: 0.03),
                .scale(to: 1.0,  duration: 0.03),
            ]))
            SoundFX.shared.play(.brick)
            return
        }

        var hits = (brick.userData?["hits"] as? Int) ?? 1
        hits -= 1
        SoundFX.shared.play(.brick)

        if hits > 0 {
            brick.userData?["hits"] = hits
            if let c = brick.userData?["color"] as? SKColor { brick.fillColor = c }
            brick.run(.sequence([.scale(to: 0.92, duration: 0.05), .scale(to: 1, duration: 0.05)]))
            return
        }

        let basePoints = (brick.userData?["points"] as? Int) ?? 50
        let finalPoints = basePoints * scoreMultiplier
        onEvent?(.score(finalPoints))
        floatScore(finalPoints, at: point)
        spark(at: point, color: brick.fillColor)

        // Explosive: chain-destroy neighbours
        if brick.userData?["explosive"] as? Bool == true {
            let center = brick.position
            brick.physicsBody = nil
            brick.run(.sequence([
                .group([.fadeOut(withDuration: 0.1), .scale(to: 0.5, duration: 0.1)]),
                .removeFromParent(),
            ]))
            explodeNeighbours(around: center)
        } else {
            maybeDropPowerUp(at: brick.position)
            brick.physicsBody = nil
            brick.run(.sequence([
                .group([.fadeOut(withDuration: 0.15), .scale(to: 0.6, duration: 0.15)]),
                .removeFromParent(),
                .run { [weak self] in self?.reportBrickCount(); self?.checkLevelCleared() },
            ]))
        }
    }

    private func explodeNeighbours(around center: CGPoint) {
        let radius: CGFloat = 72
        var toDestroy: [SKShapeNode] = []
        for child in children {
            guard child.name == "brick", let b = child as? SKShapeNode,
                  b.physicsBody != nil,
                  (b.userData?["steel"] as? Bool) != true else { continue }
            let dx = b.position.x - center.x
            let dy = b.position.y - center.y
            if sqrt(dx*dx + dy*dy) < radius { toDestroy.append(b) }
        }
        let big = SKEmitterNode()
        big.position = center
        big.numParticlesToEmit = 20
        big.particleBirthRate = 300
        big.particleLifetime = 0.5
        big.particleSpeed = 160
        big.particleSpeedRange = 80
        big.emissionAngleRange = .pi * 2
        big.particleAlphaSpeed = -2
        big.particleScale = 0.7
        big.particleScaleSpeed = -1.2
        big.particleColor = SKColor(red: 1, green: 0.75, blue: 0.2, alpha: 1)
        big.particleColorBlendFactor = 1
        addChild(big)
        big.run(.sequence([.wait(forDuration: 0.6), .removeFromParent()]))

        for b in toDestroy {
            let pts = ((b.userData?["points"] as? Int) ?? 50) * scoreMultiplier
            onEvent?(.score(pts))
            spark(at: b.position, color: b.fillColor)
            b.physicsBody = nil
            b.run(.sequence([
                .group([.fadeOut(withDuration: 0.15), .scale(to: 0.5, duration: 0.15)]),
                .removeFromParent(),
            ]))
        }
        run(.sequence([
            .wait(forDuration: 0.2),
            .run { [weak self] in self?.reportBrickCount(); self?.checkLevelCleared() },
        ]))
    }

    private func reportBrickCount() {
        let remaining = children.filter {
            $0.name == "brick" && ($0.userData?["steel"] as? Bool) != true && ($0.physicsBody != nil)
        }.count
        let total = totalBricksThisLevel
        onEvent?(.brickCount(remaining: remaining, total: total))
    }

    private func checkLevelCleared() {
        let nonSteelAlive = children.first {
            $0.name == "brick"
            && ($0.userData?["steel"] as? Bool) != true
            && ($0.physicsBody != nil)
        }
        guard nonSteelAlive == nil else { return }
        level += 1
        onEvent?(.levelCleared)
        SoundFX.shared.play(.levelUp)
        for b in balls { b.removeFromParent() }
        balls = []
        shieldNode?.removeFromParent(); shieldNode = nil
        wideUntil = 0; fireballUntil = 0; scoreDoubleUntil = 0
        run(.sequence([.wait(forDuration: 0.8), .run { [weak self] in
            self?.buildBricks()
            self?.spawnBall()
        }]))
    }

    private func loseOneBall(_ ball: SKShapeNode?) {
        guard let ball else { return }
        balls.removeAll { $0 === ball }
        ball.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))

        if balls.isEmpty {
            SoundFX.shared.play(.lifeLost)
            onEvent?(.ballLost)
            if shouldContinue?() == true {
                run(.sequence([.wait(forDuration: 0.8), .run { [weak self] in
                    guard let self else { return }
                    self.setPaddleWidth(self.normalPaddleWidth)
                    self.wideUntil = 0; self.fireballUntil = 0; self.scoreDoubleUntil = 0
                    self.spawnBall()
                }]))
            }
        }
    }

    // MARK: - Sparks & floats

    private func ensureSparkTexture() {
        guard sparkTexture == nil else { return }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 6, height: 6))
        let image = renderer.image { ctx in
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 6, height: 6))
        }
        sparkTexture = SKTexture(image: image)
    }

    private func spark(at point: CGPoint, color: SKColor) {
        ensureSparkTexture()
        let em = SKEmitterNode()
        em.particleTexture = sparkTexture
        em.position = point
        em.numParticlesToEmit = 10
        em.particleBirthRate = 280
        em.particleLifetime = 0.3
        em.particleSpeed = 110
        em.particleSpeedRange = 60
        em.emissionAngleRange = .pi * 2
        em.particleAlphaSpeed = -3
        em.particleScale = 0.5
        em.particleScaleSpeed = -1
        em.particleColor = color
        em.particleColorBlendFactor = 1
        addChild(em)
        em.run(.sequence([.wait(forDuration: 0.5), .removeFromParent()]))
    }

    private func floatScore(_ points: Int, at location: CGPoint) {
        let label = SKLabelNode(text: scoreMultiplier > 1 ? "+\(points) ×\(scoreMultiplier)" : "+\(points)")
        label.fontName = "AvenirNext-Bold"
        label.fontSize = 13
        label.fontColor = scoreMultiplier > 1 ? SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1) : .white
        label.position = location
        label.zPosition = 10
        addChild(label)
        label.run(.sequence([
            .group([.moveBy(x: 0, y: 24, duration: 0.5), .fadeOut(withDuration: 0.5)]),
            .removeFromParent(),
        ]))
    }

    // MARK: - Controls

    private func steer(to x: CGFloat) {
        let hw = currentPaddleWidth / 2
        let clamped = min(max(x, 14 + hw), size.width - 14 - hw)
        paddle.position.x = clamped
        if ballGlued, let b = balls.first { positionGluedBall(b) }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        steer(to: touch.location(in: self).x)
        if ballGlued, let b = balls.first {
            ballGlued = false
            let angle = CGFloat.random(in: (.pi * 0.35)...(.pi * 0.65))
            b.physicsBody?.velocity = CGVector(dx: cos(angle) * ballSpeed, dy: sin(angle) * ballSpeed)
            SoundFX.shared.play(.launch)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        steer(to: touch.location(in: self).x)
    }

    // MARK: - Frame loop

    override func update(_ currentTime: TimeInterval) {
        lastTime = currentTime

        // Falling power-up capsules
        powerUpNodes = powerUpNodes.filter { entry in
            let capsule = entry.node
            capsule.position.y -= 3.2
            let hw = currentPaddleWidth / 2 + 16
            if abs(capsule.position.y - paddle.position.y) < 16,
               abs(capsule.position.x - paddle.position.x) < hw {
                activatePowerUp(entry.kind)
                capsule.removeFromParent()
                return false
            }
            if capsule.position.y < -20 { capsule.removeFromParent(); return false }
            return true
        }

        // Expire wide paddle
        if wideUntil > 0, currentTime > wideUntil, paddle.frame.width > normalPaddleWidth + 1 {
            setPaddleWidth(normalPaddleWidth)
            wideUntil = 0
        }

        // Expire fireball
        if fireballUntil > 0, currentTime > fireballUntil, isFireball == false {
            applyFireballAppearance()
        }

        // Normalise each ball's speed
        for b in balls where b.physicsBody != nil {
            guard !ballGlued else { continue }
            var v = b.physicsBody!.velocity
            let spd = max(sqrt(v.dx * v.dx + v.dy * v.dy), 1)
            v.dx *= ballSpeed / spd
            v.dy *= ballSpeed / spd
            if abs(v.dy) < ballSpeed * 0.18 {
                v.dy = (v.dy < 0 ? -1 : 1) * ballSpeed * 0.25
                let sx: CGFloat = v.dx < 0 ? -1 : 1
                v.dx = sx * sqrt(max(ballSpeed * ballSpeed - v.dy * v.dy, 0))
            }
            b.physicsBody!.velocity = v
        }
    }

    // MARK: - Contacts

    func didBegin(_ contact: SKPhysicsContact) {
        let bodies = [contact.bodyA, contact.bodyB]
        guard let ballBody = bodies.first(where: { $0.categoryBitMask == Category.ball }),
              let other   = bodies.first(where: { $0.categoryBitMask != Category.ball })
        else { return }

        switch other.categoryBitMask {
        case Category.paddle:
            guard let ballNode = ballBody.node as? SKShapeNode else { return }
            let offset = (ballNode.position.x - paddle.position.x) / (currentPaddleWidth / 2)
            let angle = CGFloat.pi / 2 - min(max(offset, -1), 1) * (.pi / 3)
            ballBody.velocity = CGVector(dx: cos(angle) * ballSpeed, dy: abs(sin(angle)) * ballSpeed)
            SoundFX.shared.play(.paddleHit)

        case Category.brick:
            hitBrick(other.node as? SKShapeNode, at: contact.contactPoint)

        case Category.floor:
            loseOneBall(ballBody.node as? SKShapeNode)

        case Category.wall:
            onEvent?(.wallBounce)

        case Category.shield:
            breakShield()

        default:
            break
        }
    }
}
