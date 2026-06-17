//
//  MyCardsView.swift
//  Carda
//

import SwiftData
import SwiftUI

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

struct MyCardsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BusinessCard.createdAt) private var allCards: [BusinessCard]

    let accountAvatarImageData: Data?

    @State private var selectedIndex = 0
    @State private var editorMode: CardEditorMode?
    @State private var isAddSheetPresented = false
    @State private var isContextMenuVisible = false
    @State private var saveMessage: String?

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

                if let saveMessage {
                    Text(saveMessage)
                        .font(CardaTheme.pingFang(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.black.opacity(0.72)))
                        .position(x: proxy.size.width / 2, y: 600)
                        .transition(.opacity.combined(with: .scale))
                }
            }
        }
        .sheet(isPresented: $isAddSheetPresented) {
            AddCardSheet {
                isAddSheetPresented = false
                editorMode = .create
            }
            .presentationDetents([.height(465), .large])
            .presentationDragIndicator(.visible)
        }
        .cardEditorPresentation(item: $editorMode) { mode in
            CardEditorView(initialDraft: mode.draft) { draft in
                commit(draft, mode: mode)
            }
        }
        .onChange(of: myCards.count) { _, count in
            selectedIndex = min(selectedIndex, max(0, count - 1))
        }
    }

    private var emptyState: some View {
        Button {
            editorMode = .create
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
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
                    .fill(index == selectedIndex ? Color.white : Color(red: 0.929, green: 0.929, blue: 0.929))
                    .frame(width: 8, height: 8)
            }
        }
        .frame(width: CGFloat(count * 20), height: 20)
        .background(
            Capsule()
                .fill(Color(red: 0.851, green: 0.851, blue: 0.851))
        )
    }
}

struct AddCardSheet: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Button(action: onAdd) {
                HStack {
                    Text("添加名片")
                        .font(CardaTheme.pingFang(size: 17))
                        .foregroundStyle(CardaTheme.primaryText)
                    Spacer()
                    Image(systemName: "plus")
                        .foregroundStyle(CardaTheme.mainAccent)
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
            }
            .buttonStyle(.plain)

            HStack(spacing: 14) {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 6) {
                    Text("账户")
                        .font(CardaTheme.pingFang(size: 17, weight: .medium))
                    Text("账户信息、头像及设置")
                        .font(CardaTheme.pingFang(size: 14))
                        .foregroundStyle(CardaTheme.formSecondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CardaTheme.formSecondaryText)
            }
            .padding(.horizontal, 18)
            .frame(height: 100)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color.white))

            VStack(spacing: 0) {
                ForEach(["分享个人主页", "导入名片图片", "设置", "帮助"], id: \.self) { title in
                    Text(title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 52)
                        .padding(.horizontal, 16)
                        .font(CardaTheme.pingFang(size: 16))
                    if title != "帮助" {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 20).fill(Color.white))

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 36)
        .background(CardaTheme.pageBackground)
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
