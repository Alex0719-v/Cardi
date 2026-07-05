//
//  NearbyExchangeRangingSession.swift
//  Carda
//

import Foundation
import MultipeerConnectivity
import NearbyInteraction
import OSLog

final class NearbyExchangeRangingSession: NSObject {
    let peerID: MCPeerID

    var onUpdate: ((MCPeerID, Float, SIMD3<Float>?) -> Void)?
    var onRemoved: ((MCPeerID) -> Void)?
    var onInvalidated: ((MCPeerID) -> Void)?
    var onFailure: ((MCPeerID, String) -> Void)?

    private var session = NISession()
    private var peerTokenData: Data?
    private var isManuallyInvalidating = false
    private let logger = Logger(subsystem: "com.Alex.Carda", category: "NearbyExchangeRanging")

    init(peerID: MCPeerID) {
        self.peerID = peerID
        super.init()
        configureSession()
    }

    static var isSupported: Bool {
        NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
    }

    func localDiscoveryTokenData() -> Data? {
        guard let token = session.discoveryToken else { return nil }
        return try? NSKeyedArchiver.archivedData(
            withRootObject: token,
            requiringSecureCoding: true
        )
    }

    func run(withPeerTokenData tokenData: Data) {
        peerTokenData = tokenData
        runWithCachedPeerToken()
    }

    func restartRanging() {
        runWithCachedPeerToken()
    }

    func invalidate() {
        isManuallyInvalidating = true
        session.invalidate()
    }

    private func configureSession() {
        session.delegate = self
    }

    private func recreateSession() {
        session.delegate = nil
        session = NISession()
        configureSession()
    }

    private func runWithCachedPeerToken() {
        guard
            let peerTokenData,
            let token = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: NIDiscoveryToken.self,
                from: peerTokenData
            )
        else {
            onFailure?(peerID, "附近设备识别失败")
            return
        }

        let configuration = NINearbyPeerConfiguration(peerToken: token)
        session.run(configuration)
        logger.info("NISession run for \(self.peerID.displayName, privacy: .public)")
    }
}

extension NearbyExchangeRangingSession: NISessionDelegate {
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let object = nearbyObjects.first else { return }
        onUpdate?(peerID, object.distance ?? .greatestFiniteMagnitude, object.direction)
    }

    func session(
        _ session: NISession,
        didRemove nearbyObjects: [NINearbyObject],
        reason: NINearbyObject.RemovalReason
    ) {
        logger.info("NISession removed object for \(self.peerID.displayName, privacy: .public), reason=\(String(describing: reason), privacy: .public)")
        onRemoved?(peerID)
        if reason == .timeout {
            restartRanging()
        }
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        guard !isManuallyInvalidating else { return }
        logger.error("NISession invalidated for \(self.peerID.displayName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        recreateSession()
        onInvalidated?(peerID)
        restartRanging()
    }

    func sessionWasSuspended(_ session: NISession) {
        logger.info("NISession suspended for \(self.peerID.displayName, privacy: .public)")
        onRemoved?(peerID)
    }

    func sessionSuspensionEnded(_ session: NISession) {
        logger.info("NISession suspension ended for \(self.peerID.displayName, privacy: .public)")
        restartRanging()
    }
}
