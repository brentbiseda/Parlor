import SwiftUI

// MARK: - Leaderboards (score records)

struct LeaderboardsView: View {
    @EnvironmentObject var leaderboards: LeaderboardStore
    @State private var kind: GameKind = .pinball

    private var boardKinds: [GameKind] {
        GameKind.allCases.filter { $0.leaderboardTitle != nil }
    }

    var body: some View {
        List {
            Section {
                Picker("Game", selection: $kind) {
                    ForEach(boardKinds) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }

            Section(kind.leaderboardTitle ?? "Records") {
                let entries = leaderboards.entries(for: kind)
                if entries.isEmpty {
                    ContentUnavailableView("No records yet",
                                           systemImage: "rosette",
                                           description: Text("Finish a game of \(kind.title) to claim the first spot."))
                }
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    HStack(spacing: 12) {
                        medal(for: index)
                            .frame(width: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.playerName)
                                .font(.subheadline.weight(.semibold))
                            Text("\(entry.detail) · \(entry.date.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(kind.leaderboardLabel(for: entry.value))
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Leaderboards")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func medal(for index: Int) -> some View {
        switch index {
        case 0: Image(systemName: "medal.fill").font(.title3).foregroundStyle(.yellow)
        case 1: Image(systemName: "medal.fill").font(.title3).foregroundStyle(.gray)
        case 2: Image(systemName: "medal.fill").font(.title3).foregroundStyle(Color(red: 0.72, green: 0.45, blue: 0.2))
        default:
            Text("\(index + 1)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Rankings (Elo ratings)

struct RankingsView: View {
    @EnvironmentObject var profiles: ProfileStore
    @State private var kind: GameKind = .hearts

    private var competitiveKinds: [GameKind] {
        GameKind.allCases.filter(\.isCompetitive)
    }

    var body: some View {
        List {
            Section {
                Picker("Game", selection: $kind) {
                    ForEach(competitiveKinds) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
            }

            Section {
                let table = profiles.rankings(for: kind)
                if table.isEmpty {
                    ContentUnavailableView("No rated games",
                                           systemImage: "chart.line.uptrend.xyaxis",
                                           description: Text("Finish a game of \(kind.title) — every player at the table gets a rating."))
                }
                ForEach(Array(table.enumerated()), id: \.element.profile.id) { index, row in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)
                        AvatarView(profile: row.profile, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Text(row.profile.name)
                                    .font(.subheadline.weight(.semibold))
                                if index == 0 {
                                    Image(systemName: "crown.fill")
                                        .font(.caption)
                                        .foregroundStyle(.yellow)
                                }
                            }
                            Text("\(row.rating.played) played · \(row.rating.record)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(row.rating.elo.rounded()))")
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("\(kind.title) ratings")
            } footer: {
                Text("Elo ratings start at \(Int(Elo.initial)) and move after every finished game — humans and bots alike. Wins against stronger players count for more.")
            }
        }
        .navigationTitle("Rankings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
