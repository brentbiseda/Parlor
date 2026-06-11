import Foundation

/// Abstraction over Multipeer (nearby) and SharePlay (remote) so the session
/// logic doesn't care how bytes move. Peer identifiers are the stable player
/// IDs from `PlayerInfo`, not transport-level identities.
@MainActor
protocol GameTransport: AnyObject {
    var isHost: Bool { get }
    /// Connected remote peers (player IDs). Excludes self.
    var connectedPeerIDs: [String] { get }
    var onReceive: ((Envelope, _ fromPeerID: String) -> Void)? { get set }
    var onPeersChanged: (() -> Void)? { get set }

    func send(_ envelope: Envelope, to peerIDs: [String]?)  // nil = everyone
    func stop()
}

extension GameTransport {
    func broadcast(_ envelope: Envelope) { send(envelope, to: nil) }
}
