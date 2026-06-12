import SwiftUI
import SpriteKit

/// Shared wrapper for the four sports scenes: hosts the SKScene, pipes
/// `ArcadeEvent`s into the session, and shows a control hint.
private struct SportsSceneView: View {
    @ObservedObject var session: GameSession
    let hint: String
    let hintSymbol: String

    final class SceneHolder: ObservableObject {
        let scene: SportsScene
        init(scene: SportsScene) {
            self.scene = scene
            scene.scaleMode = .aspectFit
        }
    }

    @StateObject private var holder: SceneHolder

    init(session: GameSession, scene: @autoclosure @escaping () -> SportsScene,
         hint: String, hintSymbol: String) {
        self.session = session
        self.hint = hint
        self.hintSymbol = hintSymbol
        _holder = StateObject(wrappedValue: SceneHolder(scene: scene()))
    }

    var body: some View {
        VStack(spacing: 6) {
            SpriteView(scene: holder.scene, options: [.allowsTransparency])
                .aspectRatio(390.0 / 700.0, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.15), lineWidth: 1))
                .padding(.horizontal, 10)

            Label(hint, systemImage: hintSymbol)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
                .padding(.bottom, 4)
        }
        .onAppear {
            let scene = holder.scene
            scene.onEvent = { [weak session] event in
                MainActor.assumeIsolated { session?.submit(.arcade(event)) }
            }
            scene.isGameOver = { [weak session] in
                MainActor.assumeIsolated { session?.game?.isOver ?? true }
            }
        }
    }
}

class SportsScene: SKScene {
    var onEvent: ((ArcadeEvent) -> Void)?
    var isGameOver: (() -> Bool)?

    func floatLabel(_ text: String, at point: CGPoint, color: SKColor = .white) {
        let label = SKLabelNode(text: text)
        label.fontName = "AvenirNext-Bold"
        label.fontSize = 20
        label.fontColor = color
        label.position = point
        label.zPosition = 20
        addChild(label)
        label.run(.sequence([
            .group([.moveBy(x: 0, y: 30, duration: 0.8), .fadeOut(withDuration: 0.8)]),
            .removeFromParent(),
        ]))
    }
}

// MARK: - Field Goal

struct FootballView: View {
    @ObservedObject var session: GameSession
    var body: some View {
        SportsSceneView(session: session,
                        scene: FieldGoalScene(size: CGSize(width: 390, height: 700)),
                        hint: "Swipe up through the ball to kick — watch the wind",
                        hintSymbol: "wind")
    }
}

final class FieldGoalScene: SportsScene {
    private var ball: SKShapeNode!
    private var windLabel: SKLabelNode!
    private var postsCenter = CGPoint(x: 195, y: 560)
    private var wind: CGFloat = 0
    private var distance = 25          // yards, grows with each make
    private var kicking = false
    private var built = false

    override func didMove(to view: SKView) {
        guard !built else { return }
        built = true
        backgroundColor = SKColor(red: 0.07, green: 0.3, blue: 0.12, alpha: 1)

        // Yard stripes with numbers and hash marks.
        for i in 0..<8 {
            let y = 120 + CGFloat(i) * 60
            let stripe = SKShapeNode(rectOf: CGSize(width: size.width, height: 2))
            stripe.position = CGPoint(x: size.width / 2, y: y)
            stripe.fillColor = SKColor(white: 1, alpha: 0.12)
            stripe.strokeColor = .clear
            addChild(stripe)

            let number = SKLabelNode(text: "\(10 + i * 5)")
            number.fontName = "AvenirNext-Bold"
            number.fontSize = 15
            number.fontColor = SKColor(white: 1, alpha: 0.22)
            number.position = CGPoint(x: 28, y: y + 6)
            addChild(number)

            for hashX in [size.width * 0.38, size.width * 0.62] {
                let hash = SKShapeNode(rectOf: CGSize(width: 8, height: 3))
                hash.position = CGPoint(x: hashX, y: y + 30)
                hash.fillColor = SKColor(white: 1, alpha: 0.15)
                hash.strokeColor = .clear
                addChild(hash)
            }
        }

        windLabel = SKLabelNode(text: "")
        windLabel.fontName = "AvenirNext-Bold"
        windLabel.fontSize = 16
        windLabel.position = CGPoint(x: size.width / 2, y: size.height - 50)
        addChild(windLabel)

        buildPosts()
        newKick()
    }

    private var posts: SKNode?

    private func buildPosts() {
        posts?.removeFromParent()
        let node = SKNode()
        // Distance shrinks the posts (perspective-ish).
        let scale = max(0.5, 1.15 - CGFloat(distance) * 0.011)
        let halfWidth = 70 * scale
        let crossbarY = postsCenter.y
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -halfWidth, y: 90 * scale))
        path.addLine(to: CGPoint(x: -halfWidth, y: 0))
        path.addLine(to: CGPoint(x: halfWidth, y: 0))
        path.addLine(to: CGPoint(x: halfWidth, y: 90 * scale))
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: -50 * scale))
        let shape = SKShapeNode(path: path)
        shape.strokeColor = SKColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1)
        shape.lineWidth = 5 * scale
        node.addChild(shape)
        node.position = CGPoint(x: postsCenter.x, y: crossbarY)
        addChild(node)
        posts = node
    }

    private func newKick() {
        guard isGameOver?() != true else { return }
        kicking = false
        wind = CGFloat.random(in: -60...60)
        let arrows = String(repeating: wind < 0 ? "◀" : "▶", count: min(Int(abs(wind)) / 18 + 1, 4))
        windLabel.text = "WIND \(arrows) \(Int(abs(wind / 6))) mph · \(distance) yds"
        ball?.removeFromParent()
        ball = SKShapeNode(ellipseOf: CGSize(width: 26, height: 38))
        ball.fillColor = SKColor(red: 0.55, green: 0.3, blue: 0.15, alpha: 1)
        ball.strokeColor = SKColor(white: 1, alpha: 0.7)
        ball.lineWidth = 2
        ball.position = CGPoint(x: size.width / 2, y: 90)
        addChild(ball)
    }

    private var swipeStart: CGPoint?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        swipeStart = touches.first?.location(in: self)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let start = swipeStart, let end = touches.first?.location(in: self),
              !kicking, ball != nil, isGameOver?() != true else { return }
        swipeStart = nil
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard dy > 50 else { return }
        kicking = true
        SoundFX.shared.play(.launch)

        let power = min(dy / 280, 1.25)
        let driftX = dx * 1.1 + wind * power
        let target = CGPoint(x: ball.position.x + driftX, y: ball.position.y + 480 * power)
        let duration = 1.0
        let goodHeight = power >= 0.78    // enough leg to reach the crossbar

        ball.run(.group([
            .move(to: target, duration: duration),
            .scale(to: 0.45, duration: duration),
            .rotate(byAngle: .pi * 3, duration: duration),
        ])) { [weak self] in
            self?.judgeKick(landing: target, longEnough: goodHeight)
        }
    }

    private func judgeKick(landing: CGPoint, longEnough: Bool) {
        let halfWidth = max(0.5, 1.15 - CGFloat(distance) * 0.011) * 70
        let good = longEnough && abs(landing.x - postsCenter.x) < halfWidth
            && landing.y > postsCenter.y - 30
        if good {
            let points = 3 + max(0, (distance - 25) / 5)
            onEvent?(.score(points))
            SoundFX.shared.play(.win)
            floatLabel("IT'S GOOD! +\(points)", at: CGPoint(x: size.width / 2, y: size.height / 2),
                       color: SKColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1))
            distance += 4
            buildPosts()
        } else {
            SoundFX.shared.play(.error)
            floatLabel(longEnough ? "WIDE!" : "SHORT!",
                       at: CGPoint(x: size.width / 2, y: size.height / 2), color: .red)
        }
        onEvent?(.attempt)
        run(.sequence([.wait(forDuration: 0.8), .run { [weak self] in self?.newKick() }]))
    }
}

// MARK: - Home Run Derby

struct BaseballView: View {
    @ObservedObject var session: GameSession
    var body: some View {
        SportsSceneView(session: session,
                        scene: DerbyScene(size: CGSize(width: 390, height: 700)),
                        hint: "Tap to swing as the pitch crosses the plate",
                        hintSymbol: "figure.baseball")
    }
}

final class DerbyScene: SportsScene {
    private var ball: SKShapeNode?
    private var bat: SKShapeNode!
    private var pitchStart: TimeInterval = 0
    private var pitchDuration: TimeInterval = 1.0
    private var pitchActive = false
    private var swung = false
    private var pitchCount = 0
    private var lastUpdate: TimeInterval = 0
    private var built = false

    private let plateY: CGFloat = 130

    override func didMove(to view: SKView) {
        guard !built else { return }
        built = true
        backgroundColor = SKColor(red: 0.05, green: 0.18, blue: 0.1, alpha: 1)

        // Outfield fence.
        let fence = SKShapeNode(rectOf: CGSize(width: size.width, height: 6))
        fence.position = CGPoint(x: size.width / 2, y: size.height - 90)
        fence.fillColor = SKColor(red: 0.85, green: 0.75, blue: 0.3, alpha: 1)
        fence.strokeColor = .clear
        addChild(fence)
        let sign = SKLabelNode(text: "— 400 ft —")
        sign.fontName = "AvenirNext-Bold"
        sign.fontSize = 14
        sign.fontColor = SKColor(white: 1, alpha: 0.5)
        sign.position = CGPoint(x: size.width / 2, y: size.height - 78)
        addChild(sign)

        // Foul lines fanning out from the plate, plus an infield arc.
        let foulLines = SKShapeNode(path: {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: size.width / 2 - 170, y: plateY + 240))
            path.addLine(to: CGPoint(x: size.width / 2, y: plateY - 16))
            path.addLine(to: CGPoint(x: size.width / 2 + 170, y: plateY + 240))
            return path
        }())
        foulLines.strokeColor = SKColor(white: 1, alpha: 0.25)
        foulLines.lineWidth = 3
        addChild(foulLines)
        let infield = SKShapeNode(path: {
            let path = CGMutablePath()
            path.addArc(center: CGPoint(x: size.width / 2, y: plateY - 16), radius: 150,
                        startAngle: .pi * 0.25, endAngle: .pi * 0.75, clockwise: false)
            return path
        }())
        infield.strokeColor = SKColor(red: 0.75, green: 0.6, blue: 0.4, alpha: 0.4)
        infield.lineWidth = 26
        addChild(infield)

        // Infield diamond + plate.
        let plate = SKShapeNode(rectOf: CGSize(width: 30, height: 10), cornerRadius: 2)
        plate.position = CGPoint(x: size.width / 2, y: plateY - 16)
        plate.fillColor = .white
        plate.strokeColor = .clear
        addChild(plate)

        bat = SKShapeNode(rectOf: CGSize(width: 60, height: 9), cornerRadius: 4.5)
        bat.fillColor = SKColor(red: 0.75, green: 0.55, blue: 0.3, alpha: 1)
        bat.strokeColor = SKColor(white: 1, alpha: 0.5)
        bat.position = CGPoint(x: size.width / 2 + 38, y: plateY)
        bat.zRotation = 0.5
        addChild(bat)

        run(.sequence([.wait(forDuration: 1.0), .run { [weak self] in self?.pitch() }]))
    }

    private func pitch() {
        guard isGameOver?() != true else { return }
        ball?.removeFromParent()
        let ball = SKShapeNode(circleOfRadius: 9)
        ball.fillColor = .white
        ball.strokeColor = SKColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1)
        ball.lineWidth = 1.5
        ball.position = CGPoint(x: size.width / 2 + CGFloat.random(in: -14...14), y: size.height - 140)
        addChild(ball)
        self.ball = ball
        pitchDuration = TimeInterval.random(in: 0.75...1.05)
        pitchStart = 0           // set on first update tick
        pitchActive = true
        swung = false
        ball.run(.move(to: CGPoint(x: ball.position.x, y: plateY), duration: pitchDuration)) { [weak self] in
            self?.crossPlate()
        }
    }

    override func update(_ currentTime: TimeInterval) {
        lastUpdate = currentTime
        if pitchActive && pitchStart == 0 { pitchStart = currentTime }
    }

    private func crossPlate() {
        guard pitchActive else { return }
        pitchActive = false
        if !swung {
            floatLabel("CALLED STRIKE", at: CGPoint(x: size.width / 2, y: size.height / 2),
                       color: .red)
            SoundFX.shared.play(.error)
            finishPitch()
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard pitchActive, !swung, let ball else { return }
        swung = true
        bat.run(.sequence([.rotate(toAngle: -0.9, duration: 0.07),
                           .rotate(toAngle: 0.5, duration: 0.2)]))
        // Timing: perfect contact when the ball is at the plate.
        let remaining = max(ball.position.y - plateY, 0)
        let quality = 1 - min(remaining / 200, 1)          // 1.0 = on the plate
        pitchActive = false
        if quality > 0.55 {
            SoundFX.shared.play(.bumper)
            let feet = Int(220 + quality * 260 + Double.random(in: 0...40))
            let isHomer = feet >= 320
            let targetY = size.height - 90 + (isHomer ? 60 : -80)
            ball.run(.group([
                .move(to: CGPoint(x: ball.position.x + CGFloat.random(in: -110...110), y: targetY),
                      duration: 0.7),
                .scale(to: 0.4, duration: 0.7),
            ]))
            if isHomer {
                onEvent?(.score(feet))
                SoundFX.shared.play(.win)
                floatLabel("HOME RUN! \(feet) ft", at: CGPoint(x: size.width / 2, y: size.height / 2),
                           color: SKColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1))
            } else {
                SoundFX.shared.play(.error)
                floatLabel("\(feet) ft — caught", at: CGPoint(x: size.width / 2, y: size.height / 2))
            }
        } else {
            SoundFX.shared.play(.error)
            floatLabel("WHIFF!", at: CGPoint(x: size.width / 2, y: size.height / 2), color: .red)
        }
        finishPitch()
    }

    private func finishPitch() {
        onEvent?(.attempt)
        run(.sequence([.wait(forDuration: 1.1), .run { [weak self] in self?.pitch() }]))
    }
}

// MARK: - Penalty Shootout

struct SoccerView: View {
    @ObservedObject var session: GameSession
    var body: some View {
        SportsSceneView(session: session,
                        scene: ShootoutScene(size: CGSize(width: 390, height: 700)),
                        hint: "Shoot: swipe at the goal · Save: tap where to dive",
                        hintSymbol: "figure.indoor.soccer")
    }
}

final class ShootoutScene: SportsScene {
    private var ball: SKShapeNode!
    private var keeper: SKShapeNode!
    private var goalRect = CGRect.zero
    private var busy = false
    private var built = false
    /// Mirrors the engine's phase: first 5 you shoot, then 5 you keep.
    private var roundsPlayed = 0
    private var defending: Bool { roundsPlayed >= SoccerGame.roundsPerSide }

    override func didMove(to view: SKView) {
        guard !built else { return }
        built = true
        backgroundColor = SKColor(red: 0.08, green: 0.32, blue: 0.14, alpha: 1)

        goalRect = CGRect(x: 55, y: 520, width: 280, height: 110)
        let goal = SKShapeNode(rect: goalRect)
        goal.strokeColor = .white
        goal.lineWidth = 5
        addChild(goal)

        // Pitch markings: penalty box, arc, and the spot.
        let box = SKShapeNode(rect: CGRect(x: 30, y: 420, width: 330, height: 100))
        box.strokeColor = SKColor(white: 1, alpha: 0.45)
        box.lineWidth = 3
        addChild(box)
        let arc = SKShapeNode(path: {
            let path = CGMutablePath()
            path.addArc(center: CGPoint(x: size.width / 2, y: 420), radius: 60,
                        startAngle: .pi, endAngle: 0, clockwise: true)
            return path
        }())
        arc.strokeColor = SKColor(white: 1, alpha: 0.45)
        arc.lineWidth = 3
        addChild(arc)
        let spot = SKShapeNode(circleOfRadius: 4)
        spot.position = CGPoint(x: size.width / 2, y: 120)
        spot.fillColor = SKColor(white: 1, alpha: 0.6)
        spot.strokeColor = .clear
        addChild(spot)
        // Net lines.
        for i in 1..<8 {
            let line = SKShapeNode(rectOf: CGSize(width: 1, height: goalRect.height))
            line.position = CGPoint(x: goalRect.minX + goalRect.width * CGFloat(i) / 8,
                                    y: goalRect.midY)
            line.fillColor = SKColor(white: 1, alpha: 0.2)
            line.strokeColor = .clear
            addChild(line)
        }

        keeper = SKShapeNode(rectOf: CGSize(width: 46, height: 60), cornerRadius: 12)
        keeper.fillColor = SKColor(red: 0.95, green: 0.65, blue: 0.1, alpha: 1)
        keeper.strokeColor = SKColor(white: 1, alpha: 0.6)
        keeper.position = CGPoint(x: goalRect.midX, y: goalRect.minY + 32)
        addChild(keeper)

        newRound()
    }

    private func newRound() {
        guard isGameOver?() != true else { return }
        busy = false
        keeper.position = CGPoint(x: goalRect.midX, y: goalRect.minY + 32)
        ball?.removeFromParent()
        ball = SKShapeNode(circleOfRadius: 13)
        ball.fillColor = .white
        ball.strokeColor = SKColor(white: 0, alpha: 0.5)
        ball.lineWidth = 1.5
        ball.position = CGPoint(x: size.width / 2, y: defending ? 350 : 120)
        addChild(ball)
        if defending {
            // Bot lines up and shoots after a beat.
            run(.sequence([.wait(forDuration: 1.0), .run { [weak self] in self?.botShoots() }]))
        }
    }

    private var swipeStart: CGPoint?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let location = touches.first?.location(in: self), !busy else { return }
        if defending {
            // Tap a goal zone to dive.
            busy = true
            let dive = min(max(location.x, goalRect.minX + 25), goalRect.maxX - 25)
            keeper.run(.moveTo(x: dive, duration: 0.22))
        } else {
            swipeStart = location
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !defending, let start = swipeStart,
              let end = touches.first?.location(in: self), !busy else { return }
        swipeStart = nil
        let dy = end.y - start.y
        guard dy > 40 else { return }
        busy = true
        SoundFX.shared.play(.launch)

        let targetX = ball.position.x + (end.x - start.x) * 1.6
        let onTarget = goalRect.minX + 14 < targetX && targetX < goalRect.maxX - 14
        // Keeper guesses harder when you shoot down the middle.
        let guess = goalRect.midX + (Bool.random() ? 1 : -1) * CGFloat.random(in: 30...110)
        keeper.run(.sequence([.wait(forDuration: 0.12), .moveTo(x: guess, duration: 0.25)]))

        ball.run(.group([
            .move(to: CGPoint(x: targetX, y: goalRect.minY + 40), duration: 0.45),
            .scale(to: 0.6, duration: 0.45),
        ])) { [weak self] in
            guard let self else { return }
            let saved = abs(targetX - guess) < 42
            if onTarget && !saved {
                self.onEvent?(.score(1))
                SoundFX.shared.play(.win)
                self.floatLabel("GOAL!", at: CGPoint(x: self.size.width / 2, y: 420),
                                color: SKColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1))
            } else {
                SoundFX.shared.play(.error)
                self.floatLabel(onTarget ? "SAVED!" : "WIDE!",
                                at: CGPoint(x: self.size.width / 2, y: 420), color: .red)
            }
            self.onEvent?(.attempt)
            self.roundsPlayed += 1
            self.run(.sequence([.wait(forDuration: 0.9), .run { [weak self] in self?.newRound() }]))
        }
    }

    private func botShoots() {
        guard isGameOver?() != true else { return }
        busy = false   // allow the dive tap while the ball flies
        let targetX = goalRect.minX + 30 + CGFloat.random(in: 0...(goalRect.width - 60))
        SoundFX.shared.play(.launch)
        ball.run(.group([
            .move(to: CGPoint(x: targetX, y: goalRect.minY + 40), duration: 0.55),
            .scale(to: 0.6, duration: 0.55),
        ])) { [weak self] in
            guard let self else { return }
            let saved = abs(targetX - self.keeper.position.x) < 46
            if saved {
                SoundFX.shared.play(.win)
                self.floatLabel("SAVED!", at: CGPoint(x: self.size.width / 2, y: 420),
                                color: SKColor(red: 0.4, green: 0.9, blue: 0.5, alpha: 1))
            } else {
                self.onEvent?(.opponentScore(1))
                SoundFX.shared.play(.error)
                self.floatLabel("They score", at: CGPoint(x: self.size.width / 2, y: 420), color: .red)
            }
            self.onEvent?(.attempt)
            self.busy = true
            self.run(.sequence([.wait(forDuration: 0.9), .run { [weak self] in self?.newRound() }]))
        }
    }
}

// MARK: - Air Hockey

struct HockeyView: View {
    @ObservedObject var session: GameSession
    var body: some View {
        SportsSceneView(session: session,
                        scene: AirHockeyScene(size: CGSize(width: 390, height: 700)),
                        hint: "Drag your striker — first to 7",
                        hintSymbol: "hockey.puck.fill")
    }
}

final class AirHockeyScene: SportsScene {
    enum Category {
        static let puck: UInt32 = 1 << 0
        static let wall: UInt32 = 1 << 1
        static let striker: UInt32 = 1 << 2
    }

    private var puck: SKShapeNode!
    private var you: SKShapeNode!
    private var bot: SKShapeNode!
    private var goalWidth: CGFloat = 130
    private var serving = false
    private var lastUpdate: TimeInterval = 0
    private var built = false
    private var myGoals = 0
    private var botGoals = 0
    /// Rubber-banding: the bot skates harder when you're ahead.
    private var botSpeed: CGFloat {
        min(max(230 + CGFloat(myGoals - botGoals) * 16, 180), 330)
    }

    override func didMove(to view: SKView) {
        guard !built else { return }
        built = true
        backgroundColor = SKColor(red: 0.88, green: 0.92, blue: 0.96, alpha: 1)
        physicsWorld.gravity = .zero

        // Rink markings.
        let center = SKShapeNode(circleOfRadius: 55)
        center.position = CGPoint(x: size.width / 2, y: size.height / 2)
        center.strokeColor = SKColor(red: 0.8, green: 0.2, blue: 0.25, alpha: 0.5)
        center.lineWidth = 3
        addChild(center)
        let midline = SKShapeNode(rectOf: CGSize(width: size.width, height: 3))
        midline.position = CGPoint(x: size.width / 2, y: size.height / 2)
        midline.fillColor = SKColor(red: 0.8, green: 0.2, blue: 0.25, alpha: 0.5)
        midline.strokeColor = .clear
        addChild(midline)

        // Walls with goal gaps top and bottom.
        let gap = goalWidth / 2
        let mid = size.width / 2
        for (a, b) in [(CGPoint(x: 6, y: 6), CGPoint(x: 6, y: size.height - 6)),
                       (CGPoint(x: size.width - 6, y: 6), CGPoint(x: size.width - 6, y: size.height - 6)),
                       (CGPoint(x: 6, y: size.height - 6), CGPoint(x: mid - gap, y: size.height - 6)),
                       (CGPoint(x: mid + gap, y: size.height - 6), CGPoint(x: size.width - 6, y: size.height - 6)),
                       (CGPoint(x: 6, y: 6), CGPoint(x: mid - gap, y: 6)),
                       (CGPoint(x: mid + gap, y: 6), CGPoint(x: size.width - 6, y: 6))] {
            let path = CGMutablePath()
            path.move(to: a)
            path.addLine(to: b)
            let wall = SKNode()
            wall.physicsBody = SKPhysicsBody(edgeChainFrom: path)
            wall.physicsBody!.friction = 0
            wall.physicsBody!.restitution = 0.92
            wall.physicsBody!.categoryBitMask = Category.wall
            addChild(wall)
            let stroke = SKShapeNode(path: path)
            stroke.strokeColor = SKColor(red: 0.2, green: 0.3, blue: 0.5, alpha: 0.8)
            stroke.lineWidth = 4
            addChild(stroke)
        }

        you = striker(color: SKColor(red: 0.2, green: 0.45, blue: 0.9, alpha: 1))
        you.position = CGPoint(x: mid, y: 110)
        addChild(you)
        bot = striker(color: SKColor(red: 0.85, green: 0.25, blue: 0.25, alpha: 1))
        bot.position = CGPoint(x: mid, y: size.height - 110)
        addChild(bot)

        servePuck(towardBot: Bool.random())
    }

    private func striker(color: SKColor) -> SKShapeNode {
        let node = SKShapeNode(circleOfRadius: 30)
        node.fillColor = color
        node.strokeColor = SKColor(white: 1, alpha: 0.7)
        node.lineWidth = 3
        let body = SKPhysicsBody(circleOfRadius: 30)
        body.isDynamic = false
        body.friction = 0
        body.restitution = 1.0
        body.categoryBitMask = Category.striker
        node.physicsBody = body
        let cap = SKShapeNode(circleOfRadius: 14)
        cap.fillColor = SKColor(white: 1, alpha: 0.35)
        cap.strokeColor = .clear
        node.addChild(cap)
        return node
    }

    private func servePuck(towardBot: Bool) {
        guard isGameOver?() != true else { return }
        puck?.removeFromParent()
        puck = SKShapeNode(circleOfRadius: 17)
        puck.fillColor = SKColor(white: 0.12, alpha: 1)
        puck.strokeColor = SKColor(white: 0.4, alpha: 1)
        puck.lineWidth = 2
        puck.position = CGPoint(x: size.width / 2,
                                y: size.height / 2 + (towardBot ? 60 : -60))
        let body = SKPhysicsBody(circleOfRadius: 17)
        body.friction = 0
        body.restitution = 0.95
        body.linearDamping = 0.25
        body.allowsRotation = false
        body.usesPreciseCollisionDetection = true
        body.categoryBitMask = Category.puck
        body.collisionBitMask = Category.wall | Category.striker
        puck.physicsBody = body
        addChild(puck)
        serving = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { steer(touches) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { steer(touches) }

    private func steer(_ touches: Set<UITouch>) {
        guard let location = touches.first?.location(in: self) else { return }
        let x = min(max(location.x, 40), size.width - 40)
        let y = min(max(location.y, 40), size.height / 2 - 34)
        // Manual velocity so the static striker still slaps the puck hard.
        let before = you.position
        you.position = CGPoint(x: x, y: y)
        slapPuck(strikerAt: you.position, previous: before)
    }

    private var lastHitSound: TimeInterval = 0

    private func slapPuck(strikerAt position: CGPoint, previous: CGPoint) {
        guard let body = puck?.physicsBody else { return }
        let dx = puck.position.x - position.x
        let dy = puck.position.y - position.y
        let distance = sqrt(dx * dx + dy * dy)
        guard distance < 49 else { return }
        let speed = max(hypot(position.x - previous.x, position.y - previous.y) * 28, 240)
        body.velocity = CGVector(dx: dx / max(distance, 1) * speed,
                                 dy: dy / max(distance, 1) * speed)
        if lastUpdate - lastHitSound > 0.12 {
            lastHitSound = lastUpdate
            SoundFX.shared.play(.paddleHit)
        }
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 0 : min(currentTime - lastUpdate, 0.05)
        lastUpdate = currentTime
        guard let puck, !serving else { return }

        // Bot striker: track the puck in its half, return to guard the goal.
        let botTarget: CGPoint
        if puck.position.y > size.height / 2 {
            botTarget = CGPoint(x: puck.position.x, y: min(puck.position.y + 26, size.height - 60))
        } else {
            botTarget = CGPoint(x: size.width / 2, y: size.height - 110)
        }
        let bdx = botTarget.x - bot.position.x
        let bdy = botTarget.y - bot.position.y
        let bDist = max(hypot(bdx, bdy), 0.01)
        let step = min(botSpeed * CGFloat(dt), bDist)
        let before = bot.position
        bot.position = CGPoint(x: bot.position.x + bdx / bDist * step,
                               y: max(bot.position.y + bdy / bDist * step, size.height / 2 + 34))
        slapPuck(strikerAt: bot.position, previous: before)

        // Goals.
        if puck.position.y > size.height + 10 {
            scoreGoal(mine: true)
        } else if puck.position.y < -10 {
            scoreGoal(mine: false)
        }
        // Anti-stall nudge.
        if let body = puck.physicsBody {
            let speed = hypot(body.velocity.dx, body.velocity.dy)
            if speed < 30 {
                body.velocity = CGVector(dx: body.velocity.dx + CGFloat.random(in: -40...40),
                                         dy: body.velocity.dy + CGFloat.random(in: -40...40))
            }
        }
    }

    private func scoreGoal(mine: Bool) {
        guard !serving else { return }
        serving = true
        if mine { myGoals += 1 } else { botGoals += 1 }
        SoundFX.shared.play(mine ? .win : .lifeLost)
        floatLabel(mine ? "GOAL!" : "Bot scores",
                   at: CGPoint(x: size.width / 2, y: size.height / 2),
                   color: mine ? SKColor(red: 0.2, green: 0.45, blue: 0.9, alpha: 1)
                               : SKColor(red: 0.85, green: 0.25, blue: 0.25, alpha: 1))
        onEvent?(mine ? .score(1) : .opponentScore(1))
        run(.sequence([.wait(forDuration: 0.9), .run { [weak self] in
            self?.servePuck(towardBot: !mine)
        }]))
    }
}
