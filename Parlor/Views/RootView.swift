import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var stats: StatsStore
    @EnvironmentObject var profiles: ProfileStore
    @EnvironmentObject var savedGames: SavedGamesStore
    @State private var setupKind: GameKind? = nil
    @State private var soloSetupKind: GameKind? = nil
    @State private var showProfiles = false
    @AppStorage(SoundFX.enabledKey) private var soundOn = true

    var body: some View {
        NavigationStack {
            ZStack {
                HomeBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header

                        Button {
                            model.showJoinSheet = true
                        } label: {
                            Label("Join a nearby game", systemImage: "antenna.radiowaves.left.and.right")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.16))

                        if !savedGames.games.isEmpty {
                            continueSection
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Parlor")
                    .font(.system(size: 40, weight: .black, design: .serif))
                    .foregroundStyle(.white)
                Text("♠︎ ♥︎ ♣︎ ♦︎")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
            }
            HStack(spacing: 10) {
                Button {
                    showProfiles = true
                } label: {
                    HStack(spacing: 10) {
                        AvatarView(profile: profiles.active, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(profiles.active.name)
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text("Tap to switch profile")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(10)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button {
                    soundOn.toggle()
                    if soundOn { SoundFX.shared.play(.click) }
                } label: {
                    Image(systemName: soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(soundOn ? 0.9 : 0.45))
                        .frame(width: 50, height: 56)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    var continueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Continue playing")
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

    var competeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Compete")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                      spacing: 12) {
                NavigationLink(value: "leagues") {
                    CompeteTile(title: "Leagues",
                                subtitle: "Season play & standings",
                                symbol: "trophy.fill",
                                colors: [Color(red: 0.85, green: 0.55, blue: 0.1),
                                         Color(red: 0.6, green: 0.32, blue: 0.05)])
                }
                NavigationLink(value: "tournaments") {
                    CompeteTile(title: "Tournaments",
                                subtitle: "Knockout brackets",
                                symbol: "crown.fill",
                                colors: [Color(red: 0.5, green: 0.2, blue: 0.7),
                                         Color(red: 0.3, green: 0.1, blue: 0.45)])
                }
                NavigationLink(value: "rankings") {
                    CompeteTile(title: "Rankings",
                                subtitle: "Elo for every player",
                                symbol: "chart.line.uptrend.xyaxis",
                                colors: [Color(red: 0.1, green: 0.5, blue: 0.65),
                                         Color(red: 0.05, green: 0.3, blue: 0.42)])
                }
                NavigationLink(value: "leaderboards") {
                    CompeteTile(title: "Leaderboards",
                                subtitle: "High scores & records",
                                symbol: "rosette",
                                colors: [Color(red: 0.7, green: 0.25, blue: 0.3),
                                         Color(red: 0.45, green: 0.12, blue: 0.18)])
                }
            }
        }
    }

    func gameSection(_ section: GameKind.Section) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(section.rawValue)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(GameKind.allCases.filter { $0.section == section }) { kind in
                    Button {
                        if kind.hasSoloSetup {
                            soloSetupKind = kind
                        } else if kind.isSolo {
                            model.startLocal(kind: kind, options: GameOptions(), humanCount: 1)
                        } else {
                            setupKind = kind
                        }
                    } label: {
                        GameTile(kind: kind,
                                 statsLine: stats.stats(for: kind).summary,
                                 bestLine: stats.bestLine(for: kind))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.title3.weight(.bold))
            .foregroundStyle(.white)
    }
}

struct HomeBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.07, green: 0.16, blue: 0.12),
                                    Color(red: 0.03, green: 0.07, blue: 0.06)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [.white.opacity(0.07), .clear],
                           center: .top, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
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
        case .pinball: return Color(red: 0.45, green: 0.2, blue: 0.75)
        case .breakout: return Color(red: 0.15, green: 0.5, blue: 0.75)
        case .tetris: return Color(red: 0.8, green: 0.35, blue: 0.55)
        }
    }
}

struct GameTile: View {
    let kind: GameKind
    var statsLine: String? = nil
    var bestLine: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: kind.symbolName)
                    .font(.system(size: 26))
                Spacer()
            }
            Spacer(minLength: 2)
            Text(kind.title)
                .font(.headline)
            Text(kind.subtitle)
                .font(.caption)
                .opacity(0.85)
            if let line = bestLine ?? statsLine {
                Text(line)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(.black.opacity(0.25), in: Capsule())
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
        .padding(13)
        .background(
            ZStack(alignment: .topTrailing) {
                LinearGradient(colors: [kind.tileColor, kind.tileColor.opacity(0.62)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: kind.symbolName)
                    .font(.system(size: 86))
                    .foregroundStyle(.white.opacity(0.08))
                    .rotationEffect(.degrees(12))
                    .offset(x: 22, y: -8)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
    }
}

/// One suspended table on the home screen — tap to pick it back up.
struct SavedGameCard: View {
    let saved: SavedGame
    let onResume: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        Button(action: onResume) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: saved.kind.symbolName)
                        .font(.title3)
                    Text(saved.kind.title)
                        .font(.headline)
                    if saved.match != nil {
                        Image(systemName: "trophy.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                    Spacer(minLength: 8)
                    Button(action: onDiscard) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .buttonStyle(.borderless)
                }
                Text(saved.game.statusText)
                    .font(.caption)
                    .lineLimit(1)
                    .opacity(0.9)
                Text("\(saved.playersLine) · \(saved.savedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .opacity(0.65)
                    .lineLimit(1)
                Label("Resume", systemImage: "play.fill")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.18), in: Capsule())
            }
            .foregroundStyle(.white)
            .padding(12)
            .frame(width: 230, alignment: .leading)
            .background(
                LinearGradient(colors: [saved.kind.tileColor.opacity(0.85), saved.kind.tileColor.opacity(0.5)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.15), lineWidth: 1))
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
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 24))
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .opacity(0.85)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
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
                    HStack {
                        ProgressView()
                        Text("Looking for nearby tables…")
                            .foregroundStyle(.secondary)
                    }
                    Text("Make sure your friend has hosted a table and you're on the same Wi-Fi or within Bluetooth range.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(browser.discovered) { table in
                    Button {
                        model.joinNearby(table: table, browser: browser)
                    } label: {
                        HStack {
                            Image(systemName: table.gameKind?.symbolName ?? "questionmark")
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading) {
                                Text(table.gameKind?.title ?? "Game")
                                    .font(.headline)
                                Text("Hosted by \(table.hostName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
