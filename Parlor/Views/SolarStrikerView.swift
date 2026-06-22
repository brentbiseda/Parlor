import SwiftUI
import SpriteKit

// MARK: - Solar Striker View

struct SolarStrikerView: View {
    @ObservedObject var session: GameSession

    final class SceneHolder: ObservableObject {
        let scene = SolarStrikerScene(size: CGSize(width: 390, height: 700))
        init() { scene.scaleMode = .aspectFit }
    }

    @StateObject private var holder = SceneHolder()
    @State private var waveBanner: String? = nil
    @State private var waveBannerOpacity: Double = 0

    var game: SolarStrikerGame? { session.game?.engine as? SolarStrikerGame }

    var body: some View {
        VStack(spacing: 6) {
            if let g = game { strikerHeader(g).padding(.horizontal, 12) }

            SpriteView(scene: holder.scene, options: [.allowsTransparency])
                .aspectRatio(390.0 / 700.0, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.15), lineWidth: 1))
                .overlay(alignment: .top) { bannerOverlay }
                .overlay(alignment: .bottom) {
                    if let g = game, g.isBossWave { bossHealthBar(g).padding(.bottom, 12) }
                }
                .padding(.horizontal, 10)

            Label("Drag to steer  ·  ship fires automatically", systemImage: "hand.draw.fill")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
                .padding(.bottom, 4)
        }
        .onAppear {
            let scene = holder.scene
            scene.onSolarEvent = { [weak session] event in
                MainActor.assumeIsolated { session?.submit(.solar(event)) }
            }
            scene.shouldContinue = { [weak session] in
                MainActor.assumeIsolated {
                    (session?.game?.engine as? SolarStrikerGame)?.isOver == false
                }
            }
        }
        .onChange(of: game?.level) { _, newLevel in
            guard let newLevel, let g = game else { return }
            let isBoss = newLevel % 5 == 1 && newLevel > 1
            waveBanner = isBoss ? "⚠️ BOSS WAVE \(newLevel)!" : "WAVE \(newLevel)"
            withAnimation(.easeIn(duration: 0.3)) { waveBannerOpacity = 1.0 }
            Task { @MainActor in
                do {
                    try await Task.sleep(nanoseconds: 1_600_000_000)
                    withAnimation(.easeOut(duration: 0.5)) { waveBannerOpacity = 0 }
                    try await Task.sleep(nanoseconds: 500_000_000)
                    waveBanner = nil
                } catch { return }
            }
            _ = g
        }
    }

    @ViewBuilder
    private var bannerOverlay: some View {
        if let banner = waveBanner {
            Text(banner)
                .font(.title2.weight(.black))
                .foregroundStyle(.yellow)
                .shadow(color: .orange.opacity(0.8), radius: 8)
                .padding(.horizontal, 20).padding(.vertical, 8)
                .background(.black.opacity(0.75), in: Capsule())
                .padding(.top, 16)
                .opacity(waveBannerOpacity)
                .animation(.easeInOut(duration: 0.4), value: waveBannerOpacity)
        }
    }

    @ViewBuilder
    private func bossHealthBar(_ game: SolarStrikerGame) -> some View {
        if game.bossMaxHP > 0 {
            VStack(spacing: 3) {
                Text("BOSS").font(.system(size: 9, weight: .black)).kerning(2)
                    .foregroundStyle(.red.opacity(0.9))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(.red.opacity(0.18)).frame(height: 10)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(max(0, game.bossCurrentHP)) / CGFloat(game.bossMaxHP), height: 10)
                            .animation(.easeOut(duration: 0.25), value: game.bossCurrentHP)
                    }
                }
                .frame(height: 10)
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private func strikerHeader(_ game: SolarStrikerGame) -> some View {
        let cyan = Color(red: 0.3, green: 0.8, blue: 1.0)
        HStack(spacing: 6) {
            // Lives pill
            HStack(spacing: 0) {
                Text("LIVES")
                    .font(.system(size: 7, weight: .black)).kerning(0.8)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.trailing, 4)
                HStack(spacing: 2) {
                    ForEach(0..<SolarStrikerGame.livesPerGame, id: \.self) { i in
                        Image(systemName: i < game.livesLeft ? "diamond.fill" : "diamond")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(i < game.livesLeft ? cyan : .white.opacity(0.18))
                            .shadow(color: i < game.livesLeft ? cyan.opacity(0.7) : .clear, radius: 3)
                    }
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 8).strokeBorder(cyan.opacity(0.25), lineWidth: 0.75)
                }
            )

            // Score pill
            HStack(spacing: 3) {
                Image(systemName: "star.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.yellow.opacity(0.8))
                Text("\(game.score)")
                    .font(.system(size: 14, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 8).strokeBorder(.yellow.opacity(0.2), lineWidth: 0.75)
                }
            )

            Spacer(minLength: 0)

            // Weapon indicator
            if game.currentWeapon != .standard {
                let wc = weaponColor(game.currentWeapon)
                Label(game.currentWeapon.displayName, systemImage: game.currentWeapon.icon)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(wc)
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(wc.opacity(0.18), in: Capsule())
                    .overlay(Capsule().strokeBorder(wc.opacity(0.55), lineWidth: 0.75))
                    .shadow(color: wc.opacity(0.4), radius: 5)
            }
            if game.hasMultiplier {
                Text("×2")
                    .font(.caption.weight(.black)).foregroundStyle(.yellow)
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(.yellow.opacity(0.18), in: Capsule())
                    .overlay(Capsule().strokeBorder(.yellow.opacity(0.6), lineWidth: 0.75))
                    .shadow(color: .yellow.opacity(0.4), radius: 5)
            }

            // Wave chip
            HStack(spacing: 3) {
                if game.isBossWave {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 7)).foregroundStyle(.red)
                }
                Text("W\(game.level)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(game.isBossWave ? .red : cyan)
            }
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background((game.isBossWave ? Color.red : cyan).opacity(0.15), in: Capsule())
            .overlay(Capsule().strokeBorder((game.isBossWave ? Color.red : cyan).opacity(0.4), lineWidth: 0.75))

            if game.longestStreak >= 5 {
                Text("🔥\(game.longestStreak)")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .background(.orange.opacity(0.14), in: Capsule())
            }
        }
        .frame(minHeight: 36)
        .padding(.vertical, 4).padding(.horizontal, 6)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.35))
                RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.08), lineWidth: 0.75)
            }
        )
    }

    private func weaponColor(_ w: SolarWeapon) -> Color {
        switch w.tintName {
        case "purple": return Color(red: 0.75, green: 0.38, blue: 0.98)
        case "yellow": return Color(red: 0.98, green: 0.82, blue: 0.15)
        case "green":  return Color(red: 0.22, green: 0.88, blue: 0.45)
        case "orange": return Color(red: 0.95, green: 0.55, blue: 0.15)
        default:       return .white
        }
    }
}

// MARK: - SpriteKit Scene

final class SolarStrikerScene: SKScene {
    var onSolarEvent: ((SolarEvent) -> Void)?
    var shouldContinue: (() -> Bool)?

    // Constants
    private let cols = 6
    private let baseRows = 3

    // Player
    private var playerShip: SKShapeNode!
    private var engineGlow: SKShapeNode!
    private var shieldRing: SKShapeNode?
    private var hasShield = false

    // Weapon state
    private var currentWeapon: SolarWeapon = .standard
    private var weaponTimer: TimeInterval = 0
    private var hasMultiplier = false
    private var multiplierTimer: TimeInterval = 0
    private var homingMissiles: [(node: SKShapeNode, targetIdx: Int?, x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat)] = []

    // Laser
    private var laserBeam: SKShapeNode?
    private var laserActive = false

    // Bullets
    private var playerBullets: [(node: SKShapeNode, y: CGFloat, x: CGFloat, vy: CGFloat, vx: CGFloat)] = []
    private var enemyBullets: [(node: SKShapeNode, x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat)] = []

    // Enemy types: 0=regular, 1=armored, 2=zigzag, 3=shieldCarrier, 4=boss
    private struct EnemyData {
        var col: Int; var row: Int; var hp: Int; var maxHP: Int; var kind: Int
        var node: SKShapeNode; var hpLabel: SKLabelNode?
        var fireTimer: TimeInterval; var phase: Int; var phaseHP: [Int]
        var hasShield: Bool; var shieldNode: SKShapeNode?
        var zigzagPhase: CGFloat    // for zigzag motion
        var x: CGFloat; var y: CGFloat  // explicit position for independent movers
    }
    private var enemies: [EnemyData] = []

    // Formation
    private var formX: CGFloat = 0; private var formDir: CGFloat = 1
    private var formY: CGFloat = 0; private var formStepTimer: TimeInterval = 0

    // Power-ups: 0=triple, 1=shield, 2=rapid, 3=laser, 4=bomb, 5=multiplier
    private struct PowerUp {
        var node: SKShapeNode; var label: SKLabelNode; var x: CGFloat; var y: CGFloat; var kind: Int
    }
    private var powerUps: [PowerUp] = []

    // Parallax stars
    private var starLayer1: [SKShapeNode] = []   // slow
    private var starLayer2: [SKShapeNode] = []   // fast
    private var fireAccumulator: TimeInterval = 0
    private var lastUpdate: TimeInterval = 0
    private var wave = 1; private var built = false
    private var dying = false; private var deathTimer: TimeInterval = 0
    private var bossPhase = 0
    private var bossFirePattern = 0
    private var bossFireTimer: TimeInterval = 0
    private var zigzagTime: CGFloat = 0

    // Boss tracking
    private var bossMaxHP = 0
    private var bossCurrentHP = 0

    private var cellW: CGFloat { size.width / CGFloat(cols + 2) }
    private var cellH: CGFloat { 52 }
    private var formBaseX: CGFloat { cellW }
    private var formBaseY: CGFloat { size.height - 95 }
    private var formSpeed: CGFloat { 38 + CGFloat(wave - 1) * 7 }
    private var formStepInterval: TimeInterval { max(0.65 - Double(wave - 1) * 0.04, 0.28) }
    private var enemyBulletSpeed: CGFloat { 170 + CGFloat(wave - 1) * 16 }
    private var enemyFireRate: TimeInterval { max(2.4 - Double(wave - 1) * 0.16, 0.7) }
    private var fireRate: TimeInterval {
        switch currentWeapon {
        case .rapid:  return 0.14
        case .laser:  return 0.08
        default:      return 0.28
        }
    }

    // MARK: - Setup

    override func didMove(to view: SKView) {
        guard !built else { return }
        built = true
        backgroundColor = SKColor(red: 0.01, green: 0.02, blue: 0.08, alpha: 1)
        seedStars()
        buildPlayer()
        spawnWave()
    }

    private func seedStars() {
        for _ in 0..<45 {
            let node = SKShapeNode(circleOfRadius: CGFloat.random(in: 0.5...1.2))
            node.fillColor = SKColor(white: 1, alpha: CGFloat.random(in: 0.25...0.65))
            node.strokeColor = .clear
            node.position = CGPoint(x: CGFloat.random(in: 0...size.width),
                                    y: CGFloat.random(in: 0...size.height))
            node.zPosition = 0
            addChild(node)
            starLayer1.append(node)
        }
        for _ in 0..<20 {
            let node = SKShapeNode(circleOfRadius: CGFloat.random(in: 0.5...2.0))
            node.fillColor = SKColor(red: CGFloat.random(in: 0.7...1.0),
                                     green: CGFloat.random(in: 0.7...1.0),
                                     blue: 1.0, alpha: CGFloat.random(in: 0.4...0.9))
            node.strokeColor = .clear
            node.position = CGPoint(x: CGFloat.random(in: 0...size.width),
                                    y: CGFloat.random(in: 0...size.height))
            node.zPosition = 0
            addChild(node)
            starLayer2.append(node)
        }
    }

    private func buildPlayer() {
        playerShip = SKShapeNode(path: shipPath(size: 20))
        playerShip.fillColor = SKColor(red: 0.35, green: 0.65, blue: 1.0, alpha: 1)
        playerShip.strokeColor = SKColor(red: 0.7, green: 0.9, blue: 1.0, alpha: 1)
        playerShip.lineWidth = 1.5
        playerShip.position = CGPoint(x: size.width / 2, y: 68)
        playerShip.zPosition = 10
        addChild(playerShip)

        // Engine exhaust
        engineGlow = SKShapeNode(path: exhaustPath())
        engineGlow.fillColor = SKColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 0.6)
        engineGlow.strokeColor = .clear
        engineGlow.position = CGPoint(x: 0, y: -22)
        engineGlow.zPosition = -1
        playerShip.addChild(engineGlow)
        engineGlow.run(.repeatForever(.sequence([
            .scale(to: CGFloat.random(in: 0.7...1.3), duration: 0.08),
            .scale(to: CGFloat.random(in: 0.6...1.1), duration: 0.08),
        ])))

        // Wing lights
        for side in [-1, 1] as [CGFloat] {
            let light = SKShapeNode(circleOfRadius: 2.5)
            light.fillColor = SKColor(red: 0.3, green: 0.9, blue: 1.0, alpha: 1)
            light.strokeColor = .clear
            light.position = CGPoint(x: 14 * side, y: -6)
            playerShip.addChild(light)
            light.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.2, duration: 0.4),
                .fadeAlpha(to: 1.0, duration: 0.4),
            ])))
        }
    }

    private func shipPath(size s: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: s))
        p.addLine(to: CGPoint(x: s * 0.65, y: -s * 0.35))
        p.addLine(to: CGPoint(x: s * 0.95, y: -s * 0.45))
        p.addLine(to: CGPoint(x: s * 0.3, y: -s * 0.2))
        p.addLine(to: CGPoint(x: 0, y: -s * 0.65))
        p.addLine(to: CGPoint(x: -s * 0.3, y: -s * 0.2))
        p.addLine(to: CGPoint(x: -s * 0.95, y: -s * 0.45))
        p.addLine(to: CGPoint(x: -s * 0.65, y: -s * 0.35))
        p.closeSubpath()
        return p
    }

    private func exhaustPath() -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -6, y: 0))
        p.addLine(to: CGPoint(x: 6, y: 0))
        p.addLine(to: CGPoint(x: 3, y: -18))
        p.addLine(to: CGPoint(x: 0, y: -24))
        p.addLine(to: CGPoint(x: -3, y: -18))
        p.closeSubpath()
        return p
    }

    // MARK: - Wave spawning

    private func spawnWave() {
        clearEnemies()
        formX = 0; formY = 0; formDir = 1; formStepTimer = 0
        enemyBullets.forEach { $0.node.removeFromParent() }
        enemyBullets.removeAll()
        homingMissiles.forEach { $0.node.removeFromParent() }
        homingMissiles.removeAll()
        bossPhase = 0; bossFireTimer = 0; bossFirePattern = 0

        let isBoss = wave % 5 == 0
        if isBoss { spawnBoss() } else { spawnFormation() }
    }

    private func spawnFormation() {
        let rowCount = min(baseRows + (wave - 1) / 3, 5)
        zigzagTime = 0
        for row in 0..<rowCount {
            for col in 0..<cols {
                let kind: Int
                if wave >= 8 && row == 0 { kind = 3 }          // shield carriers at front
                else if wave >= 5 && row == 0 { kind = 2 }     // zigzag row
                else if wave >= 3 && row <= 1 { kind = 1 }     // armored
                else { kind = 0 }
                addEnemy(col: col, row: row, kind: kind)
            }
        }
    }

    private func spawnBoss() {
        let tier = wave / 5
        let hp = 8 + tier * 6
        bossMaxHP = hp; bossCurrentHP = hp
        let phaseHP = [hp, hp * 2 / 3, hp / 3]

        let node = SKShapeNode(path: bossPath(tier: tier))
        node.fillColor = bossColor(tier: tier)
        node.strokeColor = SKColor(red: 1.0, green: 0.6, blue: 0.7, alpha: 1)
        node.lineWidth = 2.5
        node.position = CGPoint(x: size.width / 2, y: formBaseY - 30)
        node.zPosition = 5
        addChild(node)

        // Pulsing outer ring
        let ring = SKShapeNode(circleOfRadius: 42)
        ring.fillColor = .clear
        ring.strokeColor = SKColor(red: 1.0, green: 0.3, blue: 0.4, alpha: 0.6)
        ring.lineWidth = 2
        ring.run(.repeatForever(.sequence([.fadeAlpha(to: 0.1, duration: 0.6), .fadeAlpha(to: 0.8, duration: 0.6)])))
        node.addChild(ring)

        let hpLabel = SKLabelNode(text: "\(hp)")
        hpLabel.fontName = "AvenirNext-Bold"; hpLabel.fontSize = 14
        hpLabel.fontColor = .white; hpLabel.verticalAlignmentMode = .center
        node.addChild(hpLabel)

        enemies.append(EnemyData(col: 2, row: 0, hp: hp, maxHP: hp, kind: 4,
                                  node: node, hpLabel: hpLabel,
                                  fireTimer: 0.8, phase: 0, phaseHP: phaseHP,
                                  hasShield: false, shieldNode: nil,
                                  zigzagPhase: 0, x: node.position.x, y: node.position.y))
        onSolarEvent?(.bossHP(current: hp, max: hp))
    }

    private func addEnemy(col: Int, row: Int, kind: Int) {
        let (path, color) = enemyAppearance(kind)
        let node = SKShapeNode(path: path)
        node.fillColor = color
        node.strokeColor = SKColor(white: 1, alpha: 0.35)
        node.lineWidth = 1
        let hp = [1, 2, 1, 2][min(kind, 3)]
        let pos = gridPosition(col: col, row: row)
        node.position = pos
        node.zPosition = 5
        addChild(node)

        var shieldNode: SKShapeNode? = nil
        var hasShield = false
        if kind == 3 {
            hasShield = true
            let sr = SKShapeNode(circleOfRadius: 20)
            sr.fillColor = .clear
            sr.strokeColor = SKColor(red: 0.4, green: 0.9, blue: 1.0, alpha: 0.8)
            sr.lineWidth = 2
            sr.run(.repeatForever(.sequence([.fadeAlpha(to: 0.3, duration: 0.5), .fadeAlpha(to: 1.0, duration: 0.5)])))
            node.addChild(sr)
            shieldNode = sr
        }

        enemies.append(EnemyData(col: col, row: row, hp: hp, maxHP: hp, kind: kind,
                                  node: node, hpLabel: nil,
                                  fireTimer: Double.random(in: 0.5...enemyFireRate), phase: 0, phaseHP: [],
                                  hasShield: hasShield, shieldNode: shieldNode,
                                  zigzagPhase: CGFloat(col) * 0.4, x: pos.x, y: pos.y))
    }

    private func enemyAppearance(_ kind: Int) -> (CGPath, SKColor) {
        switch kind {
        case 1: return (hexPath(r: 16), SKColor(red: 0.9, green: 0.6, blue: 0.2, alpha: 1))
        case 2: return (arrowPath(), SKColor(red: 0.6, green: 0.9, blue: 0.4, alpha: 1))
        case 3: return (diamondPath(s: 16), SKColor(red: 0.4, green: 0.8, blue: 0.95, alpha: 1))
        default: return (chevronPath(), SKColor(red: 0.35, green: 0.9, blue: 0.45, alpha: 1))
        }
    }

    private func bossColor(tier: Int) -> SKColor {
        let colors: [SKColor] = [
            SKColor(red: 0.85, green: 0.2, blue: 0.35, alpha: 1),
            SKColor(red: 0.6, green: 0.1, blue: 0.8, alpha: 1),
            SKColor(red: 0.9, green: 0.45, blue: 0.1, alpha: 1),
        ]
        return colors[min(tier - 1, colors.count - 1)]
    }

    private func gridPosition(col: Int, row: Int) -> CGPoint {
        CGPoint(x: formBaseX + CGFloat(col) * cellW + formX,
                y: formBaseY - CGFloat(row) * cellH - formY)
    }

    private func clearEnemies() {
        enemies.forEach { $0.node.removeFromParent(); $0.shieldNode?.removeFromParent() }
        enemies.removeAll()
    }

    // MARK: - Enemy paths

    private func chevronPath() -> CGPath {
        let s: CGFloat = 13, p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: -s))
        p.addLine(to: CGPoint(x: s * 0.65, y: 0))
        p.addLine(to: CGPoint(x: s * 0.95, y: s))
        p.addLine(to: CGPoint(x: -s * 0.95, y: s))
        p.addLine(to: CGPoint(x: -s * 0.65, y: 0))
        p.closeSubpath(); return p
    }
    private func hexPath(r: CGFloat) -> CGPath {
        let p = CGMutablePath()
        for i in 0..<6 {
            let a = CGFloat(i) * .pi / 3 - .pi / 6
            let pt = CGPoint(x: cos(a) * r, y: sin(a) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath(); return p
    }
    private func arrowPath() -> CGPath {
        let s: CGFloat = 13, p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: s))
        p.addLine(to: CGPoint(x: s * 0.7, y: -s * 0.3))
        p.addLine(to: CGPoint(x: s * 0.3, y: 0))
        p.addLine(to: CGPoint(x: s * 0.7, y: -s))
        p.addLine(to: CGPoint(x: 0, y: -s * 0.4))
        p.addLine(to: CGPoint(x: -s * 0.7, y: -s))
        p.addLine(to: CGPoint(x: -s * 0.3, y: 0))
        p.addLine(to: CGPoint(x: -s * 0.7, y: -s * 0.3))
        p.closeSubpath(); return p
    }
    private func diamondPath(s: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: s)); p.addLine(to: CGPoint(x: s, y: 0))
        p.addLine(to: CGPoint(x: 0, y: -s)); p.addLine(to: CGPoint(x: -s, y: 0))
        p.closeSubpath(); return p
    }
    private func bossPath(tier: Int) -> CGPath {
        let s: CGFloat = 36 + CGFloat(tier) * 4
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: -s * 0.9))
        p.addLine(to: CGPoint(x: s * 0.45, y: -s * 0.25))
        p.addLine(to: CGPoint(x: s * 1.05, y: s * 0.25))
        p.addLine(to: CGPoint(x: s * 0.55, y: s * 0.95))
        p.addLine(to: CGPoint(x: -s * 0.55, y: s * 0.95))
        p.addLine(to: CGPoint(x: -s * 1.05, y: s * 0.25))
        p.addLine(to: CGPoint(x: -s * 0.45, y: -s * 0.25))
        p.closeSubpath(); return p
    }

    // MARK: - Controls

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { steer(touches) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { steer(touches) }

    private func steer(_ touches: Set<UITouch>) {
        guard let touch = touches.first, !dying else { return }
        let x = touch.location(in: self).x
        let newX = max(22, min(size.width - 22, x))
        let dx = newX - playerShip.position.x
        playerShip.position.x = newX
        playerShip.zRotation = -dx * 0.008
        run(.sequence([.wait(forDuration: 0.1), .run { [weak self] in
            self?.playerShip.run(.rotate(toAngle: 0, duration: 0.15))
        }]))
    }

    // MARK: - Game Loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 0 : min(currentTime - lastUpdate, 0.05)
        lastUpdate = currentTime
        if dying { deathTimer -= dt; if deathTimer <= 0 { dying = false }; return }
        guard shouldContinue?() != false else { return }

        zigzagTime += CGFloat(dt) * 3.0
        tickStars(dt)
        tickWeaponTimers(dt)
        tickFormation(dt)
        tickBoss(dt)
        tickPlayerFire(dt)
        tickPlayerBullets(dt)
        tickHomingMissiles(dt)
        tickLaser(dt)
        tickEnemyFire(dt)
        tickEnemyBullets(dt)
        tickPowerUps(dt)
    }

    private func tickStars(_ dt: TimeInterval) {
        for node in starLayer1 {
            node.position.y -= 30 * CGFloat(dt)
            if node.position.y < 0 { node.position.y = size.height; node.position.x = CGFloat.random(in: 0...size.width) }
        }
        for node in starLayer2 {
            node.position.y -= 70 * CGFloat(dt)
            if node.position.y < 0 { node.position.y = size.height; node.position.x = CGFloat.random(in: 0...size.width) }
        }
    }

    private func tickWeaponTimers(_ dt: TimeInterval) {
        if currentWeapon != .standard {
            weaponTimer -= dt
            if weaponTimer <= 0 { currentWeapon = .standard; weaponTimer = 0 }
        }
        if hasMultiplier {
            multiplierTimer -= dt
            if multiplierTimer <= 0 { hasMultiplier = false }
        }
    }

    private func tickFormation(_ dt: TimeInterval) {
        guard !enemies.isEmpty else { return }
        let isBossWave = enemies.first?.kind == 4
        if isBossWave { return }   // boss movement handled separately

        let width = CGFloat(cols - 1) * cellW
        let leftEdge = formBaseX + formX
        let rightEdge = formBaseX + formX + width

        formStepTimer -= dt
        if formStepTimer <= 0 {
            formStepTimer = formStepInterval
            if (formDir > 0 && rightEdge > size.width - 22) || (formDir < 0 && leftEdge < 22) {
                formDir *= -1; formY += 16
                if formBaseY - formY < 160 { playerHit(); return }
            } else {
                formX += formDir * cellW * 0.52
            }
        }

        for i in enemies.indices {
            let e = enemies[i]
            if e.kind == 2 {
                // Zigzag enemies oscillate horizontally
                let base = gridPosition(col: e.col, row: e.row)
                let offset = sin(zigzagTime + e.zigzagPhase) * 24
                enemies[i].x = base.x + offset
                enemies[i].y = base.y
                enemies[i].node.position = CGPoint(x: enemies[i].x, y: enemies[i].y)
            } else {
                let pos = gridPosition(col: e.col, row: e.row)
                enemies[i].x = pos.x; enemies[i].y = pos.y
                enemies[i].node.position = pos
            }
        }
    }

    private func tickBoss(_ dt: TimeInterval) {
        guard var boss = enemies.first, boss.kind == 4 else { return }
        let idx = 0

        // Boss movement: sinusoidal side-to-side
        boss.x = size.width / 2 + sin(CGFloat(lastUpdate) * CGFloat(0.8 + Double(bossPhase) * 0.3)) * (size.width * 0.35)
        boss.y = formBaseY - 40 - CGFloat(bossPhase) * 20
        enemies[idx].x = boss.x; enemies[idx].y = boss.y
        enemies[idx].node.position = CGPoint(x: boss.x, y: boss.y)

        // Boss phase transitions
        let newPhase: Int
        if boss.hp > boss.phaseHP[safe: 1] ?? boss.maxHP * 2 / 3 { newPhase = 0 }
        else if boss.hp > boss.phaseHP[safe: 2] ?? boss.maxHP / 3 { newPhase = 1 }
        else { newPhase = 2 }
        if newPhase != bossPhase {
            bossPhase = newPhase
            flashBossPhase(node: boss.node, phase: newPhase)
        }
        enemies[idx].phase = bossPhase

        // Boss firing
        bossFireTimer -= dt
        if bossFireTimer <= 0 {
            let rateBase = [2.2, 1.5, 0.9][bossPhase]
            bossFireTimer = rateBase
            fireBossPattern(from: CGPoint(x: boss.x, y: boss.y))
            bossFirePattern = (bossFirePattern + 1) % 3
        }
    }

    private func flashBossPhase(node: SKShapeNode, phase: Int) {
        let colors: [SKColor] = [
            SKColor(red: 0.85, green: 0.2, blue: 0.35, alpha: 1),
            SKColor(red: 1.0, green: 0.55, blue: 0.15, alpha: 1),
            SKColor(red: 0.95, green: 0.95, blue: 0.2, alpha: 1),
        ]
        node.run(.sequence([
            .colorize(with: .white, colorBlendFactor: 1.0, duration: 0.15),
            .colorize(with: colors[phase], colorBlendFactor: 1.0, duration: 0.3),
        ]))
        SoundFX.shared.play(.levelUp)
    }

    private func fireBossPattern(from pos: CGPoint) {
        switch bossPhase {
        case 0:
            // 3-shot burst downward
            for dx in [-18.0, 0.0, 18.0] as [CGFloat] {
                fireEnemyBullet(from: CGPoint(x: pos.x + dx, y: pos.y - 40), vx: dx * 2, vy: -enemyBulletSpeed)
            }
        case 1:
            // Circular 8-shot spray
            for i in 0..<8 {
                let angle = CGFloat(i) * .pi / 4
                let spd = enemyBulletSpeed * 0.85
                fireEnemyBullet(from: pos, vx: sin(angle) * spd * 0.5, vy: -abs(cos(angle)) * spd)
            }
        case 2:
            // Spiral + aimed shot
            let angle = CGFloat(bossFirePattern) * .pi / 2 + CGFloat(lastUpdate) * 2.5
            for i in 0..<4 {
                let a = angle + CGFloat(i) * .pi / 2
                let spd = enemyBulletSpeed
                fireEnemyBullet(from: pos, vx: sin(a) * spd * 0.7, vy: -abs(cos(a)) * spd * 0.7 - 60)
            }
            // Aimed shot at player
            let dx = playerShip.position.x - pos.x
            let dy = playerShip.position.y - pos.y
            let len = hypot(dx, dy)
            if len > 0 {
                let spd = enemyBulletSpeed * 1.2
                fireEnemyBullet(from: pos, vx: dx / len * spd, vy: dy / len * spd)
            }
        default: break
        }
    }

    // MARK: - Player firing

    private func tickPlayerFire(_ dt: TimeInterval) {
        fireAccumulator += dt
        if currentWeapon == .laser { return }  // laser handled separately
        if fireAccumulator >= fireRate {
            fireAccumulator = 0
            fireBullets()
        }
    }

    private func fireBullets() {
        let origin = playerShip.position
        let top = CGPoint(x: origin.x, y: origin.y + 22)
        SoundFX.shared.play(.click)
        switch currentWeapon {
        case .triple:
            fire(from: top, vx: 0, vy: 580)
            fire(from: CGPoint(x: origin.x - 14, y: origin.y + 14), vx: -80, vy: 560)
            fire(from: CGPoint(x: origin.x + 14, y: origin.y + 14), vx:  80, vy: 560)
        case .homing:
            fireHoming(from: top)
        default:
            fire(from: top, vx: 0, vy: 580)
        }
    }

    private func fire(from pt: CGPoint, vx: CGFloat, vy: CGFloat) {
        let color: SKColor = {
            switch currentWeapon {
            case .triple:  return SKColor(red: 0.8, green: 0.5, blue: 1.0, alpha: 1)
            case .rapid:   return SKColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 1)
            default:       return SKColor(red: 0.6, green: 0.9, blue: 1.0, alpha: 1)
            }
        }()
        let bullet = SKShapeNode(rectOf: CGSize(width: 3, height: 13), cornerRadius: 1.5)
        bullet.fillColor = color; bullet.strokeColor = .clear
        bullet.position = pt; bullet.zPosition = 8
        addChild(bullet)
        playerBullets.append((node: bullet, y: pt.y, x: pt.x, vy: vy, vx: vx))
    }

    private func fireHoming(from pt: CGPoint) {
        guard !enemies.isEmpty else { fire(from: pt, vx: 0, vy: 580); return }
        let missile = SKShapeNode(path: missilePath())
        missile.fillColor = SKColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1)
        missile.strokeColor = .clear; missile.position = pt; missile.zPosition = 8
        addChild(missile)
        let targetIdx = enemies.indices.randomElement()
        homingMissiles.append((node: missile, targetIdx: targetIdx, x: pt.x, y: pt.y, vx: 0, vy: 400))
    }

    private func missilePath() -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: 10)); p.addLine(to: CGPoint(x: 4, y: -5))
        p.addLine(to: CGPoint(x: 0, y: -3)); p.addLine(to: CGPoint(x: -4, y: -5))
        p.closeSubpath(); return p
    }

    private func tickPlayerBullets(_ dt: TimeInterval) {
        var remaining: [(node: SKShapeNode, y: CGFloat, x: CGFloat, vy: CGFloat, vx: CGFloat)] = []
        for var b in playerBullets {
            b.y += b.vy * CGFloat(dt); b.x += b.vx * CGFloat(dt)
            b.node.position = CGPoint(x: b.x, y: b.y)
            if b.y > size.height || b.x < -10 || b.x > size.width + 10 { b.node.removeFromParent(); continue }
            if checkBulletHit(b.node) { continue }
            remaining.append(b)
        }
        playerBullets = remaining
    }

    private func tickHomingMissiles(_ dt: TimeInterval) {
        var remaining = homingMissiles
        for i in remaining.indices {
            var m = remaining[i]
            // Steer toward target
            if let ti = m.targetIdx, ti < enemies.count {
                let tx = enemies[ti].x, ty = enemies[ti].y
                let dx = tx - m.x, dy = ty - m.y
                let len = hypot(dx, dy)
                if len > 0 {
                    let speed: CGFloat = 420
                    m.vx += (dx / len * speed - m.vx) * 0.12
                    m.vy += (dy / len * speed - m.vy) * 0.12
                }
            }
            m.x += m.vx * CGFloat(dt); m.y += m.vy * CGFloat(dt)
            m.node.position = CGPoint(x: m.x, y: m.y)
            m.node.zRotation = atan2(m.vx, m.vy)
            if m.y > size.height || m.y < -10 || m.x < -10 || m.x > size.width + 10 {
                m.node.removeFromParent(); continue
            }
            if checkBulletHit(m.node) { continue }
            remaining[i] = m
        }
        homingMissiles = remaining.filter { $0.node.parent != nil }
    }

    private func tickLaser(_ dt: TimeInterval) {
        guard currentWeapon == .laser else {
            laserBeam?.removeFromParent(); laserBeam = nil; return
        }
        // Continuous laser beam from ship nose
        let origin = CGPoint(x: playerShip.position.x, y: playerShip.position.y + 22)
        let height = size.height - origin.y
        if laserBeam == nil {
            let beam = SKShapeNode(rectOf: CGSize(width: 4, height: height))
            beam.fillColor = SKColor(red: 0.3, green: 1.0, blue: 0.5, alpha: 0.85)
            beam.strokeColor = SKColor(red: 0.6, green: 1.0, blue: 0.7, alpha: 0.5)
            beam.lineWidth = 1; beam.zPosition = 7
            addChild(beam); laserBeam = beam
            SoundFX.shared.play(.click)
        }
        laserBeam?.position = CGPoint(x: origin.x, y: origin.y + height / 2)

        // Damage enemies overlapping the laser (once per 0.12s via fireAccumulator)
        fireAccumulator += dt
        if fireAccumulator >= 0.12 {
            fireAccumulator = 0
            let lx = origin.x
            for i in enemies.indices where enemies[i].hp > 0 {
                let ex = enemies[i].x
                if abs(ex - lx) < 18 {
                    spawnHitFlash(at: enemies[i].node.position)
                    damageEnemy(index: i)
                    return  // one enemy per tick to prevent chain-overkill
                }
            }
        }
    }

    // MARK: - Enemy hit detection

    private func checkBulletHit(_ bullet: SKNode) -> Bool {
        for i in enemies.indices where enemies[i].hp > 0 {
            let dx = abs(enemies[i].x - bullet.position.x)
            let dy = abs(enemies[i].y - bullet.position.y)
            let hitR: CGFloat = enemies[i].kind == 4 ? 42 : 22
            if dx < hitR && dy < hitR {
                bullet.removeFromParent()
                damageEnemy(index: i)
                return true
            }
        }
        return false
    }

    private func damageEnemy(index i: Int) {
        guard i < enemies.count, enemies[i].hp > 0 else { return }

        // Shield absorbs first hit
        if enemies[i].hasShield {
            enemies[i].hasShield = false
            enemies[i].shieldNode?.removeFromParent()
            enemies[i].shieldNode = nil
            SoundFX.shared.play(.brick)
            return
        }

        enemies[i].hp -= 1
        if enemies[i].hp > 0 {
            enemies[i].node.run(.sequence([
                .colorize(with: .white, colorBlendFactor: 1.0, duration: 0.05),
                .colorize(withColorBlendFactor: 0.0, duration: 0.08)
            ]))
            enemies[i].hpLabel?.text = "\(enemies[i].hp)"
            if enemies[i].kind == 4 {
                bossCurrentHP = enemies[i].hp
                onSolarEvent?(.bossHP(current: bossCurrentHP, max: bossMaxHP))
            }
            return
        }

        // Killed
        let kind = enemies[i].kind
        let pts: Int
        switch kind {
        case 0: pts = 10
        case 1: pts = 30
        case 2: pts = 20
        case 3: pts = 45
        case 4: pts = 0   // boss death sends bossHP event
        default: pts = 10
        }

        if kind == 4 {
            onSolarEvent?(.bossHP(current: 0, max: bossMaxHP))
            SoundFX.shared.play(.jackpot)
            spawnExplosion(at: enemies[i].node.position, color: enemies[i].node.fillColor, count: 24)
        } else {
            onSolarEvent?(.scored(pts * (hasMultiplier ? 2 : 1)))
            SoundFX.shared.play(.brick)
            spawnExplosion(at: enemies[i].node.position, color: enemies[i].node.fillColor, count: 8)
        }

        // Power-up drop
        let dropChance = kind == 4 ? 1.0 : (kind == 3 ? 0.5 : 0.22)
        if Double.random(in: 0...1) < dropChance {
            let puKind: Int = kind == 4 ? Int.random(in: 0...5) : Int.random(in: 0...4)
            dropPowerUp(at: enemies[i].node.position, kind: puKind)
        }

        enemies[i].node.removeFromParent()
        enemies.remove(at: i)

        if enemies.isEmpty {
            wave += 1
            onSolarEvent?(.waveCleared)
            SoundFX.shared.play(.levelUp)
            laserBeam?.removeFromParent(); laserBeam = nil
            run(.sequence([.wait(forDuration: 1.2), .run { [weak self] in self?.spawnWave() }]))
        }
    }

    // MARK: - Explosions

    private func spawnExplosion(at pos: CGPoint, color: SKColor, count: Int = 8) {
        for i in 0..<count {
            let r = CGFloat.random(in: 2...5)
            let particle = SKShapeNode(circleOfRadius: r)
            particle.fillColor = i % 3 == 0 ? .white : color
            particle.strokeColor = .clear; particle.position = pos; particle.zPosition = 9
            addChild(particle)
            let ang = CGFloat(i) / CGFloat(count) * .pi * 2 + CGFloat.random(in: -0.3...0.3)
            let spd = CGFloat.random(in: 30...100)
            let dx = cos(ang) * spd, dy = sin(ang) * spd
            particle.run(.sequence([
                .group([.moveBy(x: dx, y: dy, duration: 0.45),
                        .sequence([.wait(forDuration: 0.15), .fadeOut(withDuration: 0.3)])]),
                .removeFromParent()
            ]))
        }
        // Brief screen shake
        run(.sequence([.moveBy(x: 4, y: 2, duration: 0.04), .moveBy(x: -6, y: -4, duration: 0.04),
                       .moveBy(x: 4, y: 2, duration: 0.04), .move(to: .zero, duration: 0.04)]))
    }

    private func spawnHitFlash(at pos: CGPoint) {
        let flash = SKShapeNode(circleOfRadius: 8)
        flash.fillColor = SKColor(red: 0.5, green: 1.0, blue: 0.7, alpha: 0.9)
        flash.strokeColor = .clear; flash.position = pos; flash.zPosition = 9
        addChild(flash)
        flash.run(.sequence([.fadeOut(withDuration: 0.1), .removeFromParent()]))
    }

    // MARK: - Power-ups

    private func dropPowerUp(at pos: CGPoint, kind: Int) {
        let (emoji, color): (String, SKColor) = {
            switch kind {
            case 0: return ("⚡", SKColor(red: 0.9, green: 0.8, blue: 0.15, alpha: 1))
            case 1: return ("🛡", SKColor(red: 0.3, green: 0.8, blue: 0.5, alpha: 1))
            case 2: return ("💜", SKColor(red: 0.7, green: 0.35, blue: 0.95, alpha: 1))
            case 3: return ("🟢", SKColor(red: 0.2, green: 0.9, blue: 0.4, alpha: 1))
            case 4: return ("💣", SKColor(red: 0.9, green: 0.3, blue: 0.25, alpha: 1))
            default: return ("⭐", SKColor(red: 0.98, green: 0.75, blue: 0.15, alpha: 1))
            }
        }()
        let node = SKShapeNode(circleOfRadius: 13)
        node.fillColor = color; node.strokeColor = SKColor(white: 1, alpha: 0.6)
        node.position = pos; node.zPosition = 7
        node.run(.repeatForever(.sequence([.scale(to: 1.15, duration: 0.4), .scale(to: 0.9, duration: 0.4)])))
        addChild(node)
        let label = SKLabelNode(text: emoji); label.fontSize = 15
        label.verticalAlignmentMode = .center; label.horizontalAlignmentMode = .center
        node.addChild(label)
        powerUps.append(PowerUp(node: node, label: label, x: pos.x, y: pos.y, kind: kind))
    }

    private func tickPowerUps(_ dt: TimeInterval) {
        var remaining: [PowerUp] = []
        for var pu in powerUps {
            pu.y -= 90 * CGFloat(dt)
            pu.node.position = CGPoint(x: pu.x, y: pu.y)
            if pu.y < -20 { pu.node.removeFromParent(); continue }
            if !dying && abs(pu.x - playerShip.position.x) < 26 && abs(pu.y - playerShip.position.y) < 26 {
                pu.node.removeFromParent()
                collectPowerUp(kind: pu.kind)
                continue
            }
            remaining.append(pu)
        }
        powerUps = remaining
    }

    private func collectPowerUp(kind: Int) {
        SoundFX.shared.play(.jackpot)
        flashPlayer()
        switch kind {
        case 0:  // Rapid Fire
            currentWeapon = .rapid; weaponTimer = 10
            onSolarEvent?(.weaponPickup(.rapid))
        case 1:  // Shield
            applyShield()
            onSolarEvent?(.weaponPickup(.standard))  // shield is tracked separately
        case 2:  // Triple Shot
            currentWeapon = .triple; weaponTimer = 10
            onSolarEvent?(.weaponPickup(.triple))
        case 3:  // Laser
            currentWeapon = .laser; weaponTimer = 8
            laserBeam?.removeFromParent(); laserBeam = nil
            onSolarEvent?(.weaponPickup(.laser))
        case 4:  // Smart Bomb
            detonateSmartBomb()
            onSolarEvent?(.smartBomb)
        default: // Score Multiplier ×2
            hasMultiplier = true; multiplierTimer = 15
            onSolarEvent?(.multiplierPickup)
        }
    }

    private func applyShield() {
        hasShield = true
        if shieldRing == nil {
            let ring = SKShapeNode(circleOfRadius: 30)
            ring.fillColor = .clear
            ring.strokeColor = SKColor(red: 0.3, green: 1.0, blue: 0.6, alpha: 0.9)
            ring.lineWidth = 3; ring.position = .zero; ring.name = "shieldRing"
            ring.run(.repeatForever(.sequence([.fadeAlpha(to: 0.3, duration: 0.5), .fadeAlpha(to: 1.0, duration: 0.5)])))
            playerShip.addChild(ring); shieldRing = ring
        }
    }

    private func detonateSmartBomb() {
        let bombFlash = SKShapeNode(rectOf: size)
        bombFlash.fillColor = SKColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 0.7)
        bombFlash.strokeColor = .clear; bombFlash.position = CGPoint(x: size.width/2, y: size.height/2)
        bombFlash.zPosition = 15; addChild(bombFlash)
        bombFlash.run(.sequence([.fadeOut(withDuration: 0.4), .removeFromParent()]))

        let pts = enemies.reduce(0) { sum, e in
            sum + (e.kind == 4 ? 300 : [10, 30, 20, 45, 0][min(e.kind, 4)])
        }
        enemies.forEach { e in
            spawnExplosion(at: e.node.position, color: e.node.fillColor, count: 12)
            e.node.removeFromParent()
        }
        enemies.removeAll()
        if pts > 0 { onSolarEvent?(.scored(pts * (hasMultiplier ? 2 : 1))) }
        SoundFX.shared.play(.jackpot)
        run(.sequence([.wait(forDuration: 1.2), .run { [weak self] in
            guard let self else { return }
            self.wave += 1; self.onSolarEvent?(.waveCleared); self.spawnWave()
        }]))
    }

    private func flashPlayer() {
        playerShip.run(.sequence([
            .colorize(with: .white, colorBlendFactor: 0.8, duration: 0.08),
            .colorize(withColorBlendFactor: 0.0, duration: 0.25),
        ]))
    }

    // MARK: - Enemy fire

    private func tickEnemyFire(_ dt: TimeInterval) {
        for i in enemies.indices where enemies[i].kind != 4 {
            enemies[i].fireTimer -= dt
            if enemies[i].fireTimer <= 0 {
                enemies[i].fireTimer = enemyFireRate * Double.random(in: 0.75...1.35)
                fireEnemyBullet(from: CGPoint(x: enemies[i].x, y: enemies[i].y - 10), vx: 0, vy: -enemyBulletSpeed)
            }
        }
    }

    private func fireEnemyBullet(from pos: CGPoint, vx: CGFloat, vy: CGFloat) {
        let bullet = SKShapeNode(rectOf: CGSize(width: 3, height: 10), cornerRadius: 1.5)
        bullet.fillColor = SKColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 1)
        bullet.strokeColor = .clear; bullet.position = pos; bullet.zPosition = 8
        addChild(bullet)
        enemyBullets.append((node: bullet, x: pos.x, y: pos.y, vx: vx, vy: vy))
    }

    private func tickEnemyBullets(_ dt: TimeInterval) {
        var remaining: [(node: SKShapeNode, x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat)] = []
        for var b in enemyBullets {
            b.x += b.vx * CGFloat(dt); b.y += b.vy * CGFloat(dt)
            b.node.position = CGPoint(x: b.x, y: b.y)
            if b.y < -10 || b.y > size.height + 10 || b.x < -20 || b.x > size.width + 20 {
                b.node.removeFromParent(); continue
            }
            if !dying {
                let dx = abs(b.x - playerShip.position.x), dy = abs(b.y - playerShip.position.y)
                if dx < 18 && dy < 18 {
                    b.node.removeFromParent(); playerHit(); continue
                }
            }
            remaining.append(b)
        }
        enemyBullets = remaining
    }

    // MARK: - Player hit

    private func playerHit() {
        guard !dying else { return }
        if hasShield {
            hasShield = false; shieldRing?.removeFromParent(); shieldRing = nil
            SoundFX.shared.play(.brick)
            playerShip.run(.sequence([
                .colorize(with: SKColor(red: 0.3, green: 1.0, blue: 0.6, alpha: 1), colorBlendFactor: 1.0, duration: 0.1),
                .colorize(withColorBlendFactor: 0.0, duration: 0.35)
            ]))
            return
        }
        dying = true; deathTimer = 1.0
        currentWeapon = .standard; weaponTimer = 0
        laserBeam?.removeFromParent(); laserBeam = nil
        onSolarEvent?(.lifeLost)
        SoundFX.shared.play(.lifeLost)
        spawnExplosion(at: playerShip.position, color: SKColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 1), count: 18)
        playerShip.run(.sequence([
            .fadeAlpha(to: 0.1, duration: 0.08), .fadeAlpha(to: 0.9, duration: 0.08),
            .fadeAlpha(to: 0.1, duration: 0.08), .fadeAlpha(to: 0.9, duration: 0.08),
            .fadeAlpha(to: 0.1, duration: 0.08), .fadeAlpha(to: 1.0, duration: 0.08),
        ]))
        playerShip.position = CGPoint(x: size.width / 2, y: 68)
    }
}

