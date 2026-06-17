//
//  CardHolderView.swift
//  Carda
//

import Foundation
import SwiftData
import SwiftUI

private enum HolderMode: String, CaseIterable, Identifiable {
    case list = "列表"
    case name = "姓名"
    case organization = "单位"

    var id: String { rawValue }
}

private enum HolderCardEditorMode: Identifiable {
    case create

    var id: String { "create" }

    var draft: BusinessCardDraft { BusinessCardDraft() }
}

struct CardHolderView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BusinessCard.createdAt) private var allCards: [BusinessCard]
    @Query(sort: \BusinessCardList.sortOrder) private var cardLists: [BusinessCardList]

    let cards: [BusinessCard]
    let accountAvatarImageData: Data?
    let onAddList: () -> Void

    @State private var mode: HolderMode = .name
    @State private var expandedCardID: UUID?
    @State private var expandedListID: String?
    @State private var editorMode: HolderCardEditorMode?
    @State private var isAddSheetPresented = false
    @State private var isContextMenuVisible = false
    @State private var saveMessage: String?
    @State private var alphabetIndexRequest: AlphabetIndexRequest?
    @Namespace private var cardExpansionNamespace

    private let groupedHeaderHeight: CGFloat = 20
    private let groupedHeaderTransitionGap: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                holderBackground

                if cards.isEmpty {
                    emptyState
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                } else {
                    contentForMode
                }

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

                if let saveMessage {
                    Text(saveMessage)
                        .font(CardaTheme.pingFang(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.black.opacity(0.72)))
                        .position(x: proxy.size.width / 2, y: 600)
                        .zIndex(12)
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
        holderBackgroundColor
            .frame(width: CardaTheme.canvasWidth, height: CardaTheme.canvasHeight)
    }

    private var holderBackgroundColor: Color {
        CardaTheme.pageBackground
    }

    private var myCards: [BusinessCard] {
        allCards
            .filter { $0.ownerKind == .mine }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var topModeBar: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(holderBackgroundColor)
                .frame(width: CardaTheme.canvasWidth, height: 160)

            Text("名片夹")
                .font(CardaTheme.pingFang(size: 22, weight: .semibold))
                .foregroundStyle(CardaTheme.primaryText)
                .lineLimit(1)
                .frame(width: 80, height: 28, alignment: .center)
                .position(x: CardaTheme.canvasWidth / 2, y: 90)

            if mode == .list {
                listToolbarButton(title: "编辑", width: 72, textLeading: 19, action: {})
                    .position(x: 52, y: 90)

                listToolbarButton(
                    title: "添加列表",
                    width: 112,
                    textLeading: 21.5,
                    action: onAddList
                )
                    .position(x: 330, y: 90)
            } else {
                UserAvatarButton(imageData: accountAvatarImageData) {
                    guard !myCards.isEmpty else { return }
                    isAddSheetPresented = true
                }
                    .position(x: 364, y: 89)
            }

            categoryButton(.list, x: 56)
            categoryButton(.name, x: CardaTheme.canvasWidth / 2)
            categoryButton(.organization, x: 346)

            Rectangle()
                .fill(Color(red: 217 / 255, green: 217 / 255, blue: 217 / 255))
                .frame(width: CardaTheme.canvasWidth, height: 1)
                .offset(y: 159)

            Rectangle()
                .fill(Color.black)
                .frame(width: 26, height: 1)
                .offset(x: selectedUnderlineLeft, y: 159)
        }
        .frame(width: CardaTheme.canvasWidth, height: 160, alignment: .topLeading)
    }

    private func categoryButton(_ item: HolderMode, x: CGFloat) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.28)) {
                mode = item
                expandedCardID = nil
                expandedListID = nil
                isContextMenuVisible = false
            }
        } label: {
            Text(item.rawValue)
                .font(CardaTheme.pingFang(size: 15, weight: .regular))
                .foregroundStyle(mode == item ? Color.black : Color.black.opacity(0.5))
                .lineLimit(1)
                .frame(width: 46, height: 20, alignment: .center)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(x: x, y: 147)
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
                        CardaTheme.canvasHeight - 160 - 95 - groupedHeaderHeight
                    )
                }
                .frame(
                    width: CardaTheme.canvasWidth,
                    height: CardaTheme.canvasHeight - 160 - 95,
                    alignment: .top
                )
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear
                        .frame(height: 12)
                        .allowsHitTesting(false)
                }
                .offset(y: 160)
                .scrollIndicators(.hidden)

                TransparentGradientBlur(
                    height: 63.255,
                    direction: .top
                )
                .offset(y: 160)
                .zIndex(1)

                TransparentGradientBlur(height: 140)
                    .offset(y: 734)
                    .zIndex(1)
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
                            }
                        }
                )
                .onTapGesture {
                    withAnimation(.snappy(duration: 0.32)) {
                        expandedCardID = nil
                        isContextMenuVisible = false
                    }
                }
                .frame(width: CardaTheme.canvasWidth, alignment: .center)
        } else {
            CollapsedCardRow(data: card.renderData, namespace: cardExpansionNamespace)
                .onTapGesture {
                    withAnimation(.snappy(duration: 0.36)) {
                        expandedCardID = card.id
                        isContextMenuVisible = false
                    }
                }
                .frame(width: CardaTheme.canvasWidth, alignment: .center)
        }
    }

    private var listModeContent: some View {
        ScrollViewReader { scrollProxy in
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
                .padding(.top, 27)
                .padding(.bottom, 160)
            }
            .frame(
                width: CardaTheme.canvasWidth,
                height: CardaTheme.canvasHeight - 160 - 95,
                alignment: .top
            )
            .offset(y: 160)
            .scrollIndicators(.hidden)
        }
    }

    private func expandedListCards(_ row: HolderListRow) -> some View {
        let isExpanded = expandedListID == row.id

        return VStack(spacing: 8) {
            ForEach(cardsForList(row)) { card in
                cardRowOrExpanded(card)
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
        Button {
            let isCollapsing = expandedListID == row.id

            withAnimation(.snappy(duration: 0.28)) {
                expandedCardID = nil
                isContextMenuVisible = false
                expandedListID = isCollapsing ? nil : row.id
            }

            if isCollapsing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                    withAnimation(.snappy(duration: 0.28)) {
                        scrollProxy.scrollTo(row.id, anchor: .top)
                    }
                }
            }
        } label: {
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
                        .fill(Color(red: 0.9, green: 0.9, blue: 0.9))
                        .frame(height: 1)
                        .padding(.horizontal, 16)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 19)
        .frame(width: CardaTheme.canvasWidth, height: 53, alignment: .leading)
        .background(holderBackgroundColor)
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

    private var selectedUnderlineLeft: CGFloat {
        switch mode {
        case .list:
            43
        case .name:
            188
        case .organization:
            333
        }
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
                record.card.organizationName.isEmpty ? "未命名单位" : record.card.organizationName
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
                title: "未分类（\(uncategorizedCards.count)）",
                cards: uncategorizedCards,
                isUncategorized: true
            )
        ]
    }

    private func cardsForList(_ row: HolderListRow) -> [BusinessCard] {
        row.cards
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
}

private struct HolderListRow: Identifiable {
    let id: String
    let title: String
    let cards: [BusinessCard]
    let isUncategorized: Bool
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
