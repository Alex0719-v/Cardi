//
//  NearbyExchangeRangingSession.swift
//  Carda
//

import Foundation
import MultipeerConnectivity
import NearbyInteraction

final class NearbyExchangeRangingSession: NSObject {
    let peerID: MCPeerID

    var onUpdate: ((MCPeerID, Float, SIMD3<Float>?) -> Void)?
    var onRemoved: ((MCPeerID) -> Void)?
    var onFailure: ((MCPeerID, String) -> Void)?

    private let session = NISession()

    init(peerID: MCPeerID) {
        self.peerID = peerID
        super.init()
        session.delegate = self
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
        guard
            let token = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: NIDiscoveryToken.self,
                from: tokenData
            )
        else {
            onFailure?(peerID, "附近设备识别失败")
            return
        }

        let configuration = NINearbyPeerConfiguration(peerToken: token)
        session.run(configuration)
    }

    func invalidate() {
        session.invalidate()
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
        onRemoved?(peerID)
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        onFailure?(peerID, "近距离测距已停止")
    }
}
