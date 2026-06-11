import Foundation
import Combine

/// Local identities: user-managed human profiles plus auto-registered
/// opponents (pass-and-play guests, league entrants, bots). Every finished
/// competitive game updates per-game Elo ratings here.
@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [PlayerProfile] = [] {
        didSet { Persistence.save(profiles, to: "profiles.json") }
    }
    @Published var activeProfileID: UUID? {
        didSet { UserDefaults.standard.set(activeProfileID?.uuidString, forKey: "parlor.activeProfile") }
    }

    init() {
        profiles = Persistence.load("profiles.json") ?? []
        activeProfileID = UserDefaults.standard.string(forKey: "parlor.activeProfile").flatMap(UUID.init)
        if humanProfiles.isEmpty {
            // Migrate the pre-profile player name.
            let legacy = UserDefaults.standard.string(forKey: "parlor.name") ?? "Player"
            let first = PlayerProfile(name: legacy, symbol: "person.fill", colorIndex: 0)
            profiles.append(first)
            activeProfileID = first.id
        }
        if activeProfileID == nil || profile(id: activeProfileID!) == nil {
            activeProfileID = humanProfiles.first?.id
        }
    }

    var humanProfiles: [PlayerProfile] { profiles.filter { !$0.isBot } }

    var active: PlayerProfile {
        activeProfileID.flatMap { profile(id: $0) } ?? humanProfiles.first
            ?? PlayerProfile(name: "Player")
    }

    func profile(id: UUID) -> PlayerProfile? { profiles.first { $0.id == id } }

    // MARK: - Editing

    func add(_ profile: PlayerProfile) {
        profiles.append(profile)
    }

    func update(_ profile: PlayerProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
    }

    func delete(id: UUID) {
        guard humanProfiles.count > 1 || profile(id: id)?.isBot == true else { return }
        profiles.removeAll { $0.id == id }
        if activeProfileID == id { activeProfileID = humanProfiles.first?.id }
    }

    /// Find (case-insensitively) or create the profile for a participant.
    @discardableResult
    func ensure(name: String, isBot: Bool) -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let existing = profiles.first(where: {
            $0.isBot == isBot && $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }) {
            return existing.id
        }
        let fresh = PlayerProfile(name: trimmed,
                                  symbol: isBot ? "cpu" : "person.fill",
                                  colorIndex: abs(trimmed.hashValue) % 8,
                                  isBot: isBot)
        profiles.append(fresh)
        return fresh.id
    }

    // MARK: - Ratings

    /// Update Elo and W–D–L records for one finished game. `participants`
    /// are (name, isBot) in seat order; `seatRanking` groups seats by finish.
    func recordResult(kind: GameKind, participants: [(name: String, isBot: Bool)], seatRanking: [[Int]]) {
        guard kind.isCompetitive, !seatRanking.isEmpty else { return }
        let ids = participants.map { ensure(name: $0.name, isBot: $0.isBot) }
        guard ids.count == participants.count else { return }
        let current = ids.map { id in
            profile(id: id)?.rating(for: kind).elo ?? Elo.initial
        }
        let deltas = Elo.deltas(ranking: seatRanking, ratings: current)
        for (groupIndex, group) in seatRanking.enumerated() {
            for seat in group {
                guard let index = profiles.firstIndex(where: { $0.id == ids[seat] }) else { continue }
                var rating = profiles[index].rating(for: kind)
                rating.elo += deltas[seat]
                rating.played += 1
                if seatRanking.count == 1 {
                    rating.draws += 1
                } else if groupIndex == 0 {
                    rating.wins += 1
                } else {
                    rating.losses += 1
                }
                profiles[index].ratings[kind.rawValue] = rating
            }
        }
    }

    /// Ranked table for one game: everyone who has played it, by Elo.
    func rankings(for kind: GameKind) -> [(profile: PlayerProfile, rating: Rating)] {
        profiles.compactMap { profile in
            guard let rating = profile.ratings[kind.rawValue], rating.played > 0 else { return nil }
            return (profile, rating)
        }
        .sorted { $0.1.elo > $1.1.elo }
    }
}
