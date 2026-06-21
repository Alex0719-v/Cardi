//
//  CardExchangeCoordinator.swift
//  Carda
//

import Combine
import Foundation
import MultipeerConnectivity
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
        var lastDirection: SIMD3<Float>?
    }

    private enum Constants {
        static let topTouchDistanceThreshold: Float = 0.12
        static let topDirectionMinimumY: Float = 0.45
        static let stableContactDuration: TimeInterval = 0.5
        static let peerCooldown: TimeInterval = 5
    }

    @Published var statusMessage: String?

    var onReceivedCard: ((CardExchangePayload) -> Void)?

    private let transport = MultipeerExchangeTransport()
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
            return
        }

        isRunning = true
        transport.start()
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
    }

    private func handlePeerConnected(_ peerID: MCPeerID) {
        guard isRunning else { return }

        let rangingSession = makeRangingSession(for: peerID)
        var state = peerStates[peerID] ?? PeerState()
        state.rangingSession = rangingSession
        peerStates[peerID] = state

        guard let tokenData = rangingSession.localDiscoveryTokenData() else {
            send(.error("附近识别令牌创建失败"), to: peerID)
            return
        }

        send(.nearbyToken(tokenData), to: peerID)
    }

    private func handlePeerDisconnected(_ peerID: MCPeerID) {
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
        rangingSession.onFailure = { [weak self] peerID, message in
            self?.resetContactState(for: peerID)
            self?.statusMessage = message
        }
        return rangingSession
    }

    private func handleNearbyUpdate(
        peerID: MCPeerID,
        distance: Float,
        direction: SIMD3<Float>?
    ) {
        guard isRunning else { return }

        var state = peerStates[peerID] ?? PeerState()
        state.lastDistance = distance
        state.lastDirection = direction

        guard isTopTouch(distance: distance, direction: direction) else {
            state.stableCloseSince = nil
            state.didTriggerCurrentContact = false
            peerStates[peerID] = state
            return
        }

        let now = Date()
        if state.stableCloseSince == nil {
            state.stableCloseSince = now
            peerStates[peerID] = state
            return
        }

        guard
            !state.didTriggerCurrentContact,
            let stableCloseSince = state.stableCloseSince,
            now.timeIntervalSince(stableCloseSince) >= Constants.stableContactDuration
        else {
            peerStates[peerID] = state
            return
        }

        state.didTriggerCurrentContact = true
        peerStates[peerID] = state

        let exchangeID = UUID()
        if let cardID = localPayload?.sourceCardID {
            send(.proximityConfirmed(exchangeID: exchangeID, cardID: cardID), to: peerID)
        }
        sendCardIfAllowed(to: peerID, exchangeID: exchangeID)
    }

    private func isTopTouch(distance: Float, direction: SIMD3<Float>?) -> Bool {
        guard distance <= Constants.topTouchDistanceThreshold else { return false }
        guard let direction else { return true }
        return direction.y >= Constants.topDirectionMinimumY
    }

    private func resetContactState(for peerID: MCPeerID) {
        guard var state = peerStates[peerID] else { return }
        state.stableCloseSince = nil
        state.didTriggerCurrentContact = false
        state.lastDistance = nil
        state.lastDirection = nil
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
        send(.card(payload, exchangeID: exchangeID), to: peerID)
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
        statusMessage = "已收到\(payload.displayName)的名片"
        onReceivedCard?(payload)
    }

    private func send(_ message: CardExchangeMessage, to peerID: MCPeerID) {
        guard let data = try? encoder.encode(message) else { return }
        transport.send(data, to: peerID)
    }
}
