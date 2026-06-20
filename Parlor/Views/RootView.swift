import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var stats: StatsStore
    @EnvironmentObject var profiles: ProfileStore
    @EnvironmentObject var savedGames: SavedGamesStore
    @State private var setupKind: GameKind? = nil
    @State private var soloSetupKind: GameKind? = nil
    @State private var showProfiles = false
    @State private var joinPulse: CGFloat = 0
    @AppStorage(SoundFX.enabledKey) private var soundOn = true

    var body: some View {
        NavigationStack {
            ZStack {
                HomeBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header

                        Button {
                            model.showJoinSheet = true
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(.white.opacity(0.12))
                                        .frame(width: 42, height: 42)
                                        .scaleEffect(1 + joinPulse * 0.55)
                                        .opacity(1 - joinPulse)
                                    Circle()
                                        .fill(.white.opacity(0.07))
                                        .frame(width: 42, height: 42)
                                        .scaleEffect(1 + joinPulse * 0.85)
                                        .opacity(0.6 - joinPulse * 0.6)
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .symbolEffect(.variableColor.iterative, options: .repeating)
                                        .font(.system(size: 18, weight: .semibold))
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Join a nearby game")
                                        .font(.headline)
                                    Text("Same Wi-Fi or Bluetooth")
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.62))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background {
                                ZStack {
                                    LinearGradient(
                                        colors: [Color(red: 0.07, green: 0.50, blue: 0.50),
                                                 Color(red: 0.04, green: 0.30, blue: 0.42)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing)
                                    LinearGradient(colors: [.white.opacity(0.12), .clear],
                                                   startPoint: .top, endPoint: .center)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(
                                        LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.1)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                                        lineWidth: 1)
                            )
                            .shadow(color: Color(red: 0.07, green: 0.45, blue: 0.45).opacity(0.55), radius: 12, y: 5)
                        }
                        .buttonStyle(PressableTileStyle())
                        .foregroundStyle(.white)
                        .onAppear {
                            withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
                                joinPulse = 1.0
                            }
                        }

                        if !savedGames.games.isEmpty {
                            continueSection
                        }

                        if !model.recentKinds.isEmpty {
                            recentsRow
                        }

                        competeSection

                        ForEach(GameKind.Section.allCases) { section in
                            gameSection(section)
                        }
                    }
                    .padding()
                }
            }
            .navigationDestination(for: String.self) { destination in
                switch destination {
                case "leagues": LeagueListView()
                case "tournaments": TournamentListView()
                case "rankings": RankingsView()
                case "leaderboards": LeaderboardsView()
                default: EmptyView()
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .sheet(item: $setupKind) { kind in
            GameSetupSheet(kind: kind)
        }
        .sheet(item: $soloSetupKind) { kind in
            SoloSetupSheet(kind: kind)
        }
        .sheet(isPresented: $showProfiles) {
            ProfilesView()
        }
        .sheet(isPresented: $model.showJoinSheet) {
            JoinNearbyView()
        }
        .fullScreenCover(isPresented: Binding(
            get: { model.session != nil },
            set: { if !$0 { model.endSession() } }
        )) {
            if let session = model.session {
                TableView(session: session)
                    .environmentObject(model)
            }
        }
        .alert("Parlor", isPresented: Binding(
            get: { model.toast != nil },
            set: { if !$0 { model.toast = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.toast ?? "")
        }
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Parlor")
                        .font(.system(size: 46, weight: .black, design: .serif))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.97, blue: 0.82),
                                    Color(red: 0.88, green: 1.0, blue: 0.90),
                                    Color(red: 0.97, green: 0.88, blue: 0.62),
                                ],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color(red: 0.35, green: 0.85, blue: 0.55).opacity(0.5), radius: 18, y: 3)
                    Text("♠  ♥  ♣  ♦")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                        .kerning(5)
                }
                Spacer()
                Button {
                    soundOn.toggle()
                    if soundOn { SoundFX.shared.play(.click) }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(soundOn
                                  ? LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.07)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                                  : LinearGradient(colors: [.white.opacity(0.07), .white.opacity(0.03)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(.white.opacity(soundOn ? 0.18 : 0.08), lineWidth: 1))
                        Image(systemName: soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.white.opacity(soundOn ? 0.95 : 0.35))
                    }
                    .frame(width: 46, height: 46)
                }
                .buttonStyle(.plain)
            }
            Button {
                showProfiles = true
            } label: {
                HStack(spacing: 12) {
                    AvatarView(profile: profiles.active, size: 40)
                        .shadow(color: Avatar.color(profiles.active.colorIndex).opacity(0.6), radius: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profiles.active.name)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Tap to switch profile")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .padding(12)
                .background {
                    ZStack {
                        LinearGradient(
                            colors: [.white.opacity(0.12), .white.opacity(0.05)],
                            startPoint: .topLeading, endPoint: .bottomTrailing)
                        LinearGradient(colors: [.white.opacity(0.1), .clear], startPoint: .top, endPoint: .center)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    var continueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Continue playing", symbol: "play.circle.fill", accent: Color(red: 0.32, green: 0.78, blue: 0.55))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(savedGames.games) { saved in
                        SavedGameCard(saved: saved) {
                            model.resume(saved)
                        } onDiscard: {
                            model.discardSavedGame(saved)
                        }
                    }
                }
            }
        }
    }

    /// One-tap relaunch of the games you actually play.
    var recentsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Recents", symbol: "clock.arrow.circlepath", accent: Color(red: 0.55, green: 0.55, blue: 0.90))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(Array(model.recentKinds.enumerated()), id: \.element) { index, kind in
                        Button {
                            launch(kind)
                        } label: {
                            VStack(spacing: 7) {
                                ZStack {
                                    Circle()
                                        .fill(kind.tileColor.opacity(0.22))
                                        .frame(width: 62, height: 62)
                                    Image(systemName: kind.symbolName)
                                        .font(.system(size: 22, weight: .semibold))
                                        .frame(width: 54, height: 54)
                                        .background(
                                            LinearGradient(
                                                colors: [kind.tileColor, kind.tileColor.opacity(0.7)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing),
                                            in: Circle()
                                        )
                                        .overlay(Circle().strokeBorder(
                                            LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.1)],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                                            lineWidth: 1.5))
                                }
                                .shadow(color: kind.tileColor.opacity(0.55), radius: 8, y: 3)
                                Text(kind.title)
                                    .font(.caption2.weight(.medium))
                                    .lineLimit(1)
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                            .frame(width: 70)
                        }
                        .buttonStyle(PressableTileStyle())
                        .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
        }
    }

    private func launch(_ kind: GameKind) {
        if kind.hasSoloSetup {
            soloSetupKind = kind
        } else if kind.isSolo {
            model.startLocal(kind: kind, options: GameOptions(), humanCount: 1)
        } else {
            setupKind = kind
        }
    }

    var competeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Compete", symbol: "trophy.fill", accent: Color(red: 0.92, green: 0.65, blue: 0.10))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                      spacing: 12) {
                NavigationLink(value: "leagues") {
                    CompeteTile(title: "Leagues",
                                subtitle: "Season standings & play",
                                symbol: "trophy.fill",
                                colors: [Color(red: 0.88, green: 0.56, blue: 0.08),
                                         Color(red: 0.58, green: 0.30, blue: 0.04)])
                }
                NavigationLink(value: "tournaments") {
                    CompeteTile(title: "Tournaments",
                                subtitle: "Single elimination brackets",
                                symbol: "crown.fill",
                                colors: [Color(red: 0.52, green: 0.18, blue: 0.72),
                                         Color(red: 0.30, green: 0.08, blue: 0.46)])
                }
                NavigationLink(value: "rankings") {
                    CompeteTile(title: "Rankings",
                                subtitle: "Live Elo for every player",
                                symbol: "chart.line.uptrend.xyaxis",
                                colors: [Color(red: 0.08, green: 0.50, blue: 0.68),
                                         Color(red: 0.04, green: 0.28, blue: 0.44)])
                }
                NavigationLink(value: "leaderboards") {
                    CompeteTile(title: "Leaderboards",
                                subtitle: "High scores & hall of fame",
                                symbol: "rosette",
                                colors: [Color(red: 0.72, green: 0.22, blue: 0.28),
                                         Color(red: 0.44, green: 0.10, blue: 0.16)])
                }
            }
            .buttonStyle(PressableTileStyle())
        }
    }

    func gameSection(_ section: GameKind.Section) -> some View {
        let kinds = GameKind.allCases.filter { $0.section == section }
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle(section.rawValue, symbol: sectionSymbol(section), count: kinds.count, accent: sectionAccent(section))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 12)], spacing: 14) {
                ForEach(kinds) { kind in
                    Button {
                        launch(kind)
                    } label: {
                        GameTile(kind: kind,
                                 statsLine: stats.stats(for: kind).summary,
                                 bestLine: stats.bestLine(for: kind),
                                 winRate: stats.stats(for: kind).winRate)
                    }
                    .buttonStyle(PressableTileStyle())
                    .contextMenu {
                        Button { launch(kind) } label: {
                            Label("Play \(kind.title)", systemImage: "play.fill")
                        }
                    }
                }
            }
        }
    }

    func sectionSymbol(_ section: GameKind.Section) -> String {
        switch section {
        case .cards: return "suit.club.fill"
        case .boards: return "checkerboard.rectangle"
        case .puzzles: return "puzzlepiece.fill"
        case .arcade: return "gamecontroller.fill"
        case .sports: return "sportscourt.fill"
        }
    }

    func sectionTitle(_ text: String, symbol: String? = nil, count: Int? = nil, accent: Color? = nil) -> some View {
        HStack(spacing: 9) {
            if let accent {
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: [accent, accent.opacity(0.4)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 3, height: 22)
            }
            if let symbol {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent?.opacity(0.9) ?? .white.opacity(0.55))
            }
            Text(text)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            if let count {
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(accent?.opacity(0.22) ?? .white.opacity(0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder(accent?.opacity(0.3) ?? .white.opacity(0.1), lineWidth: 0.75))
            }
            Spacer()
        }
    }

    func sectionAccent(_ section: GameKind.Section) -> Color {
        switch section {
        case .cards:   return Color(red: 0.88, green: 0.25, blue: 0.32)
        case .boards:  return Color(red: 0.75, green: 0.52, blue: 0.22)
        case .puzzles: return Color(red: 0.25, green: 0.62, blue: 0.92)
        case .arcade:  return Color(red: 0.68, green: 0.28, blue: 0.90)
        case .sports:  return Color(red: 0.18, green: 0.74, blue: 0.44)
        }
    }
}

/// Tiles lift and squish under the finger, with a light haptic on press.
struct PressableTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.950 : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .shadow(color: .black.opacity(configuration.isPressed ? 0.1 : 0),
                    radius: configuration.isPressed ? 2 : 0, y: 1)
            .animation(.spring(response: 0.20, dampingFraction: 0.60), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
            }
    }
}

struct HomeBackground: View {
    @State private var floatPhase: Double = 0
    @State private var rotatePhase: Double = 0

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.05, green: 0.14, blue: 0.09), location: 0),
                    .init(color: Color(red: 0.04, green: 0.11, blue: 0.07), location: 0.5),
                    .init(color: Color(red: 0.02, green: 0.06, blue: 0.04), location: 1),
                ],
                startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(red: 0.18, green: 0.52, blue: 0.30).opacity(0.38), .clear],
                           center: .top, startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Color(red: 0.06, green: 0.24, blue: 0.40).opacity(0.28), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 450)
            RadialGradient(colors: [Color(red: 0.38, green: 0.14, blue: 0.08).opacity(0.18), .clear],
                           center: .bottomLeading, startRadius: 0, endRadius: 320)
            LinearGradient(colors: [.black.opacity(0.25), .clear, .black.opacity(0.18)],
                           startPoint: .top, endPoint: .bottom)
            GeometryReader { geo in
                let suits = ["♠", "♥", "♦", "♣", "♠", "♦", "♥", "♣", "♠", "♥", "♦", "♣"]
                ForEach(Array(suits.enumerated()), id: \.offset) { i, suit in
                    var generator = SplitMix64(seed: UInt64(i + 7) &* 0x9E3779B97F4A7C15)
                    let x = CGFloat(generator.unit()) * geo.size.width
                    let y = CGFloat(generator.unit()) * geo.size.height
                    let baseRotation = Double(generator.unit()) * 60 - 30
                    let rotateDir: Double = i % 2 == 0 ? 1 : -1
                    let slowRotation = rotatePhase * rotateDir * (0.4 + Double(generator.unit()) * 0.6)
                    let amplitude: CGFloat = 8 + CGFloat(i % 4) * 9
                    let dy = CGFloat(sin(floatPhase + Double(i) * 1.15)) * amplitude
                    let opacity = 0.018 + Double(generator.unit()) * 0.024
                    Text(suit)
                        .font(.system(size: 72 + CGFloat(generator.unit()) * 100))
                        .foregroundStyle(.white.opacity(opacity))
                        .rotationEffect(.degrees(baseRotation + slowRotation))
                        .offset(y: dy)
                        .position(x: x, y: y)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
                floatPhase = .pi * 2
            }
            withAnimation(.linear(duration: 90).repeatForever(autoreverses: false)) {
                rotatePhase = 360
            }
        }
    }
}

extension GameKind {
    var tileColor: Color {
        switch self {
        case .hearts: return Color(red: 0.72, green: 0.13, blue: 0.2)
        case .spades: return .indigo
        case .euchre: return .teal
        case .bridge: return .blue
        case .solitaire: return Color(red: 0.13, green: 0.5, blue: 0.3)
        case .freecell: return Color(red: 0.0, green: 0.45, blue: 0.45)
        case .mahjong: return .orange
        case .chess: return .brown
        case .checkers: return Color(red: 0.75, green: 0.3, blue: 0.4)
        case .go: return Color(white: 0.35)
        case .marioParty: return Color(red: 0.85, green: 0.2, blue: 0.35)
        case .pinball: return Color(red: 0.45, green: 0.2, blue: 0.75)
        case .breakout: return Color(red: 0.15, green: 0.5, blue: 0.75)
        case .tetris: return Color(red: 0.8, green: 0.35, blue: 0.55)
        case .uno: return Color(red: 0.8, green: 0.15, blue: 0.25)
        case .eights: return Color(red: 0.3, green: 0.35, blue: 0.75)
        case .gofish: return Color(red: 0.0, green: 0.55, blue: 0.65)
        case .capsules: return Color(red: 0.85, green: 0.4, blue: 0.2)
        case .minesweeper: return Color(red: 0.35, green: 0.55, blue: 0.35)
        case .muncher: return Color(red: 0.85, green: 0.7, blue: 0.1)
        case .hopper: return Color(red: 0.2, green: 0.6, blue: 0.3)
        case .centipede: return Color(red: 0.4, green: 0.65, blue: 0.2)
        case .snake: return Color(red: 0.2, green: 0.7, blue: 0.45)
        case .bomberman: return Color(red: 0.8, green: 0.35, blue: 0.1)
        case .solarStriker: return Color(red: 0.1, green: 0.35, blue: 0.75)
        case .football: return Color(red: 0.45, green: 0.3, blue: 0.2)
        case .baseball: return Color(red: 0.7, green: 0.25, blue: 0.2)
        case .soccer: return Color(red: 0.15, green: 0.55, blue: 0.4)
        case .hockey: return Color(red: 0.25, green: 0.45, blue: 0.7)
        case .trivia: return Color(red: 0.45, green: 0.18, blue: 0.72)
        }
    }
}

struct GameTile: View {
    let kind: GameKind
    var statsLine: String? = nil
    var bestLine: String? = nil
    var winRate: Double? = nil
    @State private var newBounce = false
    @State private var shimmerOffset: CGFloat = -1.5

    private var dotColor: Color? {
        guard let wr = winRate else { return nil }
        if wr >= 0.56 { return .green }
        if wr >= 0.35 { return Color(red: 1.0, green: 0.78, blue: 0.1) }
        return Color(red: 0.95, green: 0.28, blue: 0.28)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: kind.symbolName)
                        .font(.system(size: 22, weight: .semibold))
                }
                .overlay(alignment: .bottomTrailing) {
                    if let color = dotColor {
                        ZStack {
                            Circle().fill(color.opacity(0.35)).frame(width: 14, height: 14)
                            Circle().fill(color).frame(width: 9, height: 9)
                        }
                        .shadow(color: color.opacity(0.7), radius: 4)
                        .offset(x: 2, y: 2)
                    }
                }
                Spacer()
                if let wr = winRate {
                    Text("\(Int(wr * 100))%")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(dotColor ?? .white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((dotColor ?? .white).opacity(0.15), in: Capsule())
                        .overlay(Capsule().strokeBorder((dotColor ?? .white).opacity(0.3), lineWidth: 0.5))
                } else if statsLine == nil && bestLine == nil {
                    // "NEW" badge for games that have never been played.
                    Text("NEW")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color(red: 0.55, green: 1.0, blue: 0.55), in: Capsule())
                }
            }
            Spacer(minLength: 4)
            Text(kind.title)
                .font(.headline.weight(.bold))
            Text(kind.subtitle)
                .font(.caption)
                .opacity(0.78)
                .lineLimit(2)
            // Show win record and best score as stacked pills when both exist.
            if statsLine != nil || bestLine != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if let stats = statsLine {
                        Text(stats)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.38), in: Capsule())
                            .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                    }
                    if let best = bestLine {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.3))
                            Text(best)
                                .font(.caption2.weight(.semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(red: 1.0, green: 0.85, blue: 0.3).opacity(0.15), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color(red: 1.0, green: 0.85, blue: 0.3).opacity(0.35), lineWidth: 0.5))
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 122, alignment: .leading)
        .padding(14)
        .background(
            ZStack(alignment: .bottomTrailing) {
                LinearGradient(
                    stops: [
                        .init(color: kind.tileColor, location: 0),
                        .init(color: kind.tileColor.opacity(0.75), location: 0.55),
                        .init(color: kind.tileColor.opacity(0.55), location: 1),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: kind.symbolName)
                    .font(.system(size: 92))
                    .foregroundStyle(.white.opacity(0.09))
                    .rotationEffect(.degrees(14))
                    .offset(x: 18, y: 16)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [.white.opacity(0.25), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .allowsHitTesting(false)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.08)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1)
        )
        .shadow(color: kind.tileColor.opacity(0.65), radius: 14, y: 6)
        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
        .scaleEffect(newBounce ? 1.0 : (statsLine == nil && bestLine == nil ? 0.94 : 1.0))
        .overlay(alignment: .topLeading) {
            // Shimmer diagonal sweep for NEW tiles
            if statsLine == nil && bestLine == nil {
                LinearGradient(
                    colors: [.clear, .white.opacity(0.18), .clear],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .frame(width: 80)
                .rotationEffect(.degrees(-15))
                .offset(x: shimmerOffset * 160 - 40)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            if statsLine == nil && bestLine == nil {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.55).delay(Double.random(in: 0...0.3))) {
                    newBounce = true
                }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false).delay(Double.random(in: 0...1.0))) {
                    shimmerOffset = 1.5
                }
            }
        }
    }
}

/// One suspended table on the home screen — tap to pick it back up.
struct SavedGameCard: View {
    let saved: SavedGame
    let onResume: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        Button(action: onResume) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    HStack(spacing: 8) {
                        Image(systemName: saved.kind.symbolName)
                            .font(.system(size: 16, weight: .semibold))
                        Text(saved.kind.title)
                            .font(.headline)
                        if saved.match != nil {
                            Image(systemName: "trophy.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                        }
                    }
                    Spacer(minLength: 4)
                    Button(action: onDiscard) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.borderless)
                }
                Text(saved.game.statusText)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(.white.opacity(0.9))
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.45))
                    Text(saved.savedAt.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("Resume")
                            .font(.caption.weight(.bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4.5)
                    .background(
                        LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.16)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.75))
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                }
            }
            .foregroundStyle(.white)
            .padding(13)
            .frame(width: 240, alignment: .leading)
            .background {
                ZStack(alignment: .bottomTrailing) {
                    LinearGradient(
                        stops: [
                            .init(color: saved.kind.tileColor.opacity(0.95), location: 0),
                            .init(color: saved.kind.tileColor.opacity(0.65), location: 1),
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: saved.kind.symbolName)
                        .font(.system(size: 70))
                        .foregroundStyle(.white.opacity(0.08))
                        .rotationEffect(.degrees(-12))
                        .offset(x: 10, y: 10)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .overlay(alignment: .top) {
                LinearGradient(colors: [.white.opacity(0.24), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .allowsHitTesting(false)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.08)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1)
            )
            .shadow(color: saved.kind.tileColor.opacity(0.55), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive, action: onDiscard) {
                Label("Discard game", systemImage: "trash")
            }
        }
    }
}

struct CompeteTile: View {
    let title: String
    let subtitle: String
    let symbol: String
    let colors: [Color]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
            }
            Spacer(minLength: 4)
            Text(title)
                .font(.headline.weight(.bold))
            Text(subtitle)
                .font(.caption)
                .opacity(0.82)
                .lineLimit(2)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.45))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        .padding(14)
        .background {
            ZStack(alignment: .bottomTrailing) {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                LinearGradient(
                    colors: [.white.opacity(0.15), .clear, .black.opacity(0.08)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Image(systemName: symbol)
                    .font(.system(size: 62))
                    .foregroundStyle(.white.opacity(0.1))
                    .rotationEffect(.degrees(-14))
                    .offset(x: 14, y: 12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .overlay(alignment: .top) {
            LinearGradient(colors: [.white.opacity(0.26), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .allowsHitTesting(false)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.1)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1)
        )
        .shadow(color: colors.first?.opacity(0.6) ?? .black.opacity(0.35), radius: 14, y: 6)
        .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
    }
}

/// Options + start button for the solo games that have settings:
/// Klondike (draw count, stock passes, card backs) and Pinball (tables).
/// Choices persist as the new defaults.
struct SoloSetupSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let kind: GameKind

    @AppStorage("parlor.klondike.draw3") private var drawThree = false
    @AppStorage("parlor.klondike.passes") private var maxPasses = 0
    @AppStorage(CardBack.storageKey) private var cardBack = CardBack.classic.rawValue
    @AppStorage(FeltTheme.storageKey) private var feltTheme = FeltTheme.classic.rawValue
    @AppStorage("parlor.pinball.layout") private var layoutID = "classic"

    var body: some View {
        NavigationStack {
            Form {
                if kind == .solitaire {
                    Section("Rules") {
                        Toggle("Draw three cards", isOn: $drawThree)
                        Picker("Passes through the deck", selection: $maxPasses) {
                            Text("Unlimited").tag(0)
                            Text("1 (no redeals)").tag(1)
                            Text("2").tag(2)
                            Text("3").tag(3)
                            Text("5").tag(5)
                        }
                    }
                    Section("Card back") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(CardBack.allCases) { style in
                                    VStack(spacing: 4) {
                                        FaceDownCardView(width: 46, styleOverride: style)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 46 * 0.12)
                                                    .strokeBorder(Color.accentColor,
                                                                  lineWidth: cardBack == style.rawValue ? 3 : 0)
                                            )
                                        Text(style.title)
                                            .font(.caption2)
                                            .foregroundStyle(cardBack == style.rawValue ? .primary : .secondary)
                                    }
                                    .onTapGesture { cardBack = style.rawValue }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    Section("Table felt") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(FeltTheme.allCases) { theme in
                                    VStack(spacing: 4) {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(LinearGradient(colors: theme.colors,
                                                                  startPoint: .topLeading,
                                                                  endPoint: .bottomTrailing))
                                            .frame(width: 46, height: 46)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .strokeBorder(Color.accentColor,
                                                                  lineWidth: feltTheme == theme.rawValue ? 3 : 0)
                                            )
                                            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                                        Text(theme.title)
                                            .font(.caption2)
                                            .foregroundStyle(feltTheme == theme.rawValue ? .primary : .secondary)
                                    }
                                    .onTapGesture { feltTheme = theme.rawValue }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if kind == .pinball {
                    Section("Table") {
                        ForEach(PinballTheme.all) { theme in
                            Button {
                                layoutID = theme.id
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(theme.name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text(theme.blurb)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if layoutID == theme.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                        }
                    }
                }

                Button {
                    let options = GameOptions(klondikeDrawThree: drawThree,
                                              klondikeMaxPasses: maxPasses,
                                              pinballLayout: layoutID)
                    model.startLocal(kind: kind, options: options, humanCount: 1)
                    dismiss()
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct GameSetupSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let kind: GameKind

    @State private var humanCount = 1
    @State private var goSize = 9
    @AppStorage("parlor.botDifficulty") private var difficultyRaw = BotDifficulty.normal.rawValue

    var options: GameOptions {
        GameOptions(goBoardSize: goSize,
                    botDifficulty: BotDifficulty(rawValue: difficultyRaw) ?? .normal)
    }

    var body: some View {
        NavigationStack {
            Form {
                if kind == .go {
                    Section("Board") {
                        Picker("Size", selection: $goSize) {
                            Text("9 × 9").tag(9)
                            Text("13 × 13").tag(13)
                            Text("19 × 19").tag(19)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section {
                    Picker("Bot strength", selection: $difficultyRaw) {
                        ForEach(BotDifficulty.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Bots")
                } footer: {
                    Text((BotDifficulty(rawValue: difficultyRaw) ?? .normal).blurb)
                }

                Section("On this device") {
                    Stepper("Players here: \(humanCount)", value: $humanCount, in: 1...kind.playerCount)
                    if humanCount < kind.playerCount {
                        Text("Remaining \(kind.playerCount - humanCount) seat(s) play as bots.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        model.startLocal(kind: kind, options: options, humanCount: humanCount)
                        dismiss()
                    } label: {
                        Label(humanCount > 1 ? "Start pass & play" : "Start vs bots",
                              systemImage: "iphone")
                    }
                }

                Section("With people nearby") {
                    Text("Friends with the app on the same Wi-Fi or Bluetooth join from “Join a nearby game”.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        model.hostNearby(kind: kind, options: options)
                        dismiss()
                    } label: {
                        Label("Host a nearby table", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }

                Section {
                    Text("This device becomes the shared screen (mirror it to a TV with AirPlay). Everyone else joins from “Join a nearby game” and plays on their phone as a controller.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        model.hostBigScreen(kind: kind, options: options)
                        dismiss()
                    } label: {
                        Label("Host on a big screen", systemImage: "tv.and.hifispeaker.fill")
                    }
                } header: {
                    Text("On a big screen")
                }

                Section("With friends anywhere") {
                    Text("Start a FaceTime call (or share the link from the FaceTime app), then start SharePlay here. Friends need the app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        model.startSharePlay(kind: kind, options: options)
                        dismiss()
                    } label: {
                        Label("Play over SharePlay", systemImage: "shareplay")
                    }
                }
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct JoinNearbyView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser = MultipeerTransport()

    var body: some View {
        NavigationStack {
            List {
                if browser.discovered.isEmpty {
                    VStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.teal.opacity(0.12))
                                .frame(width: 64, height: 64)
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 28))
                                .foregroundStyle(.teal)
                                .symbolEffect(.variableColor.iterative, options: .repeating)
                        }
                        VStack(spacing: 6) {
                            Text("Looking for nearby tables…")
                                .font(.headline)
                            Text("Make sure your friend has hosted a table and you're on the same Wi-Fi or within Bluetooth range.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                ForEach(browser.discovered) { table in
                    Button {
                        model.joinNearby(table: table, browser: browser)
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill((table.gameKind?.tileColor ?? .teal).opacity(0.2))
                                    .frame(width: 44, height: 44)
                                Image(systemName: table.gameKind?.symbolName ?? "questionmark")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(table.gameKind?.tileColor ?? .teal)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(table.gameKind?.title ?? "Game")
                                    .font(.headline)
                                Label("Hosted by \(table.hostName)", systemImage: "person.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Nearby tables")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        browser.stop()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
