import SwiftUI
import SpriteKit

/// Pinball: a SpriteKit physics table built from a `PinballTheme` (10 to
/// choose from). Hold the left/right half of the screen to work the
/// flippers; hold the launch lane to charge the plunger. Score and ball
/// count live in the PinballGame engine (via the session) so results flow
/// through the normal result banner, stats, and leaderboards.
struct PinballView: View {
    @ObservedObject var session: GameSession

    final class SceneHolder: ObservableObject {
        let scene: PinballScene
        init(theme: PinballTheme) {
            scene = PinballScene(size: CGSize(width: 390, height: 700))
            scene.theme = theme
            scene.scaleMode = .aspectFit
        }
    }

    @StateObject private var holder: SceneHolder

    init(session: GameSession) {
        self.session = session
        let theme = PinballTheme.theme(id: session.lobby.options.pinballLayout)
        _holder = StateObject(wrappedValue: SceneHolder(theme: theme))
    }

    var game: PinballGame? { session.game?.engine as? PinballGame }

    var body: some View {
        VStack(spacing: 6) {
            SpriteView(scene: holder.scene, options: [.allowsTransparency])
                .aspectRatio(390.0 / 700.0, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.15), lineWidth: 1))
                .padding(.horizontal, 10)

            HStack {
                Label(holder.scene.theme.name, systemImage: "sparkles")
                Spacer()
                Label("Hold a side to flip · hold lane to launch", systemImage: "hand.tap.fill")
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.65))
            .padding(.horizontal, 22)
            .padding(.bottom, 4)
        }
        .onAppear {
            let scene = holder.scene
            scene.onEvent = { [weak session] event in
                MainActor.assumeIsolated { session?.submit(.pinball(event)) }
            }
            scene.shouldRespawn = { [weak session] in
                MainActor.assumeIsolated {
                    (session?.game?.engine as? PinballGame)?.isOver == false
                }
            }
            scene.startIfNeeded()
        }
    }
}

/// The physics table: flippers on pin joints, themed bumpers, slingshots,
/// a drop-target bank, optional spinner and tunnel, and a charge-and-release
/// plunger. Geometry constants assume the 390×700 scene.
final class PinballScene: SKScene, SKPhysicsContactDelegate {

    enum Category {
        static let ball: UInt32 = 1 << 0
        static let flipper: UInt32 = 1 << 1
        static let bumper: UInt32 = 1 << 2
        static let sling: UInt32 = 1 << 3
        static let target: UInt32 = 1 << 4
        static let drain: UInt32 = 1 << 5
        static let wall: UInt32 = 1 << 6
        static let spinner: UInt32 = 1 << 7
        static let tunnel: UInt32 = 1 << 8
    }

    var theme = PinballTheme.all[0]
    var onEvent: ((PinballEvent) -> Void)?
    var shouldRespawn: (() -> Bool)?

    private var leftFlipper: SKShapeNode!
    private var rightFlipper: SKShapeNode!
    private var plunger: SKShapeNode!
    private var ball: SKShapeNode?
    private var targets: [SKShapeNode] = []
    private var sparkTexture: SKTexture?

    private var leftPressed = false
    private var rightPressed = false
    private var charging = false
    private var charge: CGFloat = 0
    private var lastUpdate: TimeInterval = 0
    private var lastTunnelTime: TimeInterval = 0
    private var built = false
    /// Touches steering each control, so multitouch works.
    private var touchRoles: [UITouch: String] = [:]

    // Table geometry (scene units).
    private let laneX: CGFloat = 352          // inner wall of the launch lane
    private let flipperLength: CGFloat = 62
    private let leftPivot = CGPoint(x: 122, y: 98)
    private let rightPivot = CGPoint(x: 268, y: 98)

    func startIfNeeded() {
        guard built, ball == nil else { return }
        spawnBall()
    }

    override func didMove(to view: SKView) {
        guard !built else { return }
        built = true
        backgroundColor = theme.background
        physicsWorld.gravity = CGVector(dx: 0, dy: theme.gravity)
        physicsWorld.contactDelegate = self

        buildWalls()
        buildFlippers()
        buildBumpers()
        buildSlings()
        buildTargets()
        buildPlunger()
        buildExtras()
        decorate()
        spawnBall()
    }

    // MARK: - Construction

    private func addWall(path: CGPath, restitution: CGFloat = 0.35, lineWidth: CGFloat = 2.5) {
        let node = SKNode()
        node.physicsBody = SKPhysicsBody(edgeChainFrom: path)
        node.physicsBody!.friction = 0.05
        node.physicsBody!.restitution = restitution
        node.physicsBody!.categoryBitMask = Category.wall
        addChild(node)
        let outline = SKShapeNode(path: path)
        outline.strokeColor = theme.wall
        outline.lineWidth = lineWidth
        outline.lineCap = .round
        addChild(outline)
    }

    private func buildWalls() {
        // Left wall, top arch, right wall.
        let outer = CGMutablePath()
        outer.move(to: CGPoint(x: 8, y: 60))
        outer.addLine(to: CGPoint(x: 8, y: 520))
        outer.addQuadCurve(to: CGPoint(x: 195, y: 692), control: CGPoint(x: 8, y: 692))
        outer.addQuadCurve(to: CGPoint(x: 382, y: 520), control: CGPoint(x: 382, y: 692))
        outer.addLine(to: CGPoint(x: 382, y: 60))
        addWall(path: outer)

        // Launch lane: floor plus an inner wall open above y = 540 so the
        // ball arcs over into the playfield.
        let lane = CGMutablePath()
        lane.move(to: CGPoint(x: laneX, y: 540))
        lane.addLine(to: CGPoint(x: laneX, y: 60))
        lane.addLine(to: CGPoint(x: 382, y: 60))
        addWall(path: lane)

        // Funnels guiding the ball onto the flippers.
        let leftFunnel = CGMutablePath()
        leftFunnel.move(to: CGPoint(x: 8, y: 195))
        leftFunnel.addLine(to: CGPoint(x: leftPivot.x - 6, y: 108))
        leftFunnel.addLine(to: CGPoint(x: leftPivot.x - 6, y: 92))
        addWall(path: leftFunnel)

        let rightFunnel = CGMutablePath()
        rightFunnel.move(to: CGPoint(x: laneX, y: 195))
        rightFunnel.addLine(to: CGPoint(x: rightPivot.x + 6, y: 108))
        rightFunnel.addLine(to: CGPoint(x: rightPivot.x + 6, y: 92))
        addWall(path: rightFunnel)

        // Theme rails — bridges, slopes, rivers.
        for rail in theme.rails where rail.count >= 2 {
            let path = CGMutablePath()
            path.move(to: rail[0])
            for point in rail.dropFirst() { path.addLine(to: point) }
            addWall(path: path, restitution: 0.2, lineWidth: 3.5)
        }

        // Drain sensor across the bottom.
        let drain = SKNode()
        drain.position = CGPoint(x: size.width / 2, y: 14)
        drain.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width, height: 10))
        drain.physicsBody!.isDynamic = false
        drain.physicsBody!.categoryBitMask = Category.drain
        drain.physicsBody!.collisionBitMask = 0
        drain.physicsBody!.contactTestBitMask = Category.ball
        addChild(drain)
    }

    private func makeFlipper(pivot: CGPoint, pointingRight: Bool,
                             restAngle: CGFloat, lowerLimit: CGFloat, upperLimit: CGFloat) -> SKShapeNode {
        let dir: CGFloat = pointingRight ? 1 : -1
        let rect = CGRect(x: pointingRight ? -9 : -flipperLength - 9, y: -9,
                          width: flipperLength + 18, height: 18)
        let flipper = SKShapeNode(path: CGPath(roundedRect: rect, cornerWidth: 9, cornerHeight: 9, transform: nil))
        flipper.fillColor = theme.flipper
        flipper.strokeColor = SKColor(white: 1, alpha: 0.6)
        flipper.lineWidth = 1.5
        flipper.position = pivot
        flipper.zRotation = restAngle
        let body = SKPhysicsBody(rectangleOf: CGSize(width: flipperLength + 14, height: 18),
                                 center: CGPoint(x: dir * flipperLength / 2, y: 0))
        body.density = 60
        body.affectedByGravity = false
        body.allowsRotation = true
        body.categoryBitMask = Category.flipper
        body.collisionBitMask = Category.ball
        flipper.physicsBody = body
        addChild(flipper)

        let anchor = SKNode()
        anchor.position = pivot
        anchor.physicsBody = SKPhysicsBody(circleOfRadius: 4)
        anchor.physicsBody!.isDynamic = false
        anchor.physicsBody!.categoryBitMask = 0
        addChild(anchor)

        let joint = SKPhysicsJointPin.joint(withBodyA: anchor.physicsBody!, bodyB: body, anchor: pivot)
        joint.shouldEnableLimits = true
        joint.lowerAngleLimit = lowerLimit
        joint.upperAngleLimit = upperLimit
        physicsWorld.add(joint)
        return flipper
    }

    private func buildFlippers() {
        leftFlipper = makeFlipper(pivot: leftPivot, pointingRight: true,
                                  restAngle: -0.45, lowerLimit: -0.45, upperLimit: 0.55)
        rightFlipper = makeFlipper(pivot: rightPivot, pointingRight: false,
                                   restAngle: 0.45, lowerLimit: -0.55, upperLimit: 0.45)
    }

    private func buildBumpers() {
        for spec in theme.bumpers {
            let bumper = SKShapeNode(circleOfRadius: spec.radius)
            bumper.position = CGPoint(x: spec.x, y: spec.y)
            bumper.fillColor = spec.color
            bumper.strokeColor = SKColor(white: 1, alpha: 0.8)
            bumper.lineWidth = 3
            bumper.name = "bumper"
            bumper.userData = ["points": spec.points]
            bumper.physicsBody = SKPhysicsBody(circleOfRadius: spec.radius)
            bumper.physicsBody!.isDynamic = false
            bumper.physicsBody!.restitution = 1.1
            bumper.physicsBody!.categoryBitMask = Category.bumper
            bumper.physicsBody!.contactTestBitMask = Category.ball
            addChild(bumper)

            let cap = SKShapeNode(circleOfRadius: spec.radius * 0.42)
            cap.fillColor = SKColor(white: 1, alpha: 0.85)
            cap.strokeColor = .clear
            bumper.addChild(cap)
        }
    }

    private func buildSlings() {
        let shapes: [[CGPoint]] = [
            [CGPoint(x: 62, y: 150), CGPoint(x: 62, y: 215), CGPoint(x: 112, y: 158)],
            [CGPoint(x: 328, y: 150), CGPoint(x: 328, y: 215), CGPoint(x: 278, y: 158)],
        ]
        for points in shapes {
            let path = CGMutablePath()
            path.addLines(between: points)
            path.closeSubpath()
            let sling = SKShapeNode(path: path)
            sling.fillColor = theme.flipper.withAlphaComponent(0.85)
            sling.strokeColor = SKColor(white: 1, alpha: 0.7)
            sling.lineWidth = 2
            sling.name = "sling"
            sling.physicsBody = SKPhysicsBody(polygonFrom: path)
            sling.physicsBody!.isDynamic = false
            sling.physicsBody!.restitution = 1.0
            sling.physicsBody!.categoryBitMask = Category.sling
            sling.physicsBody!.contactTestBitMask = Category.ball
            addChild(sling)
        }
    }

    private func buildTargets() {
        targets = theme.targetXs.map { x in
            let target = SKShapeNode(rectOf: CGSize(width: 34, height: 10), cornerRadius: 4)
            target.position = CGPoint(x: x, y: 612)
            target.fillColor = theme.targetColor
            target.strokeColor = SKColor(white: 1, alpha: 0.8)
            target.lineWidth = 1.5
            target.name = "target"
            target.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 34, height: 10))
            target.physicsBody!.isDynamic = false
            target.physicsBody!.categoryBitMask = Category.target
            target.physicsBody!.contactTestBitMask = Category.ball
            addChild(target)
            return target
        }
    }

    private func buildPlunger() {
        plunger = SKShapeNode(rectOf: CGSize(width: 24, height: 36), cornerRadius: 6)
        plunger.position = CGPoint(x: (laneX + 382) / 2, y: 80)
        plunger.fillColor = SKColor(red: 0.8, green: 0.8, blue: 0.85, alpha: 1)
        plunger.strokeColor = SKColor(white: 1, alpha: 0.6)
        plunger.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 24, height: 36))
        plunger.physicsBody!.isDynamic = false
        plunger.physicsBody!.restitution = 0.1
        plunger.physicsBody!.categoryBitMask = Category.wall
        addChild(plunger)
    }

    /// Spinner and tunnel — the theme's special hardware.
    private func buildExtras() {
        if let center = theme.spinner {
            let bar = SKShapeNode(rectOf: CGSize(width: 64, height: 8), cornerRadius: 4)
            bar.position = center
            bar.fillColor = theme.targetColor
            bar.strokeColor = SKColor(white: 1, alpha: 0.7)
            bar.name = "spinner"
            bar.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 64, height: 8))
            bar.physicsBody!.isDynamic = false
            bar.physicsBody!.restitution = 0.9
            bar.physicsBody!.categoryBitMask = Category.spinner
            bar.physicsBody!.contactTestBitMask = Category.ball
            bar.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 2.4)))
            addChild(bar)
        }

        if let tunnel = theme.tunnel {
            let entry = SKShapeNode(circleOfRadius: 16)
            entry.position = tunnel.entry
            entry.fillColor = SKColor(white: 0, alpha: 0.85)
            entry.strokeColor = theme.wall
            entry.lineWidth = 2.5
            entry.name = "tunnelEntry"
            entry.physicsBody = SKPhysicsBody(circleOfRadius: 12)
            entry.physicsBody!.isDynamic = false
            entry.physicsBody!.categoryBitMask = Category.tunnel
            entry.physicsBody!.collisionBitMask = 0
            entry.physicsBody!.contactTestBitMask = Category.ball
            addChild(entry)

            let label = SKLabelNode(text: tunnel.label)
            label.fontName = "AvenirNext-Bold"
            label.fontSize = 9
            label.fontColor = SKColor(white: 1, alpha: 0.8)
            label.position = CGPoint(x: tunnel.entry.x, y: tunnel.entry.y - 28)
            addChild(label)

            let exit = SKShapeNode(circleOfRadius: 10)
            exit.position = tunnel.exit
            exit.strokeColor = theme.wall
            exit.lineWidth = 2
            exit.fillColor = .clear
            addChild(exit)
        }
    }

    private func decorate() {
        for decal in theme.decals {
            let label = SKLabelNode(text: decal.text)
            label.fontName = "AvenirNext-Bold"
            label.fontSize = decal.size
            label.fontColor = SKColor(white: 1, alpha: 1)
            label.alpha = decal.alpha
            label.verticalAlignmentMode = .center
            label.position = CGPoint(x: decal.x, y: decal.y)
            label.zPosition = -1
            addChild(label)
        }

        for i in 0..<3 {
            let arrow = SKLabelNode(text: "▲")
            arrow.fontSize = 14
            arrow.fontColor = SKColor(white: 1, alpha: 0.3)
            arrow.position = CGPoint(x: (laneX + 382) / 2, y: 200 + CGFloat(i) * 110)
            addChild(arrow)
        }

        let title = SKLabelNode(text: theme.watermark)
        title.fontName = "AvenirNext-Heavy"
        title.fontSize = 26
        title.fontColor = SKColor(white: 1, alpha: 0.12)
        title.position = CGPoint(x: 185, y: 320)
        title.zPosition = -1
        addChild(title)
    }

    private func spawnBall() {
        let ball = SKShapeNode(circleOfRadius: 10)
        ball.position = CGPoint(x: (laneX + 382) / 2, y: 112)
        ball.fillColor = SKColor(white: 0.92, alpha: 1)
        ball.strokeColor = SKColor(white: 0.5, alpha: 1)
        ball.lineWidth = 1
        let body = SKPhysicsBody(circleOfRadius: 10)
        body.restitution = 0.35
        body.friction = 0.04
        body.linearDamping = 0.12
        body.angularDamping = 0.1
        body.allowsRotation = true
        body.usesPreciseCollisionDetection = true
        body.categoryBitMask = Category.ball
        body.collisionBitMask = Category.wall | Category.flipper | Category.bumper
            | Category.sling | Category.target | Category.spinner
        body.contactTestBitMask = Category.bumper | Category.sling | Category.target
            | Category.drain | Category.spinner | Category.tunnel
        ball.physicsBody = body
        addChild(ball)
        self.ball = ball
    }

    private var ballOnPlunger: Bool {
        guard let ball else { return false }
        return ball.position.x > laneX && ball.position.y < 150
    }

    // MARK: - Controls

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let location = touch.location(in: self)
            if location.x > laneX - 10 && ballOnPlunger {
                touchRoles[touch] = "plunger"
                charging = true
            } else if location.x < size.width / 2 {
                touchRoles[touch] = "left"
                leftPressed = true
                SoundFX.shared.play(.flipper)
            } else {
                touchRoles[touch] = "right"
                rightPressed = true
                SoundFX.shared.play(.flipper)
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endTouches(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endTouches(touches)
    }

    private func endTouches(_ touches: Set<UITouch>) {
        for touch in touches {
            switch touchRoles.removeValue(forKey: touch) {
            case "left": leftPressed = touchRoles.values.contains("left")
            case "right": rightPressed = touchRoles.values.contains("right")
            case "plunger": launch()
            default: break
            }
        }
    }

    private func launch() {
        charging = false
        defer { charge = 0; plunger.yScale = 1 }
        guard let body = ball?.physicsBody, ballOnPlunger else { return }
        // Strong enough at full charge to clear the arch into the playfield.
        body.velocity = CGVector(dx: 0, dy: 950 + 500 * min(charge, 1))
        SoundFX.shared.play(.launch)
    }

    // MARK: - Frame loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 0 : min(currentTime - lastUpdate, 0.05)
        lastUpdate = currentTime

        leftFlipper.physicsBody?.angularVelocity = leftPressed ? 32 : -16
        rightFlipper.physicsBody?.angularVelocity = rightPressed ? -32 : 16

        if charging {
            charge = min(charge + CGFloat(dt) * 1.3, 1)
            plunger.yScale = 1 - 0.4 * charge
        }

        // Safety net: a ball that tunnels out of the table counts as drained.
        if let ball, !frame.insetBy(dx: -40, dy: -40).contains(ball.position) {
            drainBall()
        }
    }

    // MARK: - Contacts

    func didBegin(_ contact: SKPhysicsContact) {
        let bodies = [contact.bodyA, contact.bodyB]
        guard let ballBody = bodies.first(where: { $0.categoryBitMask == Category.ball }),
              let other = bodies.first(where: { $0.categoryBitMask != Category.ball })
        else { return }

        switch other.categoryBitMask {
        case Category.bumper:
            let points = (other.node?.userData?["points"] as? Int) ?? 100
            score(points, at: contact.contactPoint)
            kick(ballBody, from: other.node?.position ?? contact.contactPoint, boost: 380)
            pulse(other.node)
            spark(at: contact.contactPoint)
            SoundFX.shared.play(.bumper)
        case Category.sling:
            score(25, at: contact.contactPoint)
            kick(ballBody, from: other.node?.position ?? contact.contactPoint, boost: 300)
            pulse(other.node)
            SoundFX.shared.play(.sling)
        case Category.spinner:
            score(50, at: contact.contactPoint)
            SoundFX.shared.play(.spinner)
        case Category.target:
            score(250, at: contact.contactPoint)
            dropTarget(other.node as? SKShapeNode)
            SoundFX.shared.play(.target)
        case Category.tunnel:
            rideTunnel(ballBody)
        case Category.drain:
            drainBall()
        default:
            break
        }
    }

    /// Pop the ball away from `origin`, adding `boost` points/sec along the normal.
    private func kick(_ body: SKPhysicsBody, from origin: CGPoint, boost: CGFloat) {
        guard let ballNode = body.node else { return }
        let dx = ballNode.position.x - origin.x
        let dy = ballNode.position.y - origin.y
        let length = max(sqrt(dx * dx + dy * dy), 0.01)
        body.velocity = CGVector(dx: body.velocity.dx + boost * dx / length,
                                 dy: body.velocity.dy + boost * dy / length)
    }

    /// Swallow the ball and shoot it out of the tunnel exit.
    private func rideTunnel(_ body: SKPhysicsBody) {
        guard let tunnel = theme.tunnel, let ballNode = body.node,
              lastUpdate - lastTunnelTime > 1.5 else { return }
        lastTunnelTime = lastUpdate
        score(75, at: ballNode.position)
        SoundFX.shared.play(.tunnel)
        body.velocity = .zero
        ballNode.run(.sequence([
            .group([.scale(to: 0.2, duration: 0.12), .fadeOut(withDuration: 0.12)]),
            .run {
                ballNode.position = tunnel.exit
            },
            .group([.scale(to: 1, duration: 0.1), .fadeIn(withDuration: 0.1)]),
            .run {
                body.velocity = CGVector(dx: CGFloat.random(in: -80...80), dy: -150)
            },
        ]))
    }

    private func pulse(_ node: SKNode?) {
        node?.run(.sequence([.scale(to: 1.18, duration: 0.06), .scale(to: 1, duration: 0.1)]))
    }

    /// Quick particle burst on bumper hits.
    private func spark(at point: CGPoint) {
        if sparkTexture == nil {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
            let image = renderer.image { ctx in
                ctx.cgContext.setFillColor(UIColor.white.cgColor)
                ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 8, height: 8))
            }
            sparkTexture = SKTexture(image: image)
        }
        let emitter = SKEmitterNode()
        emitter.particleTexture = sparkTexture
        emitter.position = point
        emitter.numParticlesToEmit = 12
        emitter.particleBirthRate = 300
        emitter.particleLifetime = 0.35
        emitter.particleSpeed = 140
        emitter.particleSpeedRange = 80
        emitter.emissionAngleRange = .pi * 2
        emitter.particleAlphaSpeed = -2.5
        emitter.particleScale = 0.5
        emitter.particleScaleSpeed = -1
        emitter.particleColor = theme.flipper
        emitter.particleColorBlendFactor = 1
        emitter.zPosition = 5
        addChild(emitter)
        emitter.run(.sequence([.wait(forDuration: 0.6), .removeFromParent()]))
    }

    private func dropTarget(_ target: SKShapeNode?) {
        guard let target, target.physicsBody?.categoryBitMask != 0 else { return }
        target.physicsBody?.categoryBitMask = 0
        target.run(.fadeAlpha(to: 0.12, duration: 0.15))
        if targets.allSatisfy({ $0.physicsBody?.categoryBitMask == 0 }) {
            score(1000, at: CGPoint(x: 195, y: 580))
            SoundFX.shared.play(.jackpot)
            run(.sequence([.wait(forDuration: 1.2), .run { [weak self] in self?.resetTargets() }]))
        }
    }

    private func resetTargets() {
        for target in targets {
            target.physicsBody?.categoryBitMask = Category.target
            target.run(.fadeAlpha(to: 1, duration: 0.2))
        }
    }

    private func score(_ points: Int, at location: CGPoint) {
        onEvent?(.score(points))
        let label = SKLabelNode(text: "+\(points)")
        label.fontName = "AvenirNext-Bold"
        label.fontSize = 15
        label.fontColor = .white
        label.position = location
        label.zPosition = 10
        addChild(label)
        label.run(.sequence([
            .group([.moveBy(x: 0, y: 26, duration: 0.6), .fadeOut(withDuration: 0.6)]),
            .removeFromParent(),
        ]))
    }

    private func drainBall() {
        guard let ball else { return }
        self.ball = nil
        ball.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))
        SoundFX.shared.play(.drain)
        onEvent?(.ballDrained)
        if shouldRespawn?() == true {
            run(.sequence([.wait(forDuration: 0.9), .run { [weak self] in self?.spawnBall() }]))
        }
    }
}
