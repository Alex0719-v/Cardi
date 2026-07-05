//
//  MyCardsView.swift
//  Carda
//

import SwiftData
import SwiftUI
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
    let id = UUID()
    let data: CardRenderData
}

private struct PendingReceivedCardExchange: Identifiable, Equatable {
    let id = UUID()
    let payload: CardExchangePayload

    var renderData: CardRenderData {
        payload.renderData
    }

    static func == (lhs: PendingReceivedCardExchange, rhs: PendingReceivedCardExchange) -> Bool {
        lhs.id == rhs.id
    }
}

private extension CardExchangePayload {
    var renderData: CardRenderData {
        CardRenderData(
            id: sourceCardID,
            name: name,
            phoneticName: phoneticName,
            position: position,
            organizationName: organizationName,
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
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BusinessCard.createdAt) private var allCards: [BusinessCard]

    let accountAvatarImageData: Data?
    let accountName: String?
    let accountEmail: String?
    var showsPageBackground = true

    @State private var selectedIndex = 0
    @State private var editorMode: CardEditorMode?
    @State private var isAddSheetPresented = false
    @State private var isContextMenuVisible = false
    @State private var saveMessage: String?
    @State private var outgoingCardSnapshot: OutgoingCardSnapshot?
    @State private var outgoingAnimationEndsAt: Date?
    @State private var pendingReceivedCard: PendingReceivedCardExchange?
    @State private var queuedReceivedCard: PendingReceivedCardExchange?
    @State private var delayedReceiveWorkItem: DispatchWorkItem?
    @State private var receiveScheduleID = UUID()
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
                    avatarAction: handleAvatarTap
                )

                if myCards.isEmpty {
                    emptyState
                        .position(x: proxy.size.width / 2, y: 269)
                } else {
                    cardCarousel(width: min(370, proxy.size.width - 32))
                        .position(x: proxy.size.width / 2, y: 268)

                    if myCards.count > 1 {
                        PageIndicatorCapsule(count: myCards.count, selectedIndex: selectedIndex)
                            .position(x: proxy.size.width / 2, y: 760)
                    }
                }

                if let outgoingCardSnapshot {
                    OutgoingCardSendOffView(
                        snapshot: outgoingCardSnapshot,
                        width: min(370, proxy.size.width - 32),
                        screenSize: proxy.size,
                        cardCenterY: 268,
                        onFinished: { completedID in
                            if outgoingCardSnapshot.id == completedID {
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
                        width: min(370, proxy.size.width - 32),
                        screenSize: proxy.size,
                        cardTop: 326,
                        cardHolderIconCenter: CGPoint(x: 163.5, y: 822),
                        onReject: rejectReceivedCard,
                        onAccepted: finishReceivingCard
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
                                    deleteCurrentCard(card)
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
                }

                #if DEBUG && targetEnvironment(simulator)
                if isExchangeSimulationEnabled, let currentCard {
                    Button("模拟碰一碰") {
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
        }
        .sheet(isPresented: $isAddSheetPresented) {
            AddCardSheet(
                accountAvatarImageData: accountAvatarImageData,
                accountName: accountName,
                accountEmail: accountEmail
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
        .onChange(of: myCards.count) { _, count in
            selectedIndex = min(selectedIndex, max(0, count - 1))
            refreshExchangeSession()
            #if DEBUG && targetEnvironment(simulator)
            runAutomaticExchangeSimulationIfNeeded()
            #endif
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
        .onChange(of: editorMode?.id) { _, _ in
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
        .onAppear {
            #if DEBUG && targetEnvironment(simulator)
            seedSimulatorExchangeCardIfNeeded()
            #endif
            exchangeCoordinator.onReceivedCard = presentReceivedCard
            exchangeCoordinator.onOutgoingCardSent = startOutgoingCardAnimation
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
    #endif

    private var emptyState: some View {
        Button {
            editorMode = .create
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .circular)
                    .fill(CardaTheme.formFill)
                    .frame(width: 370, height: 223)

                ZStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.75))
                        .frame(width: 32, height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.75))
                        .frame(width: 4, height: 32)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("创建第一张名片")
    }

    private func cardCarousel(width: CGFloat) -> some View {
        MyCardCarousel(
            cards: myCards,
            selectedIndex: $selectedIndex,
            width: width
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in
                    withAnimation(.snappy(duration: 0.24)) {
                        isContextMenuVisible = true
                    }
                }
        )
        .onTapGesture {
            withAnimation(.snappy(duration: 0.18)) {
                isContextMenuVisible = false
            }
        }
    }

    private func handleAvatarTap() {
        guard !myCards.isEmpty else { return }
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

    private func presentReceivedCard(_ payload: CardExchangePayload) {
        let exchange = PendingReceivedCardExchange(payload: payload)
        queuedReceivedCard = exchange
        delayedReceiveWorkItem?.cancel()
        receiveScheduleID = UUID()

        if currentCard != nil {
            startOutgoingCardAnimation()
        }

        scheduleQueuedReceivedCardPresentation()
    }

    private func showReceivedCard(_ exchange: PendingReceivedCardExchange) {
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
        guard pendingReceivedCard?.id == id else { return }
        delayedReceiveWorkItem?.cancel()
        receiveScheduleID = UUID()
        withAnimation(.easeInOut(duration: 0.18)) {
            pendingReceivedCard = nil
        }
        exchangeCoordinator.statusMessage = "已拒绝名片"
    }

    private func finishReceivingCard(_ id: UUID) {
        guard let pendingReceivedCard, pendingReceivedCard.id == id else { return }
        delayedReceiveWorkItem?.cancel()
        receiveScheduleID = UUID()
        insertReceivedCard(pendingReceivedCard.payload)
        withAnimation(.easeInOut(duration: 0.18)) {
            self.pendingReceivedCard = nil
        }
    }

    private func insertReceivedCard(_ payload: CardExchangePayload) {
        modelContext.insert(payload.receivedBusinessCard())

        do {
            try modelContext.save()
            exchangeCoordinator.statusMessage = "已接收\(payload.displayName)的名片"
        } catch {
            exchangeCoordinator.statusMessage = "交换名片保存失败"
        }
    }

    private func startOutgoingCardAnimation() {
        guard let currentCard else { return }
        if outgoingCardSnapshot != nil {
            if outgoingAnimationEndsAt == nil {
                outgoingAnimationEndsAt = Date().addingTimeInterval(OutgoingCardSendOffView.totalDuration)
            }
            return
        }
        outgoingCardSnapshot = OutgoingCardSnapshot(data: currentCard.renderData)
        outgoingAnimationEndsAt = Date().addingTimeInterval(OutgoingCardSendOffView.totalDuration)
    }

    #if DEBUG && targetEnvironment(simulator)
    private func seedSimulatorExchangeCardIfNeeded() {
        guard isExchangeSimulationEnabled, myCards.isEmpty else { return }

        let draft = BusinessCardDraft(
            name: "Carda 测试",
            phoneticName: "Carda Test",
            position: "产品体验",
            organizationName: "Carda",
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

private struct OutgoingCardSendOffView: View {
    let snapshot: OutgoingCardSnapshot
    let width: CGFloat
    let screenSize: CGSize
    let cardCenterY: CGFloat
    let onFinished: (UUID) -> Void

    @State private var pullOutProgress: CGFloat = 0
    @State private var flightStartDate: Date?

    private let pullOutDuration: TimeInterval = 0.18
    private let holdDuration: TimeInterval = 0.25
    private let flightDuration: TimeInterval = 0.3

    static let totalDuration: TimeInterval = 0.18 + 0.25 + 0.3

    private var height: CGFloat {
        CardLayoutCalculator.height(for: snapshot.data) * width / CardaTheme.cardWidth
    }

    private var pulledScale: CGFloat {
        (width + 6) / width
    }

    private var flightTargetScale: CGFloat {
        1
    }

    private var flightTargetCenterY: CGFloat {
        -height / 2 - 32
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let linearFlightProgress = elapsedFlightProgress(at: timeline.date)
            let flightProgress = smoothStep(linearFlightProgress)
            let pullDown = 3 * pullOutProgress
            let currentScale = pulledScale + (flightTargetScale - pulledScale) * flightProgress
            let currentYOffset = pullDown + (flightTargetCenterY - cardCenterY - pullDown) * flightProgress

            ZStack(alignment: .topLeading) {
                BusinessCardView(data: snapshot.data, width: width)
                    .scaleEffect(currentScale)
                    .rotationEffect(.degrees(-0.45 * pullOutProgress * (1 - flightProgress)))
                    .offset(y: currentYOffset)
                    .opacity(1 - max(0, flightProgress - 0.86) / 0.14)
                    .position(x: screenSize.width / 2, y: cardCenterY)
            }
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .allowsHitTesting(false)
        .id(snapshot.id)
        .task(id: snapshot.id) {
            await runAnimation()
        }
        .accessibilityHidden(true)
    }

    private func elapsedFlightProgress(at date: Date) -> CGFloat {
        guard let flightStartDate else { return 0 }
        return min(max(date.timeIntervalSince(flightStartDate) / flightDuration, 0), 1)
    }

    private func smoothStep(_ value: CGFloat) -> CGFloat {
        value * value * (3 - 2 * value)
    }

    @MainActor
    private func runAnimation() async {
        pullOutProgress = 0
        flightStartDate = nil

        withAnimation(.interpolatingSpring(stiffness: 560, damping: 34)) {
            pullOutProgress = 1
        }

        try? await Task.sleep(nanoseconds: UInt64((pullOutDuration + holdDuration) * 1_000_000_000))
        flightStartDate = Date()
        try? await Task.sleep(nanoseconds: UInt64(flightDuration * 1_000_000_000))
        onFinished(snapshot.id)
    }
}

private struct ReceivedCardExchangeOverlay: View {
    let exchange: PendingReceivedCardExchange
    let width: CGFloat
    let screenSize: CGSize
    let cardTop: CGFloat
    let cardHolderIconCenter: CGPoint
    let onReject: (UUID) -> Void
    let onAccepted: (UUID) -> Void

    @State private var blurOpacity: Double = 0
    @State private var entranceStartDate: Date?
    @State private var collectStartDate: Date?
    @State private var isCollecting = false
    @State private var didFinish = false

    private let entranceDuration: TimeInterval = 0.3
    private let blurDuration: TimeInterval = 0.2
    private let autoAcceptDelay: TimeInterval = 3
    private let collectDuration: TimeInterval = 0.3

    private var height: CGFloat {
        CardLayoutCalculator.height(for: exchange.renderData) * width / CardaTheme.cardWidth
    }

    private var entranceSourceCenterY: CGFloat {
        -height / 2 - 32
    }

    private var entranceSourceScale: CGFloat {
        (width + 6) / width
    }

    private var cardTargetCenterY: CGFloat {
        cardTop + height / 2
    }

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

            receiveActionButton(
                title: "拒绝",
                width: 72,
                action: {
                    guard !isCollecting else { return }
                    onReject(exchange.id)
                }
            )
            .position(x: 52, y: 90)

            receiveActionButton(
                title: "分到列表",
                width: 112,
                action: {
                    startCollecting()
                }
            )
            .position(x: 330, y: 90)
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .id(exchange.id)
        .task(id: exchange.id) {
            await runPresentation()
        }
    }

    private var receivedCard: some View {
        TimelineView(.animation) { timeline in
            let entranceProgress = smoothStep(elapsedProgress(
                from: entranceStartDate,
                at: timeline.date,
                duration: entranceDuration
            ))
            let collectProgress = smoothStep(elapsedProgress(
                from: collectStartDate,
                at: timeline.date,
                duration: collectDuration
            ))

            let entranceCenter = CGPoint(
                x: screenSize.width / 2,
                y: entranceSourceCenterY + (cardTargetCenterY - entranceSourceCenterY) * entranceProgress
            )
            let entranceScale = entranceSourceScale + (1 - entranceSourceScale) * entranceProgress
            let x = entranceCenter.x + (cardHolderIconCenter.x - entranceCenter.x) * collectProgress
            let y = entranceCenter.y + (cardHolderIconCenter.y - entranceCenter.y) * collectProgress
            let scale = entranceScale + (0.2 - entranceScale) * collectProgress
            let opacity = 1 - max(0, collectProgress - 0.86) / 0.14

            BusinessCardView(data: exchange.renderData, width: width)
                .scaleEffect(scale)
                .opacity(opacity)
                .position(x: x, y: y)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

    private func elapsedProgress(from startDate: Date?, at date: Date, duration: TimeInterval) -> CGFloat {
        guard let startDate else { return 0 }
        return min(max(date.timeIntervalSince(startDate) / duration, 0), 1)
    }

    private func smoothStep(_ value: CGFloat) -> CGFloat {
        value * value * (3 - 2 * value)
    }

    @MainActor
    private func runPresentation() async {
        blurOpacity = 0
        entranceStartDate = Date()
        collectStartDate = nil
        isCollecting = false
        didFinish = false

        withAnimation(.easeInOut(duration: blurDuration)) {
            blurOpacity = 1
        }

        try? await Task.sleep(nanoseconds: UInt64(autoAcceptDelay * 1_000_000_000))
        guard !Task.isCancelled else { return }
        startCollecting()
    }

    @MainActor
    private func startCollecting() {
        guard !isCollecting, !didFinish else { return }
        isCollecting = true
        collectStartDate = Date()

        Task {
            try? await Task.sleep(nanoseconds: UInt64(collectDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            didFinish = true
            onAccepted(exchange.id)
        }
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
    private static let cardSpacing: CGFloat = 32
    private static let pageAnimationDuration: TimeInterval = 0.18

    let cards: [BusinessCard]
    @Binding var selectedIndex: Int
    let width: CGFloat
    @State private var dragOffset: CGFloat = 0
    @State private var isSettlingPage = false

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
        .gesture(dragGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard cards.count > 1, !isSettlingPage else { return }
                dragOffset = clampedDragOffset(value.translation.width)
            }
            .onEnded { value in
                guard cards.count > 1 else {
                    dragOffset = 0
                    return
                }

                let predicted = value.predictedEndTranslation.width
                let measured = value.translation.width
                if measured < -35 || predicted < -85 {
                    settlePage(direction: .forward)
                } else if measured > 35 || predicted > 85 {
                    settlePage(direction: .backward)
                } else {
                    withAnimation(.snappy(duration: 0.14)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private enum PageDirection {
        case forward
        case backward
    }

    private var visibleSlots: [Int] {
        cards.count > 1 ? [-1, 0, 1] : [0]
    }

    private var pageStride: CGFloat {
        width + Self.cardSpacing
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

    private func clampedDragOffset(_ translation: CGFloat) -> CGFloat {
        let limit = pageStride
        return min(max(translation, -limit), limit)
    }

    private func settlePage(direction: PageDirection) {
        guard !isSettlingPage else { return }
        isSettlingPage = true

        let targetOffset: CGFloat = direction == .forward ? -pageStride : pageStride
        withAnimation(.snappy(duration: Self.pageAnimationDuration)) {
            dragOffset = targetOffset
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pageAnimationDuration) {
            switch direction {
            case .forward:
                selectedIndex = wrappedIndex(selectedIndex + 1)
            case .backward:
                selectedIndex = wrappedIndex(selectedIndex - 1)
            }

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                dragOffset = 0
            }
            isSettlingPage = false
        }
    }
}

private struct PageIndicatorCapsule: View {
    let count: Int
    let selectedIndex: Int

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(
                        index == selectedIndex
                            ? CardaTheme.pageIndicatorActiveDot
                            : CardaTheme.pageIndicatorInactiveDot
                    )
                    .frame(width: 8, height: 8)
            }
        }
        .frame(width: CGFloat(count * 20), height: 20)
        .background(
            Capsule()
                .fill(CardaTheme.pageIndicatorFill)
        )
    }
}

struct AddCardSheet: View {
    let accountAvatarImageData: Data?
    let accountName: String?
    let accountEmail: String?
    let onAdd: () -> Void

    init(
        accountAvatarImageData: Data?,
        accountName: String? = nil,
        accountEmail: String? = nil,
        onAdd: @escaping () -> Void
    ) {
        self.accountAvatarImageData = accountAvatarImageData
        self.accountName = accountName
        self.accountEmail = accountEmail
        self.onAdd = onAdd
    }

    var body: some View {
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

            actionRow(title: "设置", showsChevron: true)
                .offset(x: 16, y: 259)

            actionRow(title: "关联应用", showsChevron: true)
                .offset(x: 16, y: 338)

            actionRow(title: "退出登录")
                .offset(x: 16, y: 417)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
    }

    private var accountCard: some View {
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
        .accessibilityElement(children: .combine)
    }

    private var isLoggedIn: Bool {
        normalizedAccountName != nil && normalizedAccountEmail != nil
    }

    private var normalizedAccountName: String? {
        normalized(accountName)
    }

    private var normalizedAccountEmail: String? {
        normalized(accountEmail)
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

    private func actionRow(title: String, showsChevron: Bool = false) -> some View {
        ZStack(alignment: .topLeading) {
            Capsule()
                .fill(sheetItemFill)

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
        .frame(width: 370, height: 52)
        .accessibilityElement(children: .combine)
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
