//
//  CardExchangeCoordinator.swift
//  Carda
//

import Combine
import Foundation
import MultipeerConnectivity
import OSLog
import UIKit

final class CardExchangeCoordinator: ObservableObject {
    private struct PeerState {
        var rangingSession: NearbyExchangeRangingSession?
        var stableCloseSince: Date?
        var didTriggerCurrentContact = false
        var lastSentCardAt: Date?
        var lastReceivedCardAt: Date?
        var sentExchangeIDs: Set<UUID> = []
        var receivedExchangeIDs: Set<UUID> = []
        var lastDistance: Float?
        var lastDistanceUpdatedAt: Date?
    }

    private enum Constants {
        static let cardaExchangeDistanceThreshold: Float = 0.05
        static let distanceReadingTTL: TimeInterval = 1.25
        static let stableCloseDuration: TimeInterval = 0
        static let peerCooldown: TimeInterval = 5
    }

    @Published var statusMessage: String?
    @Published private(set) var outgoingCardAnimationID: UUID?

    var onReceivedCard: ((CardExchangePayload) -> Void)?
    var onOutgoingCardSent: (() -> Void)?

    private let transport = MultipeerExchangeTransport()
    private let logger = Logger(subsystem: "com.Alex.Carda", category: "CardExchange")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var peerStates: [MCPeerID: PeerState] = [:]
    private var localPayload: CardExchangePayload?
    private var isRunning = false

    init() {
        transport.onPeerConnected = { [weak self] peerID in
            self?.handlePeerConnected(peerID)
        }
        transport.onPeerDisconnected = { [weak self] peerID in
            self?.handlePeerDisconnected(peerID)
        }
        transport.onDataReceived = { [weak self] data, peerID in
            self?.handleData(data, from: peerID)
        }
        transport.onFailure = { [weak self] message in
            self?.statusMessage = message
        }
    }

    func start(with card: CardRenderData) {
        localPayload = CardExchangePayload(data: card)
        guard !isRunning else { return }

        guard NearbyExchangeRangingSession.isSupported else {
            statusMessage = "当前设备不支持近距离交换"
            logger.error("Start failed: Nearby Interaction precise distance unsupported")
            return
        }

        isRunning = true
        transport.start()
        logger.info("Card exchange started")
    }

    func updateLocalCard(_ card: CardRenderData) {
        localPayload = CardExchangePayload(data: card)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        transport.stop()

        for state in peerStates.values {
            state.rangingSession?.invalidate()
        }
        peerStates.removeAll()
        localPayload = nil
        logger.info("Card exchange stopped")
    }

    private func handlePeerConnected(_ peerID: MCPeerID) {
        guard isRunning else { return }
        logger.info("Peer connected: \(peerID.displayName, privacy: .public)")

        let rangingSession = makeRangingSession(for: peerID)
        var state = peerStates[peerID] ?? PeerState()
        state.rangingSession = rangingSession
        peerStates[peerID] = state

        guard let tokenData = rangingSession.localDiscoveryTokenData() else {
            send(.error("附近识别令牌创建失败"), to: peerID)
            logger.error("Failed to create local NI discovery token for \(peerID.displayName, privacy: .public)")
            return
        }

        send(.nearbyToken(tokenData), to: peerID)
    }

    private func handlePeerDisconnected(_ peerID: MCPeerID) {
        logger.info("Peer disconnected: \(peerID.displayName, privacy: .public)")
        peerStates[peerID]?.rangingSession?.invalidate()
        peerStates.removeValue(forKey: peerID)
    }

    private func handleData(_ data: Data, from peerID: MCPeerID) {
        guard
            isRunning,
            let message = try? decoder.decode(CardExchangeMessage.self, from: data)
        else {
            return
        }

        switch message.kind {
        case .nearbyToken:
            guard let tokenData = message.nearbyTokenData else { return }
            handleNearbyToken(tokenData, from: peerID)
        case .proximityConfirmed:
            guard let exchangeID = message.exchangeID else { return }
            sendCardIfAllowed(to: peerID, exchangeID: exchangeID)
        case .card:
            guard
                let exchangeID = message.exchangeID,
                let payload = message.card
            else {
                return
            }
            handleReceivedCard(payload, exchangeID: exchangeID, from: peerID)
        case .ack:
            break
        case .error:
            statusMessage = message.message
        }
    }

    private func handleNearbyToken(_ tokenData: Data, from peerID: MCPeerID) {
        var state = peerStates[peerID] ?? PeerState()
        let rangingSession = state.rangingSession ?? makeRangingSession(for: peerID)
        state.rangingSession = rangingSession
        peerStates[peerID] = state
        rangingSession.run(withPeerTokenData: tokenData)
    }

    private func makeRangingSession(for peerID: MCPeerID) -> NearbyExchangeRangingSession {
        let rangingSession = NearbyExchangeRangingSession(peerID: peerID)
        rangingSession.onUpdate = { [weak self] peerID, distance, direction in
            self?.handleNearbyUpdate(peerID: peerID, distance: distance, direction: direction)
        }
        rangingSession.onRemoved = { [weak self] peerID in
            self?.resetContactState(for: peerID)
        }
        rangingSession.onInvalidated = { [weak self] peerID in
            self?.handleRangingInvalidated(for: peerID)
        }
        rangingSession.onFailure = { [weak self] peerID, message in
            self?.resetContactState(for: peerID)
            self?.statusMessage = message
        }
        return rangingSession
    }

    private func handleNearbyUpdate(
        peerID: MCPeerID,
        distance: Float,
        direction _: SIMD3<Float>?
    ) {
        guard isRunning else { return }

        var state = peerStates[peerID] ?? PeerState()
        state.lastDistance = distance
        state.lastDistanceUpdatedAt = Date()
        logger.info("NI update peer=\(peerID.displayName, privacy: .public) distance=\(distance, format: .fixed(precision: 3))")

        let now = Date()
        guard isCardaExchangeProximity(
            distance: distance,
            updatedAt: state.lastDistanceUpdatedAt,
            now: now
        ) else {
            state.stableCloseSince = nil
            state.didTriggerCurrentContact = false
            peerStates[peerID] = state
            return
        }

        if state.stableCloseSince == nil {
            state.stableCloseSince = now
        }
        peerStates[peerID] = state
        evaluateProximityExchange(for: peerID)
    }

    private func handleRangingInvalidated(for peerID: MCPeerID) {
        guard isRunning, let rangingSession = peerStates[peerID]?.rangingSession else { return }
        resetContactState(for: peerID)
        guard let tokenData = rangingSession.localDiscoveryTokenData() else {
            logger.error("Failed to recreate local NI discovery token for \(peerID.displayName, privacy: .public)")
            return
        }

        logger.info("Re-sending NI discovery token after invalidation for \(peerID.displayName, privacy: .public)")
        send(.nearbyToken(tokenData), to: peerID)
    }

    private func evaluateProximityExchange(for peerID: MCPeerID) {
        guard isRunning else { return }

        var state = peerStates[peerID] ?? PeerState()
        let now = Date()

        guard
            !state.didTriggerCurrentContact,
            let stableCloseSince = state.stableCloseSince,
            now.timeIntervalSince(stableCloseSince) >= Constants.stableCloseDuration
        else {
            peerStates[peerID] = state
            return
        }

        state.didTriggerCurrentContact = true
        peerStates[peerID] = state
        logger.info("Proximity exchange confirmed peer=\(peerID.displayName, privacy: .public) distance=\(state.lastDistance ?? -1, format: .fixed(precision: 3))")

        let exchangeID = UUID()
        if let cardID = localPayload?.sourceCardID {
            send(.proximityConfirmed(exchangeID: exchangeID, cardID: cardID), to: peerID)
        }
        sendCardIfAllowed(to: peerID, exchangeID: exchangeID)
    }

    private func isCardaExchangeProximity(
        distance: Float?,
        updatedAt: Date?,
        now: Date
    ) -> Bool {
        guard
            let distance,
            let updatedAt,
            now.timeIntervalSince(updatedAt) <= Constants.distanceReadingTTL
        else {
            return false
        }

        return distance <= Constants.cardaExchangeDistanceThreshold
    }

    private func resetContactState(for peerID: MCPeerID) {
        guard var state = peerStates[peerID] else { return }
        state.stableCloseSince = nil
        state.didTriggerCurrentContact = false
        state.lastDistance = nil
        state.lastDistanceUpdatedAt = nil
        peerStates[peerID] = state
    }

    private func sendCardIfAllowed(to peerID: MCPeerID, exchangeID: UUID) {
        guard let payload = localPayload else { return }

        var state = peerStates[peerID] ?? PeerState()
        let now = Date()
        if
            let lastSent = state.lastSentCardAt,
            now.timeIntervalSince(lastSent) < Constants.peerCooldown
        {
            peerStates[peerID] = state
            return
        }

        guard !state.sentExchangeIDs.contains(exchangeID) else {
            peerStates[peerID] = state
            return
        }

        state.sentExchangeIDs.insert(exchangeID)
        state.lastSentCardAt = now
        peerStates[peerID] = state
        statusMessage = "已触发 Carda 近距离交换"
        logger.info("Sending card to \(peerID.displayName, privacy: .public)")
        send(.card(payload, exchangeID: exchangeID), to: peerID)
        notifyOutgoingCardSent()
    }

    private func handleReceivedCard(
        _ payload: CardExchangePayload,
        exchangeID: UUID,
        from peerID: MCPeerID
    ) {
        var state = peerStates[peerID] ?? PeerState()
        let now = Date()

        if state.receivedExchangeIDs.contains(exchangeID) {
            peerStates[peerID] = state
            return
        }

        if
            let lastReceived = state.lastReceivedCardAt,
            now.timeIntervalSince(lastReceived) < Constants.peerCooldown
        {
            peerStates[peerID] = state
            return
        }

        state.receivedExchangeIDs.insert(exchangeID)
        state.lastReceivedCardAt = now
        peerStates[peerID] = state

        send(.ack(exchangeID: exchangeID), to: peerID)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        statusMessage = "收到\(payload.displayName)的名片"
        logger.info("Received card from \(peerID.displayName, privacy: .public)")
        onReceivedCard?(payload)
    }

    private func send(_ message: CardExchangeMessage, to peerID: MCPeerID) {
        guard let data = try? encoder.encode(message) else { return }
        transport.send(data, to: peerID)
        logger.debug("Sent \(message.kind.rawValue, privacy: .public) to \(peerID.displayName, privacy: .public)")
    }

    private func notifyOutgoingCardSent() {
        outgoingCardAnimationID = UUID()
        onOutgoingCardSent?()
    }

    #if DEBUG && targetEnvironment(simulator)
    func simulateProximityExchange(with card: CardRenderData) {
        let simulatedDistance: Float = 0.04
        guard isCardaExchangeProximity(
            distance: simulatedDistance,
            updatedAt: Date(),
            now: Date()
        ) else {
            statusMessage = "模拟碰一碰未达到触发条件"
            return
        }

        var payload = CardExchangePayload(data: card)
        payload.sourceCardID = UUID()
        if payload.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload.name = "模拟对方"
        } else {
            payload.name += "（模拟对方）"
        }

        let peerID = MCPeerID(displayName: "Carda-SimulatorPeer")
        notifyOutgoingCardSent()
        handleReceivedCard(payload, exchangeID: UUID(), from: peerID)
    }
    #endif
}
