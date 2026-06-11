import SwiftUI
import SpriteKit

/// Breakout: drag anywhere to steer the paddle, tap to launch. Levels get
/// faster and add tougher bricks; score/lives/level live in BreakoutGame so
/// results reach the banner, stats, and leaderboards like every other game.
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

    var body: some View {
        VStack(spacing: 6) {
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
}

final class BreakoutScene: SKScene, SKPhysicsContactDelegate {

    enum Category {
        static let ball: UInt32 = 1 << 0
        static let paddle: UInt32 = 1 << 1
        static let brick: UInt32 = 1 << 2
        static let wall: UInt32 = 1 << 3
        static let floor: UInt32 = 1 << 4
    }

    var onEvent: ((BreakoutEvent) -> Void)?
    var shouldContinue: (() -> Bool)?

    private var paddle: SKShapeNode!
    private var ball: SKShapeNode?
    private var ballGlued = true
    private var level = 1
    private var built = false

    private let paddleSize = CGSize(width: 92, height: 14)
    private var ballSpeed: CGFloat { 430 + CGFloat(level - 1) * 45 }

    private let rowColors: [SKColor] = [
        SKColor(red: 0.92, green: 0.3, blue: 0.3, alpha: 1),
        SKColor(red: 0.95, green: 0.6, blue: 0.2, alpha: 1),
        SKColor(red: 0.95, green: 0.85, blue: 0.25, alpha: 1),
        SKColor(red: 0.35, green: 0.8, blue: 0.4, alpha: 1),
        SKColor(red: 0.3, green: 0.6, blue: 0.95, alpha: 1),
        SKColor(red: 0.6, green: 0.4, blue: 0.9, alpha: 1),
    ]

    func startIfNeeded() {
        guard built, ball == nil else { return }
        spawnBall()
    }

    override func didMove(to view: SKView) {
        guard !built else { return }
        built = true
        backgroundColor = SKColor(red: 0.04, green: 0.05, blue: 0.12, alpha: 1)
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self

        // Walls: left, top, right (bottom open).
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
        addChild(wallNode)
        let outline = SKShapeNode(path: walls)
        outline.strokeColor = SKColor(white: 1, alpha: 0.25)
        outline.lineWidth = 2
        addChild(outline)

        // Floor sensor.
        let floor = SKNode()
        floor.position = CGPoint(x: size.width / 2, y: -16)
        floor.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 2, height: 10))
        floor.physicsBody!.isDynamic = false
        floor.physicsBody!.categoryBitMask = Category.floor
        floor.physicsBody!.collisionBitMask = 0
        floor.physicsBody!.contactTestBitMask = Category.ball
        addChild(floor)

        paddle = SKShapeNode(rectOf: paddleSize, cornerRadius: 7)
        paddle.position = CGPoint(x: size.width / 2, y: 64)
        paddle.fillColor = SKColor(red: 0.85, green: 0.88, blue: 0.95, alpha: 1)
        paddle.strokeColor = SKColor(white: 1, alpha: 0.7)
        paddle.physicsBody = SKPhysicsBody(rectangleOf: paddleSize)
        paddle.physicsBody!.isDynamic = false
        paddle.physicsBody!.friction = 0
        paddle.physicsBody!.restitution = 1
        paddle.physicsBody!.categoryBitMask = Category.paddle
        paddle.physicsBody!.contactTestBitMask = Category.ball
        addChild(paddle)

        buildBricks()
        spawnBall()
    }

    /// Brick layouts thicken with the level; every third row is armored
    /// (two hits) from level 2 on.
    private func buildBricks() {
        let columns = 9
        let rows = min(4 + level, 8)
        let brickWidth = (size.width - 24 - CGFloat(columns - 1) * 4) / CGFloat(columns)
        let brickHeight: CGFloat = 18
        for row in 0..<rows {
            for col in 0..<columns {
                // Level 3+ carves a checkerboard gap pattern for variety.
                if level >= 3 && (row + col) % 5 == 0 { continue }
                let armored = level >= 2 && row % 3 == 2
                let brick = SKShapeNode(rectOf: CGSize(width: brickWidth, height: brickHeight), cornerRadius: 3)
                brick.position = CGPoint(
                    x: 12 + brickWidth / 2 + CGFloat(col) * (brickWidth + 4),
                    y: 660 - CGFloat(row) * (brickHeight + 6)
                )
                let color = rowColors[row % rowColors.count]
                brick.fillColor = armored ? SKColor(white: 0.45, alpha: 1) : color
                brick.strokeColor = SKColor(white: 1, alpha: 0.4)
                brick.name = "brick"
                brick.userData = ["hits": armored ? 2 : 1,
                                  "points": 50 + (rows - 1 - row) * 10,
                                  "color": color]
                brick.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: brickWidth, height: brickHeight))
                brick.physicsBody!.isDynamic = false
                brick.physicsBody!.friction = 0
                brick.physicsBody!.restitution = 1
                brick.physicsBody!.categoryBitMask = Category.brick
                brick.physicsBody!.contactTestBitMask = Category.ball
                addChild(brick)
            }
        }
    }

    private func spawnBall() {
        let ball = SKShapeNode(circleOfRadius: 8)
        ball.fillColor = SKColor(white: 0.95, alpha: 1)
        ball.strokeColor = SKColor(white: 0.6, alpha: 1)
        let body = SKPhysicsBody(circleOfRadius: 8)
        body.friction = 0
        body.restitution = 1
        body.linearDamping = 0
        body.angularDamping = 0
        body.allowsRotation = false
        body.usesPreciseCollisionDetection = true
        body.categoryBitMask = Category.ball
        body.collisionBitMask = Category.wall | Category.paddle | Category.brick
        body.contactTestBitMask = Category.paddle | Category.brick | Category.floor
        ball.physicsBody = body
        addChild(ball)
        self.ball = ball
        ballGlued = true
        positionGluedBall()
    }

    private func positionGluedBall() {
        ball?.position = CGPoint(x: paddle.position.x, y: paddle.position.y + 18)
        ball?.physicsBody?.velocity = .zero
    }

    // MARK: - Controls

    private func steer(to x: CGFloat) {
        let clamped = min(max(x, 14 + paddleSize.width / 2), size.width - 14 - paddleSize.width / 2)
        paddle.position.x = clamped
        if ballGlued { positionGluedBall() }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        steer(to: touch.location(in: self).x)
        if ballGlued, ball != nil {
            ballGlued = false
            let angle = CGFloat.random(in: (.pi * 0.35)...(.pi * 0.65))
            ball?.physicsBody?.velocity = CGVector(dx: cos(angle) * ballSpeed, dy: sin(angle) * ballSpeed)
            SoundFX.shared.play(.launch)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        steer(to: touch.location(in: self).x)
    }

    // MARK: - Frame loop

    override func update(_ currentTime: TimeInterval) {
        // Keep the ball at constant speed and never perfectly horizontal.
        guard let body = ball?.physicsBody, !ballGlued else { return }
        var v = body.velocity
        let speed = max(sqrt(v.dx * v.dx + v.dy * v.dy), 1)
        v.dx *= ballSpeed / speed
        v.dy *= ballSpeed / speed
        if abs(v.dy) < ballSpeed * 0.18 {
            v.dy = (v.dy < 0 ? -1 : 1) * ballSpeed * 0.25
            let dxSign: CGFloat = v.dx < 0 ? -1 : 1
            v.dx = dxSign * sqrt(max(ballSpeed * ballSpeed - v.dy * v.dy, 0))
        }
        body.velocity = v
    }

    // MARK: - Contacts

    func didBegin(_ contact: SKPhysicsContact) {
        let bodies = [contact.bodyA, contact.bodyB]
        guard let ballBody = bodies.first(where: { $0.categoryBitMask == Category.ball }),
              let other = bodies.first(where: { $0.categoryBitMask != Category.ball })
        else { return }

        switch other.categoryBitMask {
        case Category.paddle:
            // Reflect by hit offset so players can aim.
            guard let ballNode = ballBody.node else { return }
            let offset = (ballNode.position.x - paddle.position.x) / (paddleSize.width / 2)
            let angle = CGFloat.pi / 2 - offset * (.pi / 3)
            ballBody.velocity = CGVector(dx: cos(angle) * ballSpeed, dy: abs(sin(angle)) * ballSpeed)
            SoundFX.shared.play(.paddleHit)
        case Category.brick:
            hitBrick(other.node as? SKShapeNode, at: contact.contactPoint)
        case Category.floor:
            loseBall()
        default:
            break
        }
    }

    private func hitBrick(_ brick: SKShapeNode?, at point: CGPoint) {
        guard let brick, var hits = brick.userData?["hits"] as? Int else { return }
        hits -= 1
        SoundFX.shared.play(.brick)
        if hits > 0 {
            brick.userData?["hits"] = hits
            if let color = brick.userData?["color"] as? SKColor { brick.fillColor = color }
            brick.run(.sequence([.scale(to: 0.92, duration: 0.05), .scale(to: 1, duration: 0.05)]))
            return
        }
        let points = (brick.userData?["points"] as? Int) ?? 50
        onEvent?(.score(points))
        floatScore(points, at: point)
        brick.physicsBody = nil
        brick.run(.sequence([
            .group([.fadeOut(withDuration: 0.15), .scale(to: 0.6, duration: 0.15)]),
            .removeFromParent(),
            .run { [weak self] in self?.checkLevelCleared() },
        ]))
    }

    private func checkLevelCleared() {
        guard children.first(where: { $0.name == "brick" }) == nil else { return }
        level += 1
        onEvent?(.levelCleared)
        SoundFX.shared.play(.levelUp)
        ball?.removeFromParent()
        ball = nil
        run(.sequence([.wait(forDuration: 0.8), .run { [weak self] in
            self?.buildBricks()
            self?.spawnBall()
        }]))
    }

    private func loseBall() {
        guard let ball else { return }
        self.ball = nil
        ball.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))
        SoundFX.shared.play(.lifeLost)
        onEvent?(.ballLost)
        if shouldContinue?() == true {
            run(.sequence([.wait(forDuration: 0.8), .run { [weak self] in self?.spawnBall() }]))
        }
    }

    private func floatScore(_ points: Int, at location: CGPoint) {
        let label = SKLabelNode(text: "+\(points)")
        label.fontName = "AvenirNext-Bold"
        label.fontSize = 13
        label.fontColor = .white
        label.position = location
        label.zPosition = 10
        addChild(label)
        label.run(.sequence([
            .group([.moveBy(x: 0, y: 20, duration: 0.5), .fadeOut(withDuration: 0.5)]),
            .removeFromParent(),
        ]))
    }
}
