import Foundation
import MultipeerConnectivity

struct CardExchangeTarget: Equatable {
    let peerID: MCPeerID
    let displayName: String
    let distance: Float
}

@main
private enum CardExchangeTargetSelectorTests {
    private static let now = Date(timeIntervalSince1970: 10_000)

    static func main() {
        acceptsInclusiveGeometricAndFreshnessBoundariesAfterStabilityThreshold()
        rejectsCandidatesOutsideEveryBoundary()
        treatsOnlySubThresholdDistanceGapsAsAmbiguous()
        locksTheNearestEligiblePeer()
        print("CardExchangeTargetSelectorTests: PASS")
    }

    private static func acceptsInclusiveGeometricAndFreshnessBoundariesAfterStabilityThreshold() {
        let selector = CardExchangeTargetSelector()
        let direction = directionAtForwardAngle(.pi / 4)
        let candidate = makeCandidate(
            name: "boundary",
            distance: 1.5,
            direction: direction,
            // Date stores this synthetic timestamp with roughly 24ns of
            // quantization, so use 1ms beyond the contractual 0.4s boundary.
            qualifiedSince: now.addingTimeInterval(-0.401),
            updatedAt: now.addingTimeInterval(-1.25)
        )

        guard case .locked(let target) = selector.select(from: [candidate], now: now) else {
            preconditionFailure("Inclusive geometric and freshness boundaries should be eligible")
        }
        precondition(target.displayName == "boundary")
        precondition(target.distance == 1.5)
    }

    private static func rejectsCandidatesOutsideEveryBoundary() {
        let selector = CardExchangeTargetSelector()
        let valid = makeCandidate(name: "valid", distance: 1.0)

        let tooFar = replacing(valid, distance: 1.5001)
        assertNone(selector.select(from: [tooFar], now: now), "distance > 1.5m")

        let outsideCone = replacing(
            valid,
            direction: directionAtForwardAngle(.pi / 4 + 0.001)
        )
        assertNone(selector.select(from: [outsideCone], now: now), "angle > 45 degrees")

        let unstable = replacing(
            valid,
            qualifiedSince: now.addingTimeInterval(-0.399)
        )
        assertNone(selector.select(from: [unstable], now: now), "stability < 0.4s")

        let stale = replacing(
            valid,
            updatedAt: now.addingTimeInterval(-1.251)
        )
        assertNone(selector.select(from: [stale], now: now), "reading age > 1.25s")

        let zeroVector = replacing(valid, direction: .zero)
        assertNone(selector.select(from: [zeroVector], now: now), "zero direction vector")
    }

    private static func treatsOnlySubThresholdDistanceGapsAsAmbiguous() {
        let selector = CardExchangeTargetSelector()
        let nearest = makeCandidate(name: "nearest", distance: 0.8)
        let gapBelowThreshold = makeCandidate(name: "second", distance: 1.099)

        guard case .ambiguous = selector.select(
            from: [nearest, gapBelowThreshold],
            now: now
        ) else {
            preconditionFailure("A distance gap below 0.3m must be ambiguous")
        }

        let exactThreshold = makeCandidate(name: "second", distance: 1.1)
        guard case .locked(let target) = selector.select(
            from: [exactThreshold, nearest],
            now: now
        ) else {
            preconditionFailure("An exact 0.3m gap must lock the nearest peer")
        }
        precondition(target.displayName == "nearest")
    }

    private static func locksTheNearestEligiblePeer() {
        let selector = CardExchangeTargetSelector()
        let farther = makeCandidate(name: "farther", distance: 1.4)
        let nearest = makeCandidate(name: "nearest", distance: 0.4)
        let staleButCloser = makeCandidate(
            name: "stale",
            distance: 0.1,
            updatedAt: now.addingTimeInterval(-2)
        )

        guard case .locked(let target) = selector.select(
            from: [farther, staleButCloser, nearest],
            now: now
        ) else {
            preconditionFailure("The nearest eligible peer should be locked")
        }
        precondition(target.displayName == "nearest")
    }

    private static func makeCandidate(
        name: String,
        distance: Float,
        direction: SIMD3<Float> = SIMD3<Float>(0, 0, -1),
        qualifiedSince: Date = now.addingTimeInterval(-1),
        updatedAt: Date = now
    ) -> CardExchangeTargetCandidate {
        CardExchangeTargetCandidate(
            peerID: MCPeerID(displayName: name),
            displayName: name,
            distance: distance,
            direction: direction,
            qualifiedSince: qualifiedSince,
            updatedAt: updatedAt
        )
    }

    private static func replacing(
        _ candidate: CardExchangeTargetCandidate,
        distance: Float? = nil,
        direction: SIMD3<Float>? = nil,
        qualifiedSince: Date? = nil,
        updatedAt: Date? = nil
    ) -> CardExchangeTargetCandidate {
        CardExchangeTargetCandidate(
            peerID: candidate.peerID,
            displayName: candidate.displayName,
            distance: distance ?? candidate.distance,
            direction: direction ?? candidate.direction,
            qualifiedSince: qualifiedSince ?? candidate.qualifiedSince,
            updatedAt: updatedAt ?? candidate.updatedAt
        )
    }

    private static func directionAtForwardAngle(_ angle: Float) -> SIMD3<Float> {
        SIMD3<Float>(sin(angle), 0, -cos(angle))
    }

    private static func assertNone(
        _ selection: CardExchangeTargetSelection,
        _ reason: String
    ) {
        guard case .none = selection else {
            preconditionFailure("Expected no target for \(reason)")
        }
    }
}
