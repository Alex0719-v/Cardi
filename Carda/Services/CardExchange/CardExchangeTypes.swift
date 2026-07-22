//
//  CardExchangeTypes.swift
//  Cardi
//

import Foundation
import MultipeerConnectivity

enum CardExchangeTransferMode: String, Codable, Equatable {
    case delivery
    case mutual
    case returnDelivery

    var isMutual: Bool {
        self == .mutual
    }
}

struct CardExchangeTarget: Identifiable, Equatable {
    let peerID: MCPeerID
    let displayName: String
    let distance: Float

    var id: String {
        peerID.displayName
    }
}

struct CardExchangeIncomingDelivery: Identifiable, Equatable {
    let exchangeID: UUID
    let peerID: MCPeerID
    let payload: CardExchangePayload
    let mode: CardExchangeTransferMode

    var id: UUID {
        exchangeID
    }

    var peerDisplayName: String {
        payload.displayName
    }
}

enum CardExchangePhase: Equatable {
    case unavailable
    case listening
    case discovering
    case confirmingDirection
    case targetLocked(CardaExchangeTargetSummary)
    case resolvingIntent(CardaExchangeTargetSummary)
    case sending(CardaExchangeTargetSummary, CardExchangeTransferMode)
    case waitingForPersistence(CardaExchangeTargetSummary, CardExchangeTransferMode)
    case ambiguous
    case noTarget
    case failed(String)

    var diagnosticCode: String {
        switch self {
        case .unavailable: "unavailable"
        case .listening: "listening"
        case .discovering: "discovering"
        case .confirmingDirection: "confirming_direction"
        case .targetLocked: "target_locked"
        case .resolvingIntent: "resolving_intent"
        case .sending(_, let mode): "sending_\(mode.rawValue)"
        case .waitingForPersistence(_, let mode): "waiting_persistence_\(mode.rawValue)"
        case .ambiguous: "ambiguous"
        case .noTarget: "no_target"
        case .failed: "failed"
        }
    }
}

struct CardaExchangeTargetSummary: Equatable {
    let displayName: String
    let distance: Float
}

extension CardExchangeTarget {
    var summary: CardaExchangeTargetSummary {
        CardaExchangeTargetSummary(displayName: displayName, distance: distance)
    }
}
