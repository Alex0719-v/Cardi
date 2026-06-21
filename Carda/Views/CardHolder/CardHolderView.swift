//
//  CardHolderView.swift
//  Carda
//

import Foundation
import SwiftData
import SwiftUI
import UIKit

private enum HolderMode: String, CaseIterable, Identifiable {
    case list = "列表"
    case name = "姓名"
    case organization = "公司"

    var id: String { rawValue }
}

private enum HolderCardEditorMode: Identifiable {
    case create

    var id: String { "create" }

    var draft: BusinessCardDraft { BusinessCardDraft() }
}

struct CardHolderView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BusinessCardList.sortOrder) private var cardLists: [BusinessCardList]

    let cards: [BusinessCard]
    let accountAvatarImageData: Data?
    let onAddList: () -> Void
    let onRenameList: (BusinessCardList) -> Void
    let onDeleteList: (BusinessCardList) -> Void

    @State private var mode: HolderMode = .name
    @State private var expandedCardID: UUID?
    @State private var expandedListID: String?
    @State private var editorMode: HolderCardEditorMode?
    @State private var isAddSheetPresented = false
    @State private var isContextMenuVisible = false
    @State private var listContextMenuListID: UUID?
    @State private var dropTargetListRowID: String?
    @State private var draggingListCardID: UUID?
    @State private var collapsedDragSourceListID: String?
    @State private var collapsedDragSourceCardID: UUID?
    @State private var collapsedDragSourceScrollOffsetY: CGFloat?
    @State private var listScrollRequest: ListScrollRequest?
    @State private var listScrollPosition = ScrollPosition()
    @State private var listScrollOffsetY: CGFloat = 0
    @State private var ignoreListRowGesturesUntil = Date.distantPast
    @State private var saveMessage: String?
    @State private var alphabetIndexRequest: AlphabetIndexRequest?
    @Namespace private var cardExpansionNamespace

    private let groupedHeaderHeight: CGFloat = 20
    private let groupedHeaderTransitionGap: CGFloat = 10
    private let holderPanelTop: CGFloat = 126
    private let holderContentTop: CGFloat = 164
    private let holderBottomBlurTop: CGFloat = 737
    private let holderBottomBlurHeight: CGFloat = 140

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                holderBackground
                holderPanelBackground

                if cards.isEmpty {
                    emptyState
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                } else {
                    contentForMode
                }

                holderBottomBlur
                    .zIndex(4)

                topModeBar
                    .zIndex(5)

                if mode != .list && !cards.isEmpty {
                    ContactAlphabetIndex { letter in
                        alphabetIndexRequest = AlphabetIndexRequest(letter: letter)
                    }
                        .position(x: 394, y: CardaTheme.canvasHeight / 2)
                        .zIndex(6)
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

                    if let card = expandedCard {
                        ContextActionMenu(actions: [
                            ContextAction(title: "分享名片") {},
                            ContextAction(title: "保存为图片") {
                                saveExpandedCard(card)
                            }
                        ])
                        .frame(width: 250)
                        .position(x: proxy.size.width / 2, y: 654)
                        .transition(.cardaContextActionMenu)
                        .zIndex(11)
                    }
                }

                if let list = contextMenuList {
                    Color.clear
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.snappy(duration: 0.18)) {
                                listContextMenuListID = nil
                            }
                        }
                        .zIndex(12)

                    ContextActionMenu(actions: [
                        ContextAction(title: "修改列表名称") {
                            withAnimation(.snappy(duration: 0.18)) {
                                listContextMenuListID = nil
                            }
                            onRenameList(list)
                        },
                        ContextAction(title: "删除列表", role: .destructive) {
                            withAnimation(.snappy(duration: 0.18)) {
                                listContextMenuListID = nil
                                if expandedListID == list.id.uuidString {
                                    expandedListID = nil
                                    expandedCardID = nil
                                }
                            }
                            onDeleteList(list)
                        }
                    ])
                    .frame(width: 250)
                    .position(x: proxy.size.width / 2, y: 302)
                    .transition(.cardaContextActionMenu)
                    .zIndex(13)
                }

                if let saveMessage {
                    Text(saveMessage)
                        .font(CardaTheme.pingFang(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.black.opacity(0.72)))
                        .position(x: proxy.size.width / 2, y: 600)
                        .zIndex(14)
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
                commit(draft)
            }
        }
    }

    private var holderBackground: some View {
        ZStack {
            Color.white
            CardHolderFigmaColor.pageTint
        }
        .frame(width: CardaTheme.canvasWidth, height: CardaTheme.canvasHeight)
    }

    private var holderPanelBackground: some View {
        HolderPanelShape(mode: mode)
            .fill(Color.white)
            .overlay {
                HolderPanelShape(mode: mode)
                    .fill(CardHolderFigmaColor.panelTint.opacity(holderPanelTintOpacity))
            }
            .frame(
                width: CardaTheme.canvasWidth,
                height: mode == .list ? 821 : 811,
                alignment: .top
            )
            .offset(y: holderPanelTop)
    }

    private var holderPanelTintOpacity: CGFloat {
        mode == .list ? 0.65 : 0.5
    }

    private var holderPinnedBackgroundColor: Color {
        CardHolderFigmaColor.panelComposite(opacity: holderPanelTintOpacity)
    }

    private var holderScrollHeight: CGFloat {
        CardaTheme.canvasHeight - holderContentTop
    }

    private var holderBottomBlur: some View {
        TransparentGradientBlur(height: holderBottomBlurHeight)
            .offset(y: holderBottomBlurTop)
    }

    private var topModeBar: some View {
        ZStack(alignment: .topLeading) {
            if mode == .list {
                Text("名片夹")
                    .font(CardaTheme.pingFang(size: 22, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .lineLimit(1)
                    .frame(width: 80, height: 28, alignment: .center)
                    .position(x: CardaTheme.canvasWidth / 2, y: 88)

                listToolbarButton(title: "多选", width: 72, textLeading: 19, action: {})
                    .position(x: 52, y: 88)

                listToolbarButton(
                    title: "添加列表",
                    width: 112,
                    textLeading: 22,
                    action: onAddList
                )
                    .position(x: 330, y: 88)
            } else {
                Text("名片夹")
                    .font(CardaTheme.pingFang(size: 34, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(Color.black)
                    .lineLimit(1)
                    .frame(width: 370, height: 41, alignment: .leading)
                    .offset(x: 16, y: 62)

                TemporaryHolderAvatar()
                    .offset(x: 342, y: 62)
            }

            holderModeTabs
        }
        .frame(width: CardaTheme.canvasWidth, height: 171, alignment: .topLeading)
    }

    private var holderModeTabs: some View {
        ZStack(alignment: .topLeading) {
            ForEach(HolderMode.allCases) { item in
                if mode != item {
                    modeTabBackground(item)
                }
            }

            categoryButton(.list, x: mode == .list ? 67 : 65)
            categoryButton(.name, x: CardaTheme.canvasWidth / 2)
            categoryButton(.organization, x: mode == .list ? 337 : 335)
        }
    }

    private func modeTabBackground(_ item: HolderMode) -> some View {
        let frame = modeTabFrame(for: item)
        let shape = modeTabShape(for: item)

        return shape
            .fill(Color.white)
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.x, y: frame.y)
    }

    private func modeTabFrame(for item: HolderMode) -> (x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        switch item {
        case .list:
            return (mode == .list ? 0 : 2, 126, 130, 44.988)
        case .name:
            if mode == .list {
                return (136, 126, 143.274, 36)
            }
            if mode == .organization {
                return (122.726, 126, 143.274, 36)
            }
            return (134, 126, 130, 44.988)
        case .organization:
            return (270, 126, 130, 44.988)
        }
    }

    private func modeTabShape(for item: HolderMode) -> HolderModeTabShape {
        switch (mode, item) {
        case (.list, .name):
            return HolderModeTabShape(style: .middleTailRight)
        case (.organization, .name):
            return HolderModeTabShape(style: .middleTailLeft)
        case (.list, .organization), (.name, .organization):
            return HolderModeTabShape(style: .edgeTailRight)
        case (.organization, .list), (.name, .list):
            return HolderModeTabShape(style: .edgeTailLeft)
        case (.list, .list), (.name, .name), (.organization, .organization):
            return HolderModeTabShape(style: .edgeTailRight)
        }
    }

    private func categoryButton(_ item: HolderMode, x: CGFloat) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.28)) {
                mode = item
                expandedCardID = nil
                expandedListID = nil
                isContextMenuVisible = false
                listContextMenuListID = nil
                dropTargetListRowID = nil
                draggingListCardID = nil
                collapsedDragSourceListID = nil
                collapsedDragSourceCardID = nil
                collapsedDragSourceScrollOffsetY = nil
                listScrollRequest = nil
                ignoreListRowGesturesUntil = .distantPast
            }
        } label: {
            Text(item.rawValue)
                .font(CardaTheme.pingFang(size: 15, weight: .regular))
                .foregroundStyle(modeTabTextColor(for: item))
                .lineLimit(1)
                .frame(width: 46, height: 20, alignment: .center)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(x: x, y: 145)
    }

    private func modeTabTextColor(for item: HolderMode) -> Color {
        mode == .name && item == .organization
            ? CardHolderFigmaColor.segmentCompanyText
            : CardHolderFigmaColor.segmentText
    }

    private func listToolbarButton(
        title: String,
        width: CGFloat,
        textLeading: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                FigmaGlassShape(cornerRadius: 296, interactive: true)
                    .shadow(color: .black.opacity(0.0225), radius: 9, x: 0, y: 2)

                Text(title)
                    .font(CardaTheme.pingFang(size: 17, weight: .medium))
                    .foregroundStyle(Color.black)
                    .lineLimit(1)
                    .frame(height: 22, alignment: .leading)
                    .offset(x: textLeading, y: 12)
            }
        }
        .buttonStyle(.plain)
        .frame(width: width, height: 46)
    }

    @ViewBuilder
    private var contentForMode: some View {
        switch mode {
        case .list:
            listModeContent
        case .name, .organization:
            groupedCardContent
        }
    }

    private var groupedCardContent: some View {
        ScrollViewReader { scrollProxy in
            ZStack(alignment: .topLeading) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14, pinnedViews: [.sectionHeaders]) {
                        ForEach(groupedCards) { group in
                            Section {
                                VStack(spacing: 8) {
                                    ForEach(group.cards) { card in
                                        cardRowOrExpanded(card)
                                    }
                                }
                                .padding(.top, -12)
                            } header: {
                                trackedGroupTitle(group.title)
                            }
                            .id(group.id)
                        }
                    }
                    .frame(width: CardaTheme.canvasWidth, alignment: .leading)
                    .padding(
                        .bottom,
                        holderScrollHeight - groupedHeaderHeight
                    )
                }
                .frame(
                    width: CardaTheme.canvasWidth,
                    height: holderScrollHeight,
                    alignment: .top
                )
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear
                        .frame(height: 24)
                        .allowsHitTesting(false)
                }
                .offset(y: holderContentTop)
                .scrollIndicators(.hidden)

            }
            .frame(
                width: CardaTheme.canvasWidth,
                height: CardaTheme.canvasHeight,
                alignment: .topLeading
            )
            .overlayPreferenceValue(GroupedHeaderAnchorPreferenceKey.self) { headers in
                GeometryReader { proxy in
                    ForEach(headers, id: \.title) { header in
                        let frame = proxy[header.bounds]
                        groupTitle(header.title)
                            .position(x: frame.midX, y: frame.midY)
                    }
                }
                .mask(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        Color.clear
                            .frame(height: holderContentTop)

                        Rectangle()
                            .fill(Color.black)
                            .frame(
                                width: CardaTheme.canvasWidth,
                                height: holderScrollHeight
                            )
                    }
                    .frame(
                        width: CardaTheme.canvasWidth,
                        height: CardaTheme.canvasHeight,
                        alignment: .topLeading
                    )
                }
                .allowsHitTesting(false)
            }
            .onChange(of: alphabetIndexRequest) { _, request in
                guard
                    let request,
                    let targetID = groupedSectionID(for: request.letter)
                else {
                    return
                }
                scrollProxy.scrollTo(targetID, anchor: .top)
            }
        }
    }

    private func trackedGroupTitle(_ title: String) -> some View {
        groupTitle(title)
            .anchorPreference(
                key: GroupedHeaderAnchorPreferenceKey.self,
                value: .bounds
            ) {
                [GroupedHeaderAnchor(title: title, bounds: $0)]
            }
            .opacity(0)
    }

    private func groupTitle(_ title: String) -> some View {
        Text(title)
            .font(groupTitleFont(for: title))
            .foregroundStyle(Color.black)
            .frame(width: CardaTheme.canvasWidth - 16, height: groupedHeaderHeight, alignment: .leading)
            .padding(.leading, 16)
            .frame(
                width: CardaTheme.canvasWidth,
                height: groupedHeaderHeight + groupedHeaderTransitionGap,
                alignment: .topLeading
            )
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func cardRowOrExpanded(_ card: BusinessCard) -> some View {
        if expandedCardID == card.id {
            BusinessCardView(data: card.renderData, width: CardaTheme.cardWidth)
                .matchedGeometryEffect(id: "holder-card-\(card.id)", in: cardExpansionNamespace)
                .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45)
                    .onEnded { _ in
                        withAnimation(.snappy(duration: 0.24)) {
                            isContextMenuVisible = true
                            listContextMenuListID = nil
                        }
                    }
            )
            .onTapGesture {
                withAnimation(.snappy(duration: 0.32)) {
                    expandedCardID = nil
                    isContextMenuVisible = false
                    listContextMenuListID = nil
                }
            }
            .frame(width: CardaTheme.canvasWidth, alignment: .center)
        } else {
            let expandCard = {
                withAnimation(.snappy(duration: 0.36)) {
                    expandedCardID = card.id
                    isContextMenuVisible = false
                    listContextMenuListID = nil
                }
            }

            let collapsedRow = CollapsedCardRow(data: card.renderData, namespace: cardExpansionNamespace)
                .frame(width: CardaTheme.canvasWidth, alignment: .center)

            if mode == .list {
                collapsedRow
                    .overlay {
                        ListCardDragSource(
                            data: card.renderData,
                            onTap: expandCard,
                            onDragBegan: {
                                draggingListCardID = card.id
                                collapseSourceListIfNeeded(for: card)
                            },
                            onDragEnded: {
                                finishListDragIfStillActive(cardID: card.id)
                            }
                        )
                        .frame(width: CardaTheme.cardWidth, height: 60)
                    }
            } else {
                collapsedRow
                    .onTapGesture(perform: expandCard)
            }
        }
    }

    private var listModeContent: some View {
        ScrollViewReader { scrollProxy in
            ZStack(alignment: .topLeading) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(Array(listRows.enumerated()), id: \.element.id) { index, row in
                            Section {
                                expandedListCards(row)
                            } header: {
                                listModeRow(
                                    row,
                                    showsTopSeparator: index > 0,
                                    scrollProxy: scrollProxy
                                )
                                .id(row.id)
                            }
                        }
                    }
                    .frame(width: CardaTheme.canvasWidth, alignment: .leading)
                    .padding(.top, 33)
                    .padding(.bottom, 255)
                }
                .frame(
                    width: CardaTheme.canvasWidth,
                    height: holderScrollHeight,
                    alignment: .top
                )
                .offset(y: holderContentTop)
                .scrollIndicators(.hidden)
                .scrollPosition($listScrollPosition)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, offsetY in
                    listScrollOffsetY = max(0, offsetY)
                }

            }
            .frame(
                width: CardaTheme.canvasWidth,
                height: CardaTheme.canvasHeight,
                alignment: .topLeading
            )
            .dropDestination(for: String.self) { items, _ in
                restoreCollapsedSourceListAfterMissedDrop(with: items)
            } isTargeted: { _ in
            }
            .onChange(of: listScrollRequest) { _, request in
                guard let request else { return }

                DispatchQueue.main.asyncAfter(deadline: .now() + request.delay) {
                    guard listScrollRequest == request else { return }

                    withAnimation(.snappy(duration: 0.28)) {
                        switch request.target {
                        case .row(let rowID):
                            scrollProxy.scrollTo(rowID, anchor: .top)
                        case .offset(let offsetY):
                            listScrollPosition.scrollTo(y: offsetY)
                        }
                    }

                    listScrollRequest = nil
                }
            }
        }
    }
    private func expandedListCards(_ row: HolderListRow) -> some View {
        let isExpanded = expandedListID == row.id

        return VStack(spacing: 8) {
            ForEach(cardsForList(row)) { card in
                cardRowOrExpanded(card)
                    .id(card.id)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(
            width: CardaTheme.canvasWidth,
            height: isExpanded ? expandedListContentHeight(for: row) : 0,
            alignment: .top
        )
        .offset(y: isExpanded ? 0 : -68)
        .clipped()
        .allowsHitTesting(isExpanded)
        .zIndex(0)
    }

    private func expandedListContentHeight(for row: HolderListRow) -> CGFloat {
        guard !row.cards.isEmpty else { return 0 }
        let cardHeights = row.cards.reduce(CGFloat.zero) { height, card in
            height + (
                expandedCardID == card.id
                    ? CardLayoutCalculator.height(for: card.renderData)
                    : 60
            )
        }
        let cardSpacing = CGFloat(max(0, row.cards.count - 1)) * 8
        return cardHeights + cardSpacing + 20
    }

    private func listModeRow(
        _ row: HolderListRow,
        showsTopSeparator: Bool,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        HStack(spacing: 0) {
            Text(row.title)
                .font(CardaTheme.pingFang(size: 17, weight: .regular))
                .foregroundStyle(row.isUncategorized ? Color.black.opacity(0.35) : Color.black)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(
                    Color.black.opacity(row.isUncategorized ? 0.16 : 0.22)
                )
                .rotationEffect(.degrees(expandedListID == row.id ? 90 : 0))
                .frame(width: 16, height: 22)
        }
        .frame(width: 330, height: 53)
        .padding(.horizontal, 16)
        .overlay(alignment: .top) {
            if showsTopSeparator {
                Rectangle()
                    .fill(CardHolderFigmaColor.listSeparator)
                    .frame(height: 1)
                    .padding(.horizontal, 16)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            LongPressGesture(minimumDuration: 0.45)
                .exclusively(before: TapGesture())
                .onEnded { value in
                    guard !shouldIgnoreListRowGesture() else { return }

                    switch value {
                    case .first(true):
                        presentListContextMenu(for: row)
                    case .second:
                        toggleListRow(row, scrollProxy: scrollProxy)
                    default:
                        break
                    }
                }
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard !shouldIgnoreListRowGesture() else { return }
            toggleListRow(row, scrollProxy: scrollProxy)
        }
        .dropDestination(for: String.self) { items, _ in
            moveDraggedCard(with: items, to: row)
        } isTargeted: { isTargeted in
            withAnimation(.snappy(duration: 0.16)) {
                dropTargetListRowID = isTargeted ? row.id : nil
            }
        }
        .padding(.leading, 19)
        .frame(width: CardaTheme.canvasWidth, height: 53, alignment: .leading)
        .background(holderPinnedBackgroundColor)
        .overlay {
            if dropTargetListRowID == row.id {
                RoundedRectangle(cornerRadius: 20, style: .circular)
                    .stroke(Color.blue.opacity(0.42), lineWidth: 2)
                    .padding(.horizontal, 19)
                    .padding(.vertical, 5)
                    .allowsHitTesting(false)
            }
        }
        .zIndex(1)
    }

    private var emptyState: some View {
        Text("暂无收到的名片")
            .font(CardaTheme.pingFang(size: 17))
            .foregroundStyle(CardaTheme.formSecondaryText)
    }

    private var expandedCard: BusinessCard? {
        guard let expandedCardID else { return nil }
        return cards.first { $0.id == expandedCardID }
    }

    private var contextMenuList: BusinessCardList? {
        guard let listContextMenuListID else { return nil }
        return cardLists.first { $0.id == listContextMenuListID }
    }

    private var groupedCards: [GroupedCardSection] {
        switch mode {
        case .list:
            return []
        case .name:
            let sorted = cards
                .map { GroupedCardSortRecord(card: $0) }
                .sorted { $0.nameSortKey < $1.nameSortKey }
            return Dictionary(grouping: sorted) { record in
                pinyinInitial(forSortKey: record.nameSortKey)
            }
            .map { key, records in
                GroupedCardSection(
                    title: key.isEmpty ? "#" : key,
                    cards: records.map(\.card)
                )
            }
            .sorted { $0.title < $1.title }
        case .organization:
            let sorted = cards
                .map { GroupedCardSortRecord(card: $0) }
                .sorted { lhs, rhs in
                    if lhs.organizationSortKey == rhs.organizationSortKey {
                        return lhs.nameSortKey < rhs.nameSortKey
                    }
                    return lhs.organizationSortKey < rhs.organizationSortKey
                }
            return Dictionary(grouping: sorted) { record in
                record.card.organizationName.isEmpty ? "未命名公司" : record.card.organizationName
            }
            .map { title, records in
                GroupedCardSection(
                    title: title,
                    cards: records.map(\.card),
                    sortKey: records.first?.organizationSortKey ?? "#"
                )
            }
            .sorted { $0.sortKey < $1.sortKey }
        }
    }

    private func groupedSectionID(for letter: String) -> String? {
        switch mode {
        case .list:
            return nil
        case .name:
            return groupedCards.first { $0.title == letter }?.id
        case .organization:
            return groupedCards.first {
                pinyinInitial(forSortKey: $0.sortKey) == letter
            }?.id
        }
    }

    private var listRows: [HolderListRow] {
        let validListIDs = Set(cardLists.map(\.id))
        let sortedLists = cardLists.sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.createdAt < $1.createdAt
            }
            return $0.sortOrder < $1.sortOrder
        }
        let assignedRows = sortedLists.map { list in
            let assignedCards = cards
                .filter { $0.cardListID == list.id }
                .sorted { $0.createdAt > $1.createdAt }
            return HolderListRow(
                id: list.id.uuidString,
                listID: list.id,
                title: "\(list.name)（\(assignedCards.count)）",
                cards: assignedCards,
                isUncategorized: false
            )
        }
        let uncategorizedCards = cards
            .filter { card in
                guard let cardListID = card.cardListID else { return true }
                return !validListIDs.contains(cardListID)
            }
            .sorted { $0.createdAt > $1.createdAt }

        return assignedRows + [
            HolderListRow(
                id: "uncategorized",
                listID: nil,
                title: "未分类（\(uncategorizedCards.count)）",
                cards: uncategorizedCards,
                isUncategorized: true
            )
        ]
    }

    private func cardsForList(_ row: HolderListRow) -> [BusinessCard] {
        row.cards
    }

    private func listRowID(for card: BusinessCard) -> String {
        let validListIDs = Set(cardLists.map(\.id))
        guard let cardListID = card.cardListID, validListIDs.contains(cardListID) else {
            return "uncategorized"
        }

        return cardListID.uuidString
    }

    private func collapseSourceListIfNeeded(for card: BusinessCard) {
        let sourceRowID = listRowID(for: card)
        guard expandedListID == sourceRowID else { return }
        collapsedDragSourceListID = sourceRowID
        collapsedDragSourceCardID = card.id
        collapsedDragSourceScrollOffsetY = listScrollOffsetY

        withAnimation(.snappy(duration: 0.24)) {
            expandedCardID = nil
            isContextMenuVisible = false
            listContextMenuListID = nil
            dropTargetListRowID = nil
            expandedListID = nil
        }

        listScrollRequest = ListScrollRequest(target: .row(sourceRowID), delay: 0.28)
    }

    private func restoreCollapsedSourceListAfterMissedDrop(with payloads: [String]) -> Bool {
        guard
            dropTargetListRowID == nil,
            let draggingListCardID,
            payloads.contains(draggingListCardID.uuidString)
        else {
            return false
        }

        restoreCollapsedDragSourceListIfNeeded()
        return true
    }

    private func restoreCollapsedDragSourceListIfNeeded() {
        guard let sourceRowID = collapsedDragSourceListID else {
            clearListDragTracking()
            return
        }
        let sourceScrollOffsetY = collapsedDragSourceScrollOffsetY
        ignoreListRowGesturesDuringDropSettle()

        withAnimation(.snappy(duration: 0.28)) {
            expandedCardID = nil
            isContextMenuVisible = false
            listContextMenuListID = nil
            dropTargetListRowID = nil
            expandedListID = sourceRowID
        }

        draggingListCardID = nil
        collapsedDragSourceListID = nil
        collapsedDragSourceCardID = nil
        collapsedDragSourceScrollOffsetY = nil
        dropTargetListRowID = nil
        listScrollRequest = ListScrollRequest(
            target: sourceScrollOffsetY.map(ListScrollTarget.offset) ?? .row(sourceRowID),
            delay: 0.34
        )
    }

    private func clearListDragStateAfterSuccessfulMove() {
        ignoreListRowGesturesDuringDropSettle()
        clearListDragTracking()
    }

    private func clearListDragTracking() {
        draggingListCardID = nil
        collapsedDragSourceListID = nil
        collapsedDragSourceCardID = nil
        collapsedDragSourceScrollOffsetY = nil
        dropTargetListRowID = nil
        listScrollRequest = nil
    }

    private func shouldIgnoreListRowGesture() -> Bool {
        Date() < ignoreListRowGesturesUntil
    }

    private func ignoreListRowGesturesDuringDropSettle() {
        ignoreListRowGesturesUntil = Date().addingTimeInterval(0.75)
    }

    private func finishListDragIfStillActive(cardID: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard draggingListCardID == cardID else { return }
            restoreCollapsedDragSourceListIfNeeded()
        }
    }

    private func groupTitleFont(for title: String) -> Font {
        title.unicodeScalars.allSatisfy { $0.isASCII }
            ? CardaTheme.sfPro(size: 15, weight: .regular)
            : CardaTheme.pingFang(size: 15, weight: .regular)
    }

    private func saveExpandedCard(_ card: BusinessCard) {
        let ok = CardImageExporter.savePNG(for: card.renderData)
        withAnimation {
            saveMessage = ok ? "已保存为图片" : "保存失败"
            isContextMenuVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation {
                saveMessage = nil
            }
        }
    }

    private func commit(_ draft: BusinessCardDraft) {
        let card = BusinessCard(draft: draft)
        modelContext.insert(card)

        do {
            try modelContext.save()
        } catch {
            saveMessage = "保存失败"
        }
    }

    private func toggleListRow(_ row: HolderListRow, scrollProxy: ScrollViewProxy) {
        clearListDragTracking()
        let isCollapsing = expandedListID == row.id

        withAnimation(.snappy(duration: 0.28)) {
            expandedCardID = nil
            isContextMenuVisible = false
            listContextMenuListID = nil
            expandedListID = isCollapsing ? nil : row.id
        }

        if isCollapsing {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                withAnimation(.snappy(duration: 0.28)) {
                    scrollProxy.scrollTo(row.id, anchor: .top)
                }
            }
        }
    }

    private func presentListContextMenu(for row: HolderListRow) {
        guard let listID = row.listID else { return }
        clearListDragTracking()

        withAnimation(.snappy(duration: 0.24)) {
            expandedCardID = nil
            isContextMenuVisible = false
            listContextMenuListID = listID
        }
    }

    private func moveDraggedCard(with payloads: [String], to row: HolderListRow) -> Bool {
        guard
            let cardID = payloads.compactMap({ UUID(uuidString: $0) }).first,
            let card = cards.first(where: { $0.id == cardID })
        else {
            restoreCollapsedDragSourceListIfNeeded()
            return false
        }

        return move(card, to: row)
    }

    private func move(_ card: BusinessCard, to row: HolderListRow) -> Bool {
        let sourceListID = card.cardListID
        let targetListID = row.listID
        let sourceRowID = listRowID(for: card)
        let sourceRemainingCount = (listRows.first { $0.id == sourceRowID }?.cards.count ?? 1) - 1
        dropTargetListRowID = nil

        guard sourceListID != targetListID else {
            restoreCollapsedDragSourceListIfNeeded()
            return true
        }

        let now = Date()
        let affectedListIDs = Set([sourceListID, targetListID].compactMap { $0 })

        withAnimation(.snappy(duration: 0.24)) {
            expandedCardID = nil
            isContextMenuVisible = false
            listContextMenuListID = nil
            card.cardListID = targetListID
            card.updatedAt = now

            if expandedListID == sourceRowID && sourceRemainingCount <= 0 {
                expandedListID = nil
            }
        }

        for list in cardLists where affectedListIDs.contains(list.id) {
            list.updatedAt = now
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            saveMessage = "移动失败"
            restoreCollapsedDragSourceListIfNeeded()
            return true
        }

        clearListDragStateAfterSuccessfulMove()
        return true
    }
}

private struct HolderListRow: Identifiable {
    let id: String
    let listID: UUID?
    let title: String
    let cards: [BusinessCard]
    let isUncategorized: Bool
}

private struct ListScrollRequest: Equatable {
    let id = UUID()
    let target: ListScrollTarget
    var delay: TimeInterval = 0
}

private enum ListScrollTarget: Equatable {
    case row(String)
    case offset(CGFloat)
}

private struct ListCardDragSource: UIViewRepresentable {
    let data: CardRenderData
    let onTap: () -> Void
    let onDragBegan: () -> Void
    let onDragEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            data: data,
            onTap: onTap,
            onDragBegan: onDragBegan,
            onDragEnded: onDragEnded
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap)
        )
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)

        let dragInteraction = UIDragInteraction(delegate: context.coordinator)
        dragInteraction.isEnabled = true
        view.addInteraction(dragInteraction)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.data = data
        context.coordinator.onTap = onTap
        context.coordinator.onDragBegan = onDragBegan
        context.coordinator.onDragEnded = onDragEnded
    }

    final class Coordinator: NSObject, UIDragInteractionDelegate {
        var data: CardRenderData
        var onTap: () -> Void
        var onDragBegan: () -> Void
        var onDragEnded: () -> Void

        init(
            data: CardRenderData,
            onTap: @escaping () -> Void,
            onDragBegan: @escaping () -> Void,
            onDragEnded: @escaping () -> Void
        ) {
            self.data = data
            self.onTap = onTap
            self.onDragBegan = onDragBegan
            self.onDragEnded = onDragEnded
        }

        @objc func handleTap() {
            onTap()
        }

        func dragInteraction(
            _ interaction: UIDragInteraction,
            itemsForBeginning session: UIDragSession
        ) -> [UIDragItem] {
            onDragBegan()

            let itemProvider = NSItemProvider(object: data.id.uuidString as NSString)
            let item = UIDragItem(itemProvider: itemProvider)
            item.localObject = data.id
            item.previewProvider = { [data] in
                UIDragPreview(view: Self.previewView(for: data))
            }
            return [item]
        }

        func dragInteraction(
            _ interaction: UIDragInteraction,
            session: UIDragSession,
            didEndWith operation: UIDropOperation
        ) {
            onDragEnded()
        }

        private static func previewView(for data: CardRenderData) -> UIView {
            let preview = UIView(frame: CGRect(x: 0, y: 0, width: 370, height: 60))
            preview.backgroundColor = .white
            preview.layer.cornerRadius = 30
            preview.layer.cornerCurve = .circular
            preview.clipsToBounds = true

            let organizationLabel = UILabel(frame: CGRect(x: 25, y: 5.5, width: 220, height: 20))
            organizationLabel.text = data.displayOrganizationName
            organizationLabel.textColor = UIColor.black.withAlphaComponent(0.5)
            organizationLabel.font = UIFont.systemFont(ofSize: 15, weight: .regular)
            organizationLabel.lineBreakMode = .byTruncatingTail

            let nameLabel = UILabel(frame: CGRect(x: 25, y: 30.5, width: 220, height: 22))
            nameLabel.text = data.displayName
            nameLabel.textColor = .black
            nameLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
            nameLabel.lineBreakMode = .byTruncatingTail

            preview.addSubview(organizationLabel)
            preview.addSubview(nameLabel)
            return preview
        }
    }
}

private struct HolderPanelShape: Shape {
    let mode: HolderMode

    private let bodyTop: CGFloat = 38
    private let circularCornerRadius: CGFloat = 20

    func path(in rect: CGRect) -> Path {
        let minX = rect.minX
        let maxX = rect.maxX
        let top = rect.minY
        let bodyY = rect.minY + bodyTop
        let bottom = rect.maxY
        let tab = selectedTabFrame(in: rect)
        let radius = min(circularCornerRadius, bodyTop / 2, tab.width / 2)

        var path = Path()
        path.move(to: CGPoint(x: minX, y: bottom))

        switch mode {
        case .list:
            path.addLine(to: CGPoint(x: minX, y: top + radius))
            path.addCircularCorner(
                via: CGPoint(x: minX, y: top),
                to: CGPoint(x: minX + radius, y: top),
                radius: radius
            )
            path.addLine(to: CGPoint(x: tab.maxX - radius, y: top))
            path.addCircularCorner(
                via: CGPoint(x: tab.maxX, y: top),
                to: CGPoint(x: tab.maxX, y: top + radius),
                radius: radius
            )
            path.addLine(to: CGPoint(x: tab.maxX, y: bodyY - radius))
            path.addCircularCorner(
                via: CGPoint(x: tab.maxX, y: bodyY),
                to: CGPoint(x: tab.maxX + radius, y: bodyY),
                radius: radius
            )

        case .name:
            path.addLine(to: CGPoint(x: minX, y: bodyY + radius))
            path.addCircularCorner(
                via: CGPoint(x: minX, y: bodyY),
                to: CGPoint(x: minX + radius, y: bodyY),
                radius: radius
            )
            path.addLine(to: CGPoint(x: tab.minX - radius, y: bodyY))
            path.addCircularCorner(
                via: CGPoint(x: tab.minX, y: bodyY),
                to: CGPoint(x: tab.minX, y: bodyY - radius),
                radius: radius
            )
            path.addLine(to: CGPoint(x: tab.minX, y: top + radius))
            path.addCircularCorner(
                via: CGPoint(x: tab.minX, y: top),
                to: CGPoint(x: tab.minX + radius, y: top),
                radius: radius
            )
            path.addLine(to: CGPoint(x: tab.maxX - radius, y: top))
            path.addCircularCorner(
                via: CGPoint(x: tab.maxX, y: top),
                to: CGPoint(x: tab.maxX, y: top + radius),
                radius: radius
            )
            path.addLine(to: CGPoint(x: tab.maxX, y: bodyY - radius))
            path.addCircularCorner(
                via: CGPoint(x: tab.maxX, y: bodyY),
                to: CGPoint(x: tab.maxX + radius, y: bodyY),
                radius: radius
            )

        case .organization:
            path.addLine(to: CGPoint(x: minX, y: bodyY + radius))
            path.addCircularCorner(
                via: CGPoint(x: minX, y: bodyY),
                to: CGPoint(x: minX + radius, y: bodyY),
                radius: radius
            )
            path.addLine(to: CGPoint(x: tab.minX - radius, y: bodyY))
            path.addCircularCorner(
                via: CGPoint(x: tab.minX, y: bodyY),
                to: CGPoint(x: tab.minX, y: bodyY - radius),
                radius: radius
            )
            path.addLine(to: CGPoint(x: tab.minX, y: top + radius))
            path.addCircularCorner(
                via: CGPoint(x: tab.minX, y: top),
                to: CGPoint(x: tab.minX + radius, y: top),
                radius: radius
            )
            path.addLine(to: CGPoint(x: maxX - radius, y: top))
            path.addCircularCorner(
                via: CGPoint(x: maxX, y: top),
                to: CGPoint(x: maxX, y: top + radius),
                radius: radius
            )
            path.addLine(to: CGPoint(x: maxX, y: bottom))
            path.closeSubpath()
            return path
        }

        path.addLine(to: CGPoint(x: maxX - radius, y: bodyY))
        path.addCircularCorner(
            via: CGPoint(x: maxX, y: bodyY),
            to: CGPoint(x: maxX, y: bodyY + radius),
            radius: radius
        )
        path.addLine(to: CGPoint(x: maxX, y: bottom))
        path.closeSubpath()
        return path
    }

    private func selectedTabFrame(in rect: CGRect) -> CGRect {
        let designX: CGFloat
        switch mode {
        case .list:
            designX = 0
        case .name:
            designX = 134
        case .organization:
            designX = 268
        }

        return CGRect(
            x: rect.minX + designX,
            y: rect.minY,
            width: 134,
            height: bodyTop
        )
    }
}

private extension Path {
    mutating func addCircularCorner(via corner: CGPoint, to end: CGPoint, radius: CGFloat) {
        guard radius > 0 else {
            addLine(to: corner)
            addLine(to: end)
            return
        }

        addArc(tangent1End: corner, tangent2End: end, radius: radius)
    }
}

private struct HolderModeTabShape: Shape {
    enum Style {
        case edgeTailRight
        case edgeTailLeft
        case middleTailRight
        case middleTailLeft
    }

    let style: Style

    func path(in rect: CGRect) -> Path {
        switch style {
        case .edgeTailRight:
            return edgePath(in: rect, mirrored: false)
        case .edgeTailLeft:
            return edgePath(in: rect, mirrored: true)
        case .middleTailRight:
            return middlePath(in: rect, mirrored: false)
        case .middleTailLeft:
            return middlePath(in: rect, mirrored: true)
        }
    }

    private func edgePath(in rect: CGRect, mirrored: Bool) -> Path {
        let sourceWidth: CGFloat = 130
        let sourceHeight: CGFloat = 44.9883
        let sx = rect.width / sourceWidth
        let sy = rect.height / sourceHeight

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let adjustedX = mirrored ? sourceWidth - x : x
            return CGPoint(x: rect.minX + adjustedX * sx, y: rect.minY + y * sy)
        }

        var path = Path()
        path.move(to: point(130, 44.9883))
        path.addCurve(
            to: point(112.774, 36),
            control1: point(126.204, 39.555),
            control2: point(119.905, 36)
        )
        path.addCurve(
            to: point(112, 36.0166),
            control1: point(112.515, 36),
            control2: point(112.257, 36.0073)
        )
        path.addLine(to: point(112, 36))
        path.addLine(to: point(18, 36))
        path.addCurve(
            to: point(0, 18),
            control1: point(8.05887, 36),
            control2: point(0, 27.9411)
        )
        path.addCurve(
            to: point(18, 0),
            control1: point(0, 8.05888),
            control2: point(8.05888, 0)
        )
        path.addLine(to: point(112, 0))
        path.addCurve(
            to: point(130, 18),
            control1: point(121.941, 0),
            control2: point(130, 8.05887)
        )
        path.addLine(to: point(130, 44.9883))
        path.closeSubpath()
        return path
    }

    private func middlePath(in rect: CGRect, mirrored: Bool) -> Path {
        let sourceWidth: CGFloat = 143.274
        let sourceHeight: CGFloat = 36
        let sx = rect.width / sourceWidth
        let sy = rect.height / sourceHeight

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let adjustedX = mirrored ? sourceWidth - x : x
            return CGPoint(x: rect.minX + adjustedX * sx, y: rect.minY + y * sy)
        }

        var path = Path()
        path.move(to: point(114, 0))
        path.addCurve(
            to: point(132, 18),
            control1: point(123.941, 0),
            control2: point(132, 8.05887)
        )
        path.addCurve(
            to: point(143.274, 36),
            control1: point(132, 25.9173),
            control2: point(136.601, 32.759)
        )
        path.addLine(to: point(18, 36))
        path.addCurve(
            to: point(0, 18),
            control1: point(8.05887, 36),
            control2: point(0, 27.9411)
        )
        path.addCurve(
            to: point(18, 0),
            control1: point(0, 8.05887),
            control2: point(8.05888, 0)
        )
        path.addLine(to: point(114, 0))
        path.closeSubpath()
        return path
    }
}

private enum CardHolderFigmaColor {
    static let pageTint = Color(red: 48 / 255, green: 49 / 255, blue: 54 / 255)
        .opacity(0.06)
    static let panelTint = Color(red: 195 / 255, green: 194 / 255, blue: 200 / 255)
    static let segmentText = Color(red: 24 / 255, green: 25 / 255, blue: 30 / 255)
    static let segmentCompanyText = Color(red: 48 / 255, green: 49 / 255, blue: 54 / 255)
    static let listSeparator = Color(red: 198 / 255, green: 198 / 255, blue: 200 / 255)

    static func panelComposite(opacity: CGFloat) -> Color {
        let alpha = Double(opacity)
        let red = (255 * (1 - alpha) + 195 * alpha) / 255
        let green = (255 * (1 - alpha) + 194 * alpha) / 255
        let blue = (255 * (1 - alpha) + 200 * alpha) / 255
        return Color(red: red, green: green, blue: blue)
    }
}

private struct TemporaryHolderAvatar: View {
    var body: some View {
        Image("TemporaryHolderAvatar")
            .resizable()
            .scaledToFill()
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .accessibilityLabel("临时头像")
    }
}

private struct GroupedHeaderAnchor {
    let title: String
    let bounds: Anchor<CGRect>
}

private struct GroupedHeaderAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [GroupedHeaderAnchor] = []

    static func reduce(
        value: inout [GroupedHeaderAnchor],
        nextValue: () -> [GroupedHeaderAnchor]
    ) {
        value.append(contentsOf: nextValue())
    }
}

private struct GroupedCardSection: Identifiable {
    let title: String
    let cards: [BusinessCard]
    let sortKey: String

    var id: String { title }

    init(title: String, cards: [BusinessCard], sortKey: String? = nil) {
        self.title = title
        self.cards = cards
        self.sortKey = sortKey ?? title
    }
}

private struct GroupedCardSortRecord {
    let card: BusinessCard
    let nameSortKey: String
    let organizationSortKey: String

    init(card: BusinessCard) {
        self.card = card
        self.nameSortKey = pinyinSortKey(for: card.name)
        self.organizationSortKey = pinyinSortKey(for: card.organizationName)
    }
}

private struct AlphabetIndexRequest: Equatable {
    let id = UUID()
    let letter: String
}

private struct ContactAlphabetIndex: View {
    let onSelect: (String) -> Void

    private let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ#").map(String.init)
    private let letterHeight: CGFloat = 13
    private let letterSpacing: CGFloat = 1
    private let indexHeight: CGFloat = 770

    @State private var lastDraggedLetter: String?

    var body: some View {
        VStack(spacing: 1) {
            ForEach(letters, id: \.self) { letter in
                Button {
                    onSelect(letter)
                } label: {
                    Text(letter)
                        .font(CardaTheme.sfPro(size: 11, weight: .semibold))
                        .tracking(0.06)
                        .foregroundStyle(Color.black)
                        .frame(width: 22, height: letterHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("跳转到 \(letter)")
            }
        }
        .frame(width: 22, height: indexHeight, alignment: .center)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    guard let letter = letter(at: value.location.y) else { return }
                    guard letter != lastDraggedLetter else { return }
                    lastDraggedLetter = letter
                    onSelect(letter)
                }
                .onEnded { _ in
                    lastDraggedLetter = nil
                }
        )
    }

    private func letter(at y: CGFloat) -> String? {
        let contentHeight =
            CGFloat(letters.count) * letterHeight
            + CGFloat(letters.count - 1) * letterSpacing
        let contentTop = (indexHeight - contentHeight) / 2
        let relativeY = y - contentTop
        guard relativeY >= 0, relativeY < contentHeight else { return nil }

        let rowHeight = letterHeight + letterSpacing
        let index = min(Int(relativeY / rowHeight), letters.count - 1)
        return letters[index]
    }
}

private func pinyinInitial(forSortKey key: String) -> String {
    guard let scalar = key.unicodeScalars.first, CharacterSet.letters.contains(scalar) else { return "#" }
    return String(Character(scalar)).uppercased()
}

private func pinyinSortKey(for text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "#" }
    let mutable = NSMutableString(string: trimmed) as CFMutableString
    CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
    CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)
    return (mutable as String)
        .uppercased()
        .replacingOccurrences(of: " ", with: "")
}
