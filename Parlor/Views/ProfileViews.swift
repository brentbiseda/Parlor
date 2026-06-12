import SwiftUI

enum Avatar {
    static let colors: [Color] = [.blue, .red, .green, .orange, .purple, .pink, .teal, .indigo]
    static func color(_ index: Int) -> Color { colors[abs(index) % colors.count] }
}

struct AvatarView: View {
    let profile: PlayerProfile
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Avatar.color(profile.colorIndex),
                                              Avatar.color(profile.colorIndex).opacity(0.6)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: profile.isBot ? "cpu" : profile.symbol)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
    }
}

/// Manage local identities, switch who "you" are, and pick the table look.
struct ProfilesView: View {
    @EnvironmentObject var profiles: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing: PlayerProfile? = nil
    @AppStorage(FeltTheme.storageKey) private var feltRaw = FeltTheme.classic.rawValue
    @AppStorage(CardBack.storageKey) private var cardBack = CardBack.classic.rawValue

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(profiles.humanProfiles) { profile in
                        Button {
                            profiles.activeProfileID = profile.id
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(profile: profile, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(profile.ratedGameCount > 0
                                         ? "\(profile.ratedGameCount) rated games"
                                         : "No rated games yet")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if profile.id == profiles.activeProfileID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                                Button {
                                    editing = profile
                                } label: {
                                    Image(systemName: "pencil.circle")
                                        .font(.title3)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for offset in offsets { profiles.delete(id: profiles.humanProfiles[offset].id) }
                    }
                    .deleteDisabled(profiles.humanProfiles.count <= 1)
                } header: {
                    Text("Who's playing?")
                } footer: {
                    Text("The active profile is your name at every table, on leaderboards, and in the rankings. Pass-and-play guests and bots get their own ranking entries automatically.")
                }

                Button {
                    let fresh = PlayerProfile(name: "Player \(profiles.humanProfiles.count + 1)",
                                              symbol: PlayerProfile.symbols.randomElement()!,
                                              colorIndex: Int.random(in: 0..<Avatar.colors.count))
                    profiles.add(fresh)
                    editing = fresh
                } label: {
                    Label("New profile", systemImage: "person.badge.plus")
                }

                Section("Table felt") {
                    HStack(spacing: 12) {
                        ForEach(FeltTheme.allCases) { theme in
                            VStack(spacing: 5) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(LinearGradient(colors: theme.colors,
                                                         startPoint: .top, endPoint: .bottom))
                                    .frame(width: 58, height: 42)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(Color.accentColor,
                                                          lineWidth: feltRaw == theme.rawValue ? 3 : 0)
                                    )
                                Text(theme.title)
                                    .font(.caption2)
                                    .foregroundStyle(feltRaw == theme.rawValue ? .primary : .secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity)
                            .onTapGesture {
                                feltRaw = theme.rawValue
                                SoundFX.shared.play(.click)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Card back") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(CardBack.allCases) { style in
                                VStack(spacing: 4) {
                                    FaceDownCardView(width: 44, styleOverride: style)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 44 * 0.12)
                                                .strokeBorder(Color.accentColor,
                                                              lineWidth: cardBack == style.rawValue ? 3 : 0)
                                        )
                                    Text(style.title)
                                        .font(.caption2)
                                        .foregroundStyle(cardBack == style.rawValue ? .primary : .secondary)
                                }
                                .onTapGesture {
                                    cardBack = style.rawValue
                                    SoundFX.shared.play(.click)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Profiles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .sheet(item: $editing) { profile in
                ProfileEditor(profile: profile)
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct ProfileEditor: View {
    @EnvironmentObject var profiles: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @State var profile: PlayerProfile

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        AvatarView(profile: profile, size: 72)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    TextField("Name", text: $profile.name)
                        .font(.headline)
                }

                Section("Symbol") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 10)], spacing: 10) {
                        ForEach(PlayerProfile.symbols, id: \.self) { symbol in
                            Button {
                                profile.symbol = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .background(profile.symbol == symbol
                                                ? Avatar.color(profile.colorIndex).opacity(0.3)
                                                : Color.gray.opacity(0.12),
                                                in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(profile.symbol == symbol
                                                          ? Avatar.color(profile.colorIndex) : .clear,
                                                          lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Color") {
                    HStack(spacing: 12) {
                        ForEach(Avatar.colors.indices, id: \.self) { index in
                            Button {
                                profile.colorIndex = index
                            } label: {
                                Circle()
                                    .fill(Avatar.colors[index])
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Circle().strokeBorder(.white,
                                                              lineWidth: profile.colorIndex == index ? 3 : 0)
                                    )
                                    .shadow(radius: profile.colorIndex == index ? 3 : 0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        profiles.update(profile)
                        dismiss()
                    }
                    .disabled(profile.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
