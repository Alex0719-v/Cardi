//
//  NearbyExchangeRangingSession.swift
//  Cardi
//

import Foundation
import MultipeerConnectivity
import NearbyInteraction
import OSLog

final class NearbyExchangeRangingSession: NSObject {
    let peerID: MCPeerID

    var onUpdate: ((MCPeerID, Float?, SIMD3<Float>?) -> Void)?
    var onRemoved: ((MCPeerID) -> Void)?
    var onInvalidated: ((MCPeerID) -> Void)?
    var onFailure: ((MCPeerID, String) -> Void)?

    private var session = NISession()
    private var peerTokenData: Data?
    private var isManuallyInvalidating = false
    private let logger = Logger(subsystem: "com.Alex.Carda", category: "NearbyExchangeRanging")
    private let diagnostics = CardExchangeDiagnostics.shared

    init(peerID: MCPeerID) {
        self.peerID = peerID
        super.init()
        configureSession()
    }

    static var isSupported: Bool {
        supportsPreciseDistanceMeasurement
    }

    static var supportsPreciseDistanceMeasurement: Bool {
        NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
    }

    static var supportsDirectionMeasurement: Bool {
        NISession.deviceCapabilities.supportsDirectionMeasurement
    }

    func localDiscoveryTokenData() -> Data? {
        guard let token = session.discoveryToken else {
            diagnostics.record(
                stage: .token,
                name: "local_token_unavailable",
                level: .error,
                peerIdentifier: peerID.displayName
            )
            return nil
        }
        do {
            let data = try NSKeyedArchiver.archivedData(
                withRootObject: token,
                requiringSecureCoding: true
            )
            diagnostics.record(
                stage: .token,
                name: "local_token_created",
                peerIdentifier: peerID.displayName,
                details: ["bytes": String(data.count)]
            )
            return data
        } catch {
            let nsError = error as NSError
            diagnostics.record(
                stage: .token,
                name: "local_token_encoding_failed",
                level: .error,
                peerIdentifier: peerID.displayName,
                details: [
                    "errorDomain": nsError.domain,
                    "errorCode": String(nsError.code)
                ]
            )
            return nil
        }
    }

    func run(withPeerTokenData tokenData: Data) {
        peerTokenData = tokenData
        diagnostics.record(
            stage: .token,
            name: "remote_token_received",
            peerIdentifier: peerID.displayName,
            details: ["bytes": String(tokenData.count)]
        )
        runWithCachedPeerToken()
    }

    func restartRanging() {
        diagnostics.record(
            stage: .ranging,
            name: "ranging_restart_requested",
            peerIdentifier: peerID.displayName
        )
        runWithCachedPeerToken()
    }

    func invalidate() {
        isManuallyInvalidating = true
        diagnostics.record(
            stage: .ranging,
            name: "ranging_invalidated_by_app",
            peerIdentifier: peerID.displayName
        )
        session.invalidate()
    }

    private func configureSession() {
        session.delegate = self
    }

    private func recreateSession() {
        session.delegate = nil
        session = NISession()
        isManuallyInvalidating = false
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
            diagnostics.record(
                stage: .token,
                name: "remote_token_decoding_failed",
                level: .error,
                peerIdentifier: peerID.displayName
            )
            onFailure?(peerID, "附近设备识别失败")
            return
        }
        guard token.deviceCapabilities.supportsPreciseDistanceMeasurement else {
            diagnostics.record(
                stage: .ranging,
                name: "remote_precise_distance_unsupported",
                level: .error,
                peerIdentifier: peerID.displayName,
                details: [
                    "peerDirection": String(
                        token.deviceCapabilities.supportsDirectionMeasurement
                    )
                ]
            )
            onFailure?(peerID, "对方设备不支持近距离测距")
            return
        }

        let configuration = NINearbyPeerConfiguration(peerToken: token)
        session.run(configuration)
        diagnostics.record(
            stage: .ranging,
            name: "ranging_session_run",
            peerIdentifier: peerID.displayName,
            details: [
                "localDirection": String(Self.supportsDirectionMeasurement),
                "peerDirection": String(
                    token.deviceCapabilities.supportsDirectionMeasurement
                )
            ]
        )
        logger.info(
            "NISession run for \(self.peerID.displayName, privacy: .public) localDirection=\(Self.supportsDirectionMeasurement, privacy: .public) peerDirection=\(token.deviceCapabilities.supportsDirectionMeasurement, privacy: .public)"
        )
    }
}

extension NearbyExchangeRangingSession: NISessionDelegate {
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let object = nearbyObjects.first else {
            diagnostics.record(
                stage: .ranging,
                name: "ranging_update_empty",
                level: .warning,
                peerIdentifier: peerID.displayName
            )
            return
        }
        var details = [
            "objectCount": String(nearbyObjects.count),
            "hasDistance": String(object.distance != nil),
            "hasDirection": String(object.direction != nil)
        ]
        if let distance = object.distance {
            details["distanceMeters"] = String(format: "%.3f", distance)
        }
        if let direction = object.direction {
            details["directionX"] = String(format: "%.3f", direction.x)
            details["directionY"] = String(format: "%.3f", direction.y)
            details["directionZ"] = String(format: "%.3f", direction.z)
        }
        diagnostics.record(
            stage: .ranging,
            name: "ranging_update",
            level: .debug,
            peerIdentifier: peerID.displayName,
            details: details
        )
        onUpdate?(peerID, object.distance, object.direction)
    }

    func session(
        _ session: NISession,
        didRemove nearbyObjects: [NINearbyObject],
        reason: NINearbyObject.RemovalReason
    ) {
        diagnostics.record(
            stage: .ranging,
            name: "ranging_object_removed",
            level: reason == .timeout ? .warning : .info,
            peerIdentifier: peerID.displayName,
            details: ["reason": String(describing: reason)]
        )
        logger.info("NISession removed object for \(self.peerID.displayName, privacy: .public), reason=\(String(describing: reason), privacy: .public)")
        onRemoved?(peerID)
        if reason == .timeout {
            restartRanging()
        }
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        guard !isManuallyInvalidating else {
            diagnostics.record(
                stage: .ranging,
                name: "manual_invalidation_completed",
                peerIdentifier: peerID.displayName
            )
            return
        }
        let nsError = error as NSError
        diagnostics.record(
            stage: .ranging,
            name: "ranging_session_invalidated",
            level: .error,
            peerIdentifier: peerID.displayName,
            details: [
                "errorDomain": nsError.domain,
                "errorCode": String(nsError.code)
            ]
        )
        logger.error("NISession invalidated for \(self.peerID.displayName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        recreateSession()
        onInvalidated?(peerID)
        restartRanging()
    }

    func sessionWasSuspended(_ session: NISession) {
        diagnostics.record(
            stage: .ranging,
            name: "ranging_session_suspended",
            level: .warning,
            peerIdentifier: peerID.displayName
        )
        logger.info("NISession suspended for \(self.peerID.displayName, privacy: .public)")
        onRemoved?(peerID)
    }

    func sessionSuspensionEnded(_ session: NISession) {
        diagnostics.record(
            stage: .ranging,
            name: "ranging_session_resumed",
            peerIdentifier: peerID.displayName
        )
        logger.info("NISession suspension ended for \(self.peerID.displayName, privacy: .public)")
        restartRanging()
    }
}
