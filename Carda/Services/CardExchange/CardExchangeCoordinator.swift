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
            self?.phase = .failed(message)
            self?.statusMessage = message
        }
    }

    func start(with card: CardRenderData) {
        localPayload = CardExchangePayload(data: card)
        guard !isRunning else { return }

        isRunning = true
        transport.startReceiving()
        phase = NearbyExchangeRangingSession.isSupported ? .listening : .unavailable
        logger.info("Swipe card exchange passive receiver started")
    }

    func updateLocalCard(_ card: CardRenderData) {
        localPayload = CardExchangePayload(data: card)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        cancelTasks()
        transport.stop()
        invalidateRangingSessions()
        peerStates.removeAll()
        localPayload = nil
        localIntent = nil
        outgoingTransactions.removeAll()
        incomingTransactions.removeAll()
        lastGestureSentAtByPeer.removeAll()
        currentTarget = nil
        isSwipePrimed = false
        phase = .listening
        logger.info("Swipe card exchange stopped")
    }

    @discardableResult
    func beginThrowGesture() -> Bool {
        guard isRunning, localPayload != nil else { return false }
        guard NearbyExchangeRangingSession.isSupported else {
            phase = .unavailable
            statusMessage = "当前设备不支持精准方向识别"
            return false
        }
        guard localIntent == nil, outgoingTransactions.isEmpty else {
            statusMessage = "正在完成上一张名片"
            return false
        }

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
            return
        }

        localIntent = LocalThrowIntent(
            exchangeID: UUID(),
            cardID: localPayload.sourceCardID,
            createdAt: Date(),
            targetPeerID: nil
        )
        statusMessage = "正在确认递卡对象"
        evaluateTargetSelection()
    }

    func cancelThrowGesture() {
        guard localIntent == nil else { return }
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
        guard incomingTransactions[delivery.exchangeID] == delivery.peerID else { return false }

        incomingTransactions.removeValue(forKey: delivery.exchangeID)
        var state = peerStates[delivery.peerID] ?? PeerState()
        state.pendingIncomingExchangeIDs.remove(delivery.exchangeID)
        state.persistedIncomingExchangeIDs.insert(delivery.exchangeID)
        peerStates[delivery.peerID] = state

        send(.persistedAck(exchangeID: delivery.exchangeID), to: delivery.peerID)
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
        incomingTransactions.removeValue(forKey: delivery.exchangeID)
        var state = peerStates[delivery.peerID] ?? PeerState()
        state.pendingIncomingExchangeIDs.remove(delivery.exchangeID)
        peerStates[delivery.peerID] = state
        send(.rejected(exchangeID: delivery.exchangeID), to: delivery.peerID)
        statusMessage = "已拒绝名片"
        scheduleCleanupIfIdle()
    }

    func reportIncomingPersistenceFailure(_ delivery: CardExchangeIncomingDelivery) {
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
        logger.info("Peer connected: \(peerID.displayName, privacy: .public)")

        var state = peerStates[peerID] ?? PeerState()
        if state.rangingSession == nil, NearbyExchangeRangingSession.isSupported {
            state.rangingSession = makeRangingSession(for: peerID)
        }
        peerStates[peerID] = state

        send(.hello(displayName: localPayload?.displayName ?? "Cardi 用户"), to: peerID)

        guard let rangingSession = state.rangingSession else {
            send(.error("当前设备不支持精准方向识别"), to: peerID)
            return
        }
        guard let tokenData = rangingSession.localDiscoveryTokenData() else {
            send(.error("附近识别令牌创建失败"), to: peerID)
            return
        }

        send(.nearbyToken(tokenData), to: peerID)
        schedulePassivePeerTimeout()
    }

    private func handlePeerDisconnected(_ peerID: MCPeerID) {
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
        }
        if !interrupted.isEmpty {
            phase = .failed("名片投递连接已中断")
            statusMessage = "名片投递连接已中断"
        }
    }

    private func handleData(_ data: Data, from peerID: MCPeerID) {
        guard isRunning, data.count <= Constants.maximumMessageBytes else { return }
        guard let message = try? decoder.decode(CardExchangeMessage.self, from: data) else {
            send(.error("交换消息无法解析"), to: peerID)
            return
        }
        guard message.protocolVersion == 2 else {
            send(.error("交换协议版本不兼容"), to: peerID)
            return
        }

        switch message.kind {
        case .hello:
            handleHello(message.message, from: peerID)
        case .nearbyToken:
            guard let tokenData = message.nearbyTokenData else { return }
            handleNearbyToken(tokenData, from: peerID)
        case .throwIntent:
            guard
                let exchangeID = message.exchangeID,
                let cardID = message.cardID,
                let createdAt = message.intentCreatedAt
            else {
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
            phase = .failed(message.message ?? "名片交换失败")
            statusMessage = message.message ?? "名片交换失败"
        }
    }

    private func handleHello(_ displayName: String?, from peerID: MCPeerID) {
        let normalized = displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized, !normalized.isEmpty else { return }

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
            self?.resetRangingState(for: peerID)
        }
        rangingSession.onInvalidated = { [weak self] peerID in
            self?.handleRangingInvalidated(for: peerID)
        }
        rangingSession.onFailure = { [weak self] peerID, message in
            self?.resetRangingState(for: peerID)
            self?.phase = .failed(message)
            self?.statusMessage = message
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

        if
            let medianDistance = state.medianDistance,
            let direction,
            medianDistance <= Constants.maximumDistance,
            targetSelector.isDirectionForward(direction)
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
        resetRangingState(for: peerID)
        guard let tokenData = rangingSession.localDiscoveryTokenData() else { return }
        send(.nearbyToken(tokenData), to: peerID)
    }

    private func resetRangingState(for peerID: MCPeerID) {
        guard var state = peerStates[peerID] else { return }
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
                let direction = state.lastDirection,
                let qualifiedSince = state.qualifiedSince,
                let updatedAt = state.lastDistanceUpdatedAt
            else {
                return nil
            }
            return CardExchangeTargetCandidate(
                peerID: peerID,
                displayName: state.displayName ?? "对方",
                distance: distance,
                direction: direction,
                qualifiedSince: qualifiedSince,
                updatedAt: updatedAt
            )
        }

        switch targetSelector.select(from: candidates, now: now) {
        case .none:
            currentTarget = nil
            if hasNearbyPeerWithoutClearDirection {
                phase = .confirmingDirection
                statusMessage = "轻轻将手机朝向对方"
            } else {
                phase = .discovering
                statusMessage = "正在寻找附近可接收的人"
            }
        case .ambiguous:
            currentTarget = nil
            phase = .ambiguous
            statusMessage = "目标不明确，请将手机朝向对方"
        case .locked(let target):
            let isNewTarget = currentTarget?.peerID != target.peerID
            currentTarget = target
            phase = .targetLocked(target.summary)
            statusMessage = "已对准\(target.displayName)"
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

    private func bindLocalIntent(to target: CardExchangeTarget) {
        guard var intent = localIntent, intent.targetPeerID == nil else { return }
        if
            let lastSentAt = lastGestureSentAtByPeer[target.peerID],
            Date().timeIntervalSince(lastSentAt) < Constants.repeatedGestureCooldown
        {
            localIntent = nil
            isSwipePrimed = false
            phase = .failed("请稍后再向同一用户递卡")
            statusMessage = "请稍后再向同一用户递卡"
            scheduleCleanupIfIdle()
            return
        }

        intent.targetPeerID = target.peerID
        localIntent = intent
        send(
            .throwIntent(
                exchangeID: intent.exchangeID,
                cardID: intent.cardID,
                createdAt: intent.createdAt
            ),
            to: target.peerID
        )
        phase = .resolvingIntent(target.summary)
        statusMessage = "正在确认是否互换"
        scheduleIntentResolution(for: intent, target: target)
        tryResolveMutualIntent()
    }

    private func handleRemoteIntent(_ intent: RemoteThrowIntent, from peerID: MCPeerID) {
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
        send(.card(payload, exchangeID: intent.exchangeID, mode: mode), to: peerID)
        notifyOutgoingCardSent(mode: mode)
        phase = .waitingForPersistence(target.summary, mode)
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
            send(.persistedAck(exchangeID: exchangeID), to: peerID)
            return
        }
        guard !state.pendingIncomingExchangeIDs.contains(exchangeID) else { return }

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
        statusMessage = "收到\(payload.displayName)的名片"
        onIncomingCard?(delivery)
        logger.info("Received validated card exchange=\(exchangeID.uuidString, privacy: .public)")
    }

    private func handlePersistedAck(exchangeID: UUID, from peerID: MCPeerID) {
        guard let transaction = outgoingTransactions[exchangeID], transaction.peerID == peerID else {
            return
        }
        outgoingTransactions.removeValue(forKey: exchangeID)
        let displayName = transaction.peerDisplayName == "对方"
            ? "对方"
            : transaction.peerDisplayName
        statusMessage = "\(displayName)已接住"
        onOutgoingPersisted?(displayName, transaction.mode)
        logger.info("Persistence ACK received exchange=\(exchangeID.uuidString, privacy: .public)")
        scheduleCleanupIfIdle()
    }

    private func handleRejected(exchangeID: UUID, reason: String?, from peerID: MCPeerID) {
        guard let transaction = outgoingTransactions[exchangeID], transaction.peerID == peerID else {
            return
        }
        outgoingTransactions.removeValue(forKey: exchangeID)
        let message = reason ?? "对方暂未接收"
        phase = .failed(message)
        statusMessage = message
        scheduleCleanupIfIdle()
    }

    @discardableResult
    private func sendReturnCard(_ card: CardRenderData, to peerID: MCPeerID) -> Bool {
        guard transport.connectedPeers.contains(peerID) else {
            phase = .failed("回递连接已断开")
            statusMessage = "回递连接已断开"
            scheduleCleanupIfIdle()
            return false
        }

        let exchangeID = UUID()
        let displayName = peerStates[peerID]?.displayName ?? "对方"
        outgoingTransactions[exchangeID] = OutgoingTransaction(
            peerID: peerID,
            peerDisplayName: displayName,
            mode: .returnDelivery
        )
        send(
            .card(CardExchangePayload(data: card), exchangeID: exchangeID, mode: .returnDelivery),
            to: peerID
        )
        statusMessage = "正在回递名片"
        notifyOutgoingCardSent(mode: .returnDelivery)
        return true
    }

    private func send(_ message: CardExchangeMessage, to peerID: MCPeerID) {
        guard let data = try? encoder.encode(message) else { return }
        transport.send(data, to: peerID)
        logger.debug(
            "Sent \(message.kind.rawValue, privacy: .public) to \(peerID.displayName, privacy: .public)"
        )
    }

    private func notifyOutgoingCardSent(mode: CardExchangeTransferMode) {
        outgoingCardAnimationID = UUID()
        onOutgoingCardSent?(mode)
    }

    private func scheduleDiscoveryTimeout() {
        discoveryTimeoutTask?.cancel()
        discoveryTimeoutTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64(Constants.activeDiscoveryWindow * 1_000_000_000)
            )
            guard !Task.isCancelled, let self else { return }
            self.transport.stopActiveDiscovery()
            if self.localIntent != nil || self.isSwipePrimed {
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

    private func performCleanupIfIdle() {
        guard localIntent == nil, outgoingTransactions.isEmpty, incomingTransactions.isEmpty else {
            return
        }
        discoveryTimeoutTask?.cancel()
        intentResolutionTask?.cancel()
        transport.stopActiveDiscovery()
        invalidateRangingSessions()
        peerStates.removeAll()
        transport.disconnectAllPeers()
        currentTarget = nil
        isSwipePrimed = false
        phase = NearbyExchangeRangingSession.isSupported ? .listening : .unavailable
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
