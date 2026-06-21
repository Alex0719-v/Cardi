//
//  MultipeerExchangeTransport.swift
//  Carda
//

import Foundation
import MultipeerConnectivity
import UIKit

final class MultipeerExchangeTransport: NSObject {
    static let serviceType = "carda-ex"

    var onPeerConnected: ((MCPeerID) -> Void)?
    var onPeerDisconnected: ((MCPeerID) -> Void)?
    var onDataReceived: ((Data, MCPeerID) -> Void)?
    var onFailure: ((String) -> Void)?

    private let localPeerID: MCPeerID
    private let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var invitedPeers: Set<MCPeerID> = []
    private var isRunning = false

    override init() {
        let peerUUID = Self.localPeerUUID()
        self.localPeerID = MCPeerID(displayName: "Carda-\(peerUUID.uuidString.prefix(8))")
        self.session = MCSession(
            peer: localPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        super.init()
        session.delegate = self
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let discoveryInfo = [
            "app": "Carda",
            "mode": "card-exchange"
        ]

        let advertiser = MCNearbyServiceAdvertiser(
            peer: localPeerID,
            discoveryInfo: discoveryInfo,
            serviceType: Self.serviceType
        )
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser

        let browser = MCNearbyServiceBrowser(
            peer: localPeerID,
            serviceType: Self.serviceType
        )
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        advertiser = nil

        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        browser = nil

        invitedPeers.removeAll()
        session.disconnect()
    }

    func send(_ data: Data, to peer: MCPeerID) {
        guard session.connectedPeers.contains(peer) else { return }

        do {
            try session.send(data, toPeers: [peer], with: .reliable)
        } catch {
            onFailure?("名片交换发送失败")
        }
    }

    private static func localPeerUUID() -> UUID {
        let key = "CardaExchangeLocalPeerUUID"
        if
            let stored = UserDefaults.standard.string(forKey: key),
            let uuid = UUID(uuidString: stored)
        {
            return uuid
        }

        let uuid = UUID()
        UserDefaults.standard.set(uuid.uuidString, forKey: key)
        return uuid
    }

    private func shouldInvite(_ peerID: MCPeerID) -> Bool {
        localPeerID.displayName < peerID.displayName
    }
}

extension MultipeerExchangeTransport: MCNearbyServiceAdvertiserDelegate {
    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRunning else {
                invitationHandler(false, nil)
                return
            }

            invitationHandler(true, self.session)
        }
    }

    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didNotStartAdvertisingPeer error: Error
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.onFailure?("附近发现广播启动失败")
        }
    }
}

extension MultipeerExchangeTransport: MCNearbyServiceBrowserDelegate {
    func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        DispatchQueue.main.async { [weak self] in
            guard
                let self,
                self.isRunning,
                self.shouldInvite(peerID),
                !self.invitedPeers.contains(peerID),
                !self.session.connectedPeers.contains(peerID)
            else {
                return
            }

            self.invitedPeers.insert(peerID)
            browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 8)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async { [weak self] in
            self?.invitedPeers.remove(peerID)
        }
    }

    func browser(
        _ browser: MCNearbyServiceBrowser,
        didNotStartBrowsingForPeers error: Error
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.onFailure?("附近设备浏览启动失败")
        }
    }
}

extension MultipeerExchangeTransport: MCSessionDelegate {
    func session(
        _ session: MCSession,
        peer peerID: MCPeerID,
        didChange state: MCSessionState
    ) {
        DispatchQueue.main.async { [weak self] in
            switch state {
            case .connected:
                self?.onPeerConnected?(peerID)
            case .notConnected:
                self?.invitedPeers.remove(peerID)
                self?.onPeerDisconnected?(peerID)
            case .connecting:
                break
            @unknown default:
                break
            }
        }
    }

    func session(
        _ session: MCSession,
        didReceive data: Data,
        fromPeer peerID: MCPeerID
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.onDataReceived?(data, peerID)
        }
    }

    func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}

    func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {}

    func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {}
}
