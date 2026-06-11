import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var setupKind: GameKind? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        TextField("Your name", text: $model.playerName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 220)
                        Spacer()
                    }

                    Button {
                        model.showJoinSheet = true
                    } label: {
                        Label("Join a nearby game", systemImage: "antenna.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Text("Games")
                        .font(.title2.weight(.bold))

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                        ForEach(GameKind.allCases) { kind in
                            Button {
                                if kind.isSolo {
                                    model.startLocal(kind: kind, options: GameOptions(), humanCount: 1)
                                } else {
                                    setupKind = kind
                                }
                            } label: {
                                GameTile(kind: kind)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Parlor")
        }
        .sheet(item: $setupKind) { kind in
            GameSetupSheet(kind: kind)
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
}

extension GameKind {
    var tileColor: Color {
        switch self {
        case .hearts: return .red
        case .spades: return .indigo
        case .euchre: return .teal
        case .bridge: return .blue
        case .solitaire: return .green
        case .mahjong: return .orange
        case .chess: return .brown
        case .checkers: return .pink
        case .go: return .gray
        }
    }
}

struct GameTile: View {
    let kind: GameKind

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: kind.symbolName)
                .font(.system(size: 28))
            Text(kind.title)
                .font(.headline)
            Text(kind.subtitle)
                .font(.caption)
                .opacity(0.85)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            LinearGradient(colors: [kind.tileColor, kind.tileColor.opacity(0.7)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 14)
        )
    }
}

struct GameSetupSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let kind: GameKind

    @State private var humanCount = 1
    @State private var goSize = 9
    @State private var drawThree = false

    var options: GameOptions {
        GameOptions(goBoardSize: goSize, klondikeDrawThree: drawThree)
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
