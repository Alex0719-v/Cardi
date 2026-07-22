//
//  MultipeerExchangeTransport.swift
//  Cardi
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
    private let diagnostics = CardExchangeDiagnostics.shared

    override init() {
        let peerUUID = Self.localPeerUUID()
        self.localPeerID = MCPeerID(displayName: "Cardi-\(peerUUID.uuidString.prefix(8))")
        self.session = MCSession(
            peer: localPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        super.init()
        session.delegate = self
    }

    var connectedPeers: [MCPeerID] {
        session.connectedPeers
    }

    var localPeerIdentifier: String {
        localPeerID.displayName
    }

    func startReceiving() {
        guard !isRunning else { return }
        isRunning = true

        let discoveryInfo = [
            "app": "Cardi",
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
        diagnostics.record(
            stage: .discovery,
            name: "advertising_started",
            details: [
                "service": Self.serviceType,
                "localPeerHash": CardExchangeDiagnostics.anonymousIdentifier(
                    localPeerID.displayName
                )
            ]
        )
    }

    func startActiveDiscovery() {
        if !isRunning {
            startReceiving()
        }
        guard browser == nil else { return }

        let browser = MCNearbyServiceBrowser(
            peer: localPeerID,
            serviceType: Self.serviceType
        )
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
        diagnostics.record(
            stage: .discovery,
            name: "browsing_started",
            details: ["service": Self.serviceType]
        )
    }

    func stopActiveDiscovery() {
        let wasBrowsing = browser != nil
        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        browser = nil
        if wasBrowsing {
            diagnostics.record(stage: .discovery, name: "browsing_stopped")
        }
    }

    func disconnectAllPeers() {
        let peerCount = session.connectedPeers.count
        invitedPeers.removeAll()
        session.disconnect()
        diagnostics.record(
            stage: .connection,
            name: "disconnect_all_requested",
            details: ["connectedPeerCount": String(peerCount)]
        )
    }

    func stop() {
        isRunning = false

        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        advertiser = nil

        stopActiveDiscovery()

        disconnectAllPeers()
        diagnostics.record(stage: .lifecycle, name: "transport_stopped")
    }

    @discardableResult
    func send(_ data: Data, to peer: MCPeerID) -> Bool {
        guard session.connectedPeers.contains(peer) else {
            diagnostics.record(
                stage: .transfer,
                name: "transport_send_rejected_not_connected",
                level: .error,
                peerIdentifier: peer.displayName,
                details: ["bytes": String(data.count)]
            )
            onFailure?("名片交换连接已断开")
            return false
        }

        do {
            try session.send(data, toPeers: [peer], with: .reliable)
            diagnostics.record(
                stage: .transfer,
                name: "transport_send_succeeded",
                peerIdentifier: peer.displayName,
                details: ["bytes": String(data.count)]
            )
            return true
        } catch {
            let nsError = error as NSError
            diagnostics.record(
                stage: .transfer,
                name: "transport_send_failed",
                level: .error,
                peerIdentifier: peer.displayName,
                details: [
                    "bytes": String(data.count),
                    "errorDomain": nsError.domain,
                    "errorCode": String(nsError.code)
                ]
            )
            onFailure?("名片交换发送失败")
            return false
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
                self?.diagnostics.record(
                    stage: .connection,
                    name: "incoming_invitation_rejected_not_running",
                    level: .warning,
                    peerIdentifier: peerID.displayName
                )
                invitationHandler(false, nil)
                return
            }

            self.diagnostics.record(
                stage: .connection,
                name: "incoming_invitation_accepted",
                peerIdentifier: peerID.displayName
            )
            invitationHandler(true, self.session)
        }
    }

    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didNotStartAdvertisingPeer error: Error
    ) {
        DispatchQueue.main.async { [weak self] in
            let nsError = error as NSError
            self?.diagnostics.record(
                stage: .discovery,
                name: "advertising_failed",
                level: .error,
                details: [
                    "errorDomain": nsError.domain,
                    "errorCode": String(nsError.code)
                ]
            )
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
                !self.invitedPeers.contains(peerID),
                !self.session.connectedPeers.contains(peerID)
            else {
                return
            }

            self.invitedPeers.insert(peerID)
            self.diagnostics.record(
                stage: .discovery,
                name: "peer_found_invitation_sent",
                peerIdentifier: peerID.displayName,
                details: ["timeoutSeconds": "8"]
            )
            browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 8)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async { [weak self] in
            self?.invitedPeers.remove(peerID)
            self?.diagnostics.record(
                stage: .discovery,
                name: "peer_lost",
                peerIdentifier: peerID.displayName
            )
        }
    }

    func browser(
        _ browser: MCNearbyServiceBrowser,
        didNotStartBrowsingForPeers error: Error
    ) {
        DispatchQueue.main.async { [weak self] in
            let nsError = error as NSError
            self?.diagnostics.record(
                stage: .discovery,
                name: "browsing_failed",
                level: .error,
                details: [
                    "errorDomain": nsError.domain,
                    "errorCode": String(nsError.code)
                ]
            )
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
            let stateName: String
            switch state {
            case .connected:
                stateName = "connected"
            case .notConnected:
                stateName = "not_connected"
            case .connecting:
                stateName = "connecting"
            @unknown default:
                stateName = "unknown"
            }
            self?.diagnostics.record(
                stage: .connection,
                name: "peer_state_changed",
                peerIdentifier: peerID.displayName,
                details: ["state": stateName]
            )
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
            self?.diagnostics.record(
                stage: .transfer,
                name: "transport_data_received",
                peerIdentifier: peerID.displayName,
                details: ["bytes": String(data.count)]
            )
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
