import Foundation
import MultipeerConnectivity

struct DiscoveredTable: Identifiable, Hashable {
    var id: String           // host player ID (MCPeerID display name)
    var hostName: String
    var gameKind: GameKind?
    let peer: MCPeerID

    static func == (lhs: DiscoveredTable, rhs: DiscoveredTable) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Nearby play over MultipeerConnectivity (Bluetooth / local Wi-Fi).
/// The MCPeerID display name carries the stable player ID; human-readable
/// names travel inside `Envelope.hello` and the advertiser's discovery info.
@MainActor
final class MultipeerTransport: NSObject, ObservableObject, GameTransport {
    static let serviceType = "parlor-game"

    let isHost: Bool
    var onReceive: ((Envelope, String) -> Void)?
    var onPeersChanged: (() -> Void)?

    @Published var discovered: [DiscoveredTable] = []
    @Published var connectionState: MCSessionState = .notConnected

    private let myPeerID: MCPeerID
    private let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    var connectedPeerIDs: [String] {
        session.connectedPeers.map(\.displayName)
    }

    /// Host: advertise a table for the chosen game.
    init(hostingGame kind: GameKind, hostName: String) {
        isHost = true
        myPeerID = MCPeerID(displayName: Identity.playerID)
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
        let info = ["name": String(hostName.prefix(40)), "game": kind.rawValue]
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: info, serviceType: Self.serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
    }

    /// Joiner: browse for nearby tables; call `join(_:)` to connect.
    override init() {
        isHost = false
        myPeerID = MCPeerID(displayName: Identity.playerID)
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
    }

    func join(_ table: DiscoveredTable) {
        browser?.invitePeer(table.peer, to: session, withContext: nil, timeout: 30)
    }

    func send(_ envelope: Envelope, to peerIDs: [String]?) {
        let targets: [MCPeerID]
        if let peerIDs {
            targets = session.connectedPeers.filter { peerIDs.contains($0.displayName) }
        } else {
            targets = session.connectedPeers
        }
        guard !targets.isEmpty, let data = try? envelope.encoded() else { return }
        try? session.send(data, toPeers: targets, with: .reliable)
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session.disconnect()
    }
}

extension MultipeerTransport: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            self.connectionState = state
            self.onPeersChanged?()
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let envelope = try? Envelope.decoded(from: data) else { return }
        let sender = peerID.displayName
        Task { @MainActor in
            self.onReceive?(envelope, sender)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension MultipeerTransport: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // The table is open; anyone nearby with the app may sit down.
        Task { @MainActor in
            invitationHandler(true, self.session)
        }
    }
}

extension MultipeerTransport: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let table = DiscoveredTable(
            id: peerID.displayName,
            hostName: info?["name"] ?? "Nearby player",
            gameKind: info?["game"].flatMap(GameKind.init(rawValue:)),
            peer: peerID
        )
        Task { @MainActor in
            if !self.discovered.contains(table) {
                self.discovered.append(table)
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let id = peerID.displayName
        Task { @MainActor in
            self.discovered.removeAll { $0.id == id }
        }
    }
}
