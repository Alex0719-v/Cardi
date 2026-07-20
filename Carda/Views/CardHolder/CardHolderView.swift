//
//  CardHolderView.swift
//  Cardi
//

import Foundation
import Observation
import SwiftData
import SwiftUI
import UIKit

enum HolderMode: String, CaseIterable, Identifiable {
    case list = "列表"
    case name = "姓名"
    case organization = "公司"

    var id: String { rawValue }
}

@Observable
final class CardHolderHeaderCollapseState {
    var offset: CGFloat = 0
}

private enum HolderCardEditorMode: Identifiable {
    case create

    var id: String { "create" }

    var draft: BusinessCardDraft { BusinessCardDraft() }
}

private enum HolderScrollSource: Equatable {
    case grouped
    case list
}

private enum HolderHeaderScrollDirection: Equatable {
    case collapsing
    case expanding
}

private struct HolderScrollMetrics: Equatable {
    let offsetY: CGFloat
    let maximumOffsetY: CGFloat
}

struct CardHolderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.cardaReduceMotion) private var settingsReduceMotion
    @Query(sort: \BusinessCardList.sortOrder) private var cardLists: [BusinessCardList]
    @AppStorage(CardaSettingsPreferenceKeys.confirmsCardDeletion)
    private var confirmsCardDeletion = true

    let cards: [BusinessCard]
    let accountAvatarImageData: Data?
    let accountName: String?
    let accountPhoneNumber: String?
    let accountEmail: String?
    let isAccountLoggedIn: Bool
    let onUpdateAccount: (Data?, String, String, String) -> Bool
    let onLogout: () -> Bool
    let onAddList: () -> Void
    let onRenameList: (BusinessCardList) -> Void
    let onDeleteList: (BusinessCardList) -> Void
    let onInfoAction: (CardFieldKind, String) -> Void
    @Binding var mode: HolderMode
    let headerCollapseState: CardHolderHeaderCollapseState
    var showsPageBackground = true

    private var accessibilityReduceMotion: Bool {
        systemReduceMotion || settingsReduceMotion
    }

    @State private var expandedCardID: UUID?
    @State private var expandedListID: String?
    @State private var editorMode: HolderCardEditorMode?
    @State private var isAddSheetPresented = false
    @State private var isContextMenuVisible = false
    @State private var contextMenuCardID: UUID?
    @State private var geometryFrameStore = HolderGeometryFrameStore()
    @State private var contextMenuDragStartOffsetY: CGFloat?
    @State private var contextMenuDragDismissProgress: CGFloat = 0
    @State private var listContextMenuListID: UUID?
    @State private var listContextMenuRowID: String?
    @State private var dropTargetListRowID: String?
    @State private var draggingListCardID: UUID?
    @State private var collapsedDragSourceListID: String?
    @State private var collapsedDragSourceCardID: UUID?
    @State private var collapsedDragSourceScrollOffsetY: CGFloat?
    @State private var listScrollRequest: ListScrollRequest?
    @State private var listScrollPosition = ScrollPosition()
    @State private var groupedScrollPosition = ScrollPosition()
    @State private var scrollRuntime = HolderScrollRuntime()
    @State private var derivedDataCache = HolderDerivedDataCache()
    @State private var ignoreListRowGesturesUntil = Date.distantPast
    @State private var saveMessage: String?
    @State private var cardPendingDeletionID: UUID?
    @State private var revealedDeleteCardID: UUID?
    @State private var alphabetIndexRequest: AlphabetIndexRequest?
    @State private var retainedGroupedHeaderTitle: String?
    @State private var delayedGroupedHeaderTitles: Set<String> = []
    @State private var groupedHeaderTransitionGeneration = 0
    @State private var modeInteractionGeneration = 0
    @State private var groupedHeaderTransitionActive = false
    @State private var suppressGroupedContentAnimation = false
    @State private var headerMorphProgress: CGFloat = 0
    @State private var headerLeftControlProgress: CGFloat = 0
    @State private var headerRightLabelRevealProgress: CGFloat = 0
    @State private var headerMorphGeneration = 0
    @State private var isHeaderModeTransitioning = false
    @State private var isMultiSelecting = false
    @State private var selectedCardIDs: Set<UUID> = []
    private let groupedHeaderHeight: CGFloat = 20
    private let groupedHeaderTransitionGap: CGFloat = 10
    private let groupedHeaderTopInset: CGFloat = 24
    private let holderPanelTop: CGFloat = 126
    private let holderContentTop: CGFloat = 164
    private let holderCollapsedContentTop: CGFloat = 54
    private let holderHeaderClipTop: CGFloat = 62
    private let holderTopCardMaskTop: CGFloat = 178
    private let holderTopCardMaskHeight: CGFloat = 47
    private let holderTopCardMaskHorizontalInset: CGFloat = 16
    private let holderBottomSoftEdgeTop: CGFloat = 737
    private let holderBottomSoftEdgeHeight: CGFloat = 140
    private let listContextMenuHeight: CGFloat = 104
    private let listContextMenuGap: CGFloat = 8
    private let listStickyHeaderExpandedMaskHeight: CGFloat = 33
    private let listStickyHeaderClipInsetHeight: CGFloat = 12
    private let listStickyHeaderPinInsetHeight: CGFloat = 7
    private let listStickyHeaderRowHeight: CGFloat = 53
    private let headerMorphDuration: TimeInterval = 0.56
    // The forward cubic reaches 50% of its spatial presentation at
    // 0.137945 of the duration. Reveal starts at that exact halfway shape.
    private let headerLabelRevealDelay: TimeInterval = 0.07725
    private let headerLabelRevealDuration: TimeInterval = 0.58275
    private static let holderCoordinateSpaceName = "CardHolderCoordinateSpace"

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if showsPageBackground {
                    holderBackground
                    holderPanelBackground
                }

                if cards.isEmpty {
                    emptyState
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        .zIndex(1)
                } else {
                    contentForMode
                        .zIndex(1)
                }

                if !cards.isEmpty {
                    holderBottomSoftEdge
                        .zIndex(5)
                }

                collapsibleTopModeBar
                    .zIndex(9)

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
                            dismissCardContextMenu()
                        }
                        .gesture(cardContextMenuScrollGesture)
                        .zIndex(10)

                    if let card = contextMenuCard {
                        ContextActionMenu(actions: [
                            ContextAction(title: "分享名片") {},
                            ContextAction(title: "保存为图片") {
                                saveExpandedCard(card)
                            }
                        ])
                        .frame(width: 250)
                        .position(
                            x: proxy.size.width / 2,
                            y: cardContextMenuCenterY
                        )
                        .scaleEffect(
                            1 - contextMenuDragDismissProgress * 0.04,
                            anchor: .top
                        )
                        .opacity(1 - contextMenuDragDismissProgress)
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
                                listContextMenuRowID = nil
                            }
                        }
                        .zIndex(12)

                    ContextActionMenu(actions: [
                        ContextAction(title: "修改列表名称") {
                            withAnimation(.snappy(duration: 0.18)) {
                                listContextMenuListID = nil
                                listContextMenuRowID = nil
                            }
                            onRenameList(list)
                        },
                        ContextAction(title: "删除列表", role: .destructive) {
                            withAnimation(.snappy(duration: 0.18)) {
                                listContextMenuListID = nil
                                listContextMenuRowID = nil
                                if expandedListID == list.id.uuidString {
                                    expandedListID = nil
                                    expandedCardID = nil
                                }
                            }
                            onDeleteList(list)
                        }
                    ])
                    .frame(width: 250)
                    .position(
                        x: proxy.size.width / 2,
                        y: listContextMenuCenterY
                    )
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
            .coordinateSpace(name: Self.holderCoordinateSpaceName)
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
                commit(draft)
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
            Button("删除", role: .destructive) {
                deletePendingCard()
            }
            Button("取消", role: .cancel) {
                cardPendingDeletionID = nil
            }
        } message: {
            Text("删除后无法恢复。")
        }
        .onAppear {
            resetHeaderTrackingForModeChange()
            setHeaderCollapseOffset(0, animated: false)
        }
        .onChange(of: expandedCardID) { _, _ in
            withAnimation(.snappy(duration: 0.22)) {
                revealedDeleteCardID = nil
            }
        }
        .onChange(of: expandedListID) { _, newExpandedListID in
            withAnimation(.snappy(duration: 0.22)) {
                revealedDeleteCardID = nil
            }

            guard mode == .list, newExpandedListID == nil else { return }
            resetHeaderDirectionTracking()
            setHeaderCollapseOffset(0, animated: !accessibilityReduceMotion)
        }
        .onChange(of: cards.isEmpty) { _, isEmpty in
            guard isEmpty else { return }
            exitMultiSelection()
            setHeaderCollapseOffset(0, animated: !accessibilityReduceMotion)
        }
        .onChange(of: cards.map(\.id)) { _, cardIDs in
            selectedCardIDs.formIntersection(cardIDs)
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
            .fill(CardaTheme.searchBackground)
            .frame(
                width: CardaTheme.canvasWidth,
                height: mode == .list ? 821 : 811,
                alignment: .top
            )
            .offset(y: currentHolderPanelTop)
    }

    private var holderPinnedBackgroundColor: Color {
        CardaTheme.searchBackground
    }

    private var holderPageBackgroundColor: Color {
        Color(red: 243 / 255, green: 243 / 255, blue: 243 / 255)
    }

    private var holderScrollHeight: CGFloat {
        CardaTheme.canvasHeight - holderCollapsedContentTop
    }

    private var listStickyHeaderMaskTravel: CGFloat {
        listStickyHeaderExpandedMaskHeight - listStickyHeaderPinInsetHeight
    }

    private var headerCollapseDistance: CGFloat {
        holderContentTop - holderCollapsedContentTop
    }

    private var clampedHeaderCollapseOffset: CGFloat {
        min(max(headerCollapseState.offset, 0), headerCollapseDistance)
    }

    private var currentHolderPanelTop: CGFloat {
        holderPanelTop - clampedHeaderCollapseOffset
    }

    private var currentHolderContentTop: CGFloat {
        holderContentTop - clampedHeaderCollapseOffset
    }

    private var currentHolderTopCardMaskTop: CGFloat {
        currentHolderContentTop + (holderTopCardMaskTop - holderContentTop)
    }

    private var currentGroupedHeaderPinTop: CGFloat {
        currentHolderContentTop + groupedHeaderTopInset
    }

    private var collapsibleTopModeBar: some View {
        topModeBar
            .modifier(
                CardHolderHeaderChromeModifier(
                    collapseState: headerCollapseState,
                    maximumOffset: headerCollapseDistance,
                    clipTop: holderHeaderClipTop
                )
            )
    }

    private var topModeBar: some View {
        ZStack(alignment: .topLeading) {
            morphingHolderTitle
            morphingHeaderActionControls

            holderModeTabs
        }
        .frame(width: CardaTheme.canvasWidth, height: 171, alignment: .topLeading)
        .onAppear {
            synchronizeHeaderMorphState()
        }
        .onChange(of: mode) { oldMode, newMode in
            guard (oldMode == .list) != (newMode == .list) else { return }
            animateHeaderTransition(to: newMode)
        }
    }

    private var morphingHolderTitle: some View {
        let progress = clampedHeaderMorphProgress
        let groupedScale: CGFloat = 1
        let listScale: CGFloat = 22 / 34

        return Text("名片夹")
            .font(CardaTheme.pingFang(size: 34, weight: .semibold))
            .tracking(0.4 * Double(1 - progress))
            .foregroundStyle(Color.black)
            .lineLimit(1)
            .fixedSize()
            .scaleEffect(
                groupedScale + (listScale - groupedScale) * progress
            )
            .position(
                x: 67 + (CardaTheme.canvasWidth / 2 - 67) * progress,
                y: 82.5 + (88 - 82.5) * progress
            )
            .modifier(headerTextOpacityModifier)
    }

    private var morphingHeaderActionControls: some View {
        headerActionControls
    }

    private var headerActionControls: some View {
        ZStack(alignment: .topLeading) {
            morphingLeftListControl
            morphingAvatarListControl
        }
        .frame(width: CardaTheme.canvasWidth, height: 116, alignment: .topLeading)
    }

    private var morphingLeftListControl: some View {
        let progress = min(max(headerLeftControlProgress, 0), 1)

        return Button {
            if isMultiSelecting {
                exitMultiSelection()
            } else {
                enterMultiSelection()
            }
        } label: {
            ZStack {
                FigmaGlassShape(cornerRadius: 296, interactive: true)

                Text(isMultiSelecting ? "退出" : "多选")
                    .font(CardaTheme.pingFang(size: 17, weight: .medium))
                    .foregroundStyle(Color.black)
                    .lineLimit(1)
                    .blur(radius: 15 * (1 - progress))
                    .opacity(Double(progress))
                    .modifier(headerTextOpacityModifier)
            }
            .frame(width: 72, height: 46)
            .scaleEffect(max(progress, 0.001))
            .opacity(Double(min(progress * 3, 1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .position(x: 52, y: 88)
        .allowsHitTesting(mode == .list && !isHeaderModeTransitioning)
        .accessibilityHidden(isHeaderModeTransitioning || mode != .list)
    }

    private var morphingAvatarListControl: some View {
        let progress = clampedHeaderMorphProgress
        let width = 44 + (112 - 44) * progress
        let height = 44 + (46 - 44) * progress
        let cornerRadius = 22 + progress
        let hasAvatarImage = isAccountLoggedIn && accountAvatarImageData != nil

        return Button {
            guard !isHeaderModeTransitioning else { return }
            if mode == .list {
                if isMultiSelecting {
                    cancelCardSelection()
                } else {
                    onAddList()
                }
            } else {
                isAddSheetPresented = true
            }
        } label: {
            AccountAvatarGlassSurface(
                width: width,
                height: height,
                cornerRadius: cornerRadius,
                interactive: true
            )
            .opacity(hasAvatarImage ? Double(min(progress * 2, 1)) : 1)
            .overlay {
                if hasAvatarImage {
                    DataImageView(data: accountAvatarImageData)
                        .frame(width: width, height: height)
                        .modifier(
                            CardHolderAvatarMorphModifier(progress: progress)
                        )
                        .frame(width: width, height: height)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: cornerRadius,
                                style: .circular
                            )
                        )
                }
            }
            .overlay {
                MorphingCardHolderListLabel(
                    text: isMultiSelecting ? "取消选择" : "添加列表",
                    spreadProgress: progress,
                    revealProgress: headerRightLabelRevealProgress
                )
                .modifier(headerTextOpacityModifier)
            }
            .contentShape(
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .circular
                )
            )
        }
        .buttonStyle(.plain)
        .position(
            x: 364 + (330 - 364) * progress,
            y: 84 + (88 - 84) * progress
        )
        .allowsHitTesting(!isHeaderModeTransitioning)
        .accessibilityLabel(
            mode == .list
                ? (isMultiSelecting ? "取消选择" : "添加列表")
                : "用户头像"
        )
        .accessibilityValue(hasAvatarImage ? "已设置头像" : "未设置头像")
        .accessibilityIdentifier("card-holder-morphing-avatar-list-control")
        .accessibilityHidden(isHeaderModeTransitioning)
    }

    private var clampedHeaderMorphProgress: CGFloat {
        min(max(headerMorphProgress, 0), 1)
    }

    private var holderModeTabs: some View {
        ZStack(alignment: .topLeading) {
            if showsPageBackground {
                HolderModeTabsBackground(mode: mode)
                    .zIndex(0)

                AnimatedHolderPanelCapShape(selectionPosition: mode.selectionPosition)
                    .fill(CardaTheme.searchBackground)
                    .frame(width: CardaTheme.canvasWidth, height: 45)
                    .offset(y: holderPanelTop)
                    .zIndex(1)
            } else if mode == .list {
                // List content starts at the Union body edge (y=164), while the
                // unselected Figma tab tails continue to y≈171. Repaint only
                // those white tab silhouettes in the navigation foreground so
                // the sticky header can never cover the 公司/姓名 tab tails.
                HolderModeTabsBackground(mode: mode)
                    .allowsHitTesting(false)
                    .zIndex(1)
            }

            categoryButton(.list, x: 65)
                .zIndex(2)
            categoryButton(.name, x: CardaTheme.canvasWidth / 2)
                .zIndex(2)
            categoryButton(.organization, x: 335)
                .zIndex(2)
        }
    }

    private func categoryButton(_ item: HolderMode, x: CGFloat) -> some View {
        let tabsBackground = HolderModeTabsBackground(mode: mode)
        let hitFrame = tabsBackground.modeTabFrame(for: item)
        let hitShape = tabsBackground.modeTabShape(for: item)

        return Button {
            selectMode(item)
        } label: {
            ZStack(alignment: .topLeading) {
                Color.clear

                Text(item.rawValue)
                    .font(CardaTheme.pingFang(size: 15, weight: .regular))
                    .foregroundStyle(modeTabTextColor(for: item))
                    .lineLimit(1)
                    .frame(width: 46, height: 20, alignment: .center)
                    .position(
                        x: x - hitFrame.x,
                        y: 145 - hitFrame.y
                    )
                    .modifier(headerTextOpacityModifier)
            }
            .frame(
                width: hitFrame.width,
                height: hitFrame.height,
                alignment: .topLeading
            )
            .contentShape(hitShape)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("card-holder-mode-\(item.rawValue)")
        .accessibilityValue(mode == item ? "已选择" : "未选择")
        .position(
            x: hitFrame.x + hitFrame.width / 2,
            y: hitFrame.y + hitFrame.height / 2
        )
    }

    private func modeTabTextColor(for item: HolderMode) -> Color {
        mode == .name && item == .organization
            ? CardHolderFigmaColor.segmentCompanyText
            : CardHolderFigmaColor.segmentText
    }

    private var headerTextOpacityModifier: CardHolderHeaderTextOpacityModifier {
        CardHolderHeaderTextOpacityModifier(
            collapseState: headerCollapseState,
            maximumOffset: headerCollapseDistance
        )
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
        let groupedMode = mode

        return ScrollViewReader { scrollProxy in
            ZStack(alignment: .topLeading) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(groupedCards) { group in
                            Section {
                                VStack(spacing: 8) {
                                    ForEach(group.cards) { card in
                                        cardRowOrExpanded(card)
                                    }
                                }
                                .padding(.top, -12)
                            } header: {
                                trackedGroupTitle(group.title, mode: groupedMode)
                            }
                            .id(group.id)
                        }
                    }
                    .background {
                        scrollPanObserver(source: .grouped)
                    }
                    // Mode changes animate the shared foreground headers, not stale list rows.
                    .transaction { transaction in
                        if suppressGroupedContentAnimation {
                            transaction.animation = nil
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
                        .frame(height: 24 + headerCollapseDistance)
                        .allowsHitTesting(false)
                }
                .mask(alignment: .topLeading) {
                    groupedScrollClipMask
                }
                .offset(y: holderCollapsedContentTop)
                .scrollIndicators(.hidden)
                .scrollPosition($groupedScrollPosition)
                .onScrollGeometryChange(for: HolderScrollMetrics.self) { geometry in
                    holderScrollMetrics(from: geometry)
                } action: { _, metrics in
                    handleScrollMetrics(metrics, source: .grouped)
                }

                holderTopCardGradientMask
            }
            .frame(
                width: CardaTheme.canvasWidth,
                height: CardaTheme.canvasHeight,
                alignment: .topLeading
            )
            .overlayPreferenceValue(GroupedHeaderAnchorPreferenceKey.self) { headers in
                GeometryReader { proxy in
                    let activeHeaders = headers.filter { $0.mode == groupedMode }
                    let frames = activeHeaders.map { proxy[$0.bounds] }
                    let pinnedTitle = resolvedGroupedPinnedHeaderTitle(
                        headers: activeHeaders,
                        frames: frames
                    )

                    ZStack(alignment: .topLeading) {
                        ForEach(Array(activeHeaders.enumerated()), id: \.element.id) { index, header in
                            let frame = frames[index]
                            if header.title != pinnedTitle {
                                groupTitle(header.title)
                                    .position(x: frame.midX, y: frame.midY)
                                    .transition(
                                        groupedHeaderTransitionActive
                                            ? groupedHeaderTransition(for: header.title)
                                            : .identity
                                    )
                            }
                        }

                        if let pinnedTitle {
                            groupTitle(pinnedTitle)
                                .opacity(
                                    groupedPinnedHeaderOpacity(
                                        pinnedTitle: pinnedTitle,
                                        headers: activeHeaders,
                                        frames: frames
                                    )
                                )
                                .position(
                                    x: CardaTheme.canvasWidth / 2,
                                    y: currentGroupedHeaderPinTop
                                        + (groupedHeaderHeight + groupedHeaderTransitionGap) / 2
                                )
                        }

                        PinnedHeaderRetentionObserver(value: pinnedTitle) { title in
                            guard mode == groupedMode else { return }
                            guard retainedGroupedHeaderTitle != title else { return }
                            retainedGroupedHeaderTitle = title
                        }
                    }
                }
                .mask(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        Color.clear
                            .frame(height: currentHolderContentTop)

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
                prepareForProgrammaticScroll()
                scrollProxy.scrollTo(targetID, anchor: .top)
            }
        }
    }

    private func trackedGroupTitle(
        _ title: String,
        mode: HolderMode
    ) -> some View {
        groupTitle(title)
            .anchorPreference(
                key: GroupedHeaderAnchorPreferenceKey.self,
                value: .bounds
            ) {
                [
                    GroupedHeaderAnchor(
                        mode: mode,
                        title: title,
                        bounds: $0
                    )
                ]
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

    private func resolvedGroupedPinnedHeaderTitle(
        headers: [GroupedHeaderAnchor],
        frames: [CGRect]
    ) -> String? {
        if let candidateIndex = frames.indices.last(where: { index in
            frames[index].minY <= currentGroupedHeaderPinTop
        }) {
            return headers[candidateIndex].title
        }

        let groups = groupedCards
        guard
            let retainedGroupedHeaderTitle,
            let retainedGroupIndex = groups.firstIndex(where: {
                $0.title == retainedGroupedHeaderTitle
            })
        else {
            return nil
        }

        if let visibleRetainedIndex = headers.firstIndex(where: {
            $0.title == retainedGroupedHeaderTitle
        }), frames[visibleRetainedIndex].minY > currentGroupedHeaderPinTop {
            guard retainedGroupIndex > groups.startIndex else { return nil }
            return groups[groups.index(before: retainedGroupIndex)].title
        }

        return retainedGroupedHeaderTitle
    }

    private func groupedPinnedHeaderOpacity(
        pinnedTitle: String,
        headers: [GroupedHeaderAnchor],
        frames: [CGRect]
    ) -> Double {
        let orderedTitles = groupedCards.map(\.title)
        guard
            let pinnedIndex = orderedTitles.firstIndex(of: pinnedTitle),
            orderedTitles.indices.contains(pinnedIndex + 1),
            let nextHeaderIndex = headers.firstIndex(where: {
                $0.title == orderedTitles[pinnedIndex + 1]
            })
        else {
            return 1
        }

        let pinnedVisualHeight = groupedHeaderHeight + groupedHeaderTransitionGap
        let fadeStartY = currentGroupedHeaderPinTop + pinnedVisualHeight + 2.5
        let fadeEndY = currentGroupedHeaderPinTop + pinnedVisualHeight / 2
        let fadeDistance = max(fadeStartY - fadeEndY, 0.001)
        let fadeProgress = min(
            max((fadeStartY - frames[nextHeaderIndex].minY) / fadeDistance, 0),
            1
        )
        return Double(1 - fadeProgress)
    }

    private var groupedScrollClipMask: some View {
        let topClipHeight = max(
            0,
            currentHolderTopCardMaskTop - holderCollapsedContentTop
        )

        return VStack(spacing: 0) {
            Color.clear
                .frame(height: topClipHeight)

            Rectangle()
                .fill(Color.black)
                .frame(height: max(0, holderScrollHeight - topClipHeight))
        }
        .frame(
            width: CardaTheme.canvasWidth,
            height: holderScrollHeight,
            alignment: .topLeading
        )
    }

    private var holderTopCardGradientMask: some View {
        TransparentGradientBlur(
            width: CardaTheme.canvasWidth - holderTopCardMaskHorizontalInset * 2,
            height: holderTopCardMaskHeight,
            direction: .top,
            materialStyle: .ultraThinLight,
            tintColor: holderPinnedBackgroundColor,
            tintOpacity: 0.84,
            matchesOpaqueEdgeColor: true
        )
        .offset(
            x: holderTopCardMaskHorizontalInset,
            y: currentHolderTopCardMaskTop
        )
        .allowsHitTesting(false)
    }

    private var holderBottomSoftEdge: some View {
        FigmaScrollEdgeSoftOverlay(
            width: CardaTheme.canvasWidth,
            height: holderBottomSoftEdgeHeight,
            direction: .bottom
        )
        .offset(y: holderBottomSoftEdgeTop)
    }

    private func cardRowOrExpanded(_ card: BusinessCard) -> some View {
        let isExpanded = !isMultiSelecting && expandedCardID == card.id
        let isSelected = selectedCardIDs.contains(card.id)
        let cardHeight = isExpanded
            ? CardLayoutCalculator.height(for: card.renderData)
            : 60

        let expandCard = {
            withAnimation(CardExpansionMotion.shapeAnimation) {
                expandedCardID = card.id
                revealedDeleteCardID = nil
                isContextMenuVisible = false
                listContextMenuListID = nil
            }
        }

        let toggleCard = {
            if isExpanded {
                withAnimation(CardExpansionMotion.shapeAnimation) {
                    expandedCardID = nil
                    revealedDeleteCardID = nil
                    isContextMenuVisible = false
                    listContextMenuListID = nil
                }
            } else {
                expandCard()
            }
        }

        return SwipeToDeleteCardContainer(
            cardID: card.id,
            height: cardHeight,
            revealedCardID: $revealedDeleteCardID,
            isSwipeEnabled: !isMultiSelecting,
            onDelete: {
                requestDelete(card)
            }
        ) {
            ZStack(alignment: .topLeading) {
                BusinessCardView(
                    data: card.renderData,
                    width: CardaTheme.cardWidth,
                    onInfoAction: handleCardInfoAction,
                    isExpanded: isExpanded
                )

                if mode == .list && !isExpanded {
                    ListCardDragSource(
                        data: card.renderData,
                        dragItems: dragRenderData(for: card),
                        isMultiSelecting: isMultiSelecting,
                        isSelected: isSelected,
                        onTap: {
                            if isMultiSelecting {
                                toggleCardSelection(card.id)
                            } else {
                                expandCard()
                            }
                        },
                        onDragBegan: {
                            draggingListCardID = card.id
                            collapseSourceListIfNeeded(for: card)
                        },
                        onDragEnded: {
                            finishListDragIfStillActive(cardID: card.id)
                        }
                    )
                    .frame(width: CardaTheme.cardWidth, height: 60)

                    MultiSelectionCheckBadge(
                        isVisible: isMultiSelecting && isSelected
                    )
                    .frame(width: 26, height: 26)
                    .offset(x: 344, y: 0)
                    .zIndex(2)
                }
            }
        }
        .onTapGesture {
            guard mode != .list || isExpanded else { return }
            toggleCard()
        }
        .frame(
            width: CardaTheme.canvasWidth,
            height: cardHeight,
            alignment: .top
        )
        .simultaneousGesture(
            cardContextMenuLongPress(for: card),
            isEnabled: isExpanded && !isMultiSelecting
        )
        .onGeometryChange(for: CGRect.self) { geometry in
            geometry.frame(in: .named(Self.holderCoordinateSpaceName))
        } action: { _, frame in
            geometryFrameStore.cardFrames[card.id] = frame
        }
    }

    private var listModeContent: some View {
        let rows = listRows

        return ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(
                    alignment: .leading,
                    spacing: 0,
                    pinnedViews: [.sectionHeaders]
                ) {
                    ListStickyHeaderMask(
                        height: listStickyHeaderMaskTravel,
                        backgroundColor: holderPinnedBackgroundColor
                    )

                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        Section {
                            expandedListCards(row)
                        } header: {
                            ListStickyHeader(backgroundColor: holderPinnedBackgroundColor) {
                                listModeRow(
                                    row,
                                    showsTopSeparator: index > 0,
                                    scrollProxy: scrollProxy
                                )
                            }
                            .id(row.id)
                        }
                    }
                }
                .background {
                    scrollPanObserver(source: .list)
                }
                .frame(width: CardaTheme.canvasWidth, alignment: .leading)
                .padding(.bottom, 255)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                ListStickyHeaderMask(
                    height: listStickyHeaderPinInsetHeight,
                    backgroundColor: holderPinnedBackgroundColor
                )
            }
            .frame(
                width: CardaTheme.canvasWidth,
                height: holderScrollHeight,
                alignment: .top
            )
            // Keep the UIScrollView viewport stable while the complete sticky
            // module moves visually. Resizing this frame from 710...820pt during
            // the gesture changes ScrollGeometry.containerSize and feeds a
            // synthetic reverse contentOffset back into direction detection.
            .clipped()
            .mask(alignment: .topLeading) {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: listStickyHeaderClipInsetHeight)

                    Rectangle()
                        .fill(Color.black)
                        .frame(
                            height: max(
                                0,
                                holderScrollHeight - listStickyHeaderClipInsetHeight
                            )
                        )
                }
                .frame(
                    width: CardaTheme.canvasWidth,
                    height: holderScrollHeight,
                    alignment: .topLeading
                )
            }
            // This structural bridge is outside the content mask and moves with
            // the complete sticky module. Even if the backing Union is being
            // composited in a separate subtree, the module owns every pixel from
            // its top edge to the 12pt clipping line.
            .background(alignment: .topLeading) {
                Rectangle()
                    .fill(holderPinnedBackgroundColor)
                    .frame(
                        width: CardaTheme.canvasWidth,
                        height: listStickyHeaderClipInsetHeight
                    )
            }
            .modifier(
                CardHolderCollapseTranslationModifier(
                    collapseState: headerCollapseState,
                    expandedY: holderContentTop,
                    maximumOffset: headerCollapseDistance
                )
            )
            .scrollIndicators(.hidden)
            .scrollPosition($listScrollPosition)
            .onScrollGeometryChange(for: HolderScrollMetrics.self) { geometry in
                holderScrollMetrics(from: geometry)
            } action: { _, metrics in
                handleScrollMetrics(metrics, source: .list)
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

                    prepareForProgrammaticScroll()
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
        let hasSelectedCard = row.cards.contains { selectedCardIDs.contains($0.id) }

        return HStack(spacing: 0) {
            Text(row.title)
                .font(CardaTheme.pingFang(size: 17, weight: .regular))
                .foregroundStyle(
                    hasSelectedCard
                        ? CardaTheme.systemSelectionBlue
                        : row.isUncategorized ? Color.black.opacity(0.35) : Color.black
                )
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
        .background {
            Rectangle()
                .fill(CardaTheme.searchBackground)
        }
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
                        guard !isMultiSelecting else { return }
                        presentListContextMenu(
                            for: row,
                            scrollProxy: scrollProxy
                        )
                    case .second:
                        toggleListRow(row)
                    default:
                        break
                    }
                }
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(
            isMultiSelecting
                ? hasSelectedCard ? "包含已选名片" : "未包含已选名片"
                : ""
        )
        .accessibilityAction {
            guard !shouldIgnoreListRowGesture() else { return }
            toggleListRow(row)
        }
        .dropDestination(for: String.self) { items, _ in
            moveDraggedCards(with: items, to: row)
        } isTargeted: { isTargeted in
            withAnimation(.snappy(duration: 0.16)) {
                dropTargetListRowID = isTargeted ? row.id : nil
            }
        }
        .padding(.leading, 19)
        .frame(
            width: CardaTheme.canvasWidth,
            height: listStickyHeaderRowHeight,
            alignment: .leading
        )
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
        .onGeometryChange(for: CGRect.self) { geometry in
            geometry.frame(in: .named(Self.holderCoordinateSpaceName))
        } action: { _, frame in
            geometryFrameStore.listRowFrames[row.id] = frame
        }
    }

    private var emptyState: some View {
        Text("暂无收到的名片")
            .font(CardaTheme.pingFang(size: 17))
            .foregroundStyle(CardaTheme.formSecondaryText)
    }

    private var contextMenuCard: BusinessCard? {
        guard let contextMenuCardID else { return nil }
        return cards.first { $0.id == contextMenuCardID }
    }

    private var cardContextMenuCenterY: CGFloat {
        guard
            let contextMenuCardID,
            let frame = geometryFrameStore.cardFrames[contextMenuCardID]
        else {
            return 654
        }

        return frame.maxY + 16 + 52
    }

    private var contextMenuList: BusinessCardList? {
        guard let listContextMenuListID else { return nil }
        return cardLists.first { $0.id == listContextMenuListID }
    }

    private var groupedCards: [GroupedCardSection] {
        groupedCards(for: mode)
    }

    private func groupedCards(for mode: HolderMode) -> [GroupedCardSection] {
        derivedDataCache.groupedCards(for: mode, cards: cards)
    }

    private func groupedSectionID(for letter: String) -> String? {
        switch mode {
        case .list:
            return nil
        case .name:
            return groupedCards.first { $0.title == letter }?.id
        case .organization:
            return groupedCards.first { $0.title == letter }?.id
        }
    }

    private var listRows: [HolderListRow] {
        derivedDataCache.listRows(cards: cards, lists: cardLists)
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

    private func dragRenderData(for sourceCard: BusinessCard) -> [CardRenderData] {
        guard isMultiSelecting else { return [sourceCard.renderData] }
        guard selectedCardIDs.contains(sourceCard.id) else { return [] }

        let remainingSelectedCards = listRows
            .flatMap(\.cards)
            .filter {
                $0.id != sourceCard.id && selectedCardIDs.contains($0.id)
            }
        return [sourceCard.renderData] + remainingSelectedCards.map(\.renderData)
    }

    private func collapseSourceListIfNeeded(for card: BusinessCard) {
        let sourceRowID = listRowID(for: card)
        guard expandedListID == sourceRowID else { return }
        collapsedDragSourceListID = sourceRowID
        collapsedDragSourceCardID = card.id
        collapsedDragSourceScrollOffsetY = scrollRuntime.listOffsetY

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

    private func cardContextMenuLongPress(
        for card: BusinessCard
    ) -> some Gesture {
        LongPressGesture(minimumDuration: 0.45)
            .onEnded { _ in
                presentCardContextMenu(for: card)
            }
    }

    private func presentCardContextMenu(for card: BusinessCard) {
        withAnimation(.snappy(duration: 0.24)) {
            contextMenuCardID = card.id
            contextMenuDragStartOffsetY = nil
            contextMenuDragDismissProgress = 0
            isContextMenuVisible = true
            listContextMenuListID = nil
            listContextMenuRowID = nil
        }
    }

    private var cardContextMenuScrollGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .local)
            .onChanged { value in
                guard abs(value.translation.height) > abs(value.translation.width) else {
                    return
                }

                let startOffset = contextMenuDragStartOffsetY
                    ?? currentCardContextMenuScrollOffsetY
                if contextMenuDragStartOffsetY == nil {
                    contextMenuDragStartOffsetY = startOffset
                }

                scrollCardHolder(
                    to: max(0, startOffset - value.translation.height),
                    animated: false
                )
                contextMenuDragDismissProgress = min(
                    1,
                    abs(value.translation.height) / 44
                )
            }
            .onEnded { value in
                guard let startOffset = contextMenuDragStartOffsetY else {
                    return
                }

                let verticalDistance = abs(value.translation.height)
                let isVertical = verticalDistance > abs(value.translation.width)
                if isVertical {
                    let predictedOffset = max(
                        0,
                        startOffset - value.predictedEndTranslation.height
                    )
                    scrollCardHolder(to: predictedOffset, animated: true)
                }

                contextMenuDragStartOffsetY = nil
                if isVertical && verticalDistance >= 36 {
                    dismissCardContextMenu()
                } else {
                    withAnimation(.snappy(duration: 0.18)) {
                        contextMenuDragDismissProgress = 0
                    }
                }
            }
    }

    nonisolated private func holderScrollMetrics(
        from geometry: ScrollGeometry
    ) -> HolderScrollMetrics {
        let normalizedOffsetY = geometry.contentOffset.y + geometry.contentInsets.top
        let maximumOffsetY = max(
            0,
            geometry.contentSize.height
                + geometry.contentInsets.top
                + geometry.contentInsets.bottom
                - geometry.containerSize.height
        )
        let displayScale: CGFloat = 3
        return HolderScrollMetrics(
            offsetY: (normalizedOffsetY * displayScale).rounded() / displayScale,
            maximumOffsetY: (maximumOffsetY * displayScale).rounded() / displayScale
        )
    }

    private var activeScrollSource: HolderScrollSource {
        mode == .list ? .list : .grouped
    }

    private func scrollPanObserver(
        source: HolderScrollSource
    ) -> some View {
        ScrollViewPanObserver(
            generation: modeInteractionGeneration,
            onChanged: { delta in
                handleHeaderPanDelta(
                    delta,
                    source: source
                )
            },
            onEnded: {
                finishHeaderPan(source: source)
            }
        )
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
    }

    private func handleHeaderPanDelta(
        _ delta: CGSize,
        source: HolderScrollSource
    ) {
        guard source == activeScrollSource else { return }
        guard abs(delta.height) > abs(delta.width) else { return }

        registerHeaderIntent(
            delta.height < 0 ? .collapsing : .expanding,
            distance: abs(delta.height),
            source: source
        )
    }

    private func finishHeaderPan(source: HolderScrollSource) {
        guard source == activeScrollSource else { return }
        resetHeaderDirectionTracking()
    }

    private func handleScrollMetrics(
        _ metrics: HolderScrollMetrics,
        source: HolderScrollSource
    ) {
        let visibleOffsetY = visibleScrollOffset(for: metrics)

        switch source {
        case .grouped:
            scrollRuntime.groupedOffsetY = visibleOffsetY
        case .list:
            scrollRuntime.listOffsetY = visibleOffsetY
        }
    }

    private func visibleScrollOffset(for metrics: HolderScrollMetrics) -> CGFloat {
        min(max(metrics.offsetY, 0), metrics.maximumOffsetY)
    }

    private func registerHeaderIntent(
        _ direction: HolderHeaderScrollDirection,
        distance: CGFloat,
        source: HolderScrollSource
    ) {
        guard source == activeScrollSource else { return }
        guard source != .list || direction != .collapsing || expandedListID != nil else {
            resetHeaderDirectionTracking()
            return
        }
        guard scrollRuntime.direction != direction else { return }

        if scrollRuntime.pendingDirection != direction {
            scrollRuntime.pendingDirection = direction
            scrollRuntime.pendingDistance = 0
        }
        scrollRuntime.pendingDistance += distance

        // One point filters subpoint finger jitter without delaying a deliberate
        // direction. After confirmation, write exactly one binary header target;
        // content offset and ScrollPosition are never modified by this transition.
        guard scrollRuntime.pendingDistance >= 1 else { return }

        scrollRuntime.direction = direction
        scrollRuntime.pendingDirection = nil
        scrollRuntime.pendingDistance = 0
        setHeaderCollapseOffset(
            direction == .collapsing ? headerCollapseDistance : 0,
            animated: !accessibilityReduceMotion
        )
    }

    private func setHeaderCollapseOffset(_ offset: CGFloat, animated: Bool) {
        let clampedOffset = min(max(offset, 0), headerCollapseDistance)
        guard abs(clampedOffset - headerCollapseState.offset) > 0.01 else { return }
        let update = {
            headerCollapseState.offset = clampedOffset
        }

        if animated {
            withAnimation(
                .timingCurve(0.2, 0.72, 0.18, 1, duration: 0.2),
                update
            )
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, update)
        }
    }

    private func resetHeaderDirectionTracking() {
        scrollRuntime.direction = nil
        scrollRuntime.pendingDirection = nil
        scrollRuntime.pendingDistance = 0
    }

    private func prepareForProgrammaticScroll() {
        resetHeaderDirectionTracking()
    }

    private func resetHeaderTrackingForModeChange() {
        resetHeaderDirectionTracking()
    }

    private var currentCardContextMenuScrollOffsetY: CGFloat {
        mode == .list ? scrollRuntime.listOffsetY : scrollRuntime.groupedOffsetY
    }

    private func scrollCardHolder(to offsetY: CGFloat, animated: Bool) {
        prepareForProgrammaticScroll()
        let update = {
            if mode == .list {
                listScrollPosition.scrollTo(y: offsetY)
            } else {
                groupedScrollPosition.scrollTo(y: offsetY)
            }
        }

        if animated {
            withAnimation(.easeOut(duration: 0.22), update)
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, update)
        }
    }

    private func dismissCardContextMenu() {
        withAnimation(.snappy(duration: 0.18)) {
            contextMenuDragDismissProgress = 1
            isContextMenuVisible = false
        } completion: {
            contextMenuDragDismissProgress = 0
            contextMenuDragStartOffsetY = nil
        }
    }

    private func synchronizeHeaderMorphState() {
        headerMorphGeneration &+= 1
        let target: CGFloat = mode == .list ? 1 : 0
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            headerMorphProgress = target
            headerLeftControlProgress = target
            headerRightLabelRevealProgress = target
            isHeaderModeTransitioning = false
        }
    }

    private func animateHeaderTransition(to newMode: HolderMode) {
        headerMorphGeneration &+= 1
        let generation = headerMorphGeneration
        let movesToList = newMode == .list

        guard !accessibilityReduceMotion else {
            synchronizeHeaderMorphState()
            return
        }

        isHeaderModeTransitioning = true

        if movesToList {
            headerRightLabelRevealProgress = 0

            withAnimation(
                .timingCurve(
                    0.2,
                    0.72,
                    0.18,
                    1,
                    duration: headerMorphDuration
                )
            ) {
                headerMorphProgress = 1
            }

            withAnimation(
                .timingCurve(0.16, 0.82, 0.24, 1, duration: 0.5)
                    .delay(0.03)
            ) {
                headerLeftControlProgress = 1
            }

            DispatchQueue.main.asyncAfter(
                deadline: .now() + headerLabelRevealDelay
            ) {
                guard headerMorphGeneration == generation, mode == .list else { return }
                withAnimation(
                    .timingCurve(
                        0.22,
                        0.78,
                        0.2,
                        1,
                        duration: headerLabelRevealDuration
                    )
                ) {
                    headerRightLabelRevealProgress = 1
                }
            }

            DispatchQueue.main.asyncAfter(
                deadline: .now()
                    + headerLabelRevealDelay
                    + headerLabelRevealDuration
            ) {
                guard headerMorphGeneration == generation, mode == .list else { return }
                isHeaderModeTransitioning = false
            }
        } else {
            withAnimation(
                .timingCurve(
                    0.22,
                    0.78,
                    0.2,
                    1,
                    duration: headerLabelRevealDuration
                )
            ) {
                headerRightLabelRevealProgress = 0
            }

            // Use the same front-loaded curve in both directions so returning
            // to the grouped header does not feel slower than entering list.
            withAnimation(
                .timingCurve(
                    0.2,
                    0.72,
                    0.18,
                    1,
                    duration: headerMorphDuration
                )
            ) {
                headerMorphProgress = 0
            }

            withAnimation(
                .timingCurve(0.16, 0.82, 0.24, 1, duration: 0.5)
                    .delay(0.03)
            ) {
                headerLeftControlProgress = 0
            }

            DispatchQueue.main.asyncAfter(
                deadline: .now() + headerMorphDuration
            ) {
                guard headerMorphGeneration == generation, mode != .list else { return }
                isHeaderModeTransitioning = false
            }
        }
    }

    private func selectMode(_ item: HolderMode) {
        guard item != mode else { return }
        if (mode == .list) != (item == .list) {
            // Pre-arm the transition before the binding changes so the reverse
            // path keeps the morphing surface until it reaches the 44pt circle.
            isHeaderModeTransitioning = true
        }
        modeInteractionGeneration &+= 1
        resetHeaderTrackingForModeChange()
        setHeaderCollapseOffset(0, animated: false)
        retainedGroupedHeaderTitle = nil
        prepareGroupedHeaderTransition(to: item)
        updateSelectedMode(item)
    }

    private func groupedHeaderTransition(for title: String) -> AnyTransition {
        let insertionDelay = delayedGroupedHeaderTitles.contains(title) ? 0.12 : 0

        return .asymmetric(
            insertion: .opacity.animation(
                .timingCurve(0.4, 0, 0.2, 1, duration: 0.16)
                    .delay(insertionDelay)
            ),
            removal: .opacity.animation(
                .timingCurve(0.4, 0, 0.2, 1, duration: 0.12)
            )
        )
    }

    private func prepareGroupedHeaderTransition(to item: HolderMode) {
        groupedHeaderTransitionGeneration += 1
        let generation = groupedHeaderTransitionGeneration
        suppressGroupedContentAnimation = true
        groupedHeaderTransitionActive = true

        DispatchQueue.main.async {
            guard groupedHeaderTransitionGeneration == generation else { return }
            suppressGroupedContentAnimation = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            guard groupedHeaderTransitionGeneration == generation else { return }
            delayedGroupedHeaderTitles = []
            groupedHeaderTransitionActive = false
        }

        guard mode != .list, item != .list else {
            delayedGroupedHeaderTitles = []
            return
        }

        let oldTitles = Set(groupedCards(for: mode).map(\.title))
        let newTitles = Set(groupedCards(for: item).map(\.title))
        delayedGroupedHeaderTitles = newTitles.subtracting(oldTitles)

    }

    private func updateSelectedMode(_ item: HolderMode) {
        withAnimation(.snappy(duration: 0.28)) {
            mode = item
            isMultiSelecting = false
            selectedCardIDs.removeAll()
            expandedCardID = nil
            expandedListID = nil
            revealedDeleteCardID = nil
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
    }

    private func enterMultiSelection() {
        guard mode == .list, !isMultiSelecting else { return }
        clearListDragTracking()

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isMultiSelecting = true
            selectedCardIDs.removeAll()
            expandedCardID = nil
            revealedDeleteCardID = nil
            isContextMenuVisible = false
            listContextMenuListID = nil
            listContextMenuRowID = nil
            dropTargetListRowID = nil
        }
    }

    private func cancelCardSelection() {
        guard isMultiSelecting, !selectedCardIDs.isEmpty else { return }
        withAnimation(.snappy(duration: 0.18)) {
            selectedCardIDs.removeAll()
        }
    }

    private func exitMultiSelection() {
        guard isMultiSelecting || !selectedCardIDs.isEmpty else { return }
        let update = {
            isMultiSelecting = false
            selectedCardIDs.removeAll()
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, update)
    }

    private func toggleCardSelection(_ cardID: UUID) {
        guard isMultiSelecting else { return }
        withAnimation(.snappy(duration: 0.18)) {
            if selectedCardIDs.contains(cardID) {
                selectedCardIDs.remove(cardID)
            } else {
                selectedCardIDs.insert(cardID)
            }
        }
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

    private func handleCardInfoAction(_ field: CardFieldDraft) {
        switch field.kind {
        case .phone, .email, .address, .link:
            let value = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }
            onInfoAction(field.kind, value)
        case .companyLogo:
            break
        }
    }

    private func showTransientMessage(_ message: String) {
        withAnimation {
            saveMessage = message
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            guard saveMessage == message else { return }
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

    private func requestDelete(_ card: BusinessCard) {
        withAnimation(.snappy(duration: 0.2)) {
            revealedDeleteCardID = nil
            isContextMenuVisible = false
            listContextMenuListID = nil
            dropTargetListRowID = nil
        }
        cardPendingDeletionID = card.id
        if !confirmsCardDeletion {
            deletePendingCard()
        }
    }

    private func deletePendingCard() {
        guard
            let cardPendingDeletionID,
            let card = cards.first(where: { $0.id == cardPendingDeletionID })
        else {
            self.cardPendingDeletionID = nil
            return
        }

        withAnimation(.snappy(duration: 0.24)) {
            if expandedCardID == card.id {
                expandedCardID = nil
            }
            isContextMenuVisible = false
            listContextMenuListID = nil
            dropTargetListRowID = nil
        }

        modelContext.delete(card)

        do {
            try modelContext.save()
            showTransientMessage("已删除名片")
        } catch {
            modelContext.rollback()
            showTransientMessage("删除失败")
        }

        self.cardPendingDeletionID = nil
    }

    private func toggleListRow(_ row: HolderListRow) {
        clearListDragTracking()
        let isCollapsing = expandedListID == row.id

        if isCollapsing {
            resetHeaderDirectionTracking()
            setHeaderCollapseOffset(0, animated: !accessibilityReduceMotion)
            listScrollRequest = ListScrollRequest(target: .offset(0))
        }

        withAnimation(.snappy(duration: 0.28)) {
            expandedCardID = nil
            isContextMenuVisible = false
            listContextMenuListID = nil
            expandedListID = isCollapsing ? nil : row.id
        }
    }

    private var listContextMenuCenterY: CGFloat {
        guard
            let rowID = listContextMenuRowID,
            let rowFrame = geometryFrameStore.listRowFrames[rowID]
        else {
            return 302
        }

        return rowFrame.maxY + listContextMenuGap + listContextMenuHeight / 2
    }

    private func presentListContextMenu(
        for row: HolderListRow,
        scrollProxy: ScrollViewProxy
    ) {
        guard let listID = row.listID else { return }
        clearListDragTracking()

        if let rowFrame = geometryFrameStore.listRowFrames[row.id],
           rowFrame.maxY + listContextMenuGap + listContextMenuHeight > CardaTheme.canvasHeight - 16 {
            withAnimation(.snappy(duration: 0.24)) {
                scrollProxy.scrollTo(row.id, anchor: .top)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                showListContextMenu(listID: listID, rowID: row.id)
            }
            return
        }

        showListContextMenu(listID: listID, rowID: row.id)
    }

    private func showListContextMenu(listID: UUID, rowID: String) {
        withAnimation(.snappy(duration: 0.24)) {
            expandedCardID = nil
            isContextMenuVisible = false
            listContextMenuListID = listID
            listContextMenuRowID = rowID
        }
    }

    private func moveDraggedCards(with payloads: [String], to row: HolderListRow) -> Bool {
        var seenCardIDs: Set<UUID> = []
        let draggedCards = payloads
            .compactMap(UUID.init(uuidString:))
            .filter { seenCardIDs.insert($0).inserted }
            .compactMap { cardID in
                cards.first { $0.id == cardID }
            }

        guard !draggedCards.isEmpty else {
            restoreCollapsedDragSourceListIfNeeded()
            return false
        }

        return move(draggedCards, to: row)
    }

    private func move(_ draggedCards: [BusinessCard], to row: HolderListRow) -> Bool {
        let targetListID = row.listID
        let cardsToMove = draggedCards.filter { $0.cardListID != targetListID }
        dropTargetListRowID = nil

        guard !cardsToMove.isEmpty else {
            restoreCollapsedDragSourceListIfNeeded()
            return true
        }

        let now = Date()
        let affectedListIDs = Set(
            cardsToMove.compactMap(\.cardListID) + [targetListID].compactMap { $0 }
        )

        withAnimation(.snappy(duration: 0.24)) {
            expandedCardID = nil
            isContextMenuVisible = false
            listContextMenuListID = nil
            for card in cardsToMove {
                card.cardListID = targetListID
                card.updatedAt = now
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

        let movedCardIDs = Set(cardsToMove.map(\.id))
        withAnimation(.snappy(duration: 0.18)) {
            selectedCardIDs.subtract(movedCardIDs)
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

private struct MultiSelectionCheckBadge: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.cardaReduceMotion) private var settingsReduceMotion

    let isVisible: Bool

    private var accessibilityReduceMotion: Bool {
        systemReduceMotion || settingsReduceMotion
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(CardaTheme.systemSelectionGreen)
                .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)

            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.white)
        }
        .scaleEffect(isVisible ? 1 : 0.72)
        .offset(y: isVisible ? 0 : -2)
        .opacity(isVisible ? 1 : 0)
        .animation(
            accessibilityReduceMotion
                ? nil
                : .spring(duration: 0.22, bounce: 0.28),
            value: isVisible
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ListCardDragSource: UIViewRepresentable {
    let data: CardRenderData
    let dragItems: [CardRenderData]
    let isMultiSelecting: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onDragBegan: () -> Void
    let onDragEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            data: data,
            dragItems: dragItems,
            isMultiSelecting: isMultiSelecting,
            onTap: onTap,
            onDragBegan: onDragBegan,
            onDragEnded: onDragEnded
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.layer.cornerRadius = 30
        view.layer.cornerCurve = .circular
        view.clipsToBounds = true
        view.isAccessibilityElement = true

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
        context.coordinator.dragItems = dragItems
        context.coordinator.isMultiSelecting = isMultiSelecting
        context.coordinator.onTap = onTap
        context.coordinator.onDragBegan = onDragBegan
        context.coordinator.onDragEnded = onDragEnded

        uiView.accessibilityLabel = data.displayName
        uiView.accessibilityValue = isMultiSelecting
            ? isSelected ? "已选择" : "未选择"
            : nil
        uiView.accessibilityIdentifier = isMultiSelecting
            ? "cardHolder.multiSelect.card.\(data.id.uuidString)"
            : nil
        var accessibilityTraits: UIAccessibilityTraits = .button
        if isSelected {
            accessibilityTraits.insert(.selected)
        }
        uiView.accessibilityTraits = accessibilityTraits
    }

    final class Coordinator: NSObject, UIDragInteractionDelegate {
        var data: CardRenderData
        var dragItems: [CardRenderData]
        var isMultiSelecting: Bool
        var onTap: () -> Void
        var onDragBegan: () -> Void
        var onDragEnded: () -> Void

        init(
            data: CardRenderData,
            dragItems: [CardRenderData],
            isMultiSelecting: Bool,
            onTap: @escaping () -> Void,
            onDragBegan: @escaping () -> Void,
            onDragEnded: @escaping () -> Void
        ) {
            self.data = data
            self.dragItems = dragItems
            self.isMultiSelecting = isMultiSelecting
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
            guard !dragItems.isEmpty else { return [] }
            onDragBegan()

            let showsSelectionBadge = isMultiSelecting
            return dragItems.map { dragData in
                let itemProvider = NSItemProvider(
                    object: dragData.id.uuidString as NSString
                )
                let item = UIDragItem(itemProvider: itemProvider)
                item.localObject = dragData.id
                item.previewProvider = {
                    UIDragPreview(
                        view: Self.previewView(
                            for: dragData,
                            showsSelectionBadge: showsSelectionBadge
                        ),
                        parameters: Self.previewParameters()
                    )
                }
                return item
            }
        }

        func dragInteraction(
            _ interaction: UIDragInteraction,
            previewForLifting item: UIDragItem,
            session: UIDragSession
        ) -> UITargetedDragPreview? {
            guard let sourceView = interaction.view else { return nil }
            guard
                let itemID = item.localObject as? UUID,
                let itemData = dragItems.first(where: { $0.id == itemID })
            else {
                return nil
            }

            let preview = Self.previewView(
                for: itemData,
                showsSelectionBadge: isMultiSelecting
            )
            let target = UIDragPreviewTarget(
                container: sourceView,
                center: CGPoint(
                    x: sourceView.bounds.midX,
                    y: sourceView.bounds.midY
                )
            )

            return UITargetedDragPreview(
                view: preview,
                parameters: Self.previewParameters(),
                target: target
            )
        }

        func dragInteraction(
            _ interaction: UIDragInteraction,
            prefersFullSizePreviewsFor session: UIDragSession
        ) -> Bool {
            true
        }

        func dragInteraction(
            _ interaction: UIDragInteraction,
            sessionIsRestrictedToDraggingApplication session: UIDragSession
        ) -> Bool {
            true
        }

        func dragInteraction(
            _ interaction: UIDragInteraction,
            session: UIDragSession,
            didEndWith operation: UIDropOperation
        ) {
            onDragEnded()
        }

        private static func previewParameters() -> UIDragPreviewParameters {
            let parameters = UIDragPreviewParameters()
            parameters.backgroundColor = .clear
            parameters.visiblePath = UIBezierPath(
                roundedRect: CGRect(x: 0, y: 0, width: 370, height: 60),
                cornerRadius: 30
            )
            return parameters
        }

        private static func previewView(
            for data: CardRenderData,
            showsSelectionBadge: Bool
        ) -> UIView {
            let preview = UIView(frame: CGRect(x: 0, y: 0, width: 370, height: 60))
            preview.backgroundColor = .white
            preview.layer.cornerRadius = 30
            preview.layer.cornerCurve = .circular
            preview.clipsToBounds = true

            let organizationLabel = UILabel(frame: CGRect(x: 25, y: 6.5, width: 220, height: 20))
            organizationLabel.text = data.displayOrganizationName
            organizationLabel.textColor = UIColor.black.withAlphaComponent(0.5)
            organizationLabel.font = UIFont(name: "PingFangSC-Regular", size: 15)
                ?? .systemFont(ofSize: 15, weight: .regular)
            organizationLabel.lineBreakMode = .byTruncatingTail

            let nameLabel = UILabel(frame: CGRect(x: 25, y: 30.5, width: 220, height: 22))
            nameLabel.text = data.displayName
            nameLabel.textColor = .black
            nameLabel.font = data.displayName.unicodeScalars.allSatisfy { $0.isASCII }
                ? .systemFont(ofSize: 17, weight: .semibold)
                : UIFont(name: "PingFangSC-Semibold", size: 17)
                    ?? .systemFont(ofSize: 17, weight: .semibold)
            nameLabel.lineBreakMode = .byTruncatingTail

            preview.addSubview(organizationLabel)
            preview.addSubview(nameLabel)

            if
                let avatarImageData = data.avatarImageData,
                let image = UIImage(data: avatarImageData)
            {
                let avatarView = UIImageView(
                    frame: CGRect(x: 318, y: 8, width: 44, height: 44)
                )
                avatarView.image = image
                avatarView.contentMode = .scaleAspectFill
                avatarView.layer.cornerRadius = 22
                avatarView.clipsToBounds = true
                preview.addSubview(avatarView)
            }

            if showsSelectionBadge {
                let badge = UIView(frame: CGRect(x: 344, y: 0, width: 26, height: 26))
                badge.backgroundColor = UIColor(
                    red: 52 / 255,
                    green: 199 / 255,
                    blue: 89 / 255,
                    alpha: 1
                )
                badge.layer.cornerRadius = 13
                badge.layer.shadowColor = UIColor.black.cgColor
                badge.layer.shadowOpacity = 0.12
                badge.layer.shadowRadius = 2
                badge.layer.shadowOffset = CGSize(width: 0, height: 1)

                let checkmark = UIImageView(
                    frame: CGRect(x: 6, y: 6, width: 14, height: 14)
                )
                checkmark.image = UIImage(
                    systemName: "checkmark",
                    withConfiguration: UIImage.SymbolConfiguration(
                        pointSize: 12,
                        weight: .bold
                    )
                )
                checkmark.tintColor = .white
                checkmark.contentMode = .scaleAspectFit
                badge.addSubview(checkmark)
                preview.addSubview(badge)
            }

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

struct AnimatedHolderPanelCapShape: Shape {
    var selectionPosition: CGFloat

    private let bodyTop: CGFloat = 38
    private let tabWidth: CGFloat = 134
    private let circularCornerRadius: CGFloat = 20

    var animatableData: CGFloat {
        get { selectionPosition }
        set { selectionPosition = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clampedPosition = min(max(selectionPosition, 0), 2)
        let tabMinX = rect.minX + 134 * clampedPosition
        let tabMaxX = tabMinX + tabWidth
        let bodyY = rect.minY + bodyTop
        let leftGap = max(0, tabMinX - rect.minX)
        let rightGap = max(0, rect.maxX - tabMaxX)
        let leftRadius = min(circularCornerRadius, bodyTop / 2, leftGap / 2)
        let rightRadius = min(circularCornerRadius, bodyTop / 2, rightGap / 2)
        let tabRadius = min(circularCornerRadius, bodyTop / 2, tabWidth / 2)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))

        if leftGap == 0 {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tabRadius))
            path.addCircularCorner(
                via: CGPoint(x: rect.minX, y: rect.minY),
                to: CGPoint(x: rect.minX + tabRadius, y: rect.minY),
                radius: tabRadius
            )
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: bodyY + leftRadius))
            path.addCircularCorner(
                via: CGPoint(x: rect.minX, y: bodyY),
                to: CGPoint(x: rect.minX + leftRadius, y: bodyY),
                radius: leftRadius
            )
            path.addLine(to: CGPoint(x: tabMinX - leftRadius, y: bodyY))
            path.addCircularCorner(
                via: CGPoint(x: tabMinX, y: bodyY),
                to: CGPoint(x: tabMinX, y: bodyY - leftRadius),
                radius: leftRadius
            )
            path.addLine(to: CGPoint(x: tabMinX, y: rect.minY + tabRadius))
            path.addCircularCorner(
                via: CGPoint(x: tabMinX, y: rect.minY),
                to: CGPoint(x: tabMinX + tabRadius, y: rect.minY),
                radius: tabRadius
            )
        }

        path.addLine(to: CGPoint(x: tabMaxX - tabRadius, y: rect.minY))
        path.addCircularCorner(
            via: CGPoint(x: tabMaxX, y: rect.minY),
            to: CGPoint(x: tabMaxX, y: rect.minY + tabRadius),
            radius: tabRadius
        )

        if rightGap == 0 {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
            return path
        }

        path.addLine(to: CGPoint(x: tabMaxX, y: bodyY - rightRadius))
        path.addCircularCorner(
            via: CGPoint(x: tabMaxX, y: bodyY),
            to: CGPoint(x: tabMaxX + rightRadius, y: bodyY),
            radius: rightRadius
        )
        path.addLine(to: CGPoint(x: rect.maxX - rightRadius, y: bodyY))
        path.addCircularCorner(
            via: CGPoint(x: rect.maxX, y: bodyY),
            to: CGPoint(x: rect.maxX, y: bodyY + rightRadius),
            radius: rightRadius
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
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

extension HolderMode {
    var selectionPosition: CGFloat {
        switch self {
        case .list:
            0
        case .name:
            1
        case .organization:
            2
        }
    }
}

struct HolderModeTabsBackground: View {
    let mode: HolderMode

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(HolderMode.allCases) { item in
                if item != mode {
                    modeTabBackground(item)
                }
            }
        }
        .frame(width: CardaTheme.canvasWidth, height: 171, alignment: .topLeading)
    }

    private func modeTabBackground(_ item: HolderMode) -> some View {
        let frame = modeTabFrame(for: item)
        let shape = modeTabShape(for: item)

        return shape
            .fill(Color.white)
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.x, y: frame.y)
    }

    fileprivate func modeTabFrame(
        for item: HolderMode
    ) -> (x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
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

    fileprivate func modeTabShape(for item: HolderMode) -> HolderModeTabShape {
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
    static let segmentText = Color(red: 24 / 255, green: 25 / 255, blue: 30 / 255)
    static let segmentCompanyText = Color(red: 48 / 255, green: 49 / 255, blue: 54 / 255)
    static let listSeparator = Color(red: 198 / 255, green: 198 / 255, blue: 200 / 255)
}

private struct SwipeToDeleteCardContainer<Content: View>: View {
    let cardID: UUID
    let height: CGFloat
    @Binding var revealedCardID: UUID?
    let isSwipeEnabled: Bool
    let onDelete: () -> Void
    let content: Content

    @State private var offsetX: CGFloat = 0
    @State private var dragStartOffsetX: CGFloat?

    private let revealDistance: CGFloat = 70
    private let expandedButtonWidth: CGFloat = 60
    private let expandedButtonVerticalInset: CGFloat = 15
    private let collapsedButtonSize: CGFloat = 52
    private let collapsedButtonCenterX: CGFloat = 356
    private let expandedDeleteIconSize: CGFloat = 28 * 0.8

    private var isDeleteButtonVisible: Bool {
        revealedCardID == cardID
    }

    private var isCollapsedCard: Bool {
        height == 60
    }

    private var deleteRevealProgress: Double {
        guard isSwipeEnabled else { return 0 }
        let progress = min(max(-offsetX / revealDistance, 0), 1)
        return Double(progress)
    }

    init(
        cardID: UUID,
        height: CGFloat,
        revealedCardID: Binding<UUID?>,
        isSwipeEnabled: Bool = true,
        onDelete: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.cardID = cardID
        self.height = height
        self._revealedCardID = revealedCardID
        self.isSwipeEnabled = isSwipeEnabled
        self.onDelete = onDelete
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            deleteButton
                .offset(
                    x: isCollapsedCard
                        ? collapsedButtonCenterX - collapsedButtonSize / 2
                        : 326,
                    y: isCollapsedCard
                        ? (height - collapsedButtonSize) / 2
                        : expandedButtonVerticalInset
                )
                .opacity(deleteRevealProgress)
                .allowsHitTesting(isDeleteButtonVisible && isSwipeEnabled)
                .accessibilityHidden(!isDeleteButtonVisible || !isSwipeEnabled)

            content
                .frame(width: CardaTheme.cardWidth, height: height)
                .offset(x: 16 + offsetX)
                .gesture(deleteRevealGesture)
        }
        .frame(width: CardaTheme.canvasWidth, height: height, alignment: .topLeading)
        .clipped()
        .onChange(of: revealedCardID) { _, newValue in
            guard newValue != cardID, offsetX != 0 else { return }
            withAnimation(.snappy(duration: 0.22)) {
                offsetX = 0
            }
        }
        .onChange(of: isSwipeEnabled) { _, isEnabled in
            guard !isEnabled, offsetX != 0 else { return }
            offsetX = 0
        }
    }

    private var deleteButton: some View {
        Button {
            onDelete()
        } label: {
            RoundedRectangle(
                cornerRadius: isCollapsedCard ? collapsedButtonSize / 2 : 24,
                style: .circular
            )
                .fill(Color(red: 255 / 255, green: 56 / 255, blue: 60 / 255))
                .frame(
                    width: isCollapsedCard ? collapsedButtonSize : expandedButtonWidth,
                    height: isCollapsedCard
                        ? collapsedButtonSize
                        : max(0, height - expandedButtonVerticalInset * 2)
                )
                .overlay {
                    LocalSVGIconView(
                        fileName: isCollapsedCard ? "Trash 3" : "Trash 2"
                    )
                    .frame(
                        width: isCollapsedCard ? 22 : expandedDeleteIconSize,
                        height: isCollapsedCard ? 22 : expandedDeleteIconSize
                    )
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("删除名片")
    }

    private var deleteRevealGesture: HorizontalCardSwipeGesture {
        HorizontalCardSwipeGesture(
            isEnabled: isSwipeEnabled,
            onChanged: { translationX in
                if dragStartOffsetX == nil {
                    dragStartOffsetX = offsetX
                    if translationX < 0, revealedCardID != cardID {
                        withAnimation(.snappy(duration: 0.22)) {
                            revealedCardID = nil
                        }
                    }
                }

                let startOffset = dragStartOffsetX ?? offsetX
                let proposedOffset = translationX + startOffset
                offsetX = min(0, max(-revealDistance, proposedOffset))
            },
            onEnded: { predictedTranslationX, wasCancelled in
                let shouldReveal = !wasCancelled
                    && (offsetX < -revealDistance * 0.45 || predictedTranslationX < -revealDistance)
                withAnimation(.snappy(duration: 0.22)) {
                    revealedCardID = shouldReveal ? cardID : nil
                    offsetX = shouldReveal ? -revealDistance : 0
                }
                dragStartOffsetX = nil
            }
        )
    }
}

/// Locks the row action to a horizontal pan before recognition begins. A SwiftUI
/// `DragGesture` only knows the axis after it has already joined gesture resolution,
/// which can intermittently delay the parent `ScrollView` when a vertical drag starts
/// on a card row.
private struct HorizontalCardSwipeGesture: UIGestureRecognizerRepresentable {
    let isEnabled: Bool
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat, Bool) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(isEnabled: isEnabled)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.cancelsTouchesInView = false
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        recognizer.isEnabled = isEnabled
        return recognizer
    }

    func updateUIGestureRecognizer(
        _ recognizer: UIPanGestureRecognizer,
        context: Context
    ) {
        context.coordinator.isEnabled = isEnabled
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: UIPanGestureRecognizer,
        context: Context
    ) {
        let translationX = recognizer.translation(in: recognizer.view).x

        switch recognizer.state {
        case .began, .changed:
            onChanged(translationX)
        case .ended:
            let projectedTranslationX = translationX
                + recognizer.velocity(in: recognizer.view).x * 0.2
            onEnded(projectedTranslationX, false)
        case .cancelled, .failed:
            onEnded(translationX, true)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let horizontalDominanceRatio: CGFloat = 1.35
        var isEnabled: Bool

        init(isEnabled: Bool) {
            self.isEnabled = isEnabled
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard isEnabled else { return false }
            guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else {
                return false
            }
            let velocity = panGesture.velocity(in: panGesture.view)
            return abs(velocity.x) > abs(velocity.y) * horizontalDominanceRatio
        }
    }
}

private struct GroupedHeaderAnchor: Identifiable {
    let mode: HolderMode
    let title: String
    let bounds: Anchor<CGRect>

    var id: String { "\(mode.rawValue):\(title)" }
}

private struct ListStickyHeader<Content: View>: View {
    let backgroundColor: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
        .frame(width: CardaTheme.canvasWidth, alignment: .topLeading)
        .background(backgroundColor)
    }
}

private struct ListStickyHeaderMask: View {
    let height: CGFloat
    let backgroundColor: Color

    var body: some View {
        Rectangle()
            .fill(backgroundColor)
            .frame(width: CardaTheme.canvasWidth, height: height)
            .accessibilityHidden(true)
    }
}

private struct GroupedHeaderAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [GroupedHeaderAnchor] = []

    static func reduce(
        value: inout [GroupedHeaderAnchor],
        nextValue: () -> [GroupedHeaderAnchor]
    ) {
        StableIdentityReducer.merge(
            into: &value,
            next: nextValue(),
            id: { $0.id }
        )
    }
}

private struct PinnedHeaderRetentionObserver: View {
    let value: String?
    let onChange: (String?) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                onChange(value)
            }
            .onChange(of: value) { _, newValue in
                onChange(newValue)
            }
    }
}

/// Observes the UIScrollView's existing pan recognizer without installing a
/// competing gesture. Per-frame finger deltas are the sole header-direction
/// source, so layout changes, deceleration and elastic rebound cannot reverse it.
private struct ScrollViewPanObserver: UIViewRepresentable {
    let generation: Int
    let onChanged: (CGSize) -> Void
    let onEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            generation: generation,
            onChanged: onChanged,
            onEnded: onEnded
        )
    }

    func makeUIView(context: Context) -> AttachmentView {
        let view = AttachmentView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.onHierarchyChange = { [weak view, weak coordinator = context.coordinator] in
            guard let view, let coordinator else { return }
            coordinator.attachIfNeeded(from: view)
        }
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(from: view)
        }
        return view
    }

    func updateUIView(_ uiView: AttachmentView, context: Context) {
        context.coordinator.updateGeneration(generation)
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(from: uiView)
        }
    }

    final class AttachmentView: UIView {
        var onHierarchyChange: (() -> Void)?

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            onHierarchyChange?()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onHierarchyChange?()
        }
    }

    final class Coordinator: NSObject {
        var onChanged: (CGSize) -> Void
        var onEnded: () -> Void
        private var generationGate: InteractionGenerationGate
        private weak var panGestureRecognizer: UIPanGestureRecognizer?
        private var previousTranslation: CGPoint = .zero

        init(
            generation: Int,
            onChanged: @escaping (CGSize) -> Void,
            onEnded: @escaping () -> Void
        ) {
            generationGate = InteractionGenerationGate(
                currentGeneration: generation
            )
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        func updateGeneration(_ generation: Int) {
            generationGate.updateCurrentGeneration(generation)
        }

        deinit {
            panGestureRecognizer?.removeTarget(
                self,
                action: #selector(handlePan(_:))
            )
        }

        func attachIfNeeded(from view: UIView) {
            var ancestor = view.superview
            while let current = ancestor {
                if let scrollView = current as? UIScrollView {
                    let pan = scrollView.panGestureRecognizer
                    guard panGestureRecognizer !== pan else { return }
                    panGestureRecognizer?.removeTarget(
                        self,
                        action: #selector(handlePan(_:))
                    )
                    panGestureRecognizer = pan
                    pan.addTarget(self, action: #selector(handlePan(_:)))
                    return
                }
                ancestor = current.superview
            }
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let point = recognizer.translation(in: recognizer.view)
            switch recognizer.state {
            case .began:
                generationGate.beginGesture()
                previousTranslation = point
            case .changed:
                let delta = CGSize(
                    width: point.x - previousTranslation.x,
                    height: point.y - previousTranslation.y
                )
                previousTranslation = point
                guard generationGate.acceptsCurrentGestureEvent() else { return }
                if abs(delta.width) > 0.01 || abs(delta.height) > 0.01 {
                    onChanged(delta)
                }
            case .ended, .cancelled, .failed:
                let shouldNotify = generationGate.endGesture()
                if shouldNotify {
                    onEnded()
                }
                previousTranslation = .zero
            default:
                break
            }
        }
    }
}

/// Keeps the high-frequency collapse observation at the modifier boundary so a
/// 0.333pt scroll tick does not rebuild the complete card/list hierarchy.
private struct CardHolderCollapseTranslationModifier: ViewModifier {
    let collapseState: CardHolderHeaderCollapseState
    let expandedY: CGFloat
    let maximumOffset: CGFloat

    private var collapseOffset: CGFloat {
        min(max(collapseState.offset, 0), maximumOffset)
    }

    func body(content: Content) -> some View {
        content.offset(y: expandedY - collapseOffset)
    }
}

private struct MorphingCardHolderListLabel: View {
    let text: String
    let spreadProgress: CGFloat
    let revealProgress: CGFloat

    private var characters: [Character] {
        Array(text)
    }

    var body: some View {
        let spread = min(max(spreadProgress, 0), 1)
        let reveal = min(max(revealProgress, 0), 1)
        let characterWidth: CGFloat = 17
        let finalWidth = characterWidth * CGFloat(characters.count)
        let centerX = finalWidth / 2

        ZStack(alignment: .topLeading) {
            ForEach(Array(characters.enumerated()), id: \.offset) { index, character in
                let finalCenterX = characterWidth * (CGFloat(index) + 0.5)
                Text(String(character))
                    .font(CardaTheme.pingFang(size: 17, weight: .medium))
                    .foregroundStyle(Color.black)
                    .lineLimit(1)
                    .frame(width: characterWidth, height: 22, alignment: .center)
                    .position(
                        x: centerX + (finalCenterX - centerX) * spread,
                        y: 11
                    )
            }
        }
        .frame(width: finalWidth, height: 22, alignment: .topLeading)
        .compositingGroup()
        .blur(radius: 15 * (1 - reveal))
        .opacity(Double(reveal))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CardHolderAvatarMorphModifier: AnimatableModifier {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    private var clampedProgress: CGFloat {
        min(max(progress, 0), 1)
    }

    private var imageOpacity: Double {
        let progress = clampedProgress
        if progress <= 0.5 {
            return Double(1 - 0.8 * (progress / 0.5))
        }
        return Double(0.2 * (1 - (progress - 0.5) / 0.5))
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(1 + 0.08 * clampedProgress)
            .blur(radius: 15 * clampedProgress)
            .opacity(imageOpacity)
    }
}

private struct CardHolderHeaderChromeModifier: ViewModifier {
    let collapseState: CardHolderHeaderCollapseState
    let maximumOffset: CGFloat
    let clipTop: CGFloat

    private var collapseOffset: CGFloat {
        min(max(collapseState.offset, 0), maximumOffset)
    }

    func body(content: Content) -> some View {
        content
            .offset(y: -collapseOffset)
            .frame(
                width: CardaTheme.canvasWidth,
                height: CardaTheme.canvasHeight,
                alignment: .topLeading
            )
            .mask(alignment: .topLeading) {
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            Gradient.Stop(color: .clear, location: 0),
                            Gradient.Stop(color: .black.opacity(0.18), location: 0.35),
                            Gradient.Stop(color: .black.opacity(0.72), location: 0.75),
                            Gradient.Stop(color: .black, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: clipTop)

                    Rectangle()
                        .fill(Color.black)
                        .frame(height: CardaTheme.canvasHeight - clipTop)
                }
                .frame(
                    width: CardaTheme.canvasWidth,
                    height: CardaTheme.canvasHeight,
                    alignment: .topLeading
                )
            }
            .allowsHitTesting(collapseOffset < maximumOffset - 0.5)
    }
}

private struct CardHolderHeaderTextOpacityModifier: ViewModifier {
    let collapseState: CardHolderHeaderCollapseState
    let maximumOffset: CGFloat

    func body(content: Content) -> some View {
        content.modifier(
            CardHolderHeaderTextAnimatableOpacityModifier(
                collapseOffset: collapseState.offset,
                maximumOffset: maximumOffset
            )
        )
    }
}

/// Interpolates the collapse offset itself and derives opacity from that single
/// presentation value. A regular `opacity` animation only receives the binary
/// endpoint and can retain a stale presentation alpha when rapid reverse pans
/// repeatedly interrupt it.
private struct CardHolderHeaderTextAnimatableOpacityModifier: AnimatableModifier {
    var collapseOffset: CGFloat
    let maximumOffset: CGFloat

    var animatableData: CGFloat {
        get { collapseOffset }
        set { collapseOffset = newValue }
    }

    private var opacity: Double {
        guard maximumOffset > 0 else { return 1 }
        let progress = min(max(collapseOffset / maximumOffset, 0), 1)
        let fadeProgress = min(max((progress - 0.5) / 0.5, 0), 1)
        return Double(1 - fadeProgress)
    }

    func body(content: Content) -> some View {
        content.opacity(opacity)
    }
}

/// Scroll callbacks run at display cadence. Keeping offsets and pan-direction
/// thresholds in a reference store prevents bookkeeping writes from invalidating
/// the complete card-holder view hierarchy.
@MainActor
private final class HolderScrollRuntime {
    var groupedOffsetY: CGFloat = 0
    var listOffsetY: CGFloat = 0
    var direction: HolderHeaderScrollDirection?
    var pendingDirection: HolderHeaderScrollDirection?
    var pendingDistance: CGFloat = 0
}

/// Geometry is only consumed after a long press or drop begins. Storing every
/// scrolling frame in `@State` previously caused a broad invalidation storm.
@MainActor
private final class HolderGeometryFrameStore {
    var cardFrames: [UUID: CGRect] = [:]
    var listRowFrames: [String: CGRect] = [:]
}

private struct HolderCardGroupingCacheKey: Equatable {
    let id: UUID
    let name: String
    let organizationName: String
}

private struct HolderCardListCacheKey: Equatable {
    let id: UUID
    let cardListID: UUID?
    let createdAt: Date
}

private struct HolderListCacheKey: Equatable {
    let id: UUID
    let name: String
    let sortOrder: Int
    let createdAt: Date
}

/// Pinyin conversion and grouping are deliberately memoized outside `body` and
/// Anchor Preference resolution. Those paths execute repeatedly while scrolling.
@MainActor
private final class HolderDerivedDataCache {
    private var groupingKey: [HolderCardGroupingCacheKey] = []
    private var nameSections: [GroupedCardSection] = []
    private var organizationSections: [GroupedCardSection] = []
    private var cardListKey: [HolderCardListCacheKey] = []
    private var listKey: [HolderListCacheKey] = []
    private var cachedListRows: [HolderListRow] = []

    func groupedCards(
        for mode: HolderMode,
        cards: [BusinessCard]
    ) -> [GroupedCardSection] {
        guard mode != .list else { return [] }
        updateGroupedSectionsIfNeeded(cards: cards)
        return mode == .name ? nameSections : organizationSections
    }

    func listRows(
        cards: [BusinessCard],
        lists: [BusinessCardList]
    ) -> [HolderListRow] {
        let nextCardKey = cards.map {
            HolderCardListCacheKey(
                id: $0.id,
                cardListID: $0.cardListID,
                createdAt: $0.createdAt
            )
        }
        let nextListKey = lists.map {
            HolderListCacheKey(
                id: $0.id,
                name: $0.name,
                sortOrder: $0.sortOrder,
                createdAt: $0.createdAt
            )
        }
        guard nextCardKey != cardListKey || nextListKey != listKey else {
            return cachedListRows
        }

        cardListKey = nextCardKey
        listKey = nextListKey
        let validListIDs = Set(lists.map(\.id))
        let cardsByList = Dictionary(grouping: cards.compactMap { card -> (UUID, BusinessCard)? in
            guard let cardListID = card.cardListID, validListIDs.contains(cardListID) else {
                return nil
            }
            return (cardListID, card)
        }, by: \.0)
        let sortedLists = lists.sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.createdAt < $1.createdAt
            }
            return $0.sortOrder < $1.sortOrder
        }
        let assignedRows = sortedLists.map { list in
            let assignedCards = (cardsByList[list.id] ?? [])
                .map(\.1)
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
        cachedListRows = assignedRows + [
            HolderListRow(
                id: "uncategorized",
                listID: nil,
                title: "未分类（\(uncategorizedCards.count)）",
                cards: uncategorizedCards,
                isUncategorized: true
            )
        ]
        return cachedListRows
    }

    private func updateGroupedSectionsIfNeeded(cards: [BusinessCard]) {
        let nextKey = cards.map {
            HolderCardGroupingCacheKey(
                id: $0.id,
                name: $0.name,
                organizationName: $0.organizationName
            )
        }
        guard nextKey != groupingKey else { return }
        groupingKey = nextKey

        let records = cards.map(GroupedCardSortRecord.init(card:))
        let nameSorted = records.sorted { $0.nameSortKey < $1.nameSortKey }
        nameSections = Dictionary(grouping: nameSorted) { record in
            pinyinInitial(forSortKey: record.nameSortKey)
        }
        .map { key, records in
            GroupedCardSection(
                title: key.isEmpty ? "#" : key,
                cards: records.map(\.card)
            )
        }
        .sorted { alphabetSectionComesBefore($0.title, $1.title) }

        let organizationSorted = records.sorted { lhs, rhs in
            if lhs.organizationSortKey == rhs.organizationSortKey {
                return lhs.nameSortKey < rhs.nameSortKey
            }
            return lhs.organizationSortKey < rhs.organizationSortKey
        }
        organizationSections = Dictionary(grouping: organizationSorted) { record in
            pinyinInitial(forSortKey: record.organizationSortKey)
        }
        .map { initial, records in
            GroupedCardSection(
                title: initial,
                cards: records.map(\.card)
            )
        }
        .sorted { alphabetSectionComesBefore($0.title, $1.title) }
    }
}

private struct GroupedCardSection: Identifiable {
    let title: String
    let cards: [BusinessCard]

    var id: String { title }
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
    private let indicatorWidth: CGFloat = 69
    private let indicatorHeight: CGFloat = 58
    private let indicatorCenterX: CGFloat = -55.5

    @State private var lastDraggedLetter: String?
    @State private var activeLetter: String?
    @State private var activeLetterCenterY: CGFloat?
    @State private var indicatorDismissGeneration = 0
    @State private var suppressButtonSelection = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.cardaReduceMotion) private var settingsReduceMotion

    private var accessibilityReduceMotion: Bool {
        systemReduceMotion || settingsReduceMotion
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: letterSpacing) {
                ForEach(letters, id: \.self) { letter in
                    Button {
                        guard !suppressButtonSelection else { return }
                        select(letter, keepsIndicatorVisible: true)
                    } label: {
                        Text(letter)
                            .font(CardaTheme.sfPro(size: 11, weight: .semibold))
                            .tracking(0.06)
                            .foregroundStyle(activeLetter == letter ? Color.white : Color.black)
                            .frame(width: 22, height: letterHeight)
                            .background {
                                if activeLetter == letter {
                                    Circle()
                                        .fill(Color.black)
                                        .frame(width: 14, height: 14)
                                        .transition(.opacity)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("跳转到 \(letter)")
                }
            }
            .frame(width: 22, height: indexHeight, alignment: .center)

            if let activeLetter, let activeLetterCenterY {
                ContactAlphabetIndicator(letter: activeLetter)
                    .frame(width: indicatorWidth, height: indicatorHeight)
                    .position(x: indicatorCenterX, y: activeLetterCenterY)
                    .transition(indicatorTransition)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 22, height: indexHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    suppressButtonSelection = true
                    cancelScheduledIndicatorDismissal()
                    guard let selection = selection(at: value.location.y) else { return }

                    showIndicator(for: selection.letter, centerY: selection.centerY)
                    guard selection.letter != lastDraggedLetter else { return }
                    lastDraggedLetter = selection.letter
                    onSelect(selection.letter)
                }
                .onEnded { value in
                    lastDraggedLetter = nil
                    let movement = hypot(value.translation.width, value.translation.height)
                    scheduleIndicatorDismissal(after: movement > 4 ? 0.06 : 0.42)
                    DispatchQueue.main.async {
                        suppressButtonSelection = false
                    }
                }
        )
    }

    private var indicatorTransition: AnyTransition {
        if accessibilityReduceMotion {
            return .opacity
        }
        return .opacity.combined(with: .scale(scale: 0.96, anchor: .trailing))
    }

    private func selection(at y: CGFloat) -> (letter: String, centerY: CGFloat)? {
        let contentHeight =
            CGFloat(letters.count) * letterHeight
            + CGFloat(letters.count - 1) * letterSpacing
        let contentTop = (indexHeight - contentHeight) / 2
        let relativeY = y - contentTop
        guard relativeY >= 0, relativeY < contentHeight else { return nil }

        let rowHeight = letterHeight + letterSpacing
        let index = min(Int(relativeY / rowHeight), letters.count - 1)
        let centerY = contentTop + CGFloat(index) * rowHeight + letterHeight / 2
        return (letters[index], centerY)
    }

    private func select(_ letter: String, keepsIndicatorVisible: Bool) {
        guard let index = letters.firstIndex(of: letter) else { return }
        let rowHeight = letterHeight + letterSpacing
        let contentHeight =
            CGFloat(letters.count) * letterHeight
            + CGFloat(letters.count - 1) * letterSpacing
        let centerY = (indexHeight - contentHeight) / 2
            + CGFloat(index) * rowHeight
            + letterHeight / 2

        showIndicator(for: letter, centerY: centerY)
        onSelect(letter)
        if keepsIndicatorVisible {
            scheduleIndicatorDismissal(after: 0.42)
        }
    }

    private func showIndicator(for letter: String, centerY: CGFloat) {
        if activeLetter == nil {
            withAnimation(.easeOut(duration: 0.1)) {
                activeLetter = letter
                activeLetterCenterY = centerY
            }
        } else {
            activeLetter = letter
            activeLetterCenterY = centerY
        }
    }

    private func cancelScheduledIndicatorDismissal() {
        indicatorDismissGeneration += 1
    }

    private func scheduleIndicatorDismissal(after delay: TimeInterval) {
        indicatorDismissGeneration += 1
        let generation = indicatorDismissGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard generation == indicatorDismissGeneration else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                activeLetter = nil
                activeLetterCenterY = nil
            }
        }
    }
}

private struct ContactAlphabetIndicator: View {
    let letter: String

    var body: some View {
        ContactAlphabetIndicatorShape()
            .fill(CardaTheme.alphabetIndexIndicatorFill)
            .overlay(alignment: .topLeading) {
                Text(letter)
                    .font(CardaTheme.sfPro(size: 30, weight: .regular))
                    .foregroundStyle(Color.white)
                    .frame(width: 58, height: 58)
                    .position(x: 29, y: 29)
            }
    }
}

private struct ContactAlphabetIndicatorShape: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: rect.minX + x / 69 * rect.width,
                y: rect.minY + y / 58 * rect.height
            )
        }

        var path = Path()
        path.move(to: point(30, 0))
        path.addCurve(
            to: point(0, 29),
            control1: point(13, 0),
            control2: point(0, 13)
        )
        path.addCurve(
            to: point(30, 58),
            control1: point(0, 45),
            control2: point(13, 58)
        )
        path.addCurve(
            to: point(52, 48),
            control1: point(40, 58),
            control2: point(46, 54)
        )
        path.addCurve(
            to: point(68.5, 31),
            control1: point(58, 41),
            control2: point(64, 34)
        )
        path.addQuadCurve(
            to: point(68.5, 27),
            control: point(70.5, 29)
        )
        path.addCurve(
            to: point(52, 10),
            control1: point(64, 24),
            control2: point(58, 17)
        )
        path.addCurve(
            to: point(30, 0),
            control1: point(46, 4),
            control2: point(40, 0)
        )
        path.closeSubpath()
        return path
    }
}

private func pinyinInitial(forSortKey key: String) -> String {
    guard let scalar = key.unicodeScalars.first, CharacterSet.letters.contains(scalar) else { return "#" }
    return String(Character(scalar)).uppercased()
}

private func alphabetSectionComesBefore(_ lhs: String, _ rhs: String) -> Bool {
    guard lhs != rhs else { return false }
    if lhs == "#" { return false }
    if rhs == "#" { return true }
    return lhs < rhs
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
