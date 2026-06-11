import SwiftUI

// MARK: - Shared bits

enum BotNames {
    static let pool = ["Ada", "Otto", "Greta", "Felix", "Hazel", "Mabel", "Rufus", "Pearl",
                       "Edith", "Walter", "Flora", "Basil", "Ivy", "Clara", "Hugo", "Opal"]
    static func name(at index: Int) -> String { pool[index % pool.count] }
}

private func participantLine(_ ids: [UUID], kind: GameKind, name: (UUID) -> String) -> String {
    let names = ids.map(name)
    if kind.isPartnership, names.count == 4 {
        return "\(names[0]) & \(names[2])  vs  \(names[1]) & \(names[3])"
    }
    return names.joined(separator: kind.playerCount == 2 ? "  vs  " : " · ")
}

/// One schedule/bracket row: who plays, the result once decided, and a
/// Play (humans involved) or Simulate (all bots) action.
struct MatchRow: View {
    let match: CompetitionMatch
    let kind: GameKind
    let entrant: (UUID) -> Entrant?
    let playable: Bool
    let onPlay: () -> Void
    let onSimulate: () -> Void

    private func name(_ id: UUID) -> String { entrant(id)?.name ?? "?" }
    private var hasHuman: Bool { match.entrantIDs.contains { entrant($0)?.isBot == false } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(participantLine(match.entrantIDs, kind: kind, name: name))
                .font(.subheadline.weight(.medium))
            if let outcome = match.outcome {
                Label {
                    Text(winnersLine(outcome))
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if playable {
                Button {
                    hasHuman ? onPlay() : onSimulate()
                } label: {
                    Label(hasHuman ? "Play match" : "Simulate",
                          systemImage: hasHuman ? "play.fill" : "wand.and.stars")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Text("Waiting for earlier rounds…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func winnersLine(_ outcome: MatchOutcome) -> String {
        guard let top = outcome.rankedGroups.first else { return outcome.summary }
        if outcome.rankedGroups.count == 1 { return "Draw — \(outcome.summary)" }
        let names = top.map(name).joined(separator: " & ")
        return "\(names) won · \(outcome.summary)"
    }
}

/// Editable roster: the user plus any mix of pass-and-play guests and bots.
struct RosterEditor: View {
    @Binding var entrants: [Entrant]
    var fixedCount: Int? = nil       // tournaments lock the size

    var body: some View {
        ForEach($entrants) { $entrant in
            HStack {
                Image(systemName: entrant.isBot ? "cpu" : "person.fill")
                    .foregroundStyle(entrant.isBot ? .secondary : Color.accentColor)
                    .frame(width: 24)
                TextField("Name", text: $entrant.name)
                Spacer()
                Button(entrant.isBot ? "Bot" : "Human") {
                    entrant.isBot.toggle()
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(entrant.isBot ? .gray : .blue)
            }
        }
        .onDelete { offsets in
            if fixedCount == nil { entrants.remove(atOffsets: offsets) }
        }
        .deleteDisabled(fixedCount != nil || entrants.count <= 2)
        if fixedCount == nil {
            Button {
                entrants.append(Entrant(name: BotNames.name(at: entrants.count - 1), isBot: true))
            } label: {
                Label("Add player", systemImage: "plus.circle.fill")
            }
        }
    }
}

// MARK: - Leagues

struct LeagueListView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var competitions: CompetitionStore
    @State private var showCreate = false

    var body: some View {
        List {
            if competitions.leagues.isEmpty {
                ContentUnavailableView("No leagues yet",
                                       systemImage: "trophy",
                                       description: Text("Create a league to play a season of scheduled matches against friends and bots."))
            }
            ForEach(competitions.leagues) { league in
                NavigationLink(value: league.id) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(league.name).font(.headline)
                        Text("\(league.gameKind.title) · \(league.entrants.count) players · \(league.playedCount)/\(league.matches.count) played")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if league.isComplete, let champ = league.standings().first {
                            Label("\(champ.entrant.name) wins the league", systemImage: "trophy.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .onDelete { offsets in
                for offset in offsets { competitions.deleteLeague(id: competitions.leagues[offset].id) }
            }
        }
        .navigationTitle("Leagues")
        .navigationDestination(for: UUID.self) { LeagueDetailView(leagueID: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showCreate) { CreateLeagueView() }
    }
}

struct CreateLeagueView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var competitions: CompetitionStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = "Parlor League"
    @State private var kind: GameKind = .hearts
    @State private var entrants: [Entrant] = []
    @State private var rounds = 3
    @State private var doubleRoundRobin = false
    @State private var goSize = 9
    @State private var difficulty: BotDifficulty = .normal

    private var competitiveKinds: [GameKind] { GameKind.allCases.filter(\.isCompetitive) }

    private var rosterValid: Bool {
        guard entrants.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }) else { return false }
        return kind.playerCount == 2
            ? entrants.count >= 3
            : entrants.count >= 4 && entrants.count % 4 == 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("League") {
                    TextField("League name", text: $name)
                    Picker("Game", selection: $kind) {
                        ForEach(competitiveKinds) { Text($0.title).tag($0) }
                    }
                    if kind == .go {
                        Picker("Board", selection: $goSize) {
                            Text("9 × 9").tag(9)
                            Text("13 × 13").tag(13)
                            Text("19 × 19").tag(19)
                        }
                    }
                    Picker("Bot strength", selection: $difficulty) {
                        ForEach(BotDifficulty.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section {
                    RosterEditor(entrants: $entrants)
                } header: {
                    Text("Players")
                } footer: {
                    Text(kind.playerCount == 2
                         ? "3 or more players. Humans play pass-and-play on this device; bot-only matches can be simulated."
                         : "A multiple of 4 players (tables seat four). Partnerships rotate from round to round.")
                }

                Section("Schedule") {
                    if kind.playerCount == 2 {
                        Toggle("Double round robin", isOn: $doubleRoundRobin)
                    } else {
                        Stepper("Rounds: \(rounds)", value: $rounds, in: 1...12)
                    }
                }

                Button {
                    create()
                } label: {
                    Label("Create league", systemImage: "trophy.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!rosterValid || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .navigationTitle("New League")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } }
            }
            .onAppear { seedRoster() }
            .onChange(of: kind) { _, _ in seedRoster() }
        }
    }

    private func seedRoster() {
        let count = kind.playerCount == 2 ? 4 : 4
        var roster = [Entrant(name: model.displayName, isBot: false)]
        while roster.count < count {
            roster.append(Entrant(name: BotNames.name(at: roster.count - 1), isBot: true))
        }
        entrants = roster
    }

    private func create() {
        let options = GameOptions(goBoardSize: goSize, botDifficulty: difficulty)
        let league = League(name: name, gameKind: kind, options: options,
                            entrants: entrants,
                            rounds: kind.playerCount == 2 ? (doubleRoundRobin ? 2 : 1) : rounds)
        competitions.add(league)
        dismiss()
    }
}

struct LeagueDetailView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var competitions: CompetitionStore
    let leagueID: UUID

    var body: some View {
        if let league = competitions.league(id: leagueID) {
            List {
                if league.isComplete, let champ = league.standings().first {
                    Section {
                        ChampionBanner(text: "\(champ.entrant.name) wins \(league.name)!")
                    }
                }

                Section("Standings") {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                        GridRow {
                            Text("#").gridColumnAlignment(.trailing)
                            Text("Player")
                            Text("P").gridColumnAlignment(.trailing)
                            Text("W").gridColumnAlignment(.trailing)
                            Text("D").gridColumnAlignment(.trailing)
                            Text("L").gridColumnAlignment(.trailing)
                            Text("Pts").gridColumnAlignment(.trailing)
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        ForEach(Array(league.standings().enumerated()), id: \.element.id) { index, row in
                            GridRow {
                                Text("\(index + 1)")
                                HStack(spacing: 4) {
                                    Text(row.entrant.name).lineLimit(1)
                                    if row.entrant.isBot {
                                        Image(systemName: "cpu").font(.caption2).foregroundStyle(.tertiary)
                                    }
                                }
                                Text("\(row.played)")
                                Text("\(row.wins)")
                                Text("\(row.draws)")
                                Text("\(row.losses)")
                                Text(row.points.formatted(.number.precision(.fractionLength(0...1))))
                                    .fontWeight(.semibold)
                            }
                            .font(.subheadline)
                        }
                    }
                }

                ForEach(0..<league.roundCount, id: \.self) { round in
                    Section("Round \(round + 1)") {
                        ForEach(league.matches(inRound: round)) { match in
                            MatchRow(match: match, kind: league.gameKind,
                                     entrant: { league.entrant($0) },
                                     playable: true,
                                     onPlay: { model.playLeagueMatch(league: league, match: match) },
                                     onSimulate: { competitions.simulateLeagueMatch(leagueID: league.id, matchID: match.id) })
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        competitions.deleteLeague(id: league.id)
                    } label: {
                        Label("Delete league", systemImage: "trash")
                    }
                }
            }
            .navigationTitle(league.name)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("League deleted", systemImage: "trophy")
        }
    }
}

// MARK: - Tournaments

struct TournamentListView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var competitions: CompetitionStore
    @State private var showCreate = false

    var body: some View {
        List {
            if competitions.tournaments.isEmpty {
                ContentUnavailableView("No tournaments yet",
                                       systemImage: "crown",
                                       description: Text("Set up a knockout bracket — survive every round to take the crown."))
            }
            ForEach(competitions.tournaments) { tournament in
                NavigationLink(value: tournament.id) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tournament.name).font(.headline)
                        Text("\(tournament.gameKind.title) · \(tournament.entrants.count) entrants")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let champs = tournament.championIDs {
                            let names = champs.compactMap { tournament.entrant($0)?.name }.joined(separator: " & ")
                            Label("\(names) took the crown", systemImage: "crown.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .onDelete { offsets in
                for offset in offsets { competitions.deleteTournament(id: competitions.tournaments[offset].id) }
            }
        }
        .navigationTitle("Tournaments")
        .navigationDestination(for: UUID.self) { TournamentDetailView(tournamentID: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showCreate) { CreateTournamentView() }
    }
}

struct CreateTournamentView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var competitions: CompetitionStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = "Parlor Cup"
    @State private var kind: GameKind = .chess
    @State private var size = 8
    @State private var entrants: [Entrant] = []
    @State private var goSize = 9
    @State private var difficulty: BotDifficulty = .normal

    private var competitiveKinds: [GameKind] { GameKind.allCases.filter(\.isCompetitive) }

    private var rosterValid: Bool {
        entrants.count == size &&
        entrants.allSatisfy { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tournament") {
                    TextField("Tournament name", text: $name)
                    Picker("Game", selection: $kind) {
                        ForEach(competitiveKinds) { Text($0.title).tag($0) }
                    }
                    Picker("Entrants", selection: $size) {
                        ForEach(Tournament.validSizes(for: kind), id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if kind == .go {
                        Picker("Board", selection: $goSize) {
                            Text("9 × 9").tag(9)
                            Text("13 × 13").tag(13)
                            Text("19 × 19").tag(19)
                        }
                    }
                    Picker("Bot strength", selection: $difficulty) {
                        ForEach(BotDifficulty.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section {
                    RosterEditor(entrants: $entrants, fixedCount: size)
                } header: {
                    Text("Entrants")
                } footer: {
                    Text(kind.playerCount == 2
                         ? "Single elimination — the draw is random. Win or go home."
                         : "Tables of four; the top two finishers (the winning pair in partnership games) advance.")
                }

                Button {
                    create()
                } label: {
                    Label("Start tournament", systemImage: "crown.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!rosterValid || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .navigationTitle("New Tournament")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } }
            }
            .onAppear { seedRoster() }
            .onChange(of: size) { _, _ in seedRoster() }
            .onChange(of: kind) { _, _ in
                size = Tournament.validSizes(for: kind).contains(size) ? size : 8
                seedRoster()
            }
        }
    }

    private func seedRoster() {
        var roster = [Entrant(name: model.displayName, isBot: false)]
        while roster.count < size {
            roster.append(Entrant(name: BotNames.name(at: roster.count - 1), isBot: true))
        }
        entrants = roster
    }

    private func create() {
        let options = GameOptions(goBoardSize: goSize, botDifficulty: difficulty)
        let tournament = Tournament(name: name, gameKind: kind, options: options, entrants: entrants)
        competitions.add(tournament)
        dismiss()
    }
}

struct TournamentDetailView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var competitions: CompetitionStore
    let tournamentID: UUID

    var body: some View {
        if let tournament = competitions.tournament(id: tournamentID) {
            List {
                if let champs = tournament.championIDs {
                    let names = champs.compactMap { tournament.entrant($0)?.name }.joined(separator: " & ")
                    Section {
                        ChampionBanner(text: "\(names) win\(champs.count == 1 ? "s" : "") \(tournament.name)!")
                    }
                }

                ForEach(0..<tournament.roundCount, id: \.self) { round in
                    Section(tournament.roundTitle(round)) {
                        ForEach(tournament.matches(inRound: round)) { match in
                            MatchRow(match: match, kind: tournament.gameKind,
                                     entrant: { tournament.entrant($0) },
                                     playable: round == tournament.currentRound,
                                     onPlay: { model.playTournamentMatch(tournament: tournament, match: match) },
                                     onSimulate: { competitions.simulateTournamentMatch(tournamentID: tournament.id, matchID: match.id) })
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        competitions.deleteTournament(id: tournament.id)
                    } label: {
                        Label("Delete tournament", systemImage: "trash")
                    }
                }
            }
            .navigationTitle(tournament.name)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Tournament deleted", systemImage: "crown")
        }
    }
}

struct ChampionBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.title)
                .foregroundStyle(.yellow)
            Text(text)
                .font(.headline)
            Spacer()
        }
        .padding(.vertical, 6)
        .listRowBackground(
            LinearGradient(colors: [.orange.opacity(0.25), .yellow.opacity(0.12)],
                           startPoint: .leading, endPoint: .trailing)
        )
    }
}
