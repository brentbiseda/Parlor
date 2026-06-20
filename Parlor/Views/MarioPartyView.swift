import SwiftUI
import UIKit

// MARK: - Star Party Main View

struct MarioPartyView: View {
    @ObservedObject var session: GameSession

    @State private var diceWiggle = false
    @State private var minigameResultBanner: String? = nil
    @State private var starFlash = false
    @State private var lapFlash: Int? = nil    // seat that just completed a lap
    @State private var confettiTrigger = false

    private let playerColors: [Color] = [
        Color(red: 0.95, green: 0.28, blue: 0.30),
        Color(red: 0.28, green: 0.80, blue: 0.42),
        Color(red: 0.28, green: 0.55, blue: 0.98),
        Color(red: 0.98, green: 0.80, blue: 0.20),
    ]

    var game: MarioPartyGame? { session.game?.engine as? MarioPartyGame }

    var body: some View {
        ZStack {
            boardScreen
                .onChange(of: game?.starsSold ?? 0) { _, _ in
                    SoundFX.shared.play(.jackpot)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { starFlash = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                        withAnimation(.easeOut(duration: 0.5)) { starFlash = false }
                    }
                }
                .onChange(of: game?.minigamesPlayed ?? 0) { _, _ in
                    guard let mg = game?.lastMinigame else { return }
                    SoundFX.shared.play(.levelUp)
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                        minigameResultBanner = mg
                    }
                    Task { @MainActor in
                        do { try await Task.sleep(nanoseconds: 2_800_000_000) } catch { return }
                        withAnimation(.easeInOut(duration: 0.45)) { minigameResultBanner = nil }
                    }
                }
                .onChange(of: game?.totalRolls ?? 0) { _, _ in diceWiggle.toggle() }
                .overlay(alignment: .bottom) {
                    if let banner = minigameResultBanner { resultPill(banner) }
                }

            // Minigame overlay
            if let kind = game?.minigamePhase, session.actionableSeat != nil {
                MinigameOverlay(kind: kind, playerColors: playerColors) { score in
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    session.submit(.marioParty(.playMinigame(playerScore: score)))
                }
                .zIndex(20)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.92).combined(with: .opacity),
                    removal: .scale(scale: 1.06).combined(with: .opacity)
                ))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: kind)
            }
        }
    }

    // MARK: - Board screen

    private var boardScreen: some View {
        VStack(spacing: 8) {
            if let game {
                hudRow(game)
                boardCanvas(game)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1.08, contentMode: .fit)
                    .padding(.horizontal, 4)
                eventLine(game)
                Spacer(minLength: 0)
                controlRow(game)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - HUD

    private func hudRow(_ game: MarioPartyGame) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<MarioPartyGame.seatCount, id: \.self) { seat in
                playerChip(game, seat: seat)
            }
        }
        .padding(.horizontal, 8)
    }

    private func playerChip(_ game: MarioPartyGame, seat: Int) -> some View {
        let rolling = !game.isOver && seat == game.current && game.minigamePhase == nil
        let isYou = session.localHumanSeats.contains(seat)
        let c = playerColors[seat]
        let topStars = game.stars.max() ?? 0
        let isLeader = game.stars[seat] == topStars && topStars > 0

        return VStack(spacing: 2) {
            ZStack(alignment: .top) {
                Circle()
                    .fill(c.gradient)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().strokeBorder(
                        rolling ? .white : .white.opacity(0.4), lineWidth: rolling ? 2.5 : 1))
                    .shadow(color: rolling ? c.opacity(0.7) : .clear, radius: 6)
                    .scaleEffect(rolling ? 1.1 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: rolling)
                Text("\(seat + 1)")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                if isLeader {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.yellow)
                        .offset(y: -20)
                }
            }
            Text(session.playerName(seat: seat))
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(isYou ? .teal : .white.opacity(0.8))
                .lineLimit(1).minimumScaleFactor(0.6)
            HStack(spacing: 4) {
                Label("\(game.stars[seat])", systemImage: "star.fill")
                    .foregroundStyle(.yellow)
                Label("\(game.coins[seat])", systemImage: "circle.fill")
                    .foregroundStyle(Color(red: 0.98, green: 0.78, blue: 0.25))
            }
            .font(.system(size: 9, weight: .bold))
            .labelStyle(TightLabel())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(rolling ? c.opacity(0.18) : .white.opacity(0.05))
                .shadow(color: rolling ? c.opacity(0.4) : .clear, radius: 8)
        )
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(rolling ? c.opacity(0.9) : .white.opacity(0.1), lineWidth: rolling ? 2 : 0.75))
    }

    // MARK: - Board canvas

    private func boardCanvas(_ game: MarioPartyGame) -> some View {
        GeometryReader { geo in
            let sz = geo.size
            let inset: CGFloat = 20
            let count = MarioPartyGame.board.count
            ZStack {
                // Track shadow
                RoundedRectangle(cornerRadius: trackRadius(sz, inset: inset))
                    .fill(.black.opacity(0.25))
                    .padding(inset - 6)
                // Track outline
                RoundedRectangle(cornerRadius: trackRadius(sz, inset: inset))
                    .strokeBorder(LinearGradient(
                        colors: [.white.opacity(0.12), .white.opacity(0.06)],
                        startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 22)
                    .padding(inset)

                // Spaces
                ForEach(0..<count, id: \.self) { i in
                    spaceCircle(game, index: i)
                        .position(boardPt(i, count: count, size: sz, inset: inset))
                }

                // Center panel
                centerPanel(game, size: sz)

                // Tokens
                ForEach(0..<MarioPartyGame.seatCount, id: \.self) { seat in
                    let base = boardPt(game.positions[seat], count: count, size: sz, inset: inset)
                    let off = tokenOff(seat)
                    tokenView(seat, game: game)
                        .position(x: base.x + off.x, y: base.y + off.y)
                        .animation(.spring(response: 0.48, dampingFraction: 0.68), value: game.totalRolls)
                }
            }
            .frame(width: sz.width, height: sz.height)
        }
    }

    @ViewBuilder
    private func spaceCircle(_ game: MarioPartyGame, index: Int) -> some View {
        let isStar = index == game.starSpace
        let (col, sym) = spaceStyle(MarioPartyGame.board[index])
        if isStar {
            ZStack {
                Circle().fill(Color.yellow.gradient).frame(width: 32, height: 32)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: .yellow.opacity(starFlash ? 1.0 : 0.55),
                            radius: starFlash ? 16 : 6)
                    .scaleEffect(starFlash ? 1.25 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.5), value: starFlash)
                Image(systemName: "star.fill")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            }
        } else {
            ZStack {
                Circle().fill(col.gradient).frame(width: 27, height: 27)
                    .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1))
                Image(systemName: sym)
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.95))
            }
        }
    }

    private func tokenView(_ seat: Int, game: MarioPartyGame) -> some View {
        let isLatest = seat == game.lastMover
        return ZStack {
            Circle()
                .fill(playerColors[seat].gradient)
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(.white, lineWidth: 1.8))
                .shadow(color: .black.opacity(0.5), radius: 3, y: 1.5)
            Text("\(seat + 1)")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .scaleEffect(isLatest ? 1.2 : 1.0)
        .zIndex(isLatest ? 10 : Double(seat))
    }

    private func centerPanel(_ game: MarioPartyGame, size: CGSize) -> some View {
        VStack(spacing: 3) {
            Image(systemName: game.minigamePhase != nil ? "gamecontroller.fill" : "star.circle.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.yellow)
                .shadow(color: .yellow.opacity(0.6), radius: 8)
                .scaleEffect(starFlash ? 1.3 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.5), value: starFlash)
            Text("Round \(game.displayRound)/\(MarioPartyGame.totalRounds)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
            Text(game.minigamePhase != nil ? "🎮 Minigame!" : "⭐ costs \(MarioPartyGame.starCost)🪙")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.yellow.opacity(0.85))
        }
        .frame(width: size.width * 0.38)
        .position(x: size.width / 2, y: size.height / 2)
    }

    // MARK: - Event line

    @ViewBuilder
    private func eventLine(_ game: MarioPartyGame) -> some View {
        if game.minigamePhase != nil {
            HStack(spacing: 8) {
                Image(systemName: game.minigamePhase!.icon)
                    .foregroundStyle(.yellow)
                Text("\(game.minigamePhase!.displayName) — \(game.minigamePhase!.instructions)")
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.yellow)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(.yellow.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(.yellow.opacity(0.35), lineWidth: 0.75))
            .padding(.horizontal, 12)
        } else if let ev = game.lastEvent {
            HStack(spacing: 6) {
                if let m = game.lastMover {
                    Circle().fill(playerColors[m]).frame(width: 8, height: 8)
                    Text(session.playerName(seat: m))
                        .font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.75))
                }
                Text(ev).font(.caption.weight(.semibold)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 13).padding(.vertical, 6)
            .background(.white.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.75))
            .id(game.totalRolls)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .padding(.horizontal, 12)
        } else {
            Text("Tap the dice to start the party!")
                .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.55))
        }
    }

    private func resultPill(_ text: String) -> some View {
        VStack(spacing: 6) {
            Text("🎮 MINIGAME RESULT")
                .font(.system(size: 10, weight: .black)).kerning(2)
                .foregroundStyle(.yellow)
            Text(text)
                .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.yellow.opacity(0.45), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.55), radius: 20)
        .padding(.horizontal, 24).padding(.bottom, 90)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Control row

    @ViewBuilder
    private func controlRow(_ game: MarioPartyGame) -> some View {
        if game.minigamePhase == nil {
            HStack(spacing: 16) {
                dieFaceView(game.lastRoll)
                if session.actionableSeat != nil && !game.isOver {
                    rollButton
                } else if !game.isOver {
                    waitingIndicator(game)
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 6)
        }
    }

    private var rollButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            session.submit(.marioParty(.roll))
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "die.face.5.fill").font(.system(size: 18, weight: .bold))
                Text("ROLL").font(.system(size: 20, weight: .black, design: .rounded))
            }
            .frame(minWidth: 160)
            .padding(.vertical, 16)
            .background(LinearGradient(
                colors: [Color(red: 0.97, green: 0.35, blue: 0.42), Color(red: 0.75, green: 0.12, blue: 0.28)],
                startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.35), lineWidth: 1.2))
            .shadow(color: Color(red: 0.9, green: 0.2, blue: 0.35).opacity(0.55), radius: 12, y: 5)
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private func waitingIndicator(_ game: MarioPartyGame) -> some View {
        HStack(spacing: 10) {
            ProgressView().tint(.white).scaleEffect(0.85)
            Text("\(session.playerName(seat: game.current)) rolling…")
                .font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.65))
        }
        .frame(minWidth: 160).padding(.vertical, 16)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
    }

    private func dieFaceView(_ value: Int?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [.white, Color(white: 0.82)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 58, height: 58)
                .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black.opacity(0.12), lineWidth: 1))
            Text(value.map(String.init) ?? "?")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.82, green: 0.12, blue: 0.25))
        }
        .rotationEffect(.degrees(diceWiggle ? 10 : -10))
        .animation(.interpolatingSpring(stiffness: 200, damping: 9), value: diceWiggle)
    }

    // MARK: - Geometry helpers

    private func spaceStyle(_ space: MPSpace) -> (Color, String) {
        switch space {
        case .start:  return (Color(white: 0.52), "house.fill")
        case .blue:   return (Color(red: 0.25, green: 0.55, blue: 0.95), "plus.circle.fill")
        case .red:    return (Color(red: 0.88, green: 0.28, blue: 0.32), "minus.circle.fill")
        case .lucky:  return (Color(red: 0.28, green: 0.80, blue: 0.45), "sparkles")
        case .item:   return (Color(red: 0.60, green: 0.38, blue: 0.92), "gift.fill")
        case .bowser: return (Color(red: 0.88, green: 0.48, blue: 0.12), "flame.fill")
        case .event:  return (Color(red: 0.18, green: 0.72, blue: 0.78), "questionmark.circle.fill")
        }
    }

    private func tokenOff(_ seat: Int) -> CGPoint {
        [CGPoint(x: -8, y: -8), CGPoint(x: 8, y: -8),
         CGPoint(x: -8, y:  8), CGPoint(x: 8, y:  8)][seat]
    }

    private func trackRadius(_ size: CGSize, inset: CGFloat) -> CGFloat {
        min(size.width - inset * 2, size.height - inset * 2) * 0.20
    }

    private func boardPt(_ index: Int, count: Int, size: CGSize, inset: CGFloat) -> CGPoint {
        let w = size.width - inset * 2, h = size.height - inset * 2
        let cr = min(w, h) * 0.20
        let topLen = w - 2 * cr, sideLen = h - 2 * cr
        let arc = (CGFloat.pi / 2) * cr
        let total = 2 * topLen + 2 * sideLen + 4 * arc
        let ox = inset, oy = inset
        var d = CGFloat(index) / CGFloat(count) * total
        if d < topLen { return CGPoint(x: ox + cr + d, y: oy) }
        d -= topLen
        if d < arc { let a = d/cr - .pi/2; return CGPoint(x: ox+w-cr+cos(a)*cr, y: oy+cr+sin(a)*cr) }
        d -= arc
        if d < sideLen { return CGPoint(x: ox+w, y: oy+cr+d) }
        d -= sideLen
        if d < arc { let a = d/cr; return CGPoint(x: ox+w-cr+cos(a)*cr, y: oy+h-cr+sin(a)*cr) }
        d -= arc
        if d < topLen { return CGPoint(x: ox+w-cr-d, y: oy+h) }
        d -= topLen
        if d < arc { let a = .pi/2+d/cr; return CGPoint(x: ox+cr+cos(a)*cr, y: oy+h-cr+sin(a)*cr) }
        d -= arc
        if d < sideLen { return CGPoint(x: ox, y: oy+h-cr-d) }
        d -= sideLen
        let a = CGFloat.pi + d/cr
        return CGPoint(x: ox+cr+cos(a)*cr, y: oy+cr+sin(a)*cr)
    }
}

// MARK: - Minigame Overlay Container

private struct MinigameOverlay: View {
    let kind: MinigameKind
    let playerColors: [Color]
    let onDone: (Int) -> Void

    var accentColor: Color {
        switch kind.accentColor {
        case "red":    return Color(red: 0.92, green: 0.22, blue: 0.25)
        case "yellow": return Color(red: 0.98, green: 0.82, blue: 0.12)
        case "gold":   return Color(red: 0.98, green: 0.72, blue: 0.15)
        case "green":  return Color(red: 0.22, green: 0.85, blue: 0.42)
        case "purple": return Color(red: 0.68, green: 0.32, blue: 0.95)
        case "orange": return Color(red: 0.95, green: 0.52, blue: 0.12)
        case "teal":   return Color(red: 0.15, green: 0.82, blue: 0.75)
        case "blue":   return Color(red: 0.28, green: 0.55, blue: 0.98)
        case "indigo": return Color(red: 0.38, green: 0.32, blue: 0.92)
        case "pink":   return Color(red: 0.95, green: 0.35, blue: 0.68)
        default:       return .yellow
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            // Colored glow behind
            accentColor.opacity(0.08).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    ZStack {
                        Circle().fill(accentColor.opacity(0.18)).frame(width: 64, height: 64)
                        Image(systemName: kind.icon)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(accentColor)
                    }
                    Text(kind.displayName.uppercased())
                        .font(.system(size: 17, weight: .black)).kerning(2.5)
                        .foregroundStyle(accentColor)
                    Text(kind.instructions)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.top, 28)
                .padding(.bottom, 12)

                Divider().background(.white.opacity(0.1)).padding(.horizontal, 20)

                // Game body
                switch kind {
                case .tapFrenzy:    TapFrenzyGame(accent: accentColor, onDone: onDone)
                case .starSprint:   StarSprintGame(accent: accentColor, onDone: onDone)
                case .coinDash:     CoinDashGame(accent: accentColor, onDone: onDone)
                case .quickDraw:    QuickDrawGame(accent: accentColor, onDone: onDone)
                case .memoryMatch:  MemoryMatchGame(accent: accentColor, onDone: onDone)
                case .colorBlast:   ColorBlastGame(accent: accentColor, onDone: onDone)
                case .balanceAct:   BalanceActGame(accent: accentColor, onDone: onDone)
                case .numberCrunch: NumberCrunchGame(accent: accentColor, onDone: onDone)
                case .bombDefuse:   BombDefuseGame(accent: accentColor, onDone: onDone)
                case .starMap:      StarMapGame(accent: accentColor, onDone: onDone)
                case .rhythmTap:    RhythmTapGame(accent: accentColor, onDone: onDone)
                case .priceIsRight: PriceIsRightGame(accent: accentColor, onDone: onDone)
                case .treasureHunt: TreasureHuntGame(accent: accentColor, onDone: onDone)
                case .spinWheel:    SpinWheelGame(accent: accentColor, onDone: onDone)
                }
            }
        }
    }
}

// MARK: - 1. Tap Frenzy

private struct TapFrenzyGame: View {
    let accent: Color
    let onDone: (Int) -> Void
    @State private var taps = 0
    @State private var timeLeft: Double = 4.0
    @State private var running = false
    @State private var done = false
    @State private var btnScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 10)
                Circle().trim(from: 0, to: CGFloat(max(0, timeLeft / 4.0)))
                    .stroke(timerColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: timeLeft)
                VStack(spacing: 0) {
                    Text("\(Int(ceil(timeLeft)))")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("sec").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.45))
                }
            }
            .frame(width: 110, height: 110)

            Text("\(taps) taps")
                .font(.system(size: 52, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())

            Button {
                if !running && !done { running = true; startTimer() }
                guard running && !done else { return }
                taps += 1
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                withAnimation(.interpolatingSpring(stiffness: 600, damping: 10)) { btnScale = 0.88 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
                    withAnimation(.spring(response: 0.12)) { btnScale = 1.0 }
                }
            } label: {
                Text(running ? "TAP!" : (done ? "Done ✓" : "START"))
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .frame(width: 170, height: 170)
                    .background(Circle().fill(LinearGradient(
                        colors: running ? [accent, accent.opacity(0.6)] : [accent.opacity(0.7), accent.opacity(0.4)],
                        startPoint: .top, endPoint: .bottom)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 2))
                    .shadow(color: accent.opacity(0.55), radius: 18, y: 4)
                    .foregroundStyle(.white)
                    .scaleEffect(btnScale)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.top, 16).padding(.horizontal, 32).padding(.bottom, 16)
    }

    private var timerColor: Color {
        timeLeft > 2 ? Color(red: 0.25, green: 0.9, blue: 0.5) : timeLeft > 1 ? .yellow : .red
    }

    private func startTimer() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { t in
            guard running && !done else { t.invalidate(); return }
            timeLeft = max(0, timeLeft - 0.1)
            if timeLeft <= 0 {
                t.invalidate(); done = true; running = false
                SoundFX.shared.play(.win)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    onDone(min(100, taps * 4))
                }
            }
        }
    }
}

// MARK: - 2. Star Sprint

private struct StarSprintGame: View {
    let accent: Color
    let onDone: (Int) -> Void
    @State private var pos = 4
    @State private var round = 0
    @State private var hits = 0
    @State private var started = false
    @State private var visible = true
    @State private var waiting = false
    @State private var flash = false
    @State private var appear: Date? = nil
    let total = 6

    var body: some View {
        VStack(spacing: 14) {
            Text("\(hits) hits · round \(min(round+1, total))/\(total)")
                .font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.7))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(0..<9, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.white.opacity(0.07))
                        .frame(height: 86)
                        .overlay {
                            if i == pos && visible {
                                ZStack {
                                    Circle().fill(accent.opacity(0.2)).frame(width: 52)
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 32)).foregroundStyle(accent)
                                        .shadow(color: accent.opacity(flash ? 1.0 : 0.5), radius: flash ? 18 : 8)
                                        .scaleEffect(flash ? 1.3 : 1.0)
                                        .animation(.spring(response: 0.15), value: flash)
                                }
                            }
                        }
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.1)))
                        .onTapGesture {
                            guard visible && i == pos && started && !waiting else { return }
                            let ms = appear.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 750
                            hits += 1
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                            flash = true
                            SoundFX.shared.play(.jackpot)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { flash = false }
                            next(scored: true, ms: ms)
                        }
                }
            }
            .padding(.horizontal, 20)
            if !started {
                Button("Start") { started = true; next(scored: false, ms: 0) }
                    .font(.headline.weight(.bold))
                    .padding(.horizontal, 32).padding(.vertical, 12)
                    .background(accent, in: Capsule()).foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(.top, 14).padding(.bottom, 16)
    }

    private func next(scored: Bool, ms: Int) {
        _ = ms
        guard round < total else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onDone(min(100, hits * 16 + hits * 2)) }
            return
        }
        waiting = true; visible = false
        pos = Int.random(in: 0..<9)
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0.35...0.65)) {
            round += 1; appear = Date(); visible = true; waiting = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                guard visible else { return }
                visible = false
                SoundFX.shared.play(.click)
                next(scored: false, ms: 0)
            }
        }
    }
}

// MARK: - 3. Coin Dash

private struct CoinDashGame: View {
    let accent: Color
    let onDone: (Int) -> Void
    @State private var caught = 0
    @State private var coinX: CGFloat = 0.5
    @State private var coinY: CGFloat = -0.1
    @State private var coinVisible = false
    @State private var coinIndex = 0
    @State private var fallId = 0
    @State private var pop = false
    let total = 10

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Coin \(min(coinIndex+1, total))/\(total)")
                    .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.65))
                Spacer()
                Label("\(caught)", systemImage: "circle.fill")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(accent)
            }
            .padding(.horizontal, 24)
            GeometryReader { geo in
                ZStack {
                    if coinVisible {
                        ZStack {
                            Circle().fill(accent).frame(width: 54, height: 54)
                                .overlay(Circle().strokeBorder(.white.opacity(0.65), lineWidth: 2))
                                .shadow(color: accent.opacity(pop ? 1.0 : 0.6), radius: pop ? 24 : 10)
                                .scaleEffect(pop ? 1.45 : 1.0)
                                .animation(.spring(response: 0.12), value: pop)
                            Text("🪙").font(.system(size: 26))
                        }
                        .position(x: coinX * geo.size.width, y: coinY * geo.size.height)
                        .onTapGesture {
                            guard coinVisible else { return }
                            caught += 1; pop = true
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                            SoundFX.shared.play(.jackpot)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
                                coinVisible = false; pop = false; spawn()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.05)))
                .onAppear { spawn() }
            }
            .frame(height: 260)
            .padding(.horizontal, 20)
            Spacer()
        }
        .padding(.top, 12).padding(.bottom, 16)
    }

    private func spawn() {
        guard coinIndex < total else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onDone(min(100, caught * 10)) }
            return
        }
        let id = fallId + 1; fallId = id
        coinX = CGFloat.random(in: 0.15...0.85)
        coinY = -0.08; coinIndex += 1; coinVisible = true
        withAnimation(.linear(duration: 1.6)) { coinY = 1.05 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            guard fallId == id, coinVisible else { return }
            coinVisible = false; SoundFX.shared.play(.click); spawn()
        }
    }
}

// MARK: - 4. Quick Draw

private struct QuickDrawGame: View {
    let accent: Color
    let onDone: (Int) -> Void
    enum Ph { case idle, ready, green, showResult, done }
    @State private var ph: Ph = .idle
    @State private var round = 0
    @State private var score = 0
    @State private var msg = ""
    @State private var tooEarly = false
    @State private var greenAt: Date? = nil
    @State private var tid = UUID()
    let total = 5

    var body: some View {
        VStack(spacing: 22) {
            Text("Round \(min(round+1, total))/\(total) · score \(score)")
                .font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.7))
            if !msg.isEmpty {
                Text(msg).font(.callout.weight(.semibold)).foregroundStyle(tooEarly ? .orange : accent)
                    .transition(.opacity)
            }
            ZStack {
                Circle()
                    .fill(circleColor)
                    .frame(width: 165, height: 165)
                    .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 3))
                    .shadow(color: circleColor.opacity(ph == .green ? 0.7 : 0.3), radius: ph == .green ? 28 : 8)
                    .animation(.easeInOut(duration: 0.12), value: ph == .green)
                Text(ph == .ready ? "Wait…" : ph == .green ? "GO!" : ph == .idle && round == 0 ? "TAP" : "Next →")
                    .font(.system(size: 24, weight: .black, design: .rounded)).foregroundStyle(.white)
            }
            .onTapGesture { handleTap() }
            if ph == .idle && round == 0 {
                Button("Start") { ph = .ready; scheduleGreen() }
                    .font(.headline.weight(.bold)).padding(.horizontal, 32).padding(.vertical, 12)
                    .background(accent, in: Capsule()).foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(.top, 16).padding(.horizontal, 32).padding(.bottom, 16)
    }

    private var circleColor: Color {
        switch ph {
        case .ready: return Color(red: 0.85, green: 0.15, blue: 0.2)
        case .green: return Color(red: 0.18, green: 0.85, blue: 0.38)
        default:     return Color(white: 0.38)
        }
    }

    private func handleTap() {
        switch ph {
        case .idle where round > 0: ph = .ready; scheduleGreen()
        case .ready:
            tooEarly = true; msg = "Too early! 0 pts"; ph = .showResult; tid = UUID()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { tooEarly = false; advance(s: 0) }
        case .green:
            let ms = Int((Date().timeIntervalSince(greenAt ?? Date())) * 1000)
            let pts = max(0, 100 - ms / 8)
            score += pts; msg = "\(ms) ms  +\(pts)"; UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            SoundFX.shared.play(.jackpot); ph = .showResult; tid = UUID()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { advance(s: pts) }
        default: break
        }
    }

    private func scheduleGreen() {
        let id = tid
        let delay = Double.random(in: 1.0...2.6)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard tid == id, ph == .ready else { return }
            ph = .green; greenAt = Date(); SoundFX.shared.play(.click)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                guard tid == id, ph == .green else { return }
                msg = "Too slow!"; ph = .showResult
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { advance(s: 0) }
            }
        }
    }

    private func advance(s: Int) {
        _ = s; round += 1
        if round >= total { ph = .done; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onDone(min(100, score)) }
        } else { ph = .idle }
    }
}

// MARK: - 5. Memory Match

private struct MemoryMatchGame: View {
    let accent: Color
    let onDone: (Int) -> Void

    struct Card: Identifiable {
        let id = UUID()
        let symbol: String
        var flipped = false
        var matched = false
    }

    let symbols = ["⭐","🪙","🎮","🎲","🎀","🎯"]
    @State private var cards: [Card] = []
    @State private var selected: [UUID] = []
    @State private var pairs = 0
    @State private var moves = 0
    @State private var locked = false
    @State private var peekDone = false

    var body: some View {
        VStack(spacing: 12) {
            Text("\(pairs)/\(symbols.count) pairs · \(moves) flips")
                .font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.7))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(cards) { card in
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(card.matched ? accent.opacity(0.25) :
                                  card.flipped ? .white.opacity(0.14) : .white.opacity(0.07))
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(card.matched ? accent : .white.opacity(0.15)))
                            .frame(height: 70)
                        if card.flipped || card.matched {
                            Text(card.symbol).font(.system(size: 28))
                        } else {
                            Image(systemName: "questionmark").font(.title2.weight(.bold))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                    .onTapGesture { flip(card) }
                }
            }
            .padding(.horizontal, 16)
            Spacer()
        }
        .padding(.top, 14).padding(.bottom, 16)
        .onAppear { setup() }
    }

    private func setup() {
        var c: [Card] = []
        for s in symbols { c += [Card(symbol: s), Card(symbol: s)] }
        cards = c.shuffled()
        // Brief peek
        for i in cards.indices { cards[i].flipped = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            for i in cards.indices { cards[i].flipped = false }
            peekDone = true
        }
    }

    private func flip(_ card: Card) {
        guard peekDone, !locked, !card.matched, !card.flipped,
              let idx = cards.firstIndex(where: { $0.id == card.id }) else { return }
        cards[idx].flipped = true
        selected.append(card.id)
        moves += 1
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if selected.count == 2 {
            locked = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { check() }
        }
    }

    private func check() {
        let ids = selected
        let syms = ids.compactMap { id in cards.first(where: { $0.id == id })?.symbol }
        if syms.count == 2 && syms[0] == syms[1] {
            for i in cards.indices where ids.contains(cards[i].id) { cards[i].matched = true }
            pairs += 1
            SoundFX.shared.play(.jackpot)
            if pairs == symbols.count {
                let score = max(0, 100 - (moves - symbols.count) * 5)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onDone(min(100, score)) }
            }
        } else {
            for i in cards.indices where ids.contains(cards[i].id) { cards[i].flipped = false }
        }
        selected = []; locked = false
    }
}

// MARK: - 6. Color Blast

private struct ColorBlastGame: View {
    let accent: Color
    let onDone: (Int) -> Void

    let colors: [(Color, String)] = [
        (.red, "red"), (.blue, "blue"), (.green, "green"), (.yellow, "yellow"), (.purple, "purple")
    ]
    @State private var target: String = "red"
    @State private var targetColor: Color = .red
    @State private var grid: [(Color, String)] = []
    @State private var hits = 0
    @State private var misses = 0
    @State private var round = 0
    let total = 12

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Text("Tap:").font(.callout.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
                Circle().fill(targetColor).frame(width: 36, height: 36)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: targetColor.opacity(0.7), radius: 8)
                Text(target.capitalized).font(.title3.weight(.black)).foregroundStyle(.white)
            }
            Text("\(round)/\(total) · ✅\(hits) ❌\(misses)")
                .font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.65))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(0..<grid.count, id: \.self) { i in
                    Circle().fill(grid[i].0)
                        .frame(width: 58, height: 58)
                        .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
                        .shadow(color: grid[i].0.opacity(0.5), radius: 5)
                        .onTapGesture { tapped(i) }
                }
            }
            .padding(.horizontal, 16)
            Spacer()
        }
        .padding(.top, 14).padding(.bottom, 16)
        .onAppear { buildGrid(); pickTarget() }
    }

    private func buildGrid() {
        grid = (0..<12).map { _ in colors.randomElement()! }
    }

    private func pickTarget() {
        let c = colors.randomElement()!
        target = c.1; targetColor = c.0
    }

    private func tapped(_ i: Int) {
        guard round < total else { return }
        let correct = grid[i].1 == target
        if correct { hits += 1; SoundFX.shared.play(.jackpot) }
        else { misses += 1; UINotificationFeedbackGenerator().notificationOccurred(.error) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        round += 1
        buildGrid(); pickTarget()
        if round >= total {
            let score = min(100, hits * 10 - misses * 5)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onDone(max(0, score)) }
        }
    }
}

// MARK: - 7. Balance Act

private struct BalanceActGame: View {
    let accent: Color
    let onDone: (Int) -> Void
    @State private var needle: Double = 0.5   // 0 = far left, 1 = far right
    @State private var velocity: Double = 0
    @State private var timeLeft: Double = 8.0
    @State private var running = false
    @State private var goodTime: Double = 0   // seconds needle was near center

    var body: some View {
        VStack(spacing: 18) {
            Text(String(format: "%.1f sec", timeLeft))
                .font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(.white)

            // Balance bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.white.opacity(0.1)).frame(height: 18)
                    // Center zone indicator
                    RoundedRectangle(cornerRadius: 5)
                        .fill(accent.opacity(0.22))
                        .frame(width: geo.size.width * 0.24, height: 18)
                        .offset(x: geo.size.width * 0.38)
                    // Needle
                    Circle()
                        .fill(needleColor)
                        .frame(width: 28, height: 28)
                        .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 2))
                        .shadow(color: needleColor.opacity(0.7), radius: 8)
                        .offset(x: geo.size.width * needle - 14, y: -5)
                        .animation(.easeOut(duration: 0.05), value: needle)
                    // Center marker
                    Rectangle().fill(.white.opacity(0.35)).frame(width: 2, height: 26)
                        .offset(x: geo.size.width / 2 - 1, y: -4)
                }
                .frame(height: 18)
            }
            .frame(height: 28).padding(.horizontal, 24)

            HStack(spacing: 14) {
                Button("← LEFT") { push(left: true) }
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
                    .background(Color(red: 0.28, green: 0.55, blue: 0.98), in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
                Button("RIGHT →") { push(left: false) }
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
                    .background(Color(red: 0.88, green: 0.28, blue: 0.32), in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain).padding(.horizontal, 20)
            Spacer()
        }
        .padding(.top, 14).padding(.bottom, 16)
        .onAppear {
            running = true; needle = Double.random(in: 0.3...0.7)
            Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { t in
                guard running else { t.invalidate(); return }
                // Drift toward edges (gravity) + damping
                let drift = (needle - 0.5) * 0.06
                velocity += drift; velocity *= 0.88
                needle = max(0.02, min(0.98, needle + velocity * 0.05))
                let centered = abs(needle - 0.5) < 0.12
                if centered { goodTime += 0.05 }
                timeLeft = max(0, timeLeft - 0.05)
                if timeLeft <= 0 {
                    t.invalidate(); running = false
                    SoundFX.shared.play(.win)
                    let score = min(100, Int(goodTime / 8.0 * 100))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onDone(score) }
                }
            }
        }
    }

    private var needleColor: Color {
        abs(needle - 0.5) < 0.12 ? accent : abs(needle - 0.5) < 0.28 ? .yellow : .red
    }

    private func push(left: Bool) {
        guard running else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        velocity += left ? -0.06 : 0.06
    }
}

// MARK: - 8. Number Crunch

private struct NumberCrunchGame: View {
    let accent: Color
    let onDone: (Int) -> Void
    @State private var numbers: [Int] = []
    @State private var nextTarget = 1
    @State private var hits = 0
    @State private var misses = 0
    @State private var startTime = Date()
    let count = 9

    var body: some View {
        VStack(spacing: 14) {
            Text("Tap  \(nextTarget)  next! · \(hits) hits · \(misses) misses")
                .font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.7))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(numbers, id: \.self) { n in
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(n < nextTarget ? accent.opacity(0.18) : .white.opacity(0.08))
                            .frame(height: 80)
                            .overlay(RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(n == nextTarget ? accent : .white.opacity(0.12),
                                              lineWidth: n == nextTarget ? 2 : 0.75))
                        Text("\(n)")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(n < nextTarget ? accent.opacity(0.4) : .white)
                    }
                    .onTapGesture {
                        if n == nextTarget {
                            hits += 1; nextTarget += 1
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            SoundFX.shared.play(.click)
                            if nextTarget > count {
                                let elapsed = Date().timeIntervalSince(startTime)
                                let score = max(0, 100 - Int(elapsed * 8))
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onDone(min(100, score)) }
                            }
                        } else {
                            misses += 1; UINotificationFeedbackGenerator().notificationOccurred(.error)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            Spacer()
        }
        .padding(.top, 14).padding(.bottom, 16)
        .onAppear { numbers = (1...count).shuffled(); startTime = Date() }
    }
}

// MARK: - 9. Bomb Defuse

private struct BombDefuseGame: View {
    let accent: Color
    let onDone: (Int) -> Void
    let colors: [Color] = [Color(red: 0.92,green:0.25,blue:0.28), Color(red:0.25,green:0.55,blue:0.98),
                           Color(red:0.28,green:0.8,blue:0.45), Color(red:0.98,green:0.8,blue:0.15)]
    let wireNames = ["RED","BLUE","GREEN","YELLOW"]
    @State private var safeWire = 0
    @State private var round = 0
    @State private var score = 0
    @State private var hint = ""
    @State private var cutResult = ""
    @State private var waiting = false
    let total = 4

    var body: some View {
        VStack(spacing: 16) {
            Text("Round \(min(round+1, total))/\(total) · \(score) pts")
                .font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.7))
            if !hint.isEmpty {
                Text(hint)
                    .font(.callout.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 20).multilineTextAlignment(.center)
            }
            if !cutResult.isEmpty {
                Text(cutResult)
                    .font(.title3.weight(.black)).foregroundStyle(cutResult.contains("✅") ? .green : .red)
                    .transition(.scale.combined(with: .opacity))
            }
            if !waiting {
                VStack(spacing: 12) {
                    ForEach(0..<4, id: \.self) { i in
                        HStack(spacing: 14) {
                            RoundedRectangle(cornerRadius: 3).fill(colors[i])
                                .frame(maxWidth: .infinity, minHeight: 8, maxHeight: 8)
                                .shadow(color: colors[i].opacity(0.7), radius: 5)
                            Button("CUT") { cut(i) }
                                .font(.system(size: 14, weight: .black, design: .rounded))
                                .padding(.horizontal, 18).padding(.vertical, 9)
                                .background(colors[i].opacity(0.8), in: Capsule())
                                .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1))
                                .foregroundStyle(.white)
                                .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 24)
                    }
                }
            }
            Spacer()
        }
        .padding(.top, 14).padding(.bottom, 16)
        .onAppear { nextBomb() }
    }

    private func nextBomb() {
        safeWire = Int.random(in: 0..<4)
        waiting = false; cutResult = ""
        let hints = [
            "Not the red one!", "The safe wire isn't yellow.", "Cut the bright one.", "Avoid the warm color.",
            "It's blue or green.", "Don't cut red.", "Think cool colors.", "The answer glows."
        ]
        hint = hints.randomElement()!
    }

    private func cut(_ i: Int) {
        waiting = true
        let correct = i == safeWire
        if correct {
            score += 25
            cutResult = "✅ Defused! +25 pts"
            SoundFX.shared.play(.jackpot)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } else {
            cutResult = "💥 BOOM! Wrong wire!"
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            SoundFX.shared.play(.lifeLost)
        }
        round += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            if round >= total { onDone(min(100, score)) } else { nextBomb() }
        }
    }
}

// MARK: - 10. Star Map

private struct StarMapGame: View {
    let accent: Color
    let onDone: (Int) -> Void
    @State private var pattern: [Int] = []
    @State private var tapped: [Int] = []
    @State private var showing = true
    @State private var done = false
    @State private var score = 0
    @State private var flash: Set<Int> = []
    let gridSize = 5

    var body: some View {
        VStack(spacing: 14) {
            Text(showing ? "Memorize!" : "Tap the pattern!")
                .font(.callout.weight(.bold))
                .foregroundStyle(showing ? .yellow : accent)
            Text("\(tapped.count)/\(pattern.count) stars")
                .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: gridSize), spacing: 6) {
                ForEach(0..<(gridSize*gridSize), id: \.self) { i in
                    let inPattern = pattern.contains(i)
                    let wasTapped = tapped.contains(i)
                    let isFlash = flash.contains(i)
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill((showing && inPattern) || isFlash ? .yellow.opacity(0.35) :
                                  wasTapped ? (inPattern ? accent.opacity(0.3) : .red.opacity(0.2)) : .white.opacity(0.06))
                            .frame(height: 46)
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder((showing && inPattern) || isFlash ? .yellow : .white.opacity(0.1),
                                              lineWidth: (showing && inPattern) ? 1.5 : 0.75))
                        if (showing && inPattern) || isFlash {
                            Image(systemName: "star.fill").font(.system(size: 14)).foregroundStyle(.yellow)
                        } else if wasTapped {
                            Image(systemName: inPattern ? "checkmark" : "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(inPattern ? accent : .red)
                        }
                    }
                    .onTapGesture { tapCell(i) }
                }
            }
            .padding(.horizontal, 16)
            Spacer()
        }
        .padding(.top, 14).padding(.bottom, 16)
        .onAppear { setup() }
    }

    private func setup() {
        let count = 5
        pattern = Array(Set((0..<(gridSize*gridSize)).shuffled().prefix(count)))
        showing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { showing = false }
    }

    private func tapCell(_ i: Int) {
        guard !showing, !tapped.contains(i) else { return }
        tapped.append(i)
        let correct = pattern.contains(i)
        if correct { flash.insert(i); SoundFX.shared.play(.jackpot) }
        else { UINotificationFeedbackGenerator().notificationOccurred(.error) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if tapped.count >= pattern.count && !done {
            done = true
            let hits = tapped.filter { pattern.contains($0) }.count
            let s = min(100, hits * 20)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { onDone(s) }
        }
    }
}

// MARK: - 11. Rhythm Tap

private struct RhythmTapGame: View {
    let accent: Color
    let onDone: (Int) -> Void
    @State private var beat = 0
    @State private var hits = 0
    @State private var pulse = false
    @State private var started = false
    @State private var lastTapBeat = -2
    @State private var feedback = ""
    let total = 8
    let bpm: Double = 100   // beats per minute

    var body: some View {
        VStack(spacing: 20) {
            Text("Beat \(min(beat+1, total))/\(total) · \(hits) on beat")
                .font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.7))
            Text(feedback)
                .font(.callout.weight(.black)).foregroundStyle(accent)
                .animation(.none, value: feedback)
            ZStack {
                Circle().fill(.white.opacity(0.07)).frame(width: 160, height: 160)
                Circle().fill(accent.opacity(pulse ? 0.6 : 0.15)).frame(width: 140, height: 140)
                    .animation(.easeOut(duration: 0.08), value: pulse)
                Image(systemName: "music.note")
                    .font(.system(size: 44, weight: .bold)).foregroundStyle(.white)
                    .scaleEffect(pulse ? 1.18 : 1.0)
                    .animation(.easeOut(duration: 0.08), value: pulse)
            }
            .onTapGesture {
                guard started else { return }
                let diff = abs(beat - lastTapBeat)
                if diff <= 1 {
                    hits += 1; feedback = "🎵 On beat!"; UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } else {
                    feedback = "Off beat"; UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
                lastTapBeat = beat
            }
            if !started {
                Button("Start") { started = true; runBeats() }
                    .font(.headline.weight(.bold)).padding(.horizontal, 32).padding(.vertical, 12)
                    .background(accent, in: Capsule()).foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(.top, 14).padding(.horizontal, 32).padding(.bottom, 16)
    }

    private func runBeats() {
        let interval = 60.0 / bpm
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { t in
            guard beat < total else { t.invalidate()
                SoundFX.shared.play(.win)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onDone(min(100, hits * 13)) }
                return
            }
            pulse = true; SoundFX.shared.play(.click); beat += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { pulse = false }
        }
    }
}

// MARK: - 12. Price Is Right

private struct PriceIsRightGame: View {
    let accent: Color
    let onDone: (Int) -> Void
    @State private var prev = 0
    @State private var current = 0
    @State private var round = 0
    @State private var score = 0
    @State private var result = ""
    @State private var waiting = false
    let total = 6

    var body: some View {
        VStack(spacing: 18) {
            Text("Round \(min(round+1, total))/\(total) · \(score) pts")
                .font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.7))
            if prev > 0 {
                HStack(spacing: 6) {
                    Text("Was:").foregroundStyle(.white.opacity(0.55))
                    Label("\(prev)", systemImage: "circle.fill").foregroundStyle(.yellow)
                }
                .font(.callout.weight(.semibold))
            }
            if !result.isEmpty {
                Text(result).font(.title3.weight(.black))
                    .foregroundStyle(result.contains("✅") ? accent : .red)
                    .transition(.scale.combined(with: .opacity))
            }
            if !waiting {
                VStack(spacing: 10) {
                    Text("New amount:")
                        .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.55))
                    Label("\(current)", systemImage: "circle.fill")
                        .font(.system(size: 42, weight: .black)).foregroundStyle(.yellow)
                    HStack(spacing: 16) {
                        Button("⬆ HIGHER") { guess(higher: true) }
                            .font(.system(size: 18, weight: .black)).frame(maxWidth: .infinity).padding(.vertical, 18)
                            .background(Color(red: 0.22, green: 0.8, blue: 0.42), in: RoundedRectangle(cornerRadius: 16))
                            .foregroundStyle(.white).buttonStyle(.plain)
                        Button("LOWER ⬇") { guess(higher: false) }
                            .font(.system(size: 18, weight: .black)).frame(maxWidth: .infinity).padding(.vertical, 18)
                            .background(Color(red: 0.88, green: 0.28, blue: 0.32), in: RoundedRectangle(cornerRadius: 16))
                            .foregroundStyle(.white).buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                }
            }
            Spacer()
        }
        .padding(.top, 14).padding(.bottom, 16)
        .onAppear { prev = Int.random(in: 5...50); current = Int.random(in: 5...50) }
    }

    private func guess(higher: Bool) {
        let correct = higher ? current > prev : current < prev
        prev = current
        if correct {
            score += 17; result = "✅ Correct! +17"; SoundFX.shared.play(.jackpot)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } else {
            result = "❌ Wrong!"; UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        waiting = true; round += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            if round >= total { onDone(min(100, score)) } else {
                current = Int.random(in: 5...50); result = ""; waiting = false
            }
        }
    }
}

// MARK: - 13. Treasure Hunt

private struct TreasureHuntGame: View {
    let accent: Color
    let onDone: (Int) -> Void
    @State private var hidden = 0
    @State private var guesses: [Int] = []
    @State private var hints: [String] = []
    let grid = 4
    let maxGuesses = 3

    var body: some View {
        VStack(spacing: 14) {
            Text("Find the star · \(maxGuesses - guesses.count) guess\(maxGuesses - guesses.count == 1 ? "" : "es") left")
                .font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.7))
            if let last = hints.last {
                Text(last).font(.callout.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: grid), spacing: 8) {
                ForEach(0..<(grid*grid), id: \.self) { i in
                    let guessed = guesses.contains(i)
                    let isHidden = i == hidden && (guesses.count >= maxGuesses || guesses.last == hidden)
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isHidden ? .yellow.opacity(0.3) : guessed ? .white.opacity(0.18) : .white.opacity(0.07))
                            .frame(height: 60)
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(isHidden ? .yellow : .white.opacity(0.12), lineWidth: isHidden ? 2 : 0.75))
                        if isHidden {
                            Image(systemName: "star.fill").font(.system(size: 22)).foregroundStyle(.yellow)
                        } else if guessed {
                            Text(hintIcon(i)).font(.system(size: 18))
                        }
                    }
                    .onTapGesture { tap(i) }
                    .disabled(guessed || guesses.count >= maxGuesses)
                }
            }
            .padding(.horizontal, 16)
            Spacer()
        }
        .padding(.top, 14).padding(.bottom, 16)
        .onAppear { hidden = Int.random(in: 0..<(grid*grid)) }
    }

    private func hintIcon(_ i: Int) -> String {
        let dist = distance(i, hidden)
        if dist == 0 { return "⭐" }
        if dist <= 2 { return "🔥" }
        if dist <= 4 { return "🌡" }
        return "❄️"
    }

    private func distance(_ a: Int, _ b: Int) -> Int {
        let ax = a % grid, ay = a / grid, bx = b % grid, by = b / grid
        return abs(ax - bx) + abs(ay - by)
    }

    private func tap(_ i: Int) {
        guard !guesses.contains(i), guesses.count < maxGuesses else { return }
        guesses.append(i)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if i == hidden {
            hints = ["⭐ Found it!"]
            SoundFX.shared.play(.jackpot)
            let score = (maxGuesses - guesses.count + 1) * 33   // 99, 66, 33
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onDone(min(100, score)) }
        } else {
            let dist = distance(i, hidden)
            let hintText = dist <= 2 ? "🔥 Very close!" : dist <= 4 ? "🌡 Getting warmer" : "❄️ Far away"
            hints.append(hintText)
            if guesses.count >= maxGuesses {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { onDone(0) }
            }
        }
    }
}

// MARK: - 14. Spin the Wheel

private struct SpinWheelGame: View {
    let accent: Color
    let onDone: (Int) -> Void
    @State private var angle: Double = 0
    @State private var spinning = false
    @State private var result = ""
    @State private var done = false
    @State private var displayAngle: Double = 0

    let sliceCount = 8
    let goldSlices: Set<Int> = [0, 3]   // two gold slices out of 8

    var body: some View {
        VStack(spacing: 18) {
            Text("Tap SPIN — stop on gold!")
                .font(.callout.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
            if !result.isEmpty {
                Text(result).font(.title3.weight(.black))
                    .foregroundStyle(result.contains("⭐") ? .yellow : .red)
                    .transition(.scale.combined(with: .opacity))
            }
            ZStack {
                // Wheel
                ForEach(0..<sliceCount, id: \.self) { i in
                    slicePath(i)
                        .fill(goldSlices.contains(i) ? Color(red: 0.98, green: 0.78, blue: 0.15) :
                              i % 2 == 0 ? Color(red: 0.88, green: 0.28, blue: 0.32) : Color(red: 0.28, green: 0.55, blue: 0.98))
                    slicePath(i).stroke(.black.opacity(0.4), lineWidth: 2)
                    GeometryReader { geo in
                        let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                        let r: CGFloat = 55
                        let a = (.pi * 2 / Double(sliceCount)) * (Double(i) + 0.5) - .pi / 2
                        Text(goldSlices.contains(i) ? "⭐" : "✕")
                            .font(.system(size: 16, weight: .bold))
                            .position(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                    }
                }
                .rotationEffect(.degrees(displayAngle))
                Circle().fill(.black.opacity(0.3)).frame(width: 30, height: 30)
                // Pointer
                Triangle().fill(.white).frame(width: 16, height: 22).offset(y: -82)
            }
            .frame(width: 170, height: 170)

            if !done {
                Button(spinning ? "…" : "SPIN!") {
                    guard !spinning else { return }
                    spin()
                }
                .font(.system(size: 22, weight: .black, design: .rounded))
                .frame(minWidth: 140).padding(.vertical, 14)
                .background(accent, in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(.white).buttonStyle(.plain)
                .disabled(spinning)
            }
            Spacer()
        }
        .padding(.top, 14).padding(.horizontal, 24).padding(.bottom, 16)
    }

    private func slicePath(_ i: Int) -> Path {
        let slice = .pi * 2 / Double(sliceCount)
        let start = slice * Double(i) - .pi / 2
        let end = start + slice
        var p = Path()
        p.move(to: CGPoint(x: 85, y: 85))
        p.addArc(center: CGPoint(x: 85, y: 85), radius: 80, startAngle: .radians(start), endAngle: .radians(end), clockwise: false)
        p.closeSubpath()
        return p
    }

    private func spin() {
        spinning = true; SoundFX.shared.play(.launch)
        let spins = Double.random(in: 4...9) * 360
        let finalAngle = angle + spins
        withAnimation(.interpolatingSpring(stiffness: 14, damping: 6)) {
            displayAngle = finalAngle
        }
        angle = finalAngle
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            spinning = false; done = true
            let normalized = (360 - finalAngle.truncatingRemainder(dividingBy: 360)).truncatingRemainder(dividingBy: 360)
            let slice = Int(normalized / (360.0 / Double(sliceCount))) % sliceCount
            let hit = goldSlices.contains(slice)
            result = hit ? "⭐ Gold! 100 pts!" : "✕ Miss — 20 pts"
            if hit { SoundFX.shared.play(.jackpot); UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
            else { SoundFX.shared.play(.click) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { onDone(hit ? 100 : 20) }
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Shared utilities

private struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon.font(.system(size: 8))
            configuration.title
        }
    }
}
