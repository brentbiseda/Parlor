import Foundation
import GroupActivities
import Combine

/// The activity shared over FaceTime / Messages. The activity payload itself
/// tells every joiner what game is being set up and which player hosts.
struct ParlorActivity: GroupActivity {
    static let activityIdentifier = "com.brentbiseda.Parlor.table"

    var gameKind: GameKind
    var options: GameOptions
    var hostPlayerID: String
    var hostName: String

    var metadata: GroupActivityMetadata {
        var meta = GroupActivityMetadata()
        meta.title = "\(gameKind.title) with \(hostName)"
        meta.type = .generic
        return meta
    }
}

/// Remote play over SharePlay. Friends join from the FaceTime call or the
/// link in Messages; bytes flow through GroupSessionMessenger.
@MainActor
final class SharePlayTransport: ObservableObject, GameTransport {
    let isHost: Bool
    let activity: ParlorActivity
    var onReceive: ((Envelope, String) -> Void)?
    var onPeersChanged: (() -> Void)?

    private let groupSession: GroupSession<ParlorActivity>
    private let messenger: GroupSessionMessenger
    /// participant UUID string → stable player ID (learned from hello messages).
    private var participantToPlayer: [String: String] = [:]
    private var playerToParticipant: [String: Participant] = [:]
    private var tasks: [Task<Void, Never>] = []
    private var cancellables: Set<AnyCancellable> = []

    var connectedPeerIDs: [String] { Array(playerToParticipant.keys) }

    init(session: GroupSession<ParlorActivity>) {
        groupSession = session
        activity = session.activity
        isHost = session.activity.hostPlayerID == Identity.playerID
        messenger = GroupSessionMessenger(session: session)

        tasks.append(Task { [weak self] in
            guard let self else { return }
            for await (data, context) in self.messenger.messages(of: Data.self) {
                self.handle(data: data, from: context.source)
            }
        })

        session.$activeParticipants
            .receive(on: DispatchQueue.main)
            .sink { [weak self] participants in
                guard let self else { return }
                let active = Set(participants.map { $0.id.uuidString })
                let dropped = self.participantToPlayer.keys.filter { !active.contains($0) }
                for key in dropped {
                    if let playerID = self.participantToPlayer.removeValue(forKey: key) {
                        self.playerToParticipant.removeValue(forKey: playerID)
                    }
                }
                self.onPeersChanged?()
            }
            .store(in: &cancellables)

        session.join()
    }

    private func handle(data: Data, from participant: Participant) {
        guard let envelope = try? Envelope.decoded(from: data) else { return }
        // Learn the participant ↔ player mapping from any hello we see.
        if case .hello(let info) = envelope {
            participantToPlayer[participant.id.uuidString] = info.id
            playerToParticipant[info.id] = participant
            onPeersChanged?()
        }
        let sender = participantToPlayer[participant.id.uuidString] ?? participant.id.uuidString
        onReceive?(envelope, sender)
    }

    func send(_ envelope: Envelope, to peerIDs: [String]?) {
        guard let data = try? envelope.encoded() else { return }
        let destination: Participants
        if let peerIDs {
            let targets = Set(peerIDs.compactMap { playerToParticipant[$0] })
            guard !targets.isEmpty else { return }
            destination = .only(targets)
        } else {
            destination = .all
        }
        Task {
            try? await messenger.send(data, to: destination)
        }
    }

    func stop() {
        for task in tasks { task.cancel() }
        groupSession.leave()
    }
}
