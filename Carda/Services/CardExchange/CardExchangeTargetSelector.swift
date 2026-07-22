//
//  CardExchangeTargetSelector.swift
//  Cardi
//

import Foundation
import MultipeerConnectivity
import simd

struct CardExchangeTargetCandidate {
    let peerID: MCPeerID
    let displayName: String
    let distance: Float
    let direction: SIMD3<Float>?
    let qualifiedSince: Date
    let updatedAt: Date
}

enum CardExchangeTargetSelectionMode {
    case directionAndDistance
    case distanceOnly
}

enum CardExchangeTargetSelection {
    case none
    case ambiguous
    case locked(CardExchangeTarget)
}

struct CardExchangeTargetSelector {
    let maximumDistance: Float
    let maximumForwardAngle: Float
    let stableDuration: TimeInterval
    let ambiguousDistanceGap: Float
    let readingTTL: TimeInterval

    init(
        maximumDistance: Float = 1.5,
        maximumForwardAngle: Float = .pi / 4,
        stableDuration: TimeInterval = 0.4,
        ambiguousDistanceGap: Float = 0.3,
        readingTTL: TimeInterval = 1.25
    ) {
        self.maximumDistance = maximumDistance
        self.maximumForwardAngle = maximumForwardAngle
        self.stableDuration = stableDuration
        self.ambiguousDistanceGap = ambiguousDistanceGap
        self.readingTTL = readingTTL
    }

    func isDirectionForward(_ direction: SIMD3<Float>) -> Bool {
        let magnitude = simd_length(direction)
        guard magnitude > 0 else { return false }

        let normalized = direction / magnitude
        let forward = SIMD3<Float>(0, 0, -1)
        let cosine = min(max(simd_dot(normalized, forward), -1), 1)
        return acos(cosine) <= maximumForwardAngle
    }

    func select(
        from candidates: [CardExchangeTargetCandidate],
        now: Date,
        mode: CardExchangeTargetSelectionMode = .directionAndDistance
    ) -> CardExchangeTargetSelection {
        let eligible = candidates
            .filter { candidate in
                now.timeIntervalSince(candidate.updatedAt) <= readingTTL
                    && now.timeIntervalSince(candidate.qualifiedSince) >= stableDuration
                    && candidate.distance <= maximumDistance
                    && isDirectionEligible(candidate.direction, mode: mode)
            }
            .sorted { lhs, rhs in
                if lhs.distance == rhs.distance {
                    return lhs.displayName < rhs.displayName
                }
                return lhs.distance < rhs.distance
            }

        guard let nearest = eligible.first else {
            return .none
        }

        if
            eligible.count > 1,
            eligible[1].distance - nearest.distance < ambiguousDistanceGap
        {
            return .ambiguous
        }

        return .locked(
            CardExchangeTarget(
                peerID: nearest.peerID,
                displayName: nearest.displayName,
                distance: nearest.distance
            )
        )
    }

    private func isDirectionEligible(
        _ direction: SIMD3<Float>?,
        mode: CardExchangeTargetSelectionMode
    ) -> Bool {
        switch mode {
        case .directionAndDistance:
            guard let direction else { return false }
            return isDirectionForward(direction)
        case .distanceOnly:
            return true
        }
    }
}
