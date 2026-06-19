import SwiftUI

struct BombermanView: View {
    @ObservedObject var session: GameSession
    @State private var paused = false
    @State private var scorePopup: String? = nil
    @State private var chainPopup: String? = nil
    @State private var powerupPopup: String? = nil

    var game: BombermanGame? { session.game?.engine as? BombermanGame }

    var tickInterval: Double {
        let boosts = game?.speedBoosts ?? 0
        return max(0.05, 0.10 - Double(boosts) * 0.02)
    }

    var body: some View {
        VStack(spacing: 4) {
            if let game { statusBar(game) }

            ZStack {
                boardCanvas
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.white.opacity(0.2), lineWidth: 1))
                    .padding(.horizontal, 8)

                if let popup = scorePopup {
                    Text(popup)
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(.yellow)
                        .shadow(color: .orange, radius: 5)
                        .allowsHitTesting(false)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal:   .move(edge: .top).combined(with: .opacity)))
                }
                if let popup = chainPopup {
                    Text(popup)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(.orange)
                        .shadow(color: .red, radius: 7)
                        .allowsHitTesting(false)
                        .transition(.scale.combined(with: .opacity))
                }
                if let popup = powerupPopup {
                    VStack {
                        Spacer()
                        Text(popup)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.black.opacity(0.62), in: Capsule())
                            .padding(.bottom, 12)
                    }
                    .allowsHitTesting(false)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if let game, game.levelClearing {
                    levelClearOverlay(game)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
                if let game, !game.playerAlive && !game.isOver && !game.levelClearing {
                    Text("Respawning…")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(.black.opacity(0.65), in: Capsule())
                }
            }
            .animation(.easeOut(duration: 0.3),  value: scorePopup)
            .animation(.spring(response: 0.25),  value: chainPopup)
            .animation(.easeInOut(duration: 0.25), value: powerupPopup)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: game?.levelClearing)

            controls
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
        }
        .padding(.top, 4)
        .task(id: session.sessionID) { await clock() }
    }

    // MARK: - Level clear overlay

    @ViewBuilder
    func levelClearOverlay(_ game: BombermanGame) -> some View {
        let fraction = Double(game.levelClearCountdown) / 80.0
        VStack(spacing: 10) {
            Text("LEVEL \(game.level)")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
            Text("CLEARED!")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.yellow)
                .shadow(color: .orange.opacity(0.8), radius: 12)
            if game.deathsThisLevel == 0 {
                Text("⭐ Perfect — no deaths! +500 pts")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.yellow.opacity(0.9))
            }
            Text("+\(1000 * game.level + (game.deathsThisLevel == 0 ? 500 : 0)) bonus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.14))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [.yellow, .orange],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * max(0, 1 - fraction))
                }
            }
            .frame(height: 6)
            .padding(.horizontal, 18)
            Text("Level \(game.level + 1) incoming…")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(24)
        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: .orange.opacity(0.35), radius: 22)
    }

    // MARK: - Status bar

    func statusBar(_ game: BombermanGame) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { i in
                        Image(systemName: i < game.livesLeft ? "heart.fill" : "heart")
                            .font(.system(size: 10))
                            .foregroundStyle(i < game.livesLeft ? Color.red : Color.white.opacity(0.18))
                    }
                }
                Text("Lv\(game.level)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.white.opacity(0.1), in: Capsule())
                if game.levelsCleared > 0 {
                    Text("🏆\(game.levelsCleared)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.yellow.opacity(0.85))
                }
                Spacer()
                Text("\(game.score)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.white)
            }

            HStack(spacing: 6) {
                let avail = game.effectiveMaxBombs - game.bombs.count
                HStack(spacing: 2) {
                    Text("💣").font(.system(size: 9))
                    Text("\(avail)/\(game.effectiveMaxBombs)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(avail > 0 ? Color.white : Color.white.opacity(0.35))
                }
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(avail > 0 ? Color.orange.opacity(0.18) : Color.white.opacity(0.06),
                            in: Capsule())

                if game.effectiveBlastRadius > 2 {
                    Text("💥r\(game.effectiveBlastRadius)")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.orange)
                }
                if game.speedBoosts > 0 {
                    Text("⚡×\(game.speedBoosts)")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.cyan)
                }
                if game.hasRemote { Text("📡").font(.system(size: 10)) }
                if game.shieldTicks > 0 {
                    Text("🛡 \(game.shieldTicks / 10)s")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.cyan)
                }
                if game.skullTicks > 0 {
                    Text("💀 \(game.skullTicks / 10)s")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.red)
                }
                Spacer()
                let balloons = game.enemies.filter { $0.alive && $0.kind == .balloon }.count
                let ghosts   = game.enemies.filter { $0.alive && $0.kind == .ghost   }.count
                let demons   = game.enemies.filter { $0.alive && $0.kind == .demon   }.count
                if balloons > 0 { Text("🔵×\(balloons)").font(.system(size: 9)).foregroundStyle(.blue) }
                if ghosts   > 0 { Text("👻×\(ghosts)").font(.system(size: 9)).foregroundStyle(.purple) }
                if demons   > 0 { Text("😈×\(demons)").font(.system(size: 9)).foregroundStyle(.red) }
            }
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
    }

    // MARK: - Board canvas

    var boardCanvas: some View {
        Canvas { context, size in
            guard let game else { return }
            let cw = size.width  / CGFloat(BombermanGame.cols)
            let ch = size.height / CGFloat(BombermanGame.rows)
            let cs = min(cw, ch)

            func rect(_ x: Int, _ y: Int) -> CGRect {
                CGRect(x: CGFloat(x) * cw + 1, y: CGFloat(y) * ch + 1,
                       width: cw - 2, height: ch - 2)
            }
            func center(_ x: Int, _ y: Int) -> CGPoint {
                CGPoint(x: (CGFloat(x) + 0.5) * cw, y: (CGFloat(y) + 0.5) * ch)
            }

            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(Color(red: 0.09, green: 0.11, blue: 0.19)))

            let danger = game.dangerCells
            let dangerAlpha: Double = (game.tickCount % 8) < 4 ? 0.26 : 0.12

            for y in 0..<BombermanGame.rows {
                for x in 0..<BombermanGame.cols {
                    let r = rect(x, y)
                    let i = game.idx(x, y)
                    let c = game.grid[i]
                    switch c {
                    case .wall:
                        context.fill(Path(roundedRect: r, cornerRadius: 2),
                                     with: .color(Color(red: 0.20, green: 0.24, blue: 0.38)))
                        context.fill(Path(CGRect(x: r.minX, y: r.minY, width: r.width, height: 2)),
                                     with: .color(.white.opacity(0.14)))
                        context.fill(Path(CGRect(x: r.minX, y: r.minY, width: 2, height: r.height)),
                                     with: .color(.white.opacity(0.09)))
                        context.stroke(Path(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 2),
                                       with: .color(.white.opacity(0.07)), lineWidth: 0.5)
                    case .block:
                        context.fill(Path(roundedRect: r, cornerRadius: 2),
                                     with: .color(Color(red: 0.52, green: 0.38, blue: 0.20)))
                        context.stroke(Path(roundedRect: r.insetBy(dx: 2.5, dy: 2.5), cornerRadius: 1),
                                       with: .color(.white.opacity(0.17)), lineWidth: 1)
                        var crack = Path()
                        crack.move(to:    CGPoint(x: r.minX + 3, y: r.midY))
                        crack.addLine(to: CGPoint(x: r.maxX - 3, y: r.midY))
                        crack.move(to:    CGPoint(x: r.midX, y: r.minY + 3))
                        crack.addLine(to: CGPoint(x: r.midX, y: r.maxY - 3))
                        context.stroke(crack, with: .color(.white.opacity(0.10)), lineWidth: 0.8)
                    case .powerBomb:
                        context.fill(Path(roundedRect: r, cornerRadius: 3),
                                     with: .color(Color.yellow.opacity(0.22)))
                        context.draw(Text("💣").font(.system(size: cs * 0.62)), at: center(x, y))
                    case .powerBlast:
                        context.fill(Path(roundedRect: r, cornerRadius: 3),
                                     with: .color(Color.orange.opacity(0.22)))
                        context.draw(Text("💥").font(.system(size: cs * 0.62)), at: center(x, y))
                    case .powerSpeed:
                        context.fill(Path(roundedRect: r, cornerRadius: 3),
                                     with: .color(Color.cyan.opacity(0.22)))
                        context.draw(Text("⚡").font(.system(size: cs * 0.62)), at: center(x, y))
                    case .powerRemote:
                        context.fill(Path(roundedRect: r, cornerRadius: 3),
                                     with: .color(Color.purple.opacity(0.22)))
                        context.draw(Text("📡").font(.system(size: cs * 0.62)), at: center(x, y))
                    case .powerSkull:
                        context.fill(Path(roundedRect: r, cornerRadius: 3),
                                     with: .color(Color.red.opacity(0.22)))
                        context.draw(Text("💀").font(.system(size: cs * 0.62)), at: center(x, y))
                    case .powerShield:
                        context.fill(Path(roundedRect: r, cornerRadius: 3),
                                     with: .color(Color.blue.opacity(0.22)))
                        context.draw(Text("🛡").font(.system(size: cs * 0.62)), at: center(x, y))
                    case .empty:
                        let dc = center(x, y)
                        context.fill(Path(ellipseIn: CGRect(x: dc.x - 1.2, y: dc.y - 1.2,
                                                             width: 2.4, height: 2.4)),
                                     with: .color(.white.opacity(0.045)))
                        if danger.contains(i) {
                            context.fill(Path(roundedRect: r, cornerRadius: 2),
                                         with: .color(Color.red.opacity(dangerAlpha)))
                        }
                    }
                }
            }

            // Bonus cherry (blinks when about to expire)
            if game.hasBonusItem {
                let blink = game.bonusItemTicks < 35 && (game.tickCount % 5 < 2)
                if !blink {
                    let cr = rect(game.bonusItemX, game.bonusItemY)
                    context.fill(Path(roundedRect: cr.insetBy(dx: 1, dy: 1), cornerRadius: 4),
                                 with: .color(Color.red.opacity(0.18)))
                    context.draw(Text("🍒").font(.system(size: cs * 0.74)),
                                 at: center(game.bonusItemX, game.bonusItemY))
                }
            }

            // Explosions: center brighter, arms fade with ticksLeft
            for exp in game.explosions {
                let baseAlpha = min(1.0, Double(exp.ticksLeft) / 10.0)
                let centerIdx = exp.cells.first
                for i in exp.cells {
                    let ex = i % BombermanGame.cols; let ey = i / BombermanGame.cols
                    let r = rect(ex, ey)
                    let isCenter = (i == centerIdx)
                    let cellAlpha = (isCenter ? 1.0 : 0.68) * baseAlpha
                    let green: Double = isCenter ? 0.75 : 0.44
                    context.fill(Path(roundedRect: r, cornerRadius: 3),
                                 with: .color(Color(red: 1.0, green: green, blue: 0.05)
                                    .opacity(cellAlpha * 0.88)))
                    if isCenter {
                        context.stroke(Path(roundedRect: r.insetBy(dx: 1, dy: 1), cornerRadius: 3),
                                       with: .color(Color.yellow.opacity(cellAlpha * 0.65)),
                                       lineWidth: 1.5)
                    }
                }
            }

            // Bombs: pulsing body + spark at arc endpoint
            for bomb in game.bombs {
                let bc = center(bomb.x, bomb.y)
                let br = cs * 0.36
                let fuseRatio = Double(bomb.fuseLeft) / 120.0
                let urgent  = fuseRatio < 0.25
                let pulseOn = urgent && (game.tickCount % 3 < 1)

                let bodyColor: Color = pulseOn
                    ? Color(red: 0.45, green: 0.0, blue: 0.0)
                    : Color(white: 0.10)
                context.fill(Path(ellipseIn: CGRect(x: bc.x - br, y: bc.y - br,
                                                     width: br * 2, height: br * 2)),
                             with: .color(bodyColor))
                context.stroke(Path(ellipseIn: CGRect(x: bc.x - br, y: bc.y - br,
                                                       width: br * 2, height: br * 2)),
                               with: .color(.white.opacity(pulseOn ? 0.90 : 0.50)),
                               lineWidth: pulseOn ? 2 : 1)
                if bomb.remote {
                    context.draw(Text("📡").font(.system(size: br * 0.88)), at: bc)
                }
                var fusePath = Path()
                fusePath.addArc(center: bc, radius: br + 3.5,
                                startAngle: .degrees(-90),
                                endAngle: .degrees(-90 + 360 * fuseRatio),
                                clockwise: false)
                context.stroke(fusePath, with: .color(urgent ? Color.red : Color.orange),
                               lineWidth: 2.5)
                let endAngleRad = (-90 + 360 * fuseRatio) * .pi / 180
                let sparkPos = CGPoint(x: bc.x + cos(endAngleRad) * (br + 3.5),
                                      y: bc.y + sin(endAngleRad) * (br + 3.5))
                let sparkColor: Color = (game.tickCount % 3 < 2) ? .yellow : .orange
                context.fill(Path(ellipseIn: CGRect(x: sparkPos.x - 3, y: sparkPos.y - 3,
                                                     width: 6, height: 6)),
                             with: .color(sparkColor.opacity(0.9)))
            }

            // Enemies — distinct shapes per kind
            for enemy in game.enemies where enemy.alive {
                let ec = center(enemy.x, enemy.y)
                let er = cs * 0.40

                switch enemy.kind {

                case .balloon:
                    // Oval body + shine + dangling string
                    context.fill(Path(ellipseIn: CGRect(x: ec.x - er * 0.88, y: ec.y - er,
                                                         width: er * 1.76, height: er * 2.0)),
                                 with: .color(Color(red: 0.35, green: 0.58, blue: 1.0)))
                    context.fill(Path(ellipseIn: CGRect(x: ec.x - er * 0.44, y: ec.y - er * 0.84,
                                                         width: er * 0.40, height: er * 0.28)),
                                 with: .color(.white.opacity(0.40)))
                    var strPath = Path()
                    strPath.move(to:    CGPoint(x: ec.x,             y: ec.y + er))
                    strPath.addLine(to: CGPoint(x: ec.x + er * 0.12, y: ec.y + er * 1.42))
                    strPath.addLine(to: CGPoint(x: ec.x - er * 0.05, y: ec.y + er * 1.80))
                    context.stroke(strPath, with: .color(.white.opacity(0.62)), lineWidth: 1)
                    for dx: CGFloat in [-er * 0.28, er * 0.28] {
                        let eyeR = er * 0.17
                        context.fill(Path(ellipseIn: CGRect(x: ec.x + dx - eyeR,
                                                             y: ec.y - er * 0.28 - eyeR,
                                                             width: eyeR * 2, height: eyeR * 2.2)),
                                     with: .color(.white))
                        let pdx = CGFloat(enemy.direction.dx) * eyeR * 0.4
                        let pdy = CGFloat(enemy.direction.dy) * eyeR * 0.4
                        context.fill(Path(ellipseIn: CGRect(x: ec.x + dx - eyeR * 0.55 + pdx,
                                                             y: ec.y - er * 0.28 - eyeR * 0.55 + pdy,
                                                             width: eyeR * 1.1, height: eyeR * 1.1)),
                                     with: .color(.black))
                    }

                case .ghost:
                    // 8-point wavy polygon + tracking eyes
                    var ghostPath = Path()
                    let pts = 8
                    for k in 0..<pts {
                        let angle = Double(k) / Double(pts) * .pi * 2 - .pi / 2
                        let wobble: CGFloat = k % 2 == 0 ? er : er * 0.72
                        let px = ec.x + cos(angle) * wobble
                        let py = ec.y + sin(angle) * wobble * 0.88
                        if k == 0 { ghostPath.move(to: CGPoint(x: px, y: py)) }
                        else       { ghostPath.addLine(to: CGPoint(x: px, y: py)) }
                    }
                    ghostPath.closeSubpath()
                    context.fill(ghostPath, with: .color(Color(red: 0.76, green: 0.42, blue: 1.0)))
                    context.stroke(ghostPath, with: .color(.white.opacity(0.20)), lineWidth: 0.8)
                    for dx: CGFloat in [-er * 0.28, er * 0.28] {
                        let eyeR = er * 0.18
                        context.fill(Path(ellipseIn: CGRect(x: ec.x + dx - eyeR,
                                                             y: ec.y - er * 0.22 - eyeR,
                                                             width: eyeR * 2, height: eyeR * 2.2)),
                                     with: .color(.white))
                        let pdx = CGFloat(enemy.direction.dx) * eyeR * 0.4
                        let pdy = CGFloat(enemy.direction.dy) * eyeR * 0.4
                        context.fill(Path(ellipseIn: CGRect(x: ec.x + dx - eyeR * 0.55 + pdx,
                                                             y: ec.y - er * 0.22 - eyeR * 0.55 + pdy,
                                                             width: eyeR * 1.1, height: eyeR * 1.1)),
                                     with: .color(.black))
                    }

                case .demon:
                    // Angular body + horn triangles + yellow tracking eyes
                    context.fill(Path(ellipseIn: CGRect(x: ec.x - er * 0.92, y: ec.y - er * 0.68,
                                                         width: er * 1.84, height: er * 1.76)),
                                 with: .color(Color(red: 0.92, green: 0.20, blue: 0.26)))
                    for side: CGFloat in [-1.0, 1.0] {
                        var horn = Path()
                        let hx = ec.x + side * er * 0.40; let hy = ec.y - er * 0.58
                        horn.move(to:    CGPoint(x: hx,                    y: hy))
                        horn.addLine(to: CGPoint(x: hx - side * er * 0.16, y: hy + er * 0.28))
                        horn.addLine(to: CGPoint(x: hx + side * er * 0.16, y: hy + er * 0.28))
                        horn.closeSubpath()
                        context.fill(horn, with: .color(Color(red: 0.65, green: 0.08, blue: 0.12)))
                    }
                    for dx: CGFloat in [-er * 0.30, er * 0.30] {
                        let eyeR = er * 0.17
                        context.fill(Path(ellipseIn: CGRect(x: ec.x + dx - eyeR,
                                                             y: ec.y - er * 0.18 - eyeR,
                                                             width: eyeR * 2, height: eyeR * 2)),
                                     with: .color(.yellow))
                        let pdx = CGFloat(enemy.direction.dx) * eyeR * 0.45
                        let pdy = CGFloat(enemy.direction.dy) * eyeR * 0.45
                        context.fill(Path(ellipseIn: CGRect(x: ec.x + dx - eyeR * 0.6 + pdx,
                                                             y: ec.y - er * 0.18 - eyeR * 0.6 + pdy,
                                                             width: eyeR * 1.2, height: eyeR * 1.2)),
                                     with: .color(.black))
                    }
                }
            }

            // Player
            guard game.playerAlive else { return }
            let blinkOff = game.invincibleTicks > 0 && (game.tickCount % 6 < 3)
            if !blinkOff {
                let pc = center(game.playerX, game.playerY)
                let pr = cs * 0.42

                // Cyan glow ring when shield active
                if game.shieldTicks > 0 {
                    let glowR = pr * 1.55
                    context.fill(Path(ellipseIn: CGRect(x: pc.x - glowR, y: pc.y - glowR,
                                                         width: glowR * 2, height: glowR * 2)),
                                 with: .color(Color.cyan.opacity(0.22)))
                    context.stroke(Path(ellipseIn: CGRect(x: pc.x - glowR, y: pc.y - glowR,
                                                           width: glowR * 2, height: glowR * 2)),
                                   with: .color(Color.cyan.opacity(0.55)), lineWidth: 1.5)
                }

                // Red tint under skull penalty, otherwise green
                let bodyColor: Color = game.skullTicks > 0
                    ? Color(red: 0.72, green: 0.28, blue: 0.28)
                    : Color(red: 0.28, green: 0.88, blue: 0.48)
                context.fill(Path(ellipseIn: CGRect(x: pc.x - pr, y: pc.y - pr,
                                                     width: pr * 2, height: pr * 2)),
                             with: .color(bodyColor))
                context.stroke(Path(ellipseIn: CGRect(x: pc.x - pr, y: pc.y - pr,
                                                       width: pr * 2, height: pr * 2)),
                               with: .color((game.shieldTicks > 0 ? Color.cyan : Color.white).opacity(0.72)),
                               lineWidth: game.shieldTicks > 0 ? 2.0 : 1.5)

                // Direction chevron (triangle pointing in playerDir)
                let ddx = CGFloat(game.playerDir.dx); let ddy = CGFloat(game.playerDir.dy)
                let tip = CGPoint(x: pc.x + ddx * pr * 0.70, y: pc.y + ddy * pr * 0.70)
                let perpX = -ddy * pr * 0.20; let perpY = ddx * pr * 0.20
                let back = pr * 0.25
                var chev = Path()
                chev.move(to: tip)
                chev.addLine(to: CGPoint(x: tip.x - ddx * back + perpX, y: tip.y - ddy * back + perpY))
                chev.addLine(to: CGPoint(x: tip.x - ddx * back - perpX, y: tip.y - ddy * back - perpY))
                chev.closeSubpath()
                context.fill(chev, with: .color(.white.opacity(0.88)))

                let dotR = pr * 0.17
                context.fill(Path(ellipseIn: CGRect(x: pc.x - dotR, y: pc.y - dotR,
                                                     width: dotR * 2, height: dotR * 2)),
                             with: .color(.white.opacity(0.90)))
            }
        }
        .aspectRatio(CGFloat(BombermanGame.cols) / CGFloat(BombermanGame.rows), contentMode: .fit)
        .background(Color(red: 0.09, green: 0.11, blue: 0.19))
    }

    // MARK: - Controls

    var controls: some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                dpadButton("chevron.up",    .up).frame(maxWidth: .infinity)
                HStack(spacing: 0) {
                    dpadButton("chevron.left",  .left).frame(maxWidth: .infinity)
                    // D-pad center: animated player avatar
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(0.05))
                            .frame(width: 44, height: 44)
                        Circle()
                            .fill(Color(red: 0.28, green: 0.88, blue: 0.48).opacity(0.72))
                            .frame(width: 22, height: 22)
                        Circle().fill(.white.opacity(0.88)).frame(width: 5, height: 5)
                    }
                    dpadButton("chevron.right", .right).frame(maxWidth: .infinity)
                }
                dpadButton("chevron.down",  .down).frame(maxWidth: .infinity)
            }
            .frame(width: 132)

            Spacer()

            VStack(spacing: 8) {
                // Main bomb button with haptic feedback
                Button {
                    session.submit(.bomberman(.placeBomb))
                    SoundFX.shared.play(.brick)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    VStack(spacing: 2) {
                        Text("💣").font(.system(size: 26))
                        Text("BOMB")
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .frame(width: 64, height: 64)
                    .background(Color(red: 0.80, green: 0.20, blue: 0.20).opacity(0.88),
                                in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.28), lineWidth: 1))
                }
                .buttonStyle(.plain)

                HStack(spacing: 6) {
                    // Kick button (always shown)
                    Button { session.submit(.bomberman(.kick)) } label: {
                        VStack(spacing: 1) {
                            Text("👟").font(.system(size: 14))
                            Text("KICK").font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .frame(width: 46, height: 36)
                        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    // Remote detonate (only shown when hasRemote)
                    if let g = game, g.hasRemote {
                        Button { session.submit(.bomberman(.detonate)) } label: {
                            VStack(spacing: 1) {
                                Text("📡").font(.system(size: 14))
                                Text("BOOM").font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.red.opacity(0.9))
                            }
                            .frame(width: 46, height: 36)
                            .background(Color.red.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.red.opacity(0.45), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    func dpadButton(_ symbol: String, _ direction: GridDirection) -> some View {
        Button {
            session.submit(.bomberman(.move(direction)))
        } label: {
            Image(systemName: symbol)
                .font(.title3.weight(.bold))
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Clock + event detection

    @MainActor
    private func clock() async {
        while true {
            do {
                try await Task.sleep(nanoseconds: UInt64(tickInterval * 1_000_000_000))
            } catch { break }
            guard !paused, let before = game, !before.isOver else { continue }
            session.submit(.bomberman(.tick))
            guard let after = game else { continue }

            let aliveBefore = before.enemies.filter { $0.alive }.count
            let aliveAfter  = after.enemies.filter  { $0.alive }.count
            let killed = aliveBefore - aliveAfter

            // Kill / score popup
            if killed > 0 {
                let gain = after.score - before.score
                let p = killed > 1 ? "💀×\(killed) +\(gain)!" : "+\(gain)!"
                withAnimation { scorePopup = p }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    withAnimation { scorePopup = nil }
                }
                SoundFX.shared.play(.target)
            }

            // Chain popup
            if after.maxChain > before.maxChain && after.maxChain >= 2 {
                let p = "CHAIN ×\(after.maxChain)!"
                withAnimation { chainPopup = p }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_100_000_000)
                    withAnimation { chainPopup = nil }
                }
            }

            // Power-up popup
            if after.powerUpsCollected > before.powerUpsCollected {
                withAnimation { powerupPopup = "⚡ Power-Up!" }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_100_000_000)
                    withAnimation { powerupPopup = nil }
                }
                SoundFX.shared.play(.jackpot)
            }

            // Bonus cherry collected
            if before.hasBonusItem && !after.hasBonusItem && killed == 0 && after.score > before.score {
                withAnimation { scorePopup = "🍒 +500!" }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    withAnimation { scorePopup = nil }
                }
            }

            // Level clear sound
            if after.levelsCleared > before.levelsCleared { SoundFX.shared.play(.levelUp) }

            // Life-lost sound
            if after.livesLeft < before.livesLeft {
                SoundFX.shared.play(after.isOver ? .lose : .lifeLost)
            }
        }
    }
}
