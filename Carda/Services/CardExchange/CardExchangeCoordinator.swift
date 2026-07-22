//
//  CardExchangeCoordinator.swift
//  Cardi
//

import Combine
import Foundation
import MultipeerConnectivity
import OSLog

final class CardExchangeCoordinator: ObservableObject {
    private struct RemoteThrowIntent {
        let exchangeID: UUID
        let cardID: UUID
        let createdAt: Date
    }

    private struct LocalThrowIntent {
        let exchangeID: UUID
        let cardID: UUID
        let createdAt: Date
        var targetPeerID: MCPeerID?
    }

    private struct OutgoingTransaction {
        let peerID: MCPeerID
        let peerDisplayName: String
        let mode: CardExchangeTransferMode
    }

    private struct PeerState {
        var displayName: String?
        var rangingSession: NearbyExchangeRangingSession?
        var distanceSamples: [Float] = []
        var lastDirection: SIMD3<Float>?
        var lastDistanceUpdatedAt: Date?
        var qualifiedSince: Date?
        var remoteIntent: RemoteThrowIntent?
        var pendingIncomingExchangeIDs: Set<UUID> = []
        var persistedIncomingExchangeIDs: Set<UUID> = []

        var medianDistance: Float? {
            guard !distanceSamples.isEmpty else { return nil }
            let sorted = distanceSamples.sorted()
            let middle = sorted.count / 2
            if sorted.count.isMultiple(of: 2) {
                return (sorted[middle - 1] + sorted[middle]) / 2
            }
            return sorted[middle]
        }
    }

    private enum Constants {
        static let maximumMessageBytes = 14 * 1_024 * 1_024
        static let maximumDistance: Float = 1.5
        static let mutualIntentWindow: TimeInterval = 1.5
        static let minimumIntentNetworkGrace: TimeInterval = 0.35
        static let activeDiscoveryWindow: TimeInterval = 10
        static let idleCleanupDelay: TimeInterval = 1
        static let repeatedGestureCooldown: TimeInterval = 5
        static let outgoingPersistenceTimeout: TimeInterval = 12
        static let distanceSampleCount = 5
    }

    @Published var statusMessage: String?
    @Published private(set) var phase: CardExchangePhase = .listening
    @Published private(set) var currentTarget: CardExchangeTarget?
    @Published private(set) var outgoingCardAnimationID: UUID?

    var onIncomingCard: ((CardExchangeIncomingDelivery) -> Void)?
    var onOutgoingCardSent: ((CardExchangeTransferMode) -> Void)?
    var onTargetLocked: ((CardExchangeTarget) -> Void)?
    var onOutgoingPersisted: ((String, CardExchangeTransferMode) -> Void)?

    private let transport = MultipeerExchangeTransport()
    private let targetSelector = CardExchangeTargetSelector()
    private let logger = Logger(subsystem: "com.Alex.Carda", category: "CardExchange")
    private let diagnostics = CardExchangeDiagnostics.shared
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var peerStates: [MCPeerID: PeerState] = [:]
    private var localPayload: CardExchangePayload?
    private var localIntent: LocalThrowIntent?
    private var outgoingTransactions: [UUID: OutgoingTransaction] = [:]
    private var incomingTransactions: [UUID: MCPeerID] = [:]
    private var lastGestureSentAtByPeer: [MCPeerID: Date] = [:]
    private var isRunning = false
    private var isSwipePrimed = false
    private var discoveryTimeoutTask: Task<Void, Never>?
    private var intentResolutionTask: Task<Void, Never>?
    private var idleCleanupTask: Task<Void, Never>?
    private var outgoingTimeoutTasks: [UUID: Task<Void, Never>] = [:]
    private var lastDiagnosticSelectionSignature: String?

    #if DEBUG && targetEnvironment(simulator)
    private var simulatedExchangeIDs: Set<UUID> = []
    #endif

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
            self?.failCurrentAttempt(message)
        }
    }

    func start(with card: CardRenderData) {
        localPayload = CardExchangePayload(data: card)
        guard !isRunning else {
            diagnostics.record(
                stage: .lifecycle,
                name: "exchange_card_updated_while_running"
            )
            return
        }

        isRunning = true
        transport.startReceiving()
        phase = NearbyExchangeRangingSession.isSupported ? .listening : .unavailable
        diagnostics.record(
            stage: .lifecycle,
            name: "exchange_coordinator_started",
            level: NearbyExchangeRangingSession.isSupported ? .info : .error,
            details: [
                "preciseDistance": String(
                    NearbyExchangeRangingSession.supportsPreciseDistanceMeasurement
                ),
                "direction": String(
                    NearbyExchangeRangingSession.supportsDirectionMeasurement
                ),
                "localPeerHash": CardExchangeDiagnostics.anonymousIdentifier(
                    transport.localPeerIdentifier
                )
            ]
        )
        logger.info(
            "Swipe card exchange passive receiver started preciseDistance=\(NearbyExchangeRangingSession.supportsPreciseDistanceMeasurement, privacy: .public) direction=\(NearbyExchangeRangingSession.supportsDirectionMeasurement, privacy: .public)"
        )
    }

    func updateLocalCard(_ card: CardRenderData) {
        localPayload = CardExchangePayload(data: card)
    }

    func stop() {
        guard isRunning else { return }
        diagnostics.record(stage: .lifecycle, name: "exchange_coordinator_stopping")
        isRunning = false
        cancelTasks()
        transport.stop()
        invalidateRangingSessions()
        peerStates.removeAll()
        localPayload = nil
        localIntent = nil
        outgoingTransactions.removeAll()
        cancelOutgoingTimeouts()
        incomingTransactions.removeAll()
        lastGestureSentAtByPeer.removeAll()
        currentTarget = nil
        isSwipePrimed = false
        lastDiagnosticSelectionSignature = nil
        phase = .listening
        diagnostics.record(stage: .lifecycle, name: "exchange_coordinator_stopped")
        logger.info("Swipe card exchange stopped")
    }

    @discardableResult
    func beginThrowGesture() -> Bool {
        guard isRunning, localPayload != nil else {
            diagnostics.record(
                stage: .gesture,
                name: "gesture_begin_rejected_inactive",
                level: .warning,
                details: [
                    "isRunning": String(isRunning),
                    "hasLocalCard": String(localPayload != nil)
                ]
            )
            return false
        }
        guard NearbyExchangeRangingSession.isSupported else {
            phase = .unavailable
            statusMessage = "当前设备不支持近距离测距"
            diagnostics.record(
                stage: .gesture,
                name: "gesture_begin_rejected_ranging_unsupported",
                level: .error
            )
            return false
        }
        guard localIntent == nil, outgoingTransactions.isEmpty else {
            statusMessage = "正在完成上一张名片"
            diagnostics.record(
                stage: .gesture,
                name: "gesture_begin_rejected_busy",
                level: .warning,
                details: [
                    "hasLocalIntent": String(localIntent != nil),
                    "outgoingCount": String(outgoingTransactions.count)
                ]
            )
            return false
        }

        diagnostics.record(stage: .gesture, name: "gesture_primed")
        isSwipePrimed = true
        currentTarget = nil
        phase = .discovering
        statusMessage = "正在寻找附近可接收的人"
        transport.startActiveDiscovery()
        scheduleDiscoveryTimeout()
        evaluateTargetSelection()
        return true
    }

    func commitThrowGesture() {
        guard
            isRunning,
            isSwipePrimed,
            localIntent == nil,
            let localPayload
        else {
            diagnostics.record(
                stage: .gesture,
                name: "gesture_commit_ignored",
                level: .warning,
                details: [
                    "isRunning": String(isRunning),
                    "isPrimed": String(isSwipePrimed),
                    "hasIntent": String(localIntent != nil),
                    "hasLocalCard": String(localPayload != nil)
                ]
            )
            return
        }

        let exchangeID = UUID()
        localIntent = LocalThrowIntent(
            exchangeID: exchangeID,
            cardID: localPayload.sourceCardID,
            createdAt: Date(),
            targetPeerID: nil
        )
        diagnostics.record(
            stage: .gesture,
            name: "gesture_committed",
            exchangeID: exchangeID,
            details: ["targetAlreadyLocked": String(currentTarget != nil)]
        )
        statusMessage = "正在确认递卡对象"
        evaluateTargetSelection()
    }

    func cancelThrowGesture() {
        guard localIntent == nil else {
            diagnostics.record(
                stage: .gesture,
                name: "gesture_cancel_ignored_after_commit",
                level: .warning,
                exchangeID: localIntent?.exchangeID
            )
            return
        }
        diagnostics.record(stage: .gesture, name: "gesture_cancelled")
        isSwipePrimed = false
        currentTarget = nil
        phase = NearbyExchangeRangingSession.isSupported ? .listening : .unavailable
        statusMessage = nil
        transport.stopActiveDiscovery()
        scheduleCleanupIfIdle()
    }

    @discardableResult
    func confirmIncomingPersisted(
        _ delivery: CardExchangeIncomingDelivery,
        returnCard: CardRenderData?
    ) -> Bool {
        guard incomingTransactions[delivery.exchangeID] == delivery.peerID else {
            diagnostics.record(
                stage: .persistence,
                name: "incoming_persistence_confirmation_rejected",
                level: .warning,
                exchangeID: delivery.exchangeID,
                peerIdentifier: delivery.peerID.displayName
            )
            return false
        }

        incomingTransactions.removeValue(forKey: delivery.exchangeID)
        var state = peerStates[delivery.peerID] ?? PeerState()
        state.pendingIncomingExchangeIDs.remove(delivery.exchangeID)
        state.persistedIncomingExchangeIDs.insert(delivery.exchangeID)
        peerStates[delivery.peerID] = state

        let didSendAcknowledgement = send(
            .persistedAck(exchangeID: delivery.exchangeID),
            to: delivery.peerID
        )
        diagnostics.record(
            stage: .persistence,
            name: didSendAcknowledgement
                ? "incoming_card_persisted_ack_sent"
                : "incoming_card_persisted_ack_send_failed",
            level: didSendAcknowledgement ? .info : .error,
            exchangeID: delivery.exchangeID,
            peerIdentifier: delivery.peerID.displayName,
            details: [
                "willReturnCard": String(returnCard != nil),
                "sendSucceeded": String(didSendAcknowledgement)
            ]
        )
        statusMessage = "已接收\(delivery.payload.displayName)的名片"
        logger.info("Persistence ACK sent exchange=\(delivery.exchangeID.uuidString, privacy: .public)")

        var wasSimulated = false
        #if DEBUG && targetEnvironment(simulator)
        if simulatedExchangeIDs.contains(delivery.exchangeID) {
            wasSimulated = true
            simulatedExchangeIDs.remove(delivery.exchangeID)
            handlePersistedAck(exchangeID: delivery.exchangeID, from: delivery.peerID)
        }
        #endif

        if let returnCard {
            #if DEBUG && targetEnvironment(simulator)
            if wasSimulated {
                _ = returnCard
                statusMessage = "模拟回递已送达"
                notifyOutgoingCardSent(mode: .returnDelivery)
                scheduleCleanupIfIdle()
                return true
            }
            #endif
            return sendReturnCard(returnCard, to: delivery.peerID)
        } else {
            scheduleCleanupIfIdle()
            return true
        }
    }

    func rejectIncoming(_ delivery: CardExchangeIncomingDelivery) {
        diagnostics.record(
            stage: .persistence,
            name: "incoming_card_rejected_by_user",
            level: .warning,
            exchangeID: delivery.exchangeID,
            peerIdentifier: delivery.peerID.displayName
        )
        incomingTransactions.removeValue(forKey: delivery.exchangeID)
        var state = peerStates[delivery.peerID] ?? PeerState()
        state.pendingIncomingExchangeIDs.remove(delivery.exchangeID)
        peerStates[delivery.peerID] = state
        send(.rejected(exchangeID: delivery.exchangeID), to: delivery.peerID)
        statusMessage = "已拒绝名片"
        scheduleCleanupIfIdle()
    }

    func reportIncomingPersistenceFailure(_ delivery: CardExchangeIncomingDelivery) {
        diagnostics.record(
            stage: .persistence,
            name: "incoming_card_persistence_failed",
            level: .error,
            exchangeID: delivery.exchangeID,
            peerIdentifier: delivery.peerID.displayName
        )
        incomingTransactions.removeValue(forKey: delivery.exchangeID)
        var state = peerStates[delivery.peerID] ?? PeerState()
        state.pendingIncomingExchangeIDs.remove(delivery.exchangeID)
        peerStates[delivery.peerID] = state
        send(
            .rejected(exchangeID: delivery.exchangeID, reason: "接收方保存失败"),
            to: delivery.peerID
        )
        phase = .failed("交换名片保存失败")
        statusMessage = "交换名片保存失败"
        scheduleCleanupIfIdle()
    }

    private func handlePeerConnected(_ peerID: MCPeerID) {
        guard isRunning else { return }
        diagnostics.record(
            stage: .connection,
            name: "coordinator_peer_connected",
            peerIdentifier: peerID.displayName
        )
        logger.info("Peer connected: \(peerID.displayName, privacy: .public)")

        var state = peerStates[peerID] ?? PeerState()
        if state.rangingSession == nil, NearbyExchangeRangingSession.isSupported {
            state.rangingSession = makeRangingSession(for: peerID)
        }
        peerStates[peerID] = state

        guard send(.hello(displayName: localPayload?.displayName ?? "Cardi 用户"), to: peerID) else {
            return
        }

        guard let rangingSession = state.rangingSession else {
            diagnostics.record(
                stage: .ranging,
                name: "ranging_session_missing_after_connect",
                level: .error,
                peerIdentifier: peerID.displayName
            )
            send(.error("当前设备不支持近距离测距"), to: peerID)
            return
        }
        guard let tokenData = rangingSession.localDiscoveryTokenData() else {
            diagnostics.record(
                stage: .token,
                name: "token_send_aborted_no_local_token",
                level: .error,
                peerIdentifier: peerID.displayName
            )
            send(.error("附近识别令牌创建失败"), to: peerID)
            return
        }

        guard send(.nearbyToken(tokenData), to: peerID) else { return }
        schedulePassivePeerTimeout()
    }

    private func handlePeerDisconnected(_ peerID: MCPeerID) {
        diagnostics.record(
            stage: .connection,
            name: "coordinator_peer_disconnected",
            level: .warning,
            peerIdentifier: peerID.displayName,
            details: [
                "wasCurrentTarget": String(currentTarget?.peerID == peerID),
                "wasIntentTarget": String(localIntent?.targetPeerID == peerID)
            ]
        )
        logger.info("Peer disconnected: \(peerID.displayName, privacy: .public)")
        peerStates[peerID]?.rangingSession?.invalidate()
        peerStates.removeValue(forKey: peerID)

        if currentTarget?.peerID == peerID {
            currentTarget = nil
        }

        if localIntent?.targetPeerID == peerID {
            localIntent = nil
            isSwipePrimed = false
            intentResolutionTask?.cancel()
            phase = .failed("递卡对象已离开")
            statusMessage = "递卡对象已离开"
        }

        let interrupted = outgoingTransactions.filter { $0.value.peerID == peerID }.map(\.key)
        for exchangeID in interrupted {
            outgoingTransactions.removeValue(forKey: exchangeID)
            cancelOutgoingTimeout(for: exchangeID)
        }
        if !interrupted.isEmpty {
            phase = .failed("名片投递连接已中断")
            statusMessage = "名片投递连接已中断"
        }
        scheduleCleanupIfIdle()
    }

    private func handleData(_ data: Data, from peerID: MCPeerID) {
        guard isRunning else {
            diagnostics.record(
                stage: .transfer,
                name: "message_ignored_coordinator_inactive",
                level: .warning,
                peerIdentifier: peerID.displayName,
                details: ["bytes": String(data.count)]
            )
            return
        }
        guard data.count <= Constants.maximumMessageBytes else {
            diagnostics.record(
                stage: .transfer,
                name: "message_rejected_too_large",
                level: .error,
                peerIdentifier: peerID.displayName,
                details: [
                    "bytes": String(data.count),
                    "maximumBytes": String(Constants.maximumMessageBytes)
                ]
            )
            return
        }
        guard let message = try? decoder.decode(CardExchangeMessage.self, from: data) else {
            diagnostics.record(
                stage: .transfer,
                name: "message_decode_failed",
                level: .error,
                peerIdentifier: peerID.displayName,
                details: ["bytes": String(data.count)]
            )
            send(.error("交换消息无法解析"), to: peerID)
            return
        }
        guard message.protocolVersion == 2 else {
            diagnostics.record(
                stage: .transfer,
                name: "message_protocol_rejected",
                level: .error,
                exchangeID: message.exchangeID,
                peerIdentifier: peerID.displayName,
                details: ["protocolVersion": String(message.protocolVersion)]
            )
            send(.error("交换协议版本不兼容"), to: peerID)
            return
        }

        diagnostics.record(
            stage: diagnosticStage(for: message.kind),
            name: "message_received_\(message.kind.rawValue)",
            exchangeID: message.exchangeID,
            peerIdentifier: peerID.displayName,
            details: ["bytes": String(data.count)]
        )

        switch message.kind {
        case .hello:
            handleHello(message.message, from: peerID)
        case .nearbyToken:
            guard let tokenData = message.nearbyTokenData else {
                diagnostics.record(
                    stage: .token,
                    name: "token_message_missing_payload",
                    level: .error,
                    peerIdentifier: peerID.displayName
                )
                return
            }
            handleNearbyToken(tokenData, from: peerID)
        case .throwIntent:
            guard
                let exchangeID = message.exchangeID,
                let cardID = message.cardID,
                let createdAt = message.intentCreatedAt
            else {
                diagnostics.record(
                    stage: .intent,
                    name: "throw_intent_missing_fields",
                    level: .error,
                    exchangeID: message.exchangeID,
                    peerIdentifier: peerID.displayName
                )
                return
            }
            handleRemoteIntent(
                RemoteThrowIntent(
                    exchangeID: exchangeID,
                    cardID: cardID,
                    createdAt: createdAt
                ),
                from: peerID
            )
        case .card:
            guard
                let exchangeID = message.exchangeID,
                let payload = message.card,
                let mode = message.transferMode,
                payload.isValidForExchange
            else {
                diagnostics.record(
                    stage: .transfer,
                    name: "card_payload_validation_failed",
                    level: .error,
                    exchangeID: message.exchangeID,
                    peerIdentifier: peerID.displayName
                )
                send(.error("名片数据校验失败"), to: peerID)
                return
            }
            handleReceivedCard(payload, exchangeID: exchangeID, mode: mode, from: peerID)
        case .persistedAck:
            guard let exchangeID = message.exchangeID else { return }
            handlePersistedAck(exchangeID: exchangeID, from: peerID)
        case .rejected:
            guard let exchangeID = message.exchangeID else { return }
            handleRejected(exchangeID: exchangeID, reason: message.message, from: peerID)
        case .error:
            failCurrentAttempt(message.message ?? "名片交换失败")
        }
    }

    private func handleHello(_ displayName: String?, from peerID: MCPeerID) {
        let normalized = displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized, !normalized.isEmpty else {
            diagnostics.record(
                stage: .connection,
                name: "hello_missing_display_name",
                level: .warning,
                peerIdentifier: peerID.displayName
            )
            return
        }

        diagnostics.record(
            stage: .connection,
            name: "hello_processed",
            peerIdentifier: peerID.displayName,
            details: ["hasDisplayName": "true"]
        )

        var state = peerStates[peerID] ?? PeerState()
        state.displayName = normalized
        peerStates[peerID] = state

        if let target = currentTarget, target.peerID == peerID {
            currentTarget = CardExchangeTarget(
                peerID: peerID,
                displayName: normalized,
                distance: target.distance
            )
        }
    }

    private func handleNearbyToken(_ tokenData: Data, from peerID: MCPeerID) {
        guard NearbyExchangeRangingSession.isSupported else {
            diagnostics.record(
                stage: .token,
                name: "remote_token_rejected_local_ranging_unsupported",
                level: .error,
                peerIdentifier: peerID.displayName
            )
            send(.error("当前设备不支持近距离测距"), to: peerID)
            return
        }
        var state = peerStates[peerID] ?? PeerState()
        let rangingSession = state.rangingSession ?? makeRangingSession(for: peerID)
        state.rangingSession = rangingSession
        peerStates[peerID] = state
        rangingSession.run(withPeerTokenData: tokenData)
    }

    private func makeRangingSession(for peerID: MCPeerID) -> NearbyExchangeRangingSession {
        diagnostics.record(
            stage: .ranging,
            name: "ranging_session_created",
            peerIdentifier: peerID.displayName
        )
        let rangingSession = NearbyExchangeRangingSession(peerID: peerID)
        rangingSession.onUpdate = { [weak self] peerID, distance, direction in
            self?.handleNearbyUpdate(peerID: peerID, distance: distance, direction: direction)
        }
        rangingSession.onRemoved = { [weak self] peerID in
            self?.resetRangingState(for: peerID)
        }
        rangingSession.onInvalidated = { [weak self] peerID in
            self?.handleRangingInvalidated(for: peerID)
        }
        rangingSession.onFailure = { [weak self] peerID, message in
            self?.resetRangingState(for: peerID)
            self?.failCurrentAttempt(message)
        }
        return rangingSession
    }

    private func handleNearbyUpdate(
        peerID: MCPeerID,
        distance: Float?,
        direction: SIMD3<Float>?
    ) {
        guard isRunning else { return }
        var state = peerStates[peerID] ?? PeerState()
        let now = Date()

        if let distance, distance.isFinite {
            state.distanceSamples.append(distance)
            if state.distanceSamples.count > Constants.distanceSampleCount {
                state.distanceSamples.removeFirst(
                    state.distanceSamples.count - Constants.distanceSampleCount
                )
            }
            state.lastDistanceUpdatedAt = now
        } else {
            state.distanceSamples.removeAll()
            state.lastDistanceUpdatedAt = nil
        }
        state.lastDirection = direction

        let isDirectionQualified: Bool
        if NearbyExchangeRangingSession.supportsDirectionMeasurement {
            isDirectionQualified = direction.map(targetSelector.isDirectionForward) ?? false
        } else {
            isDirectionQualified = true
        }

        if
            let medianDistance = state.medianDistance,
            medianDistance <= Constants.maximumDistance,
            isDirectionQualified
        {
            if state.qualifiedSince == nil {
                state.qualifiedSince = now
            }
        } else {
            state.qualifiedSince = nil
        }
        peerStates[peerID] = state

        logger.debug(
            "NI peer=\(peerID.displayName, privacy: .public) distance=\(distance ?? -1, format: .fixed(precision: 3)) direction=\(String(describing: direction), privacy: .public)"
        )
        if isSwipePrimed || localIntent != nil {
            evaluateTargetSelection()
        }
    }

    private func handleRangingInvalidated(for peerID: MCPeerID) {
        guard isRunning, let rangingSession = peerStates[peerID]?.rangingSession else { return }
        diagnostics.record(
            stage: .ranging,
            name: "ranging_recovery_started",
            level: .warning,
            peerIdentifier: peerID.displayName
        )
        resetRangingState(for: peerID)
        guard let tokenData = rangingSession.localDiscoveryTokenData() else {
            diagnostics.record(
                stage: .token,
                name: "ranging_recovery_token_failed",
                level: .error,
                peerIdentifier: peerID.displayName
            )
            return
        }
        send(.nearbyToken(tokenData), to: peerID)
    }

    private func resetRangingState(for peerID: MCPeerID) {
        guard var state = peerStates[peerID] else { return }
        diagnostics.record(
            stage: .ranging,
            name: "ranging_state_reset",
            peerIdentifier: peerID.displayName
        )
        state.distanceSamples.removeAll()
        state.lastDirection = nil
        state.lastDistanceUpdatedAt = nil
        state.qualifiedSince = nil
        peerStates[peerID] = state
        if currentTarget?.peerID == peerID, localIntent?.targetPeerID == nil {
            currentTarget = nil
        }
    }

    private func evaluateTargetSelection() {
        guard isRunning, isSwipePrimed || localIntent != nil else { return }
        if localIntent?.targetPeerID != nil {
            tryResolveMutualIntent()
            return
        }

        let now = Date()
        let candidates: [CardExchangeTargetCandidate] = peerStates.compactMap { peerID, state in
            guard
                let distance = state.medianDistance,
                let qualifiedSince = state.qualifiedSince,
                let updatedAt = state.lastDistanceUpdatedAt
            else {
                return nil
            }
            return CardExchangeTargetCandidate(
                peerID: peerID,
                displayName: state.displayName ?? "对方",
                distance: distance,
                direction: state.lastDirection,
                qualifiedSince: qualifiedSince,
                updatedAt: updatedAt
            )
        }

        let selectionMode: CardExchangeTargetSelectionMode =
            NearbyExchangeRangingSession.supportsDirectionMeasurement
                ? .directionAndDistance
                : .distanceOnly

        switch targetSelector.select(from: candidates, now: now, mode: selectionMode) {
        case .none:
            recordTargetSelectionIfChanged(
                signature: "none-\(selectionMode)-\(candidates.count)",
                name: "target_none",
                candidates: candidates,
                selectionMode: selectionMode
            )
            currentTarget = nil
            if NearbyExchangeRangingSession.supportsDirectionMeasurement,
               hasNearbyPeerWithoutClearDirection {
                phase = .confirmingDirection
                statusMessage = "轻轻将手机朝向对方"
            } else {
                phase = .discovering
                statusMessage = NearbyExchangeRangingSession.supportsDirectionMeasurement
                    ? "正在寻找附近可接收的人"
                    : "正在确认最近的接收者"
            }
        case .ambiguous:
            recordTargetSelectionIfChanged(
                signature: "ambiguous-\(selectionMode)-\(candidates.count)",
                name: "target_ambiguous",
                candidates: candidates,
                selectionMode: selectionMode,
                level: .warning
            )
            currentTarget = nil
            phase = .ambiguous
            statusMessage = NearbyExchangeRangingSession.supportsDirectionMeasurement
                ? "目标不明确，请将手机朝向对方"
                : "附近目标过多，请靠近接收者"
        case .locked(let target):
            recordTargetSelectionIfChanged(
                signature: "locked-\(target.peerID.displayName)-\(selectionMode)",
                name: "target_locked",
                candidates: candidates,
                selectionMode: selectionMode,
                selectedTarget: target
            )
            let isNewTarget = currentTarget?.peerID != target.peerID
            currentTarget = target
            phase = .targetLocked(target.summary)
            statusMessage = NearbyExchangeRangingSession.supportsDirectionMeasurement
                ? "已对准\(target.displayName)"
                : "已确认最近的\(target.displayName)"
            if isNewTarget {
                onTargetLocked?(target)
            }
            if localIntent != nil {
                bindLocalIntent(to: target)
            }
        }
    }

    private var hasNearbyPeerWithoutClearDirection: Bool {
        peerStates.values.contains { state in
            guard let distance = state.medianDistance else { return false }
            return distance <= Constants.maximumDistance
                && (state.lastDirection == nil
                    || !targetSelector.isDirectionForward(state.lastDirection!))
        }
    }

    private func recordTargetSelectionIfChanged(
        signature: String,
        name: String,
        candidates: [CardExchangeTargetCandidate],
        selectionMode: CardExchangeTargetSelectionMode,
        selectedTarget: CardExchangeTarget? = nil,
        level: CardExchangeDiagnosticLevel = .info
    ) {
        guard signature != lastDiagnosticSelectionSignature else { return }
        lastDiagnosticSelectionSignature = signature
        let candidateSummary = candidates
            .sorted { $0.distance < $1.distance }
            .map { candidate in
                let hash = CardExchangeDiagnostics.anonymousIdentifier(
                    candidate.peerID.displayName
                )
                return "\(hash):\(String(format: "%.3f", candidate.distance)):\(candidate.direction != nil)"
            }
            .joined(separator: ",")
        var details = [
            "mode": diagnosticDescription(for: selectionMode),
            "candidateCount": String(candidates.count),
            "candidatesHashDistanceDirection": candidateSummary
        ]
        if let selectedTarget {
            details["selectedDistanceMeters"] = String(
                format: "%.3f",
                selectedTarget.distance
            )
        }
        diagnostics.record(
            stage: .targetSelection,
            name: name,
            level: level,
            peerIdentifier: selectedTarget?.peerID.displayName,
            details: details
        )
    }

    private func diagnosticDescription(
        for mode: CardExchangeTargetSelectionMode
    ) -> String {
        switch mode {
        case .directionAndDistance:
            "direction_and_distance"
        case .distanceOnly:
            "distance_only"
        }
    }

    private func bindLocalIntent(to target: CardExchangeTarget) {
        guard var intent = localIntent, intent.targetPeerID == nil else { return }
        if
            let lastSentAt = lastGestureSentAtByPeer[target.peerID],
            Date().timeIntervalSince(lastSentAt) < Constants.repeatedGestureCooldown
        {
            diagnostics.record(
                stage: .intent,
                name: "intent_rejected_cooldown",
                level: .warning,
                exchangeID: intent.exchangeID,
                peerIdentifier: target.peerID.displayName
            )
            localIntent = nil
            isSwipePrimed = false
            phase = .failed("请稍后再向同一用户递卡")
            statusMessage = "请稍后再向同一用户递卡"
            scheduleCleanupIfIdle()
            return
        }

        intent.targetPeerID = target.peerID
        localIntent = intent
        diagnostics.record(
            stage: .intent,
            name: "local_intent_bound_to_target",
            exchangeID: intent.exchangeID,
            peerIdentifier: target.peerID.displayName,
            details: ["distanceMeters": String(format: "%.3f", target.distance)]
        )
        guard send(
            .throwIntent(
                exchangeID: intent.exchangeID,
                cardID: intent.cardID,
                createdAt: intent.createdAt
            ),
            to: target.peerID
        ) else {
            failCurrentAttempt("递卡意图发送失败")
            return
        }
        phase = .resolvingIntent(target.summary)
        statusMessage = "正在确认是否互换"
        scheduleIntentResolution(for: intent, target: target)
        tryResolveMutualIntent()
    }

    private func handleRemoteIntent(_ intent: RemoteThrowIntent, from peerID: MCPeerID) {
        diagnostics.record(
            stage: .intent,
            name: "remote_intent_received",
            exchangeID: intent.exchangeID,
            peerIdentifier: peerID.displayName
        )
        idleCleanupTask?.cancel()
        var state = peerStates[peerID] ?? PeerState()
        state.remoteIntent = intent
        peerStates[peerID] = state
        if localIntent == nil {
            statusMessage = "对方正在递名片"
        }
        tryResolveMutualIntent()
    }

    private func tryResolveMutualIntent() {
        guard
            let localIntent,
            let targetPeerID = localIntent.targetPeerID,
            let remoteIntent = peerStates[targetPeerID]?.remoteIntent,
            abs(remoteIntent.createdAt.timeIntervalSince(localIntent.createdAt))
                <= Constants.mutualIntentWindow
        else {
            return
        }

        diagnostics.record(
            stage: .intent,
            name: "mutual_intent_matched",
            exchangeID: localIntent.exchangeID,
            peerIdentifier: targetPeerID.displayName,
            details: [
                "remoteExchangeID": remoteIntent.exchangeID.uuidString,
                "timeDeltaMilliseconds": String(
                    Int(
                        abs(remoteIntent.createdAt.timeIntervalSince(localIntent.createdAt))
                            * 1_000
                    )
                )
            ]
        )
        intentResolutionTask?.cancel()
        sendLocalCard(for: localIntent, to: targetPeerID, mode: .mutual)
    }

    private func scheduleIntentResolution(
        for intent: LocalThrowIntent,
        target: CardExchangeTarget
    ) {
        intentResolutionTask?.cancel()
        let intentWindowRemaining = max(
            0,
            intent.createdAt.addingTimeInterval(Constants.mutualIntentWindow).timeIntervalSinceNow
        )
        let delay = max(Constants.minimumIntentNetworkGrace, intentWindowRemaining)
        diagnostics.record(
            stage: .intent,
            name: "single_delivery_resolution_scheduled",
            exchangeID: intent.exchangeID,
            peerIdentifier: target.peerID.displayName,
            details: ["delayMilliseconds": String(Int(delay * 1_000))]
        )

        intentResolutionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            guard
                let currentIntent = self.localIntent,
                currentIntent.exchangeID == intent.exchangeID,
                currentIntent.targetPeerID == target.peerID
            else {
                return
            }
            self.sendLocalCard(for: currentIntent, to: target.peerID, mode: .delivery)
        }
    }

    private func sendLocalCard(
        for intent: LocalThrowIntent,
        to peerID: MCPeerID,
        mode: CardExchangeTransferMode
    ) {
        guard let payload = localPayload, localIntent?.exchangeID == intent.exchangeID else { return }
        let displayName = peerStates[peerID]?.displayName ?? "对方"
        let target = CardExchangeTarget(
            peerID: peerID,
            displayName: displayName,
            distance: currentTarget?.distance ?? Constants.maximumDistance
        )

        intentResolutionTask?.cancel()
        discoveryTimeoutTask?.cancel()
        localIntent = nil
        isSwipePrimed = false
        lastGestureSentAtByPeer[peerID] = Date()
        outgoingTransactions[intent.exchangeID] = OutgoingTransaction(
            peerID: peerID,
            peerDisplayName: displayName,
            mode: mode
        )
        phase = .sending(target.summary, mode)
        statusMessage = mode.isMutual ? "正在交换名片" : "正在递给\(displayName)"
        diagnostics.record(
            stage: .transfer,
            name: "card_send_started",
            exchangeID: intent.exchangeID,
            peerIdentifier: peerID.displayName,
            details: ["mode": mode.rawValue]
        )
        guard send(.card(payload, exchangeID: intent.exchangeID, mode: mode), to: peerID) else {
            failCurrentAttempt("名片发送失败")
            return
        }
        scheduleOutgoingTimeout(for: intent.exchangeID)
        notifyOutgoingCardSent(mode: mode)
        phase = .waitingForPersistence(target.summary, mode)
        diagnostics.record(
            stage: .persistence,
            name: "waiting_for_persistence_ack",
            exchangeID: intent.exchangeID,
            peerIdentifier: peerID.displayName,
            details: [
                "mode": mode.rawValue,
                "timeoutSeconds": String(Constants.outgoingPersistenceTimeout)
            ]
        )
        statusMessage = mode.isMutual ? "等待双方保存" : "等待对方接住"
        transport.stopActiveDiscovery()
    }

    private func handleReceivedCard(
        _ payload: CardExchangePayload,
        exchangeID: UUID,
        mode: CardExchangeTransferMode,
        from peerID: MCPeerID
    ) {
        idleCleanupTask?.cancel()
        var state = peerStates[peerID] ?? PeerState()
        if state.persistedIncomingExchangeIDs.contains(exchangeID) {
            diagnostics.record(
                stage: .persistence,
                name: "duplicate_card_reacknowledged",
                level: .warning,
                exchangeID: exchangeID,
                peerIdentifier: peerID.displayName
            )
            send(.persistedAck(exchangeID: exchangeID), to: peerID)
            return
        }
        guard !state.pendingIncomingExchangeIDs.contains(exchangeID) else {
            diagnostics.record(
                stage: .transfer,
                name: "duplicate_pending_card_ignored",
                level: .warning,
                exchangeID: exchangeID,
                peerIdentifier: peerID.displayName
            )
            return
        }

        state.pendingIncomingExchangeIDs.insert(exchangeID)
        state.displayName = payload.displayName
        peerStates[peerID] = state
        incomingTransactions[exchangeID] = peerID
        let delivery = CardExchangeIncomingDelivery(
            exchangeID: exchangeID,
            peerID: peerID,
            payload: payload,
            mode: mode
        )
        diagnostics.record(
            stage: .transfer,
            name: "validated_card_delivered_to_ui",
            exchangeID: exchangeID,
            peerIdentifier: peerID.displayName,
            details: ["mode": mode.rawValue]
        )
        statusMessage = "收到\(payload.displayName)的名片"
        onIncomingCard?(delivery)
        logger.info("Received validated card exchange=\(exchangeID.uuidString, privacy: .public)")
    }

    private func handlePersistedAck(exchangeID: UUID, from peerID: MCPeerID) {
        guard let transaction = outgoingTransactions[exchangeID], transaction.peerID == peerID else {
            diagnostics.record(
                stage: .persistence,
                name: "unexpected_persistence_ack_ignored",
                level: .warning,
                exchangeID: exchangeID,
                peerIdentifier: peerID.displayName
            )
            return
        }
        outgoingTransactions.removeValue(forKey: exchangeID)
        cancelOutgoingTimeout(for: exchangeID)
        let displayName = transaction.peerDisplayName == "对方"
            ? "对方"
            : transaction.peerDisplayName
        statusMessage = "\(displayName)已接住"
        diagnostics.record(
            stage: .persistence,
            name: "persistence_ack_received",
            exchangeID: exchangeID,
            peerIdentifier: peerID.displayName,
            details: ["mode": transaction.mode.rawValue]
        )
        onOutgoingPersisted?(displayName, transaction.mode)
        logger.info("Persistence ACK received exchange=\(exchangeID.uuidString, privacy: .public)")
        scheduleCleanupIfIdle()
    }

    private func handleRejected(exchangeID: UUID, reason: String?, from peerID: MCPeerID) {
        guard let transaction = outgoingTransactions[exchangeID], transaction.peerID == peerID else {
            diagnostics.record(
                stage: .persistence,
                name: "unexpected_rejection_ignored",
                level: .warning,
                exchangeID: exchangeID,
                peerIdentifier: peerID.displayName
            )
            return
        }
        outgoingTransactions.removeValue(forKey: exchangeID)
        cancelOutgoingTimeout(for: exchangeID)
        let message = reason ?? "对方暂未接收"
        diagnostics.record(
            stage: .persistence,
            name: "card_rejected_by_remote",
            level: .warning,
            exchangeID: exchangeID,
            peerIdentifier: peerID.displayName,
            details: ["hasReason": String(reason != nil)]
        )
        phase = .failed(message)
        statusMessage = message
        scheduleCleanupIfIdle()
    }

    @discardableResult
    private func sendReturnCard(_ card: CardRenderData, to peerID: MCPeerID) -> Bool {
        guard transport.connectedPeers.contains(peerID) else {
            diagnostics.record(
                stage: .transfer,
                name: "return_card_rejected_disconnected",
                level: .error,
                peerIdentifier: peerID.displayName
            )
            phase = .failed("回递连接已断开")
            statusMessage = "回递连接已断开"
            scheduleCleanupIfIdle()
            return false
        }

        let exchangeID = UUID()
        diagnostics.record(
            stage: .transfer,
            name: "return_card_send_started",
            exchangeID: exchangeID,
            peerIdentifier: peerID.displayName
        )
        let displayName = peerStates[peerID]?.displayName ?? "对方"
        outgoingTransactions[exchangeID] = OutgoingTransaction(
            peerID: peerID,
            peerDisplayName: displayName,
            mode: .returnDelivery
        )
        guard send(
            .card(CardExchangePayload(data: card), exchangeID: exchangeID, mode: .returnDelivery),
            to: peerID
        ) else {
            failCurrentAttempt("回递名片发送失败")
            return false
        }
        scheduleOutgoingTimeout(for: exchangeID)
        statusMessage = "正在回递名片"
        notifyOutgoingCardSent(mode: .returnDelivery)
        return true
    }

    @discardableResult
    private func send(_ message: CardExchangeMessage, to peerID: MCPeerID) -> Bool {
        guard let data = try? encoder.encode(message) else {
            diagnostics.record(
                stage: diagnosticStage(for: message.kind),
                name: "message_encoding_failed_\(message.kind.rawValue)",
                level: .error,
                exchangeID: message.exchangeID,
                peerIdentifier: peerID.displayName
            )
            return false
        }
        diagnostics.record(
            stage: diagnosticStage(for: message.kind),
            name: "message_send_requested_\(message.kind.rawValue)",
            exchangeID: message.exchangeID,
            peerIdentifier: peerID.displayName,
            details: ["bytes": String(data.count)]
        )
        guard transport.send(data, to: peerID) else { return false }
        logger.debug(
            "Sent \(message.kind.rawValue, privacy: .public) to \(peerID.displayName, privacy: .public)"
        )
        return true
    }

    private func notifyOutgoingCardSent(mode: CardExchangeTransferMode) {
        outgoingCardAnimationID = UUID()
        diagnostics.record(
            stage: .animation,
            name: "outgoing_animation_requested",
            details: ["mode": mode.rawValue]
        )
        onOutgoingCardSent?(mode)
    }

    private func diagnosticStage(
        for kind: CardExchangeMessage.Kind
    ) -> CardExchangeDiagnosticStage {
        switch kind {
        case .hello:
            .connection
        case .nearbyToken:
            .token
        case .throwIntent:
            .intent
        case .card:
            .transfer
        case .persistedAck, .rejected:
            .persistence
        case .error:
            .failure
        }
    }

    private func scheduleDiscoveryTimeout() {
        discoveryTimeoutTask?.cancel()
        diagnostics.record(
            stage: .discovery,
            name: "discovery_timeout_scheduled",
            details: ["timeoutSeconds": String(Constants.activeDiscoveryWindow)]
        )
        discoveryTimeoutTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64(Constants.activeDiscoveryWindow * 1_000_000_000)
            )
            guard !Task.isCancelled, let self else { return }
            self.transport.stopActiveDiscovery()
            if self.localIntent != nil || self.isSwipePrimed {
                self.diagnostics.record(
                    stage: .discovery,
                    name: "discovery_timed_out_without_target",
                    level: .warning,
                    exchangeID: self.localIntent?.exchangeID,
                    details: [
                        "wasPrimed": String(self.isSwipePrimed),
                        "peerCount": String(self.peerStates.count)
                    ]
                )
                self.localIntent = nil
                self.isSwipePrimed = false
                self.currentTarget = nil
                self.phase = .noTarget
                self.statusMessage = "附近没有明确的可接收对象"
            }
            self.scheduleCleanupIfIdle()
        }
    }

    private func schedulePassivePeerTimeout() {
        idleCleanupTask?.cancel()
        idleCleanupTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64(Constants.activeDiscoveryWindow * 1_000_000_000)
            )
            guard !Task.isCancelled, let self else { return }
            self.performCleanupIfIdle()
        }
    }

    private func scheduleCleanupIfIdle() {
        guard localIntent == nil, outgoingTransactions.isEmpty, incomingTransactions.isEmpty else {
            return
        }
        idleCleanupTask?.cancel()
        idleCleanupTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64(Constants.idleCleanupDelay * 1_000_000_000)
            )
            guard !Task.isCancelled, let self else { return }
            self.performCleanupIfIdle()
        }
    }

    private func scheduleOutgoingTimeout(for exchangeID: UUID) {
        cancelOutgoingTimeout(for: exchangeID)
        diagnostics.record(
            stage: .persistence,
            name: "persistence_ack_timeout_scheduled",
            exchangeID: exchangeID,
            details: ["timeoutSeconds": String(Constants.outgoingPersistenceTimeout)]
        )
        outgoingTimeoutTasks[exchangeID] = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64(Constants.outgoingPersistenceTimeout * 1_000_000_000)
            )
            guard !Task.isCancelled, let self else { return }
            guard self.outgoingTransactions[exchangeID] != nil else { return }
            self.diagnostics.record(
                stage: .persistence,
                name: "persistence_ack_timed_out",
                level: .error,
                exchangeID: exchangeID
            )
            self.outgoingTimeoutTasks[exchangeID] = nil
            self.failCurrentAttempt("对方未确认接收，请重试")
        }
    }

    private func cancelOutgoingTimeout(for exchangeID: UUID) {
        outgoingTimeoutTasks.removeValue(forKey: exchangeID)?.cancel()
    }

    private func cancelOutgoingTimeouts() {
        outgoingTimeoutTasks.values.forEach { $0.cancel() }
        outgoingTimeoutTasks.removeAll()
    }

    private func failCurrentAttempt(_ message: String) {
        diagnostics.record(
            stage: .failure,
            name: "exchange_attempt_failed",
            level: .error,
            exchangeID: localIntent?.exchangeID,
            details: ["reasonCode": diagnosticReasonCode(for: message)]
        )
        discoveryTimeoutTask?.cancel()
        intentResolutionTask?.cancel()
        localIntent = nil
        isSwipePrimed = false
        currentTarget = nil
        outgoingTransactions.removeAll()
        cancelOutgoingTimeouts()
        transport.stopActiveDiscovery()
        phase = .failed(message)
        statusMessage = message
        logger.error("Card exchange attempt failed: \(message, privacy: .public)")
        scheduleCleanupIfIdle()
    }

    private func performCleanupIfIdle() {
        guard localIntent == nil, outgoingTransactions.isEmpty, incomingTransactions.isEmpty else {
            return
        }
        diagnostics.record(
            stage: .lifecycle,
            name: "idle_cleanup_started",
            details: ["peerCount": String(peerStates.count)]
        )
        discoveryTimeoutTask?.cancel()
        intentResolutionTask?.cancel()
        transport.stopActiveDiscovery()
        invalidateRangingSessions()
        peerStates.removeAll()
        transport.disconnectAllPeers()
        currentTarget = nil
        isSwipePrimed = false
        phase = NearbyExchangeRangingSession.isSupported ? .listening : .unavailable
        lastDiagnosticSelectionSignature = nil
        diagnostics.record(stage: .lifecycle, name: "idle_cleanup_completed")
    }

    private func invalidateRangingSessions() {
        for state in peerStates.values {
            state.rangingSession?.invalidate()
        }
    }

    private func cancelTasks() {
        discoveryTimeoutTask?.cancel()
        intentResolutionTask?.cancel()
        idleCleanupTask?.cancel()
        discoveryTimeoutTask = nil
        intentResolutionTask = nil
        idleCleanupTask = nil
        cancelOutgoingTimeouts()
    }

    private func diagnosticReasonCode(for message: String) -> String {
        switch message {
        case "名片交换连接已断开": "transport_disconnected"
        case "名片交换发送失败": "transport_send_failed"
        case "递卡意图发送失败": "intent_send_failed"
        case "名片发送失败": "card_send_failed"
        case "回递名片发送失败": "return_send_failed"
        case "对方未确认接收，请重试": "persistence_ack_timeout"
        case "附近发现广播启动失败": "advertising_failed"
        case "附近设备浏览启动失败": "browsing_failed"
        case "附近设备识别失败": "remote_token_failed"
        case "对方设备不支持近距离测距": "remote_ranging_unsupported"
        default: "other"
        }
    }

    #if DEBUG && targetEnvironment(simulator)
    func simulateProximityExchange(with card: CardRenderData) {
        let simulatedMode: CardExchangeTransferMode = ProcessInfo.processInfo.environment[
            "CARDA_SIMULATE_SINGLE_DELIVERY"
        ] == "1" ? .delivery : .mutual
        var payload = CardExchangePayload(data: card)
        payload.sourceCardID = UUID()
        payload.name = "模拟对方"
        payload.phoneticName = "Remote Card"
        payload.position = "来卡"
        payload.organizationName = "对方公司"

        let peerID = MCPeerID(displayName: "Cardi-SimulatorPeer")
        let exchangeID = UUID()
        var state = peerStates[peerID] ?? PeerState()
        state.displayName = "模拟对方"
        state.pendingIncomingExchangeIDs.insert(exchangeID)
        peerStates[peerID] = state
        incomingTransactions[exchangeID] = peerID
        if simulatedMode.isMutual {
            outgoingTransactions[exchangeID] = OutgoingTransaction(
                peerID: peerID,
                peerDisplayName: "模拟对方",
                mode: simulatedMode
            )
        }
        simulatedExchangeIDs.insert(exchangeID)
        if simulatedMode.isMutual {
            notifyOutgoingCardSent(mode: simulatedMode)
        }
        onIncomingCard?(
            CardExchangeIncomingDelivery(
                exchangeID: exchangeID,
                peerID: peerID,
                payload: payload,
                mode: simulatedMode
            )
        )
        statusMessage = simulatedMode.isMutual
            ? "模拟上滑交换已触发"
            : "模拟单向来卡已触发"
    }
    #endif
}
