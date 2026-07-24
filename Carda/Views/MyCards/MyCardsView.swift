//
//  MyCardsView.swift
//  Cardi
//

import SwiftData
import SwiftUI
import MultipeerConnectivity
#if canImport(UIKit)
import UIKit
#endif

private enum CardEditorMode: Identifiable {
    case create
    case edit(BusinessCard)

    var id: String {
        switch self {
        case .create:
            "create"
        case .edit(let card):
            "edit-\(card.id.uuidString)"
        }
    }

    var draft: BusinessCardDraft {
        switch self {
        case .create:
            BusinessCardDraft()
        case .edit(let card):
            BusinessCardDraft(card: card)
        }
    }
}

private struct OutgoingCardSnapshot: Identifiable, Equatable {
    let id: UUID
    let data: CardRenderData
    let initialYOffset: CGFloat
    let initialScale: CGFloat
    let initialTilt: Double

    init(
        id: UUID = UUID(),
        data: CardRenderData,
        initialYOffset: CGFloat,
        initialScale: CGFloat = 1,
        initialTilt: Double = 0
    ) {
        self.id = id
        self.data = data
        self.initialYOffset = initialYOffset
        self.initialScale = initialScale
        self.initialTilt = initialTilt
    }
}

private struct PendingReceivedCardExchange: Identifiable, Equatable {
    let delivery: CardExchangeIncomingDelivery

    var id: UUID {
        delivery.exchangeID
    }

    var payload: CardExchangePayload {
        delivery.payload
    }

    var renderData: CardRenderData {
        payload.renderData
    }

    static func == (lhs: PendingReceivedCardExchange, rhs: PendingReceivedCardExchange) -> Bool {
        lhs.id == rhs.id
    }
}

private struct ReceivedCardListOption: Identifiable, Equatable {
    let id: UUID
    let name: String
}

private struct ReceivedCardListPickerState: Equatable {
    var selectedListID: UUID?
}

private extension CardExchangePayload {
    var renderData: CardRenderData {
        CardRenderData(
            id: sourceCardID,
            name: name,
            phoneticName: phoneticName,
            position: position,
            organizationName: organizationName,
            backgroundTemplate: CardBackgroundTemplate(
                rawValue: backgroundTemplateRaw ?? ""
            ) ?? .color1,
            avatarImageData: avatarImageData,
            companyLogoImageData: companyLogoImageData,
            fields: fields.map {
                CardFieldDraft(
                    kind: $0.kind,
                    value: $0.value,
                    sortOrder: $0.sortOrder
                )
            }
        )
    }
}

#if DEBUG && targetEnvironment(simulator)
@MainActor
private enum SimulatorExchangeAutomation {
    static var didRun = false
}
#endif

struct MyCardsView: View {
    fileprivate static let cardSpacing: CGFloat = 32
    fileprivate static let pageAnimationDuration: TimeInterval = 0.18
    fileprivate static let bottomNavigationExclusionTop: CGFloat = 779
    private static let gestureCoordinateSpace = "my-cards-canvas"

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \BusinessCard.createdAt) private var allCards: [BusinessCard]
    @Query(sort: \BusinessCardList.sortOrder) private var availableCardLists: [BusinessCardList]
    @AppStorage(CardaSettingsPreferenceKeys.allowsNearbyDiscovery)
    private var allowsNearbyDiscovery = true
    @AppStorage(CardaSettingsPreferenceKeys.confirmsIncomingCards)
    private var confirmsIncomingCards = true
    @AppStorage(CardaSettingsPreferenceKeys.exchangeHaptics)
    private var exchangeHaptics = true
    @AppStorage(CardaSettingsPreferenceKeys.exchangeSound)
    private var exchangeSound = true
    @AppStorage(CardaSettingsPreferenceKeys.defaultReceivedListID)
    private var defaultReceivedListID = ""
    @AppStorage(CardaSettingsPreferenceKeys.duplicatePolicy)
    private var duplicatePolicyRawValue = CardaDuplicateCardPolicy.ask.rawValue
    @AppStorage(CardaSettingsPreferenceKeys.confirmsCardDeletion)
    private var confirmsCardDeletion = true
    @AppStorage(CardaSettingsPreferenceKeys.interactionHaptics)
    private var interactionHaptics = true
    @AppStorage(CardaSettingsPreferenceKeys.interactionSound)
    private var interactionSound = true
    @AppStorage(CardaSettingsPreferenceKeys.allowsCardPaging)
    private var allowsCardPaging = true

    let accountAvatarImageData: Data?
    let accountName: String?
    let accountPhoneNumber: String?
    let accountEmail: String?
    let isAccountLoggedIn: Bool
    let onUpdateAccount: (Data?, String, String, String) -> Bool
    let onLogout: () -> Bool
    var showsPageBackground = true

    @State private var selectedIndex = 0
    @State private var editorMode: CardEditorMode?
    @State private var isAddSheetPresented = false
    @State private var isContextMenuVisible = false
    @State private var saveMessage: String?
    @State private var exchangeGestureCardCopy: OutgoingCardSnapshot?
    @State private var outgoingCardSnapshot: OutgoingCardSnapshot?
    @State private var outgoingAnimationEndsAt: Date?
    @State private var pendingReceivedCard: PendingReceivedCardExchange?
    @State private var queuedReceivedCard: PendingReceivedCardExchange?
    @State private var delayedReceiveWorkItem: DispatchWorkItem?
    @State private var receiveScheduleID = UUID()
    @State private var cardDragOffset: CGFloat = 0
    @State private var exchangeDragOffset: CGFloat = 0
    @State private var exchangeGestureScale: CGFloat = 1
    @State private var exchangeGestureTilt: Double = 0
    @State private var isExchangeTargetLocked = false
    @State private var exchangeCopyResetID = UUID()
    @State private var didPrimeExchangeGesture = false
    @State private var isSettlingCardPage = false
    @State private var pageIndicatorIndex = 0
    @State private var cardPendingDeletionID: UUID?
    @StateObject private var exchangeCoordinator = CardExchangeCoordinator()

    private var myCards: [BusinessCard] {
        allCards
            .filter { $0.ownerKind == .mine }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var currentCard: BusinessCard? {
        guard !myCards.isEmpty else { return nil }
        return myCards[min(selectedIndex, myCards.count - 1)]
    }

    private var receivedCardListOptions: [ReceivedCardListOption] {
        availableCardLists
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.createdAt < $1.createdAt
                }
                return $0.sortOrder < $1.sortOrder
            }
            .map { ReceivedCardListOption(id: $0.id, name: $0.name) }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if showsPageBackground {
                    CardaTheme.myCardsBackground
                        .frame(width: CardaTheme.canvasWidth, height: CardaTheme.canvasHeight)
                }

                ScreenHeader(
                    title: "我的名片",
                    avatarImageData: accountAvatarImageData,
                    isAccountLoggedIn: isAccountLoggedIn,
                    avatarAction: handleAvatarTap
                )

                if myCards.isEmpty {
                    emptyState
                        .position(x: proxy.size.width / 2, y: 269)
                } else {
                    cardCarousel(width: min(370, proxy.size.width - 32))
                        .position(x: proxy.size.width / 2, y: 268)

                    if myCards.count > 1 {
                        PageIndicatorCapsule(
                            count: myCards.count,
                            selectedIndex: pageIndicatorIndex
                        )
                            .position(x: proxy.size.width / 2, y: 760)
                    }
                }

                if let exchangeGestureCardCopy, outgoingCardSnapshot == nil {
                    BusinessCardView(
                        data: exchangeGestureCardCopy.data,
                        width: min(370, proxy.size.width - 32)
                    )
                    .scaleEffect(
                        isExchangeTargetLocked
                            ? max(exchangeGestureScale, 1.05)
                            : exchangeGestureScale
                    )
                    .rotation3DEffect(
                        .degrees(exchangeGestureTilt),
                        axis: (x: 1, y: 0, z: 0),
                        perspective: 0.28
                    )
                    .offset(
                        y: exchangeDragOffset - (isExchangeTargetLocked ? 12 : 0)
                    )
                    .position(x: proxy.size.width / 2, y: 268)
                    .allowsHitTesting(false)
                    .zIndex(7)
                }

                if let outgoingCardSnapshot {
                    OutgoingCardSendOffView(
                        snapshot: outgoingCardSnapshot,
                        width: min(370, proxy.size.width - 32),
                        screenSize: proxy.size,
                        cardCenterY: 268,
                        onFinished: { completedID in
                            if outgoingCardSnapshot.id == completedID {
                                CardExchangeDiagnostics.shared.record(
                                    stage: .animation,
                                    name: "outgoing_animation_finished",
                                    details: ["animationID": completedID.uuidString]
                                )
                                self.outgoingCardSnapshot = nil
                                self.outgoingAnimationEndsAt = nil
                                scheduleQueuedReceivedCardPresentation()
                            }
                        }
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .zIndex(8)
                }

                if let pendingReceivedCard {
                    ReceivedCardExchangeOverlay(
                        exchange: pendingReceivedCard,
                        returnCard: currentCard?.renderData,
                        listOptions: receivedCardListOptions,
                        width: min(370, proxy.size.width - 32),
                        screenSize: proxy.size,
                        cardTop: 326,
                        cardHolderIconCenter: CGPoint(x: 163.5, y: 822),
                        onReject: rejectReceivedCard,
                        onPersist: persistReceivedCard,
                        onAnimationFinished: completeReceivedCardAnimation
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .transition(.opacity)
                    .zIndex(9)
                }

                if isContextMenuVisible {
                    Color.clear
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.snappy(duration: 0.18)) {
                                isContextMenuVisible = false
                            }
                        }
                        .zIndex(10)

                    if let card = currentCard {
                        ContextActionMenu(
                            actions: [
                                ContextAction(title: "编辑名片") {
                                    withAnimation(.snappy(duration: 0.18)) {
                                        isContextMenuVisible = false
                                    }
                                    editorMode = .edit(card)
                                },
                                ContextAction(title: "保存为图片") {
                                    withAnimation(.snappy(duration: 0.18)) {
                                        isContextMenuVisible = false
                                    }
                                    saveCurrentCard(card)
                                },
                                ContextAction(title: "删除名片", role: .destructive) {
                                    requestDeleteCurrentCard(card)
                                }
                            ]
                        )
                        .frame(width: 250)
                        .position(x: proxy.size.width / 2, y: 468)
                        .transition(.cardaContextActionMenu)
                        .zIndex(11)
                    }
                }

                if let feedbackMessage {
                    Text(feedbackMessage)
                        .font(CardaTheme.pingFang(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.black.opacity(0.72)))
                        .position(x: proxy.size.width / 2, y: 600)
                        .transition(.opacity.combined(with: .scale))
                        .accessibilityIdentifier("exchange.feedback")
                }

                #if DEBUG && targetEnvironment(simulator)
                if isExchangeSimulationEnabled, let currentCard {
                    Button(simulatorExchangeButtonTitle) {
                        exchangeCoordinator.simulateProximityExchange(with: currentCard.renderData)
                    }
                    .font(CardaTheme.pingFang(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 112, height: 38)
                    .background(Capsule().fill(Color.black.opacity(0.72)))
                    .position(x: proxy.size.width / 2, y: 708)
                    .accessibilityIdentifier("debug.simulateExchange")
                    .zIndex(12)
                }
                #endif
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .coordinateSpace(name: Self.gestureCoordinateSpace)
            .simultaneousGesture(
                cardPageSwipeGesture(cardWidth: min(370, proxy.size.width - 32))
            )
        }
        .sheet(isPresented: $isAddSheetPresented) {
            AddCardSheet(
                accountAvatarImageData: accountAvatarImageData,
                accountName: accountName,
                accountPhoneNumber: accountPhoneNumber,
                accountEmail: accountEmail,
                onUpdateAccount: onUpdateAccount,
                onLogout: onLogout
            ) {
                isAddSheetPresented = false
                editorMode = .create
            }
            .presentationDetents([.height(465), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.white)
        }
        .cardEditorPresentation(item: $editorMode) { mode in
            CardEditorView(initialDraft: mode.draft) { draft in
                commit(draft, mode: mode)
            }
        }
        .alert(
            "确认删除这张名片？",
            isPresented: Binding(
                get: { cardPendingDeletionID != nil },
                set: { isPresented in
                    if !isPresented {
                        cardPendingDeletionID = nil
                    }
                }
            )
        ) {
            Button("删除", role: .destructive, action: deletePendingCurrentCard)
            Button("取消", role: .cancel) {
                cardPendingDeletionID = nil
            }
        } message: {
            Text("删除后无法恢复。")
        }
        .onChange(of: myCards.count) { _, count in
            selectedIndex = min(selectedIndex, max(0, count - 1))
            pageIndicatorIndex = min(pageIndicatorIndex, max(0, count - 1))
            refreshExchangeSession()
            #if DEBUG && targetEnvironment(simulator)
            runAutomaticExchangeSimulationIfNeeded()
            #endif
        }
        .onChange(of: selectedIndex) { _, index in
            guard !isSettlingCardPage else { return }
            pageIndicatorIndex = min(index, max(0, myCards.count - 1))
        }
        .onChange(of: currentCard?.id) { _, _ in
            refreshExchangeSession()
            #if DEBUG && targetEnvironment(simulator)
            runAutomaticExchangeSimulationIfNeeded()
            #endif
        }
        .onChange(of: currentCard?.updatedAt) { _, _ in
            refreshExchangeSession()
        }
        .onChange(of: isAddSheetPresented) { _, _ in
            refreshExchangeSession()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .cardExchangeDiagnosticsDidStart
            )
        ) { _ in
            isAddSheetPresented = false
        }
        .onChange(of: editorMode?.id) { _, _ in
            refreshExchangeSession()
        }
        .onChange(of: allowsNearbyDiscovery) { _, _ in
            refreshExchangeSession()
        }
        .onChange(of: exchangeCoordinator.statusMessage) { _, message in
            guard let message else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                if exchangeCoordinator.statusMessage == message {
                    exchangeCoordinator.statusMessage = nil
                }
            }
        }
        .onChange(of: exchangeCoordinator.phase) { _, phase in
            CardExchangeDiagnostics.shared.record(
                stage: .lifecycle,
                name: "exchange_phase_changed",
                level: {
                    if case .failed = phase { return .error }
                    return .info
                }(),
                details: ["phase": phase.diagnosticCode]
            )
            switch phase {
            case .listening, .unavailable, .noTarget, .failed:
                resetExchangeDragOffset()
            default:
                break
            }
        }
        .onChange(of: scenePhase) { _, phase in
            CardExchangeDiagnostics.shared.record(
                stage: .lifecycle,
                name: "scene_phase_changed",
                details: ["phase": String(describing: phase)]
            )
            if phase == .active {
                refreshExchangeSession()
            } else {
                exchangeCoordinator.stop()
                CardExchangeDiagnostics.shared.flush()
                resetExchangeDragOffset()
            }
        }
        .onAppear {
            #if DEBUG && targetEnvironment(simulator)
            seedSimulatorExchangeCardIfNeeded()
            #endif
            exchangeCoordinator.onIncomingCard = presentReceivedCard
            exchangeCoordinator.onOutgoingCardSent = startOutgoingCardAnimation
            exchangeCoordinator.onTargetLocked = { _ in
                withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.86)) {
                    isExchangeTargetLocked = true
                }
                CardaInteractionFeedback.targetLocked(
                    haptics: interactionHaptics && exchangeHaptics
                )
            }
            exchangeCoordinator.onOutgoingPersisted = { _, mode in
                CardaInteractionFeedback.exchangeSucceeded(
                    isMutual: mode.isMutual,
                    haptics: interactionHaptics && exchangeHaptics,
                    sound: interactionSound && exchangeSound
                )
            }
            refreshExchangeSession()
            #if DEBUG && targetEnvironment(simulator)
            runAutomaticExchangeSimulationIfNeeded()
            #endif
        }
        .onDisappear {
            delayedReceiveWorkItem?.cancel()
            receiveScheduleID = UUID()
            exchangeCoordinator.stop()
        }
    }

    private var feedbackMessage: String? {
        saveMessage ?? exchangeCoordinator.statusMessage
    }

    #if DEBUG && targetEnvironment(simulator)
    private var isExchangeSimulationEnabled: Bool {
        ProcessInfo.processInfo.environment["CARDA_ENABLE_EXCHANGE_SIMULATION"] == "1"
    }

    private var shouldAutoRunExchangeSimulation: Bool {
        ProcessInfo.processInfo.environment["CARDA_AUTO_SIMULATE_EXCHANGE"] == "1"
    }

    private var simulatorExchangeButtonTitle: String {
        ProcessInfo.processInfo.environment["CARDA_SIMULATE_SINGLE_DELIVERY"] == "1"
            ? "模拟单向来卡"
            : "模拟上滑交换"
    }
    #endif

    private var emptyState: some View {
        Button {
            editorMode = .create
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .circular)
                    .fill(CardaTheme.formFill)
                    .frame(width: 370, height: 223)

                Path { path in
                    path.move(to: CGPoint(x: 2, y: 16))
                    path.addLine(to: CGPoint(x: 30, y: 16))
                    path.move(to: CGPoint(x: 16, y: 2))
                    path.addLine(to: CGPoint(x: 16, y: 30))
                }
                .stroke(
                    Color.gray,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .frame(width: 32, height: 32)
                .opacity(0.75)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("创建第一张名片")
    }

    private func cardCarousel(width: CGFloat) -> some View {
        MyCardCarousel(
            cards: myCards,
            selectedIndex: $selectedIndex,
            width: width,
            dragOffset: cardDragOffset
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in
                    guard
                        exchangeGestureCardCopy == nil,
                        outgoingCardSnapshot == nil,
                        pendingReceivedCard == nil
                    else {
                        return
                    }
                    withAnimation(.snappy(duration: 0.24)) {
                        isContextMenuVisible = true
                    }
                }
        )
        .simultaneousGesture(
            cardExchangeSwipeGesture(cardWidth: width)
        )
        .onTapGesture {
            withAnimation(.snappy(duration: 0.18)) {
                isContextMenuVisible = false
            }
        }
    }

    private enum CardPageDirection {
        case forward
        case backward
    }

    private func cardPageSwipeGesture(cardWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .local)
            .onChanged { value in
                guard canHandleCardPageSwipe(value) else { return }
                cardDragOffset = clampedCardDragOffset(
                    value.translation.width,
                    cardWidth: cardWidth
                )
            }
            .onEnded { value in
                guard canHandleCardPageSwipe(value) else {
                    resetCardDragOffset()
                    return
                }

                let predicted = value.predictedEndTranslation.width
                let measured = value.translation.width
                if measured < -35 || predicted < -85 {
                    settleCardPage(direction: .forward, cardWidth: cardWidth)
                } else if measured > 35 || predicted > 85 {
                    settleCardPage(direction: .backward, cardWidth: cardWidth)
                } else {
                    resetCardDragOffset()
                }
            }
    }

    private func canHandleCardPageSwipe(_ value: DragGesture.Value) -> Bool {
        guard allowsCardPaging, myCards.count > 1, !isSettlingCardPage else { return false }
        guard
            !isContextMenuVisible,
            exchangeGestureCardCopy == nil,
            outgoingCardSnapshot == nil,
            pendingReceivedCard == nil
        else {
            return false
        }
        guard !didPrimeExchangeGesture else { return false }
        guard value.startLocation.y < Self.bottomNavigationExclusionTop else { return false }
        return abs(value.translation.width) >= abs(value.translation.height)
    }

    private func cardExchangeSwipeGesture(cardWidth: CGFloat) -> some Gesture {
        DragGesture(
            minimumDistance: 3,
            coordinateSpace: .named(Self.gestureCoordinateSpace)
        )
            .onChanged { value in
                guard canHandleCardExchangeSwipe(value, cardWidth: cardWidth) else { return }
                let upwardDistance = max(0, -value.translation.height)
                if upwardDistance >= 20, !didPrimeExchangeGesture {
                    didPrimeExchangeGesture = exchangeCoordinator.beginThrowGesture()
                    if didPrimeExchangeGesture, let currentCard {
                        exchangeCopyResetID = UUID()
                        exchangeGestureScale = 0.96
                        exchangeGestureTilt = 0
                        isExchangeTargetLocked = false
                        exchangeGestureCardCopy = OutgoingCardSnapshot(
                            data: currentCard.renderData,
                            initialYOffset: 0
                        )
                    }
                }
                guard didPrimeExchangeGesture else { return }
                exchangeDragOffset = -min(upwardDistance, 148)
                let liftProgress = min(max((upwardDistance - 20) / 128, 0), 1)
                exchangeGestureScale = 0.96 + 0.12 * liftProgress
                let predictedExtra = max(
                    0,
                    -value.predictedEndTranslation.height - upwardDistance
                )
                exchangeGestureTilt = -Double(min(5, predictedExtra / 32))
            }
            .onEnded { value in
                guard didPrimeExchangeGesture else {
                    let upwardDistance = max(0, -value.translation.height)
                    guard upwardDistance >= 20 else { return }
                    CardExchangeDiagnostics.shared.record(
                        stage: .gesture,
                        name: "gesture_attempt_rejected_by_ui",
                        level: .warning,
                        details: [
                            "reason": cardExchangeSwipeRejectionReason(
                                value,
                                cardWidth: cardWidth
                            ) ?? "coordinator_rejected"
                        ]
                    )
                    return
                }
                let measured = -value.translation.height
                let predicted = -value.predictedEndTranslation.height
                let shouldCommit = measured >= 120 || predicted >= 168
                didPrimeExchangeGesture = false

                if shouldCommit {
                    exchangeCoordinator.commitThrowGesture()
                    if !isExchangeTargetLocked {
                        resetExchangeDragOffset()
                    }
                } else {
                    exchangeCoordinator.cancelThrowGesture()
                    resetExchangeDragOffset()
                }
            }
    }

    private func canHandleCardExchangeSwipe(
        _ value: DragGesture.Value,
        cardWidth: CGFloat
    ) -> Bool {
        guard allowsNearbyDiscovery, currentCard != nil, !isSettlingCardPage else { return false }
        guard
            !isContextMenuVisible,
            outgoingCardSnapshot == nil,
            pendingReceivedCard == nil,
            exchangeGestureCardCopy == nil || didPrimeExchangeGesture
        else {
            return false
        }
        guard editorMode == nil, !isAddSheetPresented else { return false }
        guard value.translation.height < 0 else { return false }
        guard abs(value.translation.height) > abs(value.translation.width) * 1.1 else { return false }

        let cardHeight = currentCard.map {
            CardLayoutCalculator.height(for: $0.renderData) * cardWidth / CardaTheme.cardWidth
        } ?? CardaTheme.baseCardHeight
        let cardFrame = CGRect(
            x: (CardaTheme.canvasWidth - cardWidth) / 2,
            y: 268 - cardHeight / 2,
            width: cardWidth,
            height: cardHeight
        )
        return cardFrame.contains(value.startLocation)
    }

    private func cardExchangeSwipeRejectionReason(
        _ value: DragGesture.Value,
        cardWidth: CGFloat
    ) -> String? {
        if !allowsNearbyDiscovery { return "nearby_discovery_disabled" }
        guard let currentCard else { return "no_current_card" }
        if isSettlingCardPage { return "card_page_settling" }
        if isContextMenuVisible { return "context_menu_visible" }
        if outgoingCardSnapshot != nil { return "outgoing_animation_active" }
        if pendingReceivedCard != nil { return "incoming_card_pending" }
        if exchangeGestureCardCopy != nil, !didPrimeExchangeGesture {
            return "gesture_copy_busy"
        }
        if editorMode != nil { return "editor_presented" }
        if isAddSheetPresented { return "account_sheet_presented" }
        if value.translation.height >= 0 { return "not_upward" }
        if abs(value.translation.height) <= abs(value.translation.width) * 1.1 {
            return "not_vertical_enough"
        }

        let cardHeight =
            CardLayoutCalculator.height(for: currentCard.renderData)
            * cardWidth / CardaTheme.cardWidth
        let cardFrame = CGRect(
            x: (CardaTheme.canvasWidth - cardWidth) / 2,
            y: 268 - cardHeight / 2,
            width: cardWidth,
            height: cardHeight
        )
        if !cardFrame.contains(value.startLocation) {
            return "started_outside_card"
        }
        return nil
    }

    private func resetExchangeDragOffset() {
        didPrimeExchangeGesture = false
        let resetID = UUID()
        CardExchangeDiagnostics.shared.record(
            stage: .animation,
            name: "gesture_copy_reset_started",
            details: ["resetID": resetID.uuidString]
        )
        exchangeCopyResetID = resetID
        withAnimation(.snappy(duration: 0.2)) {
            exchangeDragOffset = 0
            exchangeGestureScale = 1
            exchangeGestureTilt = 0
            isExchangeTargetLocked = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard
                exchangeCopyResetID == resetID,
                !didPrimeExchangeGesture,
                outgoingCardSnapshot == nil
            else {
                return
            }
            exchangeGestureCardCopy = nil
            CardExchangeDiagnostics.shared.record(
                stage: .animation,
                name: "gesture_copy_reset_finished",
                details: ["resetID": resetID.uuidString]
            )
        }
    }

    private func clampedCardDragOffset(_ translation: CGFloat, cardWidth: CGFloat) -> CGFloat {
        let limit = cardPageStride(cardWidth: cardWidth)
        return min(max(translation, -limit), limit)
    }

    private func cardPageStride(cardWidth: CGFloat) -> CGFloat {
        cardWidth + Self.cardSpacing
    }

    private func settleCardPage(direction: CardPageDirection, cardWidth: CGFloat) {
        guard !isSettlingCardPage else { return }
        isSettlingCardPage = true

        let targetOffset: CGFloat
        let targetIndex: Int
        switch direction {
        case .forward:
            targetOffset = -cardPageStride(cardWidth: cardWidth)
            targetIndex = wrappedMyCardIndex(selectedIndex + 1)
        case .backward:
            targetOffset = cardPageStride(cardWidth: cardWidth)
            targetIndex = wrappedMyCardIndex(selectedIndex - 1)
        }
        withAnimation(.snappy(duration: Self.pageAnimationDuration)) {
            cardDragOffset = targetOffset
            pageIndicatorIndex = targetIndex
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pageAnimationDuration) {
            switch direction {
            case .forward:
                selectedIndex = targetIndex
            case .backward:
                selectedIndex = targetIndex
            }

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                cardDragOffset = 0
            }
            isSettlingCardPage = false
        }
    }

    private func resetCardDragOffset() {
        withAnimation(.snappy(duration: 0.14)) {
            cardDragOffset = 0
        }
    }

    private func wrappedMyCardIndex(_ index: Int) -> Int {
        guard !myCards.isEmpty else { return 0 }
        return (index % myCards.count + myCards.count) % myCards.count
    }

    private func handleAvatarTap() {
        isAddSheetPresented = true
    }

    private func commit(_ draft: BusinessCardDraft, mode: CardEditorMode) {
        switch mode {
        case .create:
            let card = BusinessCard(draft: draft)
            modelContext.insert(card)
            selectedIndex = myCards.count
        case .edit(let card):
            for field in card.fields {
                modelContext.delete(field)
            }
            card.fields.removeAll()
            card.applyMetadata(from: draft)
            card.fields = draft.fields.map(CardInfoField.init(draft:))
        }

        do {
            try modelContext.save()
        } catch {
            saveMessage = "保存失败"
        }
    }

    private func refreshExchangeSession() {
        guard
            allowsNearbyDiscovery,
            scenePhase == .active,
            let currentCard,
            editorMode == nil,
            !isAddSheetPresented
        else {
            exchangeCoordinator.stop()
            return
        }

        exchangeCoordinator.start(with: currentCard.renderData)
        exchangeCoordinator.updateLocalCard(currentCard.renderData)
    }

    private func presentReceivedCard(_ delivery: CardExchangeIncomingDelivery) {
        CardExchangeDiagnostics.shared.record(
            stage: .animation,
            name: "incoming_delivery_received_by_ui",
            exchangeID: delivery.exchangeID,
            peerIdentifier: delivery.peerID.displayName,
            details: ["mode": delivery.mode.rawValue]
        )
        let exchange = PendingReceivedCardExchange(delivery: delivery)
        let asksBecauseDuplicate = duplicatePolicy == .ask
            && matchingReceivedCard(for: delivery.payload) != nil
        if !confirmsIncomingCards && !asksBecauseDuplicate {
            if insertReceivedCard(delivery.payload) {
                CardExchangeDiagnostics.shared.record(
                    stage: .persistence,
                    name: "incoming_card_auto_save_succeeded",
                    exchangeID: delivery.exchangeID,
                    peerIdentifier: delivery.peerID.displayName
                )
                _ = exchangeCoordinator.confirmIncomingPersisted(
                    delivery,
                    returnCard: nil
                )
            } else {
                CardExchangeDiagnostics.shared.record(
                    stage: .persistence,
                    name: "incoming_card_auto_save_failed",
                    level: .error,
                    exchangeID: delivery.exchangeID,
                    peerIdentifier: delivery.peerID.displayName
                )
                exchangeCoordinator.reportIncomingPersistenceFailure(delivery)
            }
            return
        }
        queuedReceivedCard = exchange
        delayedReceiveWorkItem?.cancel()
        receiveScheduleID = UUID()
        CardaInteractionFeedback.incomingCard(
            haptics: interactionHaptics && exchangeHaptics,
            sound: interactionSound && exchangeSound
        )
        scheduleQueuedReceivedCardPresentation()
    }

    private func showReceivedCard(_ exchange: PendingReceivedCardExchange) {
        CardExchangeDiagnostics.shared.record(
            stage: .animation,
            name: "incoming_animation_presented",
            exchangeID: exchange.delivery.exchangeID,
            peerIdentifier: exchange.delivery.peerID.displayName
        )
        withAnimation(.easeInOut(duration: 0.18)) {
            pendingReceivedCard = exchange
        }
    }

    private func scheduleQueuedReceivedCardPresentation() {
        guard let exchange = queuedReceivedCard else { return }
        delayedReceiveWorkItem?.cancel()
        let receiveDelay = queuedReceiveDelay()
        let scheduleID = UUID()
        receiveScheduleID = scheduleID
        let item = DispatchWorkItem {
            guard receiveScheduleID == scheduleID else { return }
            self.queuedReceivedCard = nil
            showReceivedCard(exchange)
        }
        delayedReceiveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + receiveDelay, execute: item)
    }

    private func queuedReceiveDelay() -> TimeInterval {
        let postOutgoingPause: TimeInterval = 0.1
        guard let outgoingAnimationEndsAt else { return postOutgoingPause }
        return max(postOutgoingPause, outgoingAnimationEndsAt.timeIntervalSinceNow + postOutgoingPause)
    }

    private func rejectReceivedCard(_ id: UUID) {
        guard let pendingReceivedCard, pendingReceivedCard.id == id else { return }
        delayedReceiveWorkItem?.cancel()
        receiveScheduleID = UUID()
        exchangeCoordinator.rejectIncoming(pendingReceivedCard.delivery)
        withAnimation(.easeInOut(duration: 0.18)) {
            self.pendingReceivedCard = nil
        }
        scheduleQueuedReceivedCardPresentation()
    }

    @discardableResult
    private func persistReceivedCard(
        _ id: UUID,
        shouldReturn: Bool,
        selectedListID: UUID?
    ) -> Bool {
        guard let pendingReceivedCard, pendingReceivedCard.id == id else { return false }
        delayedReceiveWorkItem?.cancel()
        receiveScheduleID = UUID()
        let returnCard = shouldReturn ? currentCard?.renderData : nil
        if insertReceivedCard(
            pendingReceivedCard.payload,
            selectedListID: selectedListID
        ) {
            CardExchangeDiagnostics.shared.record(
                stage: .persistence,
                name: "incoming_card_manual_save_succeeded",
                exchangeID: pendingReceivedCard.delivery.exchangeID,
                peerIdentifier: pendingReceivedCard.delivery.peerID.displayName,
                details: [
                    "willReturnCard": String(shouldReturn),
                    "listSelection": selectedListID == nil ? "default" : "explicit"
                ]
            )
            return exchangeCoordinator.confirmIncomingPersisted(
                pendingReceivedCard.delivery,
                returnCard: returnCard
            )
        } else {
            CardExchangeDiagnostics.shared.record(
                stage: .persistence,
                name: "incoming_card_manual_save_failed",
                level: .error,
                exchangeID: pendingReceivedCard.delivery.exchangeID,
                peerIdentifier: pendingReceivedCard.delivery.peerID.displayName
            )
            exchangeCoordinator.reportIncomingPersistenceFailure(pendingReceivedCard.delivery)
            return false
        }
    }

    private func completeReceivedCardAnimation(_ id: UUID) {
        guard let pendingReceivedCard, pendingReceivedCard.id == id else { return }
        CardExchangeDiagnostics.shared.record(
            stage: .animation,
            name: "incoming_animation_finished",
            exchangeID: pendingReceivedCard.delivery.exchangeID,
            peerIdentifier: pendingReceivedCard.delivery.peerID.displayName
        )
        withAnimation(.easeInOut(duration: 0.18)) {
            self.pendingReceivedCard = nil
        }
        scheduleQueuedReceivedCardPresentation()
    }

    @discardableResult
    private func insertReceivedCard(
        _ payload: CardExchangePayload,
        selectedListID: UUID? = nil
    ) -> Bool {
        let destinationListID = resolvedReceivedListID(selectedListID)
        if duplicatePolicy == .replace,
           let existingCard = matchingReceivedCard(for: payload) {
            replace(existingCard, with: payload)
            if selectedListID != nil {
                existingCard.cardListID = destinationListID
            }
        } else {
            let card = payload.receivedBusinessCard()
            card.cardListID = destinationListID
            modelContext.insert(card)
        }

        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            return false
        }
    }

    private var duplicatePolicy: CardaDuplicateCardPolicy {
        CardaDuplicateCardPolicy(rawValue: duplicatePolicyRawValue) ?? .ask
    }

    private var resolvedDefaultReceivedListID: UUID? {
        guard
            let id = UUID(uuidString: defaultReceivedListID),
            availableCardLists.contains(where: { $0.id == id })
        else {
            return nil
        }
        return id
    }

    private func resolvedReceivedListID(_ selectedListID: UUID?) -> UUID? {
        guard let selectedListID else { return resolvedDefaultReceivedListID }
        return availableCardLists.contains(where: { $0.id == selectedListID })
            ? selectedListID
            : nil
    }

    private func matchingReceivedCard(for payload: CardExchangePayload) -> BusinessCard? {
        let payloadPhone = payload.fields
            .first(where: { $0.kind == .phone })
            .map { PhoneNumberFormatter.digits(in: $0.value) }
            .flatMap { $0.isEmpty ? nil : $0 }
        let payloadEmail = payload.fields
            .first(where: { $0.kind == .email })?
            .value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return allCards.first { card in
            guard card.ownerKind == .received else { return false }
            if let payloadPhone {
                let cardPhone = card.sortedFields
                    .first(where: { $0.kind == .phone })
                    .map { PhoneNumberFormatter.digits(in: $0.value) }
                if cardPhone == payloadPhone {
                    return true
                }
            }
            if let payloadEmail, !payloadEmail.isEmpty {
                let cardEmail = card.sortedFields
                    .first(where: { $0.kind == .email })?
                    .value
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                if cardEmail == payloadEmail {
                    return true
                }
            }
            return card.name.trimmingCharacters(in: .whitespacesAndNewlines)
                == payload.name.trimmingCharacters(in: .whitespacesAndNewlines)
                && card.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
                == payload.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func replace(_ card: BusinessCard, with payload: CardExchangePayload) {
        for field in card.fields {
            modelContext.delete(field)
        }
        card.fields.removeAll()
        card.name = payload.name
        card.phoneticName = payload.phoneticName
        card.position = payload.position
        card.organizationName = payload.organizationName
        card.avatarImageData = payload.avatarImageData
        card.companyLogoImageData = payload.companyLogoImageData
        card.fields = payload.fields.map(\.cardInfoField)
        card.updatedAt = Date()
        card.receivedAt = Date()
    }

    private func startOutgoingCardAnimation(_ mode: CardExchangeTransferMode) {
        guard mode != .returnDelivery else {
            CardExchangeDiagnostics.shared.record(
                stage: .animation,
                name: "return_animation_owned_by_receive_overlay"
            )
            return
        }
        guard let data = exchangeGestureCardCopy?.data ?? currentCard?.renderData else {
            CardExchangeDiagnostics.shared.record(
                stage: .animation,
                name: "outgoing_animation_missing_card_snapshot",
                level: .error,
                details: ["mode": mode.rawValue]
            )
            return
        }
        if outgoingCardSnapshot != nil {
            if outgoingAnimationEndsAt == nil {
                outgoingAnimationEndsAt = Date().addingTimeInterval(OutgoingCardSendOffView.totalDuration)
            }
            return
        }
        outgoingCardSnapshot = OutgoingCardSnapshot(
            id: exchangeGestureCardCopy?.id ?? UUID(),
            data: data,
            initialYOffset: exchangeDragOffset - (isExchangeTargetLocked ? 12 : 0),
            initialScale: exchangeGestureScale,
            initialTilt: exchangeGestureTilt
        )
        CardExchangeDiagnostics.shared.record(
            stage: .animation,
            name: "outgoing_animation_started",
            details: [
                "mode": mode.rawValue,
                "animationID": outgoingCardSnapshot?.id.uuidString ?? "missing"
            ]
        )
        exchangeCopyResetID = UUID()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            exchangeDragOffset = 0
            exchangeGestureScale = 1
            exchangeGestureTilt = 0
            isExchangeTargetLocked = false
            exchangeGestureCardCopy = nil
        }
        outgoingAnimationEndsAt = Date().addingTimeInterval(OutgoingCardSendOffView.totalDuration)
    }

    #if DEBUG && targetEnvironment(simulator)
    private func seedSimulatorExchangeCardIfNeeded() {
        guard isExchangeSimulationEnabled, myCards.isEmpty else { return }

        let draft = BusinessCardDraft(
            name: "Cardi 测试",
            phoneticName: "Cardi Test",
            position: "产品体验",
            organizationName: "Cardi",
            fields: [
                CardFieldDraft(kind: .phone, value: "13800019999", sortOrder: 0),
                CardFieldDraft(kind: .email, value: "test@carda.local", sortOrder: 1),
                CardFieldDraft(kind: .link, value: "https://carda.local", sortOrder: 2)
            ]
        )
        modelContext.insert(BusinessCard(draft: draft))

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            exchangeCoordinator.statusMessage = "模拟名片创建失败"
        }
    }

    private func runAutomaticExchangeSimulationIfNeeded() {
        guard
            isExchangeSimulationEnabled,
            shouldAutoRunExchangeSimulation,
            !SimulatorExchangeAutomation.didRun,
            let currentCard
        else {
            return
        }

        SimulatorExchangeAutomation.didRun = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            exchangeCoordinator.simulateProximityExchange(with: currentCard.renderData)
        }
    }
    #endif

    private func saveCurrentCard(_ card: BusinessCard) {
        let ok = CardImageExporter.savePNG(for: card.renderData)
        withAnimation {
            saveMessage = ok ? "已保存为图片" : "保存失败"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation {
                saveMessage = nil
            }
        }
    }

    private func requestDeleteCurrentCard(_ card: BusinessCard) {
        guard confirmsCardDeletion else {
            deleteCurrentCard(card)
            return
        }
        withAnimation(.snappy(duration: 0.18)) {
            isContextMenuVisible = false
        }
        cardPendingDeletionID = card.id
    }

    private func deletePendingCurrentCard() {
        guard
            let cardPendingDeletionID,
            let card = myCards.first(where: { $0.id == cardPendingDeletionID })
        else {
            self.cardPendingDeletionID = nil
            return
        }
        self.cardPendingDeletionID = nil
        deleteCurrentCard(card)
    }

    private func deleteCurrentCard(_ card: BusinessCard) {
        withAnimation(.snappy(duration: 0.18)) {
            isContextMenuVisible = false
        }
        let nextCount = max(0, myCards.count - 1)
        let nextIndex = min(selectedIndex, max(0, nextCount - 1))
        modelContext.delete(card)

        do {
            try modelContext.save()
            selectedIndex = nextIndex
        } catch {
            withAnimation {
                saveMessage = "删除失败"
            }
        }
    }
}

private enum OutgoingCardAnimationStyle {
    case standard
    case emphasizedReturn

    var releaseDuration: TimeInterval {
        switch self {
        case .standard: 0.24
        case .emphasizedReturn: 0.14
        }
    }

    var genieDuration: TimeInterval {
        switch self {
        case .standard: 0.85
        case .emphasizedReturn: 1.05
        }
    }

    var releaseScale: CGFloat {
        switch self {
        case .standard: 0.85
        case .emphasizedReturn: 0.9
        }
    }

    var releaseTilt: CGFloat {
        switch self {
        case .standard: -3.5
        case .emphasizedReturn: -2.2
        }
    }

    var bend: CGFloat {
        switch self {
        case .standard: 18
        case .emphasizedReturn: 14
        }
    }

    var totalDuration: TimeInterval {
        releaseDuration + genieDuration
    }
}

private struct OutgoingCardSendOffView: View {
    let snapshot: OutgoingCardSnapshot
    let width: CGFloat
    let screenSize: CGSize
    let cardCenterY: CGFloat
    var style: OutgoingCardAnimationStyle = .standard
    let onFinished: (UUID) -> Void

    @State private var releaseProgress: CGFloat = 0
    @State private var genieProgress: CGFloat = 0

    static let totalDuration = OutgoingCardAnimationStyle.standard.totalDuration

    private var sourceCenter: CGPoint {
        CGPoint(
            x: screenSize.width / 2,
            y: cardCenterY + snapshot.initialYOffset
        )
    }

    var body: some View {
        GenieCardTransitionView(
            data: snapshot.data,
            width: width,
            screenSize: screenSize,
            sourceCenter: sourceCenter,
            targetCenter: CGPoint(x: screenSize.width / 2, y: -18),
            progress: genieProgress,
            visualOpacity: 1,
            targetWidth: width * 0.15,
            bend: style.bend,
            sourceScale: mix(
                from: snapshot.initialScale,
                to: style.releaseScale,
                progress: releaseProgress
            ),
            sourceTilt: mix(
                from: CGFloat(snapshot.initialTilt),
                to: style.releaseTilt,
                progress: releaseProgress
            )
        )
        .frame(width: screenSize.width, height: screenSize.height)
        .allowsHitTesting(false)
        .id(snapshot.id)
        .task(id: snapshot.id) {
            await runAnimation()
        }
        .accessibilityHidden(true)
    }

    private func mix(from start: CGFloat, to end: CGFloat, progress: CGFloat) -> CGFloat {
        start + (end - start) * progress
    }

    @MainActor
    private func runAnimation() async {
        releaseProgress = 0
        genieProgress = 0

        withAnimation(.interactiveSpring(response: style.releaseDuration, dampingFraction: 0.9)) {
            releaseProgress = 1
        }

        try? await Task.sleep(nanoseconds: UInt64(style.releaseDuration * 1_000_000_000))
        guard !Task.isCancelled else { return }
        withAnimation(.timingCurve(0.2, 0.72, 0.18, 1, duration: style.genieDuration)) {
            genieProgress = 1
        }
        try? await Task.sleep(nanoseconds: UInt64(style.genieDuration * 1_000_000_000))
        guard !Task.isCancelled else { return }
        onFinished(snapshot.id)
    }
}

private struct ReceivedCardExchangeOverlay: View {
    @AppStorage(CardaSettingsPreferenceKeys.interactionHaptics)
    private var interactionHaptics = true
    @AppStorage(CardaSettingsPreferenceKeys.exchangeHaptics)
    private var exchangeHaptics = true

    let exchange: PendingReceivedCardExchange
    let returnCard: CardRenderData?
    let listOptions: [ReceivedCardListOption]
    let width: CGFloat
    let screenSize: CGSize
    let cardTop: CGFloat
    let cardHolderIconCenter: CGPoint
    let onReject: (UUID) -> Void
    let onPersist: (UUID, Bool, UUID?) -> Bool
    let onAnimationFinished: (UUID) -> Void

    @State private var blurOpacity: Double = 0
    @State private var entranceGenieProgress: CGFloat = 1
    @State private var isCollecting = false
    @State private var didFinish = false
    @State private var flipAngle: Double = 0
    @State private var isInteractingWithFlip = false
    @State private var usesGenieCollector = false
    @State private var isReturningWithoutCollection = false
    @State private var genieProgress: CGFloat = 0
    @State private var genieVisualOpacity: Double = 1
    @State private var returnOutgoingSnapshot: OutgoingCardSnapshot?
    @State private var listPickerState: ReceivedCardListPickerState?

    private let entranceDuration: TimeInterval = 0.85
    private let blurDuration: TimeInterval = 0.3
    private let autoAcceptDelay: TimeInterval = 3
    private let flipCompletionDuration: TimeInterval = 0.5
    private let postFlipPause: TimeInterval = 0.12
    private let genieCollectDuration: TimeInterval = 1.2

    private var height: CGFloat {
        CardLayoutCalculator.height(for: exchange.renderData) * width / CardaTheme.cardWidth
    }

    private var cardTargetCenterY: CGFloat {
        cardTop + height / 2
    }

    private var canReturn: Bool {
        exchange.delivery.mode == .delivery && returnCard != nil
    }

    #if DEBUG && targetEnvironment(simulator)
    private var shouldAutoSimulateReturn: Bool {
        ProcessInfo.processInfo.environment["CARDA_AUTO_SIMULATE_RETURN"] == "1"
    }
    #endif

    var body: some View {
        ZStack(alignment: .topLeading) {
            ReceiveBackdropBlur()
                .opacity(blurOpacity)
                .frame(width: screenSize.width, height: screenSize.height)
                .overlay {
                    Color(red: 158 / 255, green: 158 / 255, blue: 158 / 255)
                        .opacity(0.5 * blurOpacity)
                }
                .contentShape(Rectangle())

            receivedCard

            if let returnOutgoingSnapshot {
                OutgoingCardSendOffView(
                    snapshot: returnOutgoingSnapshot,
                    width: width,
                    screenSize: screenSize,
                    cardCenterY: cardTargetCenterY,
                    style: .emphasizedReturn,
                    onFinished: finishReturnAnimation
                )
                .frame(width: screenSize.width, height: screenSize.height)
                .zIndex(4)
            }

            receiveActionButton(
                title: "拒绝",
                width: 72,
                action: {
                    guard !isCollecting else { return }
                    onReject(exchange.id)
                }
            )
            .position(x: 52, y: 90)
            .opacity(isCollecting ? 0 : 1)

            receiveActionButton(
                title: "分到列表",
                width: 112,
                action: {
                    presentListPicker()
                }
            )
            .position(x: 330, y: 90)
            .opacity(isCollecting ? 0 : 1)

            if canReturn {
                Text("向侧边翻转名片可回递")
                    .font(CardaTheme.pingFang(size: 14, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.68))
                    .position(x: screenSize.width / 2, y: cardTop + height + 31)
                    .opacity(isCollecting ? 0 : blurOpacity)
                    .allowsHitTesting(false)
            }

            if listPickerState != nil {
                Color.black.opacity(0.18)
                    .frame(width: screenSize.width, height: screenSize.height)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: dismissListPicker)
                    .transition(.opacity)
                    .zIndex(5)

                ReceivedCardListPickerDialog(
                    options: listOptions,
                    selectedListID: Binding(
                        get: { self.listPickerState?.selectedListID },
                        set: { self.listPickerState?.selectedListID = $0 }
                    ),
                    onConfirm: confirmSelectedList,
                    onCancel: dismissListPicker
                )
                .position(x: screenSize.width / 2, y: screenSize.height / 2)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
                .zIndex(6)
            }
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .id(exchange.id)
        .task(id: exchange.id) {
            await runPresentation()
        }
    }

    private var receivedCard: some View {
        ZStack(alignment: .topLeading) {
            if usesGenieCollector {
                GenieCardTransitionView(
                    data: exchange.renderData,
                    width: width,
                    screenSize: screenSize,
                    sourceCenter: CGPoint(x: screenSize.width / 2, y: cardTargetCenterY),
                    targetCenter: cardHolderIconCenter,
                    progress: genieProgress,
                    visualOpacity: genieVisualOpacity,
                    targetWidth: 18,
                    bend: -14,
                    sourceScale: 1,
                    sourceTilt: 0
                )
                .zIndex(0)
            }

            if !usesGenieCollector {
                GenieCardTransitionView(
                    data: exchange.renderData,
                    width: width,
                    screenSize: screenSize,
                    sourceCenter: CGPoint(x: screenSize.width / 2, y: cardTargetCenterY),
                    targetCenter: CGPoint(x: screenSize.width / 2, y: -18),
                    progress: entranceGenieProgress,
                    visualOpacity: 1,
                    targetWidth: width * 0.15,
                    bend: 18,
                    sourceScale: 1,
                    sourceTilt: 0,
                    backData: returnCard,
                    flipAngle: CGFloat(flipAngle),
                    isInteractive: true
                )
                .contentShape(Rectangle())
                .gesture(returnGesture)
                .accessibilityLabel(
                    canReturn ? "收到的名片，向侧边翻转可回递" : "收到的名片"
                )
                .zIndex(1)
            }
        }
        .frame(width: screenSize.width, height: screenSize.height, alignment: .topLeading)
        .opacity(isReturningWithoutCollection && returnOutgoingSnapshot != nil ? 0 : 1)
    }

    private var returnGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                guard canReturn, !isCollecting, !didFinish else { return }
                isInteractingWithFlip = true
                let progress = min(abs(value.translation.width) / 120, 1)
                flipAngle = Double(progress) * 180
            }
            .onEnded { value in
                guard canReturn, !isCollecting, !didFinish else { return }
                isInteractingWithFlip = false
                if abs(value.translation.width) >= 84 || flipAngle >= 126 {
                    startReturning()
                } else {
                    withAnimation(.snappy(duration: 0.22)) {
                        flipAngle = 0
                    }
                }
            }
    }

    private func receiveActionButton(
        title: String,
        width: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(CardaTheme.pingFang(size: 17, weight: .medium))
                .foregroundStyle(Color.black)
                .frame(width: width, height: 46)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(
            FigmaGlassShape(cornerRadius: 296, interactive: true)
                .frame(width: width, height: 46)
        )
        .opacity(blurOpacity)
        .disabled(isCollecting)
        .accessibilityLabel(title)
    }

    @MainActor
    private func runPresentation() async {
        blurOpacity = 0
        entranceGenieProgress = 1
        isCollecting = false
        didFinish = false
        flipAngle = 0
        isInteractingWithFlip = false
        usesGenieCollector = false
        isReturningWithoutCollection = false
        genieProgress = 0
        genieVisualOpacity = 1
        returnOutgoingSnapshot = nil
        listPickerState = nil

        withAnimation(.easeInOut(duration: blurDuration)) {
            blurOpacity = 1
        }
        await Task.yield()
        guard !Task.isCancelled else { return }
        withAnimation(.timingCurve(0.2, 0.72, 0.18, 1, duration: entranceDuration)) {
            entranceGenieProgress = 0
        }

        #if DEBUG && targetEnvironment(simulator)
        if canReturn, shouldAutoSimulateReturn {
            try? await Task.sleep(
                nanoseconds: UInt64((entranceDuration + 0.35) * 1_000_000_000)
            )
            guard !Task.isCancelled else { return }
            startReturning()
            return
        }
        #endif

        let timerInterval: TimeInterval = 0.1
        var idleDuration: TimeInterval = 0
        while idleDuration < autoAcceptDelay, !Task.isCancelled, !didFinish {
            try? await Task.sleep(
                nanoseconds: UInt64(timerInterval * 1_000_000_000)
            )
            if listPickerState == nil, !isInteractingWithFlip {
                idleDuration += timerInterval
            } else {
                idleDuration = 0
            }
        }
        guard !Task.isCancelled, !didFinish, listPickerState == nil else { return }
        startCollecting()
    }

    @MainActor
    private func presentListPicker() {
        guard !isCollecting, !didFinish, listPickerState == nil else { return }
        withAnimation(.snappy(duration: 0.2)) {
            listPickerState = ReceivedCardListPickerState(selectedListID: nil)
        }
    }

    @MainActor
    private func dismissListPicker() {
        withAnimation(.snappy(duration: 0.18)) {
            listPickerState = nil
        }
    }

    @MainActor
    private func confirmSelectedList() {
        guard
            let selectedListID = listPickerState?.selectedListID,
            listOptions.contains(where: { $0.id == selectedListID })
        else {
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            listPickerState = nil
        }
        startCollecting(selectedListID: selectedListID)
    }

    @MainActor
    private func startCollecting(selectedListID: UUID? = nil) {
        guard !isCollecting, !didFinish else { return }
        isCollecting = true
        prepareGenieCollector()
        withAnimation(.timingCurve(0.22, 0.61, 0.36, 1, duration: genieCollectDuration)) {
            genieProgress = 1
        }

        Task {
            try? await Task.sleep(nanoseconds: UInt64(genieCollectDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            _ = onPersist(exchange.id, false, selectedListID)
            didFinish = true
            onAnimationFinished(exchange.id)
        }
    }

    @MainActor
    private func startReturning() {
        guard canReturn, !isCollecting, !didFinish else { return }
        isCollecting = true
        withAnimation(.snappy(duration: flipCompletionDuration)) {
            flipAngle = 180
        }

        Task {
            try? await Task.sleep(
                nanoseconds: UInt64(flipCompletionDuration * 1_000_000_000)
            )
            guard !Task.isCancelled else { return }
            CardaInteractionFeedback.softImpact(
                enabled: interactionHaptics && exchangeHaptics
            )
            try? await Task.sleep(
                nanoseconds: UInt64(postFlipPause * 1_000_000_000)
            )
            guard !Task.isCancelled, let returnCard else { return }

            guard onPersist(exchange.id, true, nil) else {
                didFinish = true
                onAnimationFinished(exchange.id)
                return
            }

            // The completed flip already shows the user's own card. Hand that
            // exact visual position to the outgoing genie transition without
            // collecting the received card underneath it.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isReturningWithoutCollection = true
                returnOutgoingSnapshot = OutgoingCardSnapshot(
                    data: returnCard,
                    initialYOffset: 0
                )
            }
        }
    }

    @MainActor
    private func prepareGenieCollector() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            genieProgress = 0
            genieVisualOpacity = 1
            usesGenieCollector = true
        }
    }

    @MainActor
    private func finishReturnAnimation(_ snapshotID: UUID) {
        guard returnOutgoingSnapshot?.id == snapshotID, !didFinish else { return }
        didFinish = true
        returnOutgoingSnapshot = nil
        onAnimationFinished(exchange.id)
    }
}

private struct ReceivedCardListPickerDialog: View {
    let options: [ReceivedCardListOption]
    @Binding var selectedListID: UUID?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var canConfirm: Bool {
        guard let selectedListID else { return false }
        return options.contains(where: { $0.id == selectedListID })
    }

    private var listViewportHeight: CGFloat {
        guard !options.isEmpty else { return 68 }
        return min(CGFloat(options.count) * 52, 208)
    }

    private var dialogHeight: CGFloat {
        58 + listViewportHeight + 16 + 49 + 9 + 48 + 14
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("选择名片列表")
                .font(CardaTheme.pingFang(size: 17, weight: .semibold))
                .foregroundStyle(Color.black)
                .frame(height: 58)
                .accessibilityIdentifier("exchange.listPicker.title")

            if options.isEmpty {
                Text("暂无现有列表\n请先在名片夹创建列表")
                    .font(CardaTheme.pingFang(size: 15, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .frame(width: 272, height: listViewportHeight)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                            listOptionButton(option)

                            if index < options.count - 1 {
                                Rectangle()
                                    .fill(Color.black.opacity(0.08))
                                    .frame(height: 0.5)
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .frame(width: 272)
                }
                .scrollIndicators(.hidden)
                .frame(width: 272, height: listViewportHeight)
            }

            Button(action: onConfirm) {
                Text("确认")
                    .font(CardaTheme.pingFang(size: 17, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 272, height: 49)
                    .background(
                        Capsule()
                            .fill(canConfirm ? Color.blue : Color.gray.opacity(0.45))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canConfirm)
            .padding(.top, 16)
            .accessibilityIdentifier("exchange.listPicker.confirm")

            Button(action: onCancel) {
                Text("取消")
                    .font(CardaTheme.pingFang(size: 17, weight: .regular))
                    .foregroundStyle(CardaTheme.destructive)
                    .frame(width: 272, height: 48)
                    .background(
                        Capsule()
                            .fill(
                                Color(red: 0.82, green: 0.82, blue: 0.84)
                                    .opacity(0.72)
                            )
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 9)
            .accessibilityIdentifier("exchange.listPicker.cancel")
        }
        .frame(width: 300, height: dialogHeight, alignment: .top)
        .background(FigmaGlassShape(cornerRadius: 36))
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
    }

    private func listOptionButton(_ option: ReceivedCardListOption) -> some View {
        let isSelected = selectedListID == option.id

        return Button {
            selectedListID = option.id
        } label: {
            HStack(spacing: 12) {
                Text(option.name)
                    .font(CardaTheme.pingFang(size: 17, weight: .regular))
                    .foregroundStyle(Color.black)
                    .lineLimit(1)

                Spacer(minLength: 8)

                ZStack {
                    Circle()
                        .stroke(
                            isSelected ? Color.blue : Color.black.opacity(0.2),
                            lineWidth: 1.5
                        )

                    if isSelected {
                        Circle()
                            .fill(Color.blue)
                            .padding(4)
                    }
                }
                .frame(width: 20, height: 20)
            }
            .padding(.horizontal, 16)
            .frame(width: 272, height: 51.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.name)
        .accessibilityValue(isSelected ? "已选择" : "未选择")
        .accessibilityIdentifier("exchange.listPicker.option.\(option.id.uuidString)")
    }
}

private struct GenieCardTransitionView: View, Animatable {
    let data: CardRenderData
    let width: CGFloat
    let screenSize: CGSize
    let sourceCenter: CGPoint
    let targetCenter: CGPoint
    var progress: CGFloat
    let visualOpacity: Double
    let targetWidth: CGFloat
    let bend: CGFloat
    var sourceScale: CGFloat
    var sourceTilt: CGFloat
    var backData: CardRenderData? = nil
    var flipAngle: CGFloat = 0
    var isInteractive = false

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.cardaReduceMotion) private var settingsReduceMotion

    private var reduceMotion: Bool {
        systemReduceMotion || settingsReduceMotion
    }

    var animatableData: AnimatablePair<
        CGFloat,
        AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>
    > {
        get {
            AnimatablePair(
                progress,
                AnimatablePair(
                    sourceScale,
                    AnimatablePair(sourceTilt, flipAngle)
                )
            )
        }
        set {
            progress = newValue.first
            sourceScale = newValue.second.first
            sourceTilt = newValue.second.second.first
            flipAngle = newValue.second.second.second
        }
    }

    private var height: CGFloat {
        let frontHeight = CardLayoutCalculator.height(for: data)
        let backHeight = backData.map { CardLayoutCalculator.height(for: $0) } ?? frontHeight
        return max(frontHeight, backHeight) * width / CardaTheme.cardWidth
    }

    var body: some View {
        let clampedProgress = min(max(progress, 0), 1)
        let fade = max(0, (clampedProgress - 0.78) / 0.22)

        Group {
            if reduceMotion {
                reducedMotionCard(progress: clampedProgress)
            } else {
                warpedCard(progress: clampedProgress)
            }
        }
        .frame(width: screenSize.width, height: screenSize.height, alignment: .topLeading)
        .opacity(visualOpacity * Double(1 - fade))
        .allowsHitTesting(isInteractive)
        .accessibilityHidden(!isInteractive)
    }

    private var cardSurface: some View {
        let radians = flipAngle * .pi / 180
        let edgeProgress = abs(sin(radians))
        let horizontalScale = max(0.012, abs(cos(radians)))

        return ZStack {
            BusinessCardView(data: data, width: width)
                .opacity(flipAngle < 90 ? 1 : 0)

            if let backData {
                BusinessCardView(data: backData, width: width)
                    .opacity(flipAngle >= 90 ? 1 : 0)
            }
        }
        .frame(width: width, height: height)
        .drawingGroup(opaque: false, colorMode: .linear)
        .scaleEffect(
            x: horizontalScale,
            y: 1 + edgeProgress * 0.018,
            anchor: .center
        )
        .offset(y: -edgeProgress * 3)
    }

    private func warpedCard(progress: CGFloat) -> some View {
        let renderedWidth = width * sourceScale
        let renderedHeight = height * sourceScale
        let cardOrigin = CGPoint(
            x: sourceCenter.x - renderedWidth / 2,
            y: sourceCenter.y - renderedHeight / 2
        )

        return cardSurface
            .scaleEffect(sourceScale)
            .rotation3DEffect(
                .degrees(Double(sourceTilt)),
                axis: (x: 1, y: 0, z: 0),
                perspective: 0.28
            )
            .position(x: sourceCenter.x, y: sourceCenter.y)
            .frame(
                width: screenSize.width,
                height: screenSize.height,
                alignment: .topLeading
            )
            .compositingGroup()
            .distortionEffect(
                ShaderLibrary.cardaGenieWarp(
                    .float2(Float(cardOrigin.x), Float(cardOrigin.y)),
                    .float2(Float(renderedWidth), Float(renderedHeight)),
                    .float2(Float(targetCenter.x), Float(targetCenter.y)),
                    .float(Float(progress)),
                    .float(Float(targetWidth)),
                    .float(Float(bend))
                ),
                maxSampleOffset: CGSize(
                    width: screenSize.width,
                    height: screenSize.height
                )
            )
    }

    private func reducedMotionCard(progress: CGFloat) -> some View {
        let eased = smoothStep(progress)
        let center = CGPoint(
            x: sourceCenter.x + (targetCenter.x - sourceCenter.x) * eased,
            y: sourceCenter.y + (targetCenter.y - sourceCenter.y) * eased
        )
        let finalScale = max(targetWidth / max(width, 1), 0.05)
        let scale = sourceScale + (finalScale - sourceScale) * eased

        return cardSurface
            .scaleEffect(scale)
            .position(x: center.x, y: center.y)
    }

    private func smoothStep(_ value: CGFloat) -> CGFloat {
        value * value * (3 - 2 * value)
    }
}

private struct ReceiveBackdropBlur: View {
    var body: some View {
        #if canImport(UIKit)
        ReceiveBackdropBlurRepresentable()
        #else
        Rectangle()
            .fill(.regularMaterial)
        #endif
    }
}

#if canImport(UIKit)
private struct ReceiveBackdropBlurRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .light))
        view.backgroundColor = .clear
        view.contentView.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: .light)
        uiView.backgroundColor = .clear
        uiView.contentView.backgroundColor = .clear
    }
}
#endif

private struct MyCardCarousel: View {
    let cards: [BusinessCard]
    @Binding var selectedIndex: Int
    let width: CGFloat
    let dragOffset: CGFloat

    var body: some View {
        ZStack {
            ForEach(visibleSlots, id: \.self) { slot in
                if let card = card(for: slot) {
                    BusinessCardView(data: card.renderData, width: width)
                        .id("\(card.id.uuidString)-\(slot)")
                        .offset(x: CGFloat(slot) * pageStride + dragOffset)
                }
            }
        }
        .frame(width: CardaTheme.canvasWidth, height: carouselHeight)
        .contentShape(Rectangle())
    }

    private var visibleSlots: [Int] {
        cards.count > 1 ? [-1, 0, 1] : [0]
    }

    private var pageStride: CGFloat {
        width + MyCardsView.cardSpacing
    }

    private var carouselHeight: CGFloat {
        let heights = cards.map { CardLayoutCalculator.height(for: $0.renderData) * width / CardaTheme.cardWidth }
        return heights.max() ?? CardaTheme.baseCardHeight
    }

    private func card(for slot: Int) -> BusinessCard? {
        guard !cards.isEmpty else { return nil }
        return cards[wrappedIndex(selectedIndex + slot)]
    }

    private func wrappedIndex(_ index: Int) -> Int {
        guard !cards.isEmpty else { return 0 }
        return (index % cards.count + cards.count) % cards.count
    }
}

private struct PageIndicatorCapsule: View {
    let count: Int
    let selectedIndex: Int

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 12) {
                ForEach(0..<count, id: \.self) { _ in
                    Circle()
                        .fill(CardaTheme.pageIndicatorInactiveDot)
                        .frame(width: 8, height: 8)
                }
            }
            .frame(width: capsuleWidth, height: 20)

            Circle()
                .fill(CardaTheme.pageIndicatorActiveDot)
                .frame(width: 8, height: 8)
                .offset(x: activeDotLeading)
                .animation(.snappy(duration: MyCardsView.pageAnimationDuration), value: activeIndex)
        }
        .frame(width: capsuleWidth, height: 20)
        .background(
            Capsule()
                .fill(CardaTheme.pageIndicatorFill)
        )
    }

    private var capsuleWidth: CGFloat {
        CGFloat(count * 20)
    }

    private var activeIndex: Int {
        min(max(selectedIndex, 0), max(count - 1, 0))
    }

    private var activeDotLeading: CGFloat {
        6 + CGFloat(activeIndex) * 20
    }
}

private enum AddCardSheetDestination: Hashable {
    case authentication
    case account
    case settings
    case linkedApplications
    case linkedApplicationPicker(LinkedApplicationCategory)
}

struct AddCardSheet: View {
    private enum LogoutAlert: Identifiable {
        case confirmation
        case failure

        var id: String {
            switch self {
            case .confirmation: "confirmation"
            case .failure: "failure"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss

    let accountAvatarImageData: Data?
    let accountName: String?
    let accountPhoneNumber: String?
    let accountEmail: String?
    let onUpdateAccount: (Data?, String, String, String) -> Bool
    let onLogout: () -> Bool
    let onAdd: () -> Void

    @State private var navigationPath: [AddCardSheetDestination] = []
    @State private var logoutAlert: LogoutAlert?
    @State private var authenticatedPhoneNumber: String?
    @State private var authenticatedProfile: LocalAccountProfile?

    init(
        accountAvatarImageData: Data?,
        accountName: String? = nil,
        accountPhoneNumber: String? = nil,
        accountEmail: String? = nil,
        onUpdateAccount: @escaping (Data?, String, String, String) -> Bool,
        onLogout: @escaping () -> Bool,
        onAdd: @escaping () -> Void
    ) {
        self.accountAvatarImageData = accountAvatarImageData
        self.accountName = accountName
        self.accountPhoneNumber = accountPhoneNumber
        self.accountEmail = accountEmail
        self.onUpdateAccount = onUpdateAccount
        self.onLogout = onLogout
        self.onAdd = onAdd
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack(alignment: .topLeading) {
                Color.white

                Button(action: onAdd) {
                    Text("添加名片")
                        .font(CardaTheme.pingFang(size: 17))
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .frame(width: 370, height: 52)
                .background(Capsule().fill(sheetItemFill))
                .offset(x: 16, y: 53)
                .accessibilityLabel("添加名片")

                accountCard
                    .offset(x: 16, y: 132)

                accountActionsGroup
                    .offset(x: 16, y: 259)

                Button {
                    if isLoggedIn {
                        logoutAlert = .confirmation
                    }
                } label: {
                    actionRow(title: "退出登录", textColor: CardaTheme.destructive)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!isLoggedIn)
                .offset(x: 16, y: 390)
                .accessibilityLabel("退出登录")
                .accessibilityHint("保存当前账户名片并清空 Cardi 中的名片")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.white)
            .accessibilityHidden(!navigationPath.isEmpty)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AddCardSheetDestination.self) { destination in
                switch destination {
                case .authentication:
                    LocalAccountAuthenticationPage(
                        onAuthenticated: handleAuthentication
                    )
                    .navigationBarBackButtonHidden(true)
                    .toolbar(.hidden, for: .navigationBar)
                case .account:
                    AccountProfilePage(
                        initialAvatarImageData: profileAvatarImageData,
                        initialName: profileName,
                        initialPhoneNumber: profilePhoneNumber,
                        initialEmail: profileEmail,
                        onSave: onUpdateAccount,
                        onCompletion: completeProfileEditing
                    )
                    .navigationBarBackButtonHidden(true)
                    .toolbar(.hidden, for: .navigationBar)
                case .settings:
                    CardaSettingsPage(
                        accountPhoneNumber: accountPhoneNumber,
                        onDestructiveDataChange: {
                            navigationPath.removeAll()
                        }
                    )
                    .accessibilityHidden(navigationPath.last != destination)
                    .navigationBarBackButtonHidden(true)
                    .toolbar(.hidden, for: .navigationBar)
                case .linkedApplications:
                    LinkedApplicationsPage()
                        .accessibilityHidden(navigationPath.last != destination)
                        .navigationBarBackButtonHidden(true)
                        .toolbar(.hidden, for: .navigationBar)
                case .linkedApplicationPicker(let category):
                    LinkedApplicationPickerPage(category: category)
                        .accessibilityHidden(navigationPath.last != destination)
                        .navigationBarBackButtonHidden(true)
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
        }
        .alert(item: $logoutAlert) { alert in
            switch alert {
            case .confirmation:
                Alert(
                    title: Text("退出登录？"),
                    message: Text("退出后，Cardi 中的名片将被清空；再次使用相同手机号登录即可恢复。"),
                    primaryButton: .destructive(Text("退出")) {
                        if onLogout() {
                            dismiss()
                        } else {
                            logoutAlert = .failure
                        }
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            case .failure:
                Alert(
                    title: Text("无法退出登录"),
                    message: Text("名片尚未成功保存到本地账户目录，因此没有清空当前数据。"),
                    dismissButton: .default(Text("好"))
                )
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .cardExchangeDiagnosticsDidStart
            )
        ) { _ in
            dismiss()
        }
    }

    private var accountCard: some View {
        Button {
            navigationPath.append(isLoggedIn ? .account : .authentication)
        } label: {
            accountCardContent
                .contentShape(RoundedRectangle(cornerRadius: 26, style: .circular))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("账户信息")
        .accessibilityValue(isLoggedIn ? "\(accountNameText)，\(accountEmailText)" : "未登陆")
        .accessibilityHint(isLoggedIn ? "编辑头像、昵称和邮箱" : "登录或注册本地账户")
    }

    private var profileAvatarImageData: Data? {
        authenticatedPhoneNumber == nil
            ? accountAvatarImageData
            : authenticatedProfile?.avatarImageData
    }

    private var profileName: String? {
        authenticatedPhoneNumber == nil ? accountName : authenticatedProfile?.name
    }

    private var profilePhoneNumber: String? {
        authenticatedPhoneNumber ?? accountPhoneNumber
    }

    private var profileEmail: String? {
        authenticatedPhoneNumber == nil ? accountEmail : authenticatedProfile?.email
    }

    private func handleAuthentication(phoneNumber: String) {
        authenticatedPhoneNumber = phoneNumber
        authenticatedProfile = try? LocalAccountCardStore().loadProfile(for: phoneNumber)
        navigationPath.append(.account)
    }

    private func completeProfileEditing() {
        navigationPath.removeAll()
        authenticatedPhoneNumber = nil
        authenticatedProfile = nil
    }

    private var accountCardContent: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 26, style: .circular)
                .fill(sheetItemFill)

            Group {
                if isLoggedIn, accountAvatarImageData != nil {
                    DataImageView(data: accountAvatarImageData)
                } else {
                    Circle()
                        .fill(Color(red: 128 / 255, green: 128 / 255, blue: 128 / 255))
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(Circle())
            .offset(x: 19, y: 24)

            Text(accountNameText)
                .font(CardaTheme.pingFang(size: 22, weight: .semibold))
                .foregroundStyle(Color.black)
                .frame(height: 22, alignment: .leading)
                .offset(x: 84, y: 28)

            Text(verbatim: accountEmailText)
                .font(
                    isLoggedIn
                        ? CardaTheme.sfPro(size: 15)
                        : CardaTheme.pingFang(size: 15)
                )
                .foregroundStyle(Color.black.opacity(0.5))
                .frame(height: 20, alignment: .leading)
                .offset(x: 84, y: 56)

            drillInChevron
                .offset(x: 342, y: 39)
        }
        .frame(width: 370, height: 100)
    }

    private var isLoggedIn: Bool {
        normalizedAccountName != nil
            && normalizedAccountPhoneNumber != nil
            && normalizedAccountEmail != nil
    }

    private var normalizedAccountName: String? {
        normalized(accountName)
    }

    private var normalizedAccountEmail: String? {
        normalized(accountEmail)
    }

    private var normalizedAccountPhoneNumber: String? {
        LocalAccountCardStore.canonicalPhoneNumber(accountPhoneNumber ?? "")
    }

    private var accountNameText: String {
        guard isLoggedIn else { return "未登陆" }
        return normalizedAccountName ?? "未登陆"
    }

    private var accountEmailText: String {
        guard isLoggedIn else { return "登陆邮箱" }
        return normalizedAccountEmail ?? "登陆邮箱"
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func actionRow(
        title: String,
        showsChevron: Bool = false,
        textColor: Color = .black
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Capsule()
                .fill(sheetItemFill)

            Text(title)
                .font(CardaTheme.pingFang(size: 17))
                .foregroundStyle(textColor)
                .frame(height: 22, alignment: .leading)
                .offset(x: 19, y: 15)

            if showsChevron {
                drillInChevron
                    .offset(x: 342, y: 15)
            }
        }
        .frame(width: 370, height: 52)
        .accessibilityElement(children: .combine)
    }

    private var accountActionsGroup: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 26, style: .circular)
                .fill(sheetItemFill)

            Button {
                navigationPath.append(.settings)
            } label: {
                actionRowContent(title: "设置", showsChevron: true)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("设置")
            .accessibilityHint("管理名片交换、名片、数据、交互与帮助选项")

            Button {
                navigationPath.append(.linkedApplications)
            } label: {
                actionRowContent(title: "关联应用", showsChevron: true)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(y: 52)
            .accessibilityLabel("关联应用")
            .accessibilityHint("显示 Cardi 打开浏览器、邮箱和地图时使用的应用")

            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(width: 331, height: 0.5)
                .offset(x: 19, y: 51.5)
        }
        .frame(width: 370, height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .circular))
    }

    private func actionRowContent(title: String, showsChevron: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            Text(title)
                .font(CardaTheme.pingFang(size: 17))
                .foregroundStyle(Color.black)
                .frame(height: 22, alignment: .leading)
                .offset(x: 19, y: 15)

            if showsChevron {
                drillInChevron
                    .offset(x: 342, y: 15)
            }
        }
        .frame(width: 370, height: 52, alignment: .topLeading)
    }

    private var sheetItemFill: Color {
        CardaTheme.searchBackground.opacity(0.5)
    }

    private var drillInChevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(
                Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255)
                    .opacity(0.3)
            )
            .frame(width: 8, height: 22)
    }
}

private struct LinkedApplicationsPage: View {
    private static let groupedRowsCornerRadius: CGFloat = 26
    private static let groupedRowsDescriptionOffset: CGFloat = 137

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(LinkedApplicationPreferenceKeys.browser)
    private var selectedBrowserRawValue = LinkedApplicationCategory.browser.defaultApplicationID.rawValue
    @AppStorage(LinkedApplicationPreferenceKeys.mail)
    private var selectedMailRawValue = LinkedApplicationCategory.mail.defaultApplicationID.rawValue
    @AppStorage(LinkedApplicationPreferenceKeys.maps)
    private var selectedMapsRawValue = LinkedApplicationCategory.maps.defaultApplicationID.rawValue
    @State private var isShowingResetConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            LinkedApplicationsToolbar(title: "关联应用")

            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    ForEach(Array(LinkedApplicationCategory.allCases.enumerated()), id: \.element.id) { index, category in
                        NavigationLink(value: AddCardSheetDestination.linkedApplicationPicker(category)) {
                            LinkedApplicationCategoryRow(
                                category: category,
                                application: selectedApplication(for: category)
                            )
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .bottom) {
                            if index < LinkedApplicationCategory.allCases.count - 1 {
                                Rectangle()
                                    .fill(Color.black.opacity(0.08))
                                    .frame(height: 0.5)
                                    .padding(.leading, 19)
                                    .padding(.trailing, 20)
                            }
                        }
                    }
                }
                .frame(width: 370)
                .background(
                    RoundedRectangle(cornerRadius: Self.groupedRowsCornerRadius, style: .circular)
                        .fill(CardaTheme.searchBackground.opacity(0.5))
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: Self.groupedRowsCornerRadius, style: .circular)
                )

                Button {
                    isShowingResetConfirmation = true
                } label: {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: Self.groupedRowsCornerRadius, style: .circular)
                            .fill(CardaTheme.searchBackground.opacity(0.5))

                        Text("恢复默认设置")
                            .font(CardaTheme.pingFang(size: 17))
                            .foregroundStyle(CardaTheme.destructive)
                            .padding(.leading, 19)
                    }
                    .frame(width: 370, height: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(y: 183)
                .accessibilityLabel("恢复默认设置")
                .accessibilityHint("将浏览器、邮箱和地图恢复为默认应用")
            }
            .frame(width: 370, height: 235, alignment: .top)
            .padding(.top, 8)
            .offset(y: 34)

            Text("这些选择仅影响 Cardi 内的网页、邮件和地址跳转。")
                .font(CardaTheme.pingFang(size: 13))
                .foregroundStyle(Color.black.opacity(0.5))
                .multilineTextAlignment(.center)
                .frame(width: 338)
                .padding(.top, 14)
                .offset(y: Self.groupedRowsDescriptionOffset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
        .onAppear(perform: validateSelections)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                validateSelections()
            }
        }
        .alert("恢复默认设置？", isPresented: $isShowingResetConfirmation) {
            Button("取消", role: .cancel) {}
            Button("恢复", role: .destructive, action: resetSelections)
        } message: {
            Text("浏览器、邮箱和地图将恢复为 Safari、邮件和 Apple 地图。")
        }
    }

    private func selectedApplication(
        for category: LinkedApplicationCategory
    ) -> LinkedApplicationID {
        let rawValue: String
        switch category {
        case .browser:
            rawValue = selectedBrowserRawValue
        case .mail:
            rawValue = selectedMailRawValue
        case .maps:
            rawValue = selectedMapsRawValue
        }
        return LinkedApplicationID.resolved(rawValue: rawValue, for: category)
    }

    private func validateSelections() {
        selectedBrowserRawValue = validatedRawValue(
            selectedBrowserRawValue,
            for: .browser
        )
        selectedMailRawValue = validatedRawValue(
            selectedMailRawValue,
            for: .mail
        )
        selectedMapsRawValue = validatedRawValue(
            selectedMapsRawValue,
            for: .maps
        )
    }

    private func validatedRawValue(
        _ rawValue: String,
        for category: LinkedApplicationCategory
    ) -> String {
        guard
            let application = LinkedApplicationID(rawValue: rawValue),
            application.category == category,
            LinkedApplicationAvailability.isAvailable(application)
        else {
            return category.defaultApplicationID.rawValue
        }
        return application.rawValue
    }

    private func resetSelections() {
        selectedBrowserRawValue = LinkedApplicationCategory.browser.defaultApplicationID.rawValue
        selectedMailRawValue = LinkedApplicationCategory.mail.defaultApplicationID.rawValue
        selectedMapsRawValue = LinkedApplicationCategory.maps.defaultApplicationID.rawValue
    }
}

private struct LinkedApplicationPickerPage: View {
    private static let groupedRowsCornerRadius: CGFloat = 26

    let category: LinkedApplicationCategory

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage private var selectedApplicationRawValue: String
    @State private var availableApplications: [LinkedApplicationID] = []

    init(category: LinkedApplicationCategory) {
        self.category = category
        _selectedApplicationRawValue = AppStorage(
            wrappedValue: category.defaultApplicationID.rawValue,
            category.preferenceKey
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            LinkedApplicationsToolbar(title: category.pickerTitle)

            VStack(spacing: 0) {
                ForEach(Array(availableApplications.enumerated()), id: \.element.id) { index, application in
                    Button {
                        selectedApplicationRawValue = application.rawValue
                        dismiss()
                    } label: {
                        LinkedApplicationChoiceRow(
                            application: application,
                            isSelected: application == selectedApplication
                        )
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) {
                        if index < availableApplications.count - 1 {
                            Rectangle()
                                .fill(Color.black.opacity(0.08))
                                .frame(height: 0.5)
                                .padding(.leading, category == .mail ? 19 : 61)
                                .padding(.trailing, 20)
                        }
                    }
                }
            }
            .frame(width: 370)
            .background(
                RoundedRectangle(cornerRadius: Self.groupedRowsCornerRadius, style: .circular)
                    .fill(CardaTheme.searchBackground.opacity(0.5))
            )
            .clipShape(
                RoundedRectangle(cornerRadius: Self.groupedRowsCornerRadius, style: .circular)
            )
            .padding(.top, 8)
            .offset(y: 34)

            Text("仅显示此设备已安装且 Cardi 支持的应用。")
                .font(CardaTheme.pingFang(size: 13))
                .foregroundStyle(Color.black.opacity(0.5))
                .multilineTextAlignment(.center)
                .frame(width: 338)
                .padding(.top, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
        .onAppear(perform: refreshAvailableApplications)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refreshAvailableApplications()
            }
        }
    }

    private var selectedApplication: LinkedApplicationID {
        LinkedApplicationID.resolved(
            rawValue: selectedApplicationRawValue,
            for: category
        )
    }

    private func refreshAvailableApplications() {
        availableApplications = LinkedApplicationAvailability.availableApplications(for: category)
        if selectedApplicationRawValue != selectedApplication.rawValue
            || !availableApplications.contains(selectedApplication) {
            selectedApplicationRawValue = category.defaultApplicationID.rawValue
        }
    }
}

private struct LinkedApplicationsToolbar: View {
    private static let leadingButtonInset: CGFloat = 16
    private static let toolbarContentHeight: CGFloat = 54
    private static let titleTop: CGFloat = 29

    let title: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.black)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(CardaTheme.searchBackground.opacity(0.5))
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, Self.leadingButtonInset)
            .padding(.top, Self.leadingButtonInset)
            .accessibilityLabel("返回")

            Text(title)
                .font(CardaTheme.pingFang(size: 17, weight: .medium))
                .foregroundStyle(Color.black)
                .frame(width: titleWidth, height: 22, alignment: .center)
                .padding(.top, Self.titleTop)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.toolbarContentHeight, alignment: .top)
    }

    private var titleWidth: CGFloat? {
        title == "关联应用" ? 68 : nil
    }
}

private struct LinkedApplicationCategoryRow: View {
    let category: LinkedApplicationCategory
    let application: LinkedApplicationID

    var body: some View {
        HStack(spacing: 0) {
            Text(category.title)
                .font(CardaTheme.pingFang(size: 17))
                .foregroundStyle(Color.black)

            Spacer(minLength: 12)

            HStack(spacing: 12) {
                LinkedApplicationName(application: application, size: 15)
                    .foregroundStyle(Color.black.opacity(0.5))

                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(
                        Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255)
                            .opacity(0.3)
                    )
                    .frame(width: 8, height: 22)
            }
        }
        .padding(.leading, 19)
        .padding(.trailing, 20)
        .frame(width: 370, height: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(category.title)
        .accessibilityValue(application.displayName)
        .accessibilityHint("选择 Cardi 使用的\(category.title)应用")
    }
}

private struct LinkedApplicationChoiceRow: View {
    let application: LinkedApplicationID
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            if application.category != .mail {
                LinkedApplicationChoiceIcon(application: application)
            }

            LinkedApplicationName(application: application, size: 17)
                .foregroundStyle(Color.black)

            Spacer(minLength: 12)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .frame(width: 22, height: 22)
            }
        }
        .padding(.leading, 19)
        .padding(.trailing, 20)
        .frame(width: 370, height: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(application.displayName)
        .accessibilityValue(isSelected ? "已选择" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct LinkedApplicationChoiceIcon: View {
    let application: LinkedApplicationID

    var body: some View {
        Group {
            if let fileName = application.localIconFileName {
                LocalSVGIconView(fileName: fileName)
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: application.systemImage)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.black)
            }
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}

private struct LinkedApplicationName: View {
    let application: LinkedApplicationID
    let size: CGFloat

    var body: some View {
        Group {
            switch application {
            case .chrome:
                Text(verbatim: "Google Chrome")
                    .font(CardaTheme.sfPro(size: size))
            case .qqBrowser:
                HStack(spacing: 0) {
                    Text(verbatim: "QQ")
                        .font(CardaTheme.sfPro(size: size))
                    Text("浏览器")
                        .font(CardaTheme.pingFang(size: size))
                }
            case .edge:
                Text(verbatim: "Microsoft Edge")
                    .font(CardaTheme.sfPro(size: size))
            case .ucBrowser:
                HStack(spacing: 0) {
                    Text(verbatim: "UC")
                        .font(CardaTheme.sfPro(size: size))
                    Text("浏览器")
                        .font(CardaTheme.pingFang(size: size))
                }
            case .qqMail:
                HStack(spacing: 0) {
                    Text(verbatim: "QQ")
                        .font(CardaTheme.sfPro(size: size))
                    Text(" 邮箱")
                        .font(CardaTheme.pingFang(size: size))
                }
            case .outlook:
                Text(verbatim: "Outlook")
                    .font(CardaTheme.sfPro(size: size))
            case .gmail:
                Text(verbatim: "Gmail")
                    .font(CardaTheme.sfPro(size: size))
            case .appleMaps:
                HStack(spacing: 0) {
                    Text(verbatim: "Apple")
                        .font(CardaTheme.sfPro(size: size))
                    Text(" 地图")
                        .font(CardaTheme.pingFang(size: size))
                }
            case .googleMaps:
                HStack(spacing: 0) {
                    Text(verbatim: "Google")
                        .font(CardaTheme.sfPro(size: size))
                    Text(" 地图")
                        .font(CardaTheme.pingFang(size: size))
                }
            case .waze:
                Text(verbatim: "Waze")
                    .font(CardaTheme.sfPro(size: size))
            default:
                Text(application.displayName)
                    .font(CardaTheme.pingFang(size: size))
            }
        }
        .lineLimit(1)
    }
}

enum ContextActionRole: Equatable {
    case normal
    case destructive
}

struct ContextAction: Identifiable {
    let id = UUID()
    var title: String
    var role: ContextActionRole = .normal
    var action: () -> Void
}

struct ContextActionMenu: View {
    let actions: [ContextAction]

    var body: some View {
        ZStack {
            ContextMenuGlassBackground(cornerRadius: 34)

            VStack(spacing: 0) {
                ForEach(actions) { action in
                    Button(action: action.action) {
                        Text(action.title)
                            .font(CardaTheme.pingFang(size: 17, weight: .regular))
                            .foregroundStyle(action.role == .destructive ? CardaTheme.destructive : CardaTheme.primaryText)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 250, height: CGFloat(actions.count) * 42 + 20)
    }
}

extension AnyTransition {
    static var cardaContextActionMenu: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.92, anchor: .top)
                .combined(with: .opacity)
                .combined(with: .offset(y: -8)),
            removal: .scale(scale: 0.96, anchor: .top)
                .combined(with: .opacity)
                .combined(with: .offset(y: -4))
        )
    }
}

private struct ContextMenuGlassBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            shape
                .fill(Color.white.opacity(0.01))
                .glassEffect(
                    .regular.tint(Color(red: 245 / 255, green: 245 / 255, blue: 245 / 255).opacity(0.6)),
                    in: .rect(cornerRadius: cornerRadius)
                )
                .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 4)
        } else {
            shape
                .fill(Color(red: 245 / 255, green: 245 / 255, blue: 245 / 255).opacity(0.58))
                .background(.ultraThinMaterial, in: shape)
                .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 4)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension View {
    @ViewBuilder
    func cardEditorPresentation<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(macOS)
        sheet(item: item, content: content)
        #else
        fullScreenCover(item: item, content: content)
        #endif
    }
}
