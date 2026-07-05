//
//  AppShellView.swift
//  Carda
//

import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct AppShellView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query(sort: \BusinessCard.createdAt) private var cards: [BusinessCard]
    @Query(sort: \BusinessCardList.sortOrder) private var cardLists: [BusinessCardList]
    @State private var selectedSection: AppSection = .myCards
    @State private var isSearchActive = false
    @State private var isSearchEditing = false
    @State private var searchText = ""
    @State private var holderMode: HolderMode = .name
    @State private var isAddListDialogPresented = false
    @State private var newListName = ""
    @State private var isRenameListDialogPresented = false
    @State private var renameListTargetID: UUID?
    @State private var renameListName = ""
    @State private var isDeleteListConfirmationPresented = false
    @State private var deleteListTargetID: UUID?
    @State private var selectedContactAction: ShellContactAction?
    @State private var contactActionMessage: String?
    @FocusState private var searchFieldFocused: Bool
    @FocusState private var addListNameFocused: Bool
    @FocusState private var renameListNameFocused: Bool

    private var accountAvatarImageData: Data? {
        // Account login/profile storage is not implemented yet, so the shared
        // account avatar intentionally renders as the blank glass state for now.
        nil
    }

    private var accountName: String? {
        nil
    }

    private var accountEmail: String? {
        nil
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            activePageBackground

            ZStack(alignment: .topLeading) {
                activePageContent
            }
            .animation(.easeInOut(duration: 0.24), value: activePageKey)

            BottomNavigationBar(
                selectedSection: $selectedSection,
                isSearchActive: $isSearchActive,
                isSearchEditing: $isSearchEditing,
                searchText: $searchText,
                searchFieldFocused: $searchFieldFocused
            )
            .offset(x: 0, y: bottomNavigationTop)
            .animation(.snappy(duration: 0.28), value: bottomNavigationTop)
            .zIndex(1)

            if isAddListDialogPresented {
                Color.black.opacity(0.35)
                    .frame(width: CardaTheme.canvasWidth, height: CardaTheme.canvasHeight)
                    .contentShape(Rectangle())
                    .zIndex(2)

                addListDialog
                    .position(x: CardaTheme.canvasWidth / 2, y: 437)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                    .zIndex(3)
            }

            if isRenameListDialogPresented {
                Color.black.opacity(0.35)
                    .frame(width: CardaTheme.canvasWidth, height: CardaTheme.canvasHeight)
                    .contentShape(Rectangle())
                    .zIndex(2)

                renameListDialog
                    .position(x: CardaTheme.canvasWidth / 2, y: 437)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                    .zIndex(3)
            }

            contactActionOverlay
                .animation(
                    contactPopupAnimation,
                    value: selectedContactAction != nil
                )
                .zIndex(20)
        }
        .frame(width: CardaTheme.canvasWidth, height: CardaTheme.canvasHeight)
        .clipped()
        .alert("删除列表？", isPresented: $isDeleteListConfirmationPresented) {
            Button("删除", role: .destructive, action: deletePendingList)
            Button("取消", role: .cancel) {
                deleteListTargetID = nil
            }
        } message: {
            Text(deleteListConfirmationMessage)
        }
        .onChange(of: selectedSection) { _, _ in
            dismissAddListDialog()
            dismissRenameListDialog()
            dismissContactAction()
            deleteListTargetID = nil
            isDeleteListConfirmationPresented = false
        }
        .onChange(of: isSearchActive) { _, _ in
            dismissContactAction()
        }
        .task {
            ReceivedCardSampleSeeder.seedIfNeeded(in: modelContext, existingCards: cards)
            CardListSeeder.seedIfNeeded(in: modelContext, existingLists: cardLists)
        }
    }

    private var bottomNavigationTop: CGFloat {
        isSearchActive && isSearchEditing ? 448 : 779
    }

    private var activePageKey: String {
        if isSearchActive {
            return "search"
        }
        return selectedSection.rawValue
    }

    @ViewBuilder
    private var activePageContent: some View {
        if isSearchActive {
            CardSearchView(
                cardHolderCards: cardHolderCards,
                searchText: searchText,
                isEditing: isSearchEditing,
                showsPageBackground: false
            )
            .transition(.opacity)
        } else {
            switch selectedSection {
            case .myCards:
                MyCardsView(
                    accountAvatarImageData: accountAvatarImageData,
                    accountName: accountName,
                    accountEmail: accountEmail,
                    showsPageBackground: false
                )
                .transition(.opacity)
            case .cardHolder:
                CardHolderView(
                    cards: cardHolderCards,
                    accountAvatarImageData: accountAvatarImageData,
                    onAddList: presentAddListDialog,
                    onRenameList: presentRenameListDialog,
                    onDeleteList: presentDeleteListConfirmation,
                    onInfoAction: presentContactAction,
                    mode: $holderMode,
                    showsPageBackground: false
                )
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var activePageBackground: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            Color(red: 48 / 255, green: 49 / 255, blue: 54 / 255)
                .opacity(0.06)

            HolderModeTabsBackground(mode: holderMode)

            ShellCardHolderBackgroundShape(
                mode: holderMode,
                progress: showsCardHolderPanelBackground ? 1 : 0
            )
            .fill(holderPanelColor)
            .animation(
                .easeInOut(duration: 0.32),
                value: showsCardHolderPanelBackground
            )

            AnimatedHolderPanelCapShape(selectionPosition: holderMode.selectionPosition)
                .fill(holderPanelColor)
                .frame(width: CardaTheme.canvasWidth, height: 45)
                .offset(y: 126)
                .animation(.snappy(duration: 0.28), value: holderMode)
        }
    }

    private var showsCardHolderPanelBackground: Bool {
        !isSearchActive && selectedSection == .cardHolder
    }

    private var holderPanelColor: Color {
        CardaTheme.searchBackground
    }

    private var cardHolderCards: [BusinessCard] {
        cards.filter { $0.ownerKind == .received }
    }

    private var contactPopupAnimation: Animation {
        .timingCurve(0.37, 0, 0.63, 1, duration: 0.36)
    }

    @ViewBuilder
    private var contactActionOverlay: some View {
        if let selectedContactAction {
            Color.clear
                .frame(width: CardaTheme.canvasWidth, height: CardaTheme.canvasHeight)
                .contentShape(Rectangle())
                .onTapGesture(perform: dismissContactAction)
                .zIndex(20)

            contactActionBottomBlur
                .zIndex(21)

            ShellContactActionPopup(
                action: selectedContactAction,
                onCopy: {
                    copyContactValue(selectedContactAction.value)
                },
                onOpen: {
                    openContactAction(selectedContactAction)
                }
            )
            .position(x: CardaTheme.canvasWidth / 2, y: 751.5)
            .transition(
                .asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                )
            )
            .zIndex(22)
        }

        if let contactActionMessage {
            Text(contactActionMessage)
                .font(CardaTheme.pingFang(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.black.opacity(0.72)))
                .position(x: CardaTheme.canvasWidth / 2, y: 600)
                .transition(.opacity.combined(with: .scale))
                .zIndex(23)
        }
    }

    private var contactActionBottomBlur: some View {
        TransparentGradientBlur(
            height: 199,
            tintColor: Color(red: 225 / 255, green: 224 / 255, blue: 227 / 255),
            tintOpacity: 0.28
        )
        .offset(y: 675)
        .allowsHitTesting(false)
    }

    private var addListDialog: some View {
        VStack(spacing: 0) {
            Text("创建新的列表")
                .font(CardaTheme.pingFang(size: 17, weight: .semibold))
                .foregroundStyle(Color.black)
                .frame(height: 62)

            TextField(
                "",
                text: $newListName,
                prompt: Text("列表名称")
                    .foregroundStyle(Color.black.opacity(0.35))
            )
            .focused($addListNameFocused)
            .font(CardaTheme.pingFang(size: 17, weight: .semibold))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 16)
            .frame(width: 272, height: 52)
            .background(
                Capsule()
                    .fill(Color(red: 0.82, green: 0.82, blue: 0.84).opacity(0.72))
            )
            .submitLabel(.done)
            .onSubmit(createList)

            Button(action: createList) {
                Text("创建")
                    .font(CardaTheme.pingFang(size: 17, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 272, height: 49)
                    .background(
                        Capsule()
                            .fill(canCreateList ? Color.blue : Color.gray.opacity(0.45))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canCreateList)
            .padding(.top, 20)

            Button(action: dismissAddListDialog) {
                Text("取消")
                    .font(CardaTheme.pingFang(size: 17, weight: .regular))
                    .foregroundStyle(Color.red)
                    .frame(width: 272, height: 48)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.82, green: 0.82, blue: 0.84).opacity(0.72))
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 9)
        }
        .frame(width: 300, height: 254, alignment: .top)
        .background(
            FigmaGlassShape(cornerRadius: 36)
        )
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
    }

    private var renameListDialog: some View {
        VStack(spacing: 0) {
            Text("修改列表名称")
                .font(CardaTheme.pingFang(size: 17, weight: .semibold))
                .foregroundStyle(Color.black)
                .frame(height: 62)

            TextField(
                "",
                text: $renameListName,
                prompt: Text("列表名称")
                    .foregroundStyle(Color.black.opacity(0.35))
            )
            .focused($renameListNameFocused)
            .font(CardaTheme.pingFang(size: 17, weight: .semibold))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 16)
            .frame(width: 272, height: 52)
            .background(
                Capsule()
                    .fill(Color(red: 0.82, green: 0.82, blue: 0.84).opacity(0.72))
            )
            .submitLabel(.done)
            .onSubmit(renameList)

            Button(action: renameList) {
                Text("确定")
                    .font(CardaTheme.pingFang(size: 17, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 272, height: 49)
                    .background(
                        Capsule()
                            .fill(canRenameList ? Color.blue : Color.gray.opacity(0.45))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canRenameList)
            .padding(.top, 20)

            Button(action: dismissRenameListDialog) {
                Text("取消")
                    .font(CardaTheme.pingFang(size: 17, weight: .regular))
                    .foregroundStyle(Color.red)
                    .frame(width: 272, height: 48)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.82, green: 0.82, blue: 0.84).opacity(0.72))
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 9)
        }
        .frame(width: 300, height: 254, alignment: .top)
        .background(
            FigmaGlassShape(cornerRadius: 36)
        )
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
    }

    private var trimmedNewListName: String {
        newListName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCreateList: Bool {
        !trimmedNewListName.isEmpty
    }

    private var renameTargetList: BusinessCardList? {
        guard let renameListTargetID else { return nil }
        return cardLists.first { $0.id == renameListTargetID }
    }

    private var trimmedRenameListName: String {
        renameListName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canRenameList: Bool {
        !trimmedRenameListName.isEmpty
    }

    private var deleteListConfirmationMessage: String {
        guard
            let deleteListTargetID,
            let list = cardLists.first(where: { $0.id == deleteListTargetID })
        else {
            return "是否删除该列表？"
        }

        return "是否删除“\(list.name)”列表？列表中的名片会移入未分类。"
    }

    private func presentAddListDialog() {
        dismissContactAction()
        dismissRenameListDialog()
        newListName = ""
        withAnimation(.snappy(duration: 0.24)) {
            isAddListDialogPresented = true
        }
    }

    private func dismissAddListDialog() {
        addListNameFocused = false
        withAnimation(.snappy(duration: 0.2)) {
            isAddListDialogPresented = false
        }
        newListName = ""
    }

    private func presentRenameListDialog(_ list: BusinessCardList) {
        dismissContactAction()
        dismissAddListDialog()
        renameListTargetID = list.id
        renameListName = list.name

        withAnimation(.snappy(duration: 0.24)) {
            isRenameListDialogPresented = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            renameListNameFocused = true
        }
    }

    private func dismissRenameListDialog() {
        renameListNameFocused = false
        withAnimation(.snappy(duration: 0.2)) {
            isRenameListDialogPresented = false
        }
        renameListTargetID = nil
        renameListName = ""
    }

    private func createList() {
        guard canCreateList else { return }

        for list in cardLists {
            list.sortOrder += 1
            list.updatedAt = Date()
        }
        modelContext.insert(
            BusinessCardList(
                name: trimmedNewListName,
                sortOrder: 0
            )
        )

        do {
            try modelContext.save()
            dismissAddListDialog()
        } catch {
            modelContext.rollback()
        }
    }

    private func renameList() {
        guard canRenameList, let list = renameTargetList else { return }

        list.name = trimmedRenameListName
        list.updatedAt = Date()

        do {
            try modelContext.save()
            dismissRenameListDialog()
        } catch {
            modelContext.rollback()
        }
    }

    private func presentDeleteListConfirmation(_ list: BusinessCardList) {
        dismissContactAction()
        dismissAddListDialog()
        dismissRenameListDialog()
        deleteListTargetID = list.id
        isDeleteListConfirmationPresented = true
    }

    private func presentContactAction(kind: CardFieldKind, value: String) {
        dismissAddListDialog()
        dismissRenameListDialog()
        deleteListTargetID = nil
        isDeleteListConfirmationPresented = false

        withAnimation(contactPopupAnimation) {
            selectedContactAction = ShellContactAction(kind: kind, value: value)
        }
    }

    private func dismissContactAction() {
        guard selectedContactAction != nil else { return }
        withAnimation(contactPopupAnimation) {
            selectedContactAction = nil
        }
    }

    private func copyContactValue(_ value: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = value
        #endif
        dismissContactAction()
        showContactActionMessage("已复制")
    }

    private func openContactAction(_ action: ShellContactAction) {
        guard let url = actionURL(for: action) else {
            dismissContactAction()
            showContactActionMessage("内容无效")
            return
        }

        dismissContactAction()
        openURL(url) { accepted in
            if !accepted {
                showContactActionMessage(action.failureMessage)
            }
        }
    }

    private func actionURL(for action: ShellContactAction) -> URL? {
        switch action.kind {
        case .phone:
            let allowedCharacters = CharacterSet(charactersIn: "+0123456789*#")
            let sanitized = action.value.unicodeScalars
                .filter { allowedCharacters.contains($0) }
                .map(String.init)
                .joined()
            guard !sanitized.isEmpty else { return nil }
            return URL(string: "tel://\(sanitized.replacingOccurrences(of: "#", with: "%23"))")

        case .email:
            guard let encoded = action.value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
                return nil
            }
            return URL(string: "mailto:\(encoded)")

        case .address:
            var components = URLComponents(string: "http://maps.apple.com/")
            components?.queryItems = [URLQueryItem(name: "q", value: action.value)]
            return components?.url

        case .link:
            let trimmed = action.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if let url = URL(string: trimmed), url.scheme != nil {
                return url
            }
            return URL(string: "https://\(trimmed)")

        case .companyLogo:
            return nil
        }
    }

    private func showContactActionMessage(_ message: String) {
        withAnimation(.snappy(duration: 0.16)) {
            contactActionMessage = message
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            guard contactActionMessage == message else { return }
            withAnimation(.snappy(duration: 0.16)) {
                contactActionMessage = nil
            }
        }
    }

    private func deletePendingList() {
        guard
            let deleteListTargetID,
            let list = cardLists.first(where: { $0.id == deleteListTargetID })
        else {
            self.deleteListTargetID = nil
            return
        }

        let removedSortOrder = list.sortOrder
        for card in cards where card.cardListID == deleteListTargetID {
            card.cardListID = nil
            card.updatedAt = Date()
        }
        for remainingList in cardLists where remainingList.id != deleteListTargetID {
            if remainingList.sortOrder > removedSortOrder {
                remainingList.sortOrder -= 1
                remainingList.updatedAt = Date()
            }
        }
        modelContext.delete(list)

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
        }

        self.deleteListTargetID = nil
    }
}

private struct ShellContactAction: Identifiable {
    let id = UUID()
    let kind: CardFieldKind
    let value: String

    var title: String {
        switch kind {
        case .phone:
            "电话号码"
        case .email:
            "电子邮箱"
        case .address:
            "地址"
        case .link:
            "网站"
        case .companyLogo:
            "信息"
        }
    }

    var openButtonTitle: String {
        switch kind {
        case .phone:
            "拨打"
        case .email:
            "邮件"
        case .address:
            "查询"
        case .link:
            "前往"
        case .companyLogo:
            "打开"
        }
    }

    var failureMessage: String {
        switch kind {
        case .phone:
            "无法打开电话"
        case .email:
            "无法打开邮箱"
        case .address:
            "无法打开地图"
        case .link:
            "无法打开网站"
        case .companyLogo:
            "无法打开"
        }
    }
}

private struct ShellContactActionPopup: View {
    let action: ShellContactAction
    let onCopy: () -> Void
    let onOpen: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ShellContactActionPopupBackground()

            VStack(spacing: 9) {
                Text(action.title)
                    .font(CardaTheme.pingFang(size: 17, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .lineLimit(1)
                    .frame(width: 256, height: 22)

                Text(action.value)
                    .font(CardaTheme.sfPro(size: 17, weight: .regular))
                    .foregroundStyle(Color.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(width: 256, height: 22)
            }
            .frame(width: 256, height: 54, alignment: .top)
            .offset(x: 22, y: 21)

            HStack(spacing: 12) {
                contactActionButton(title: "复制", action: onCopy)
                contactActionButton(title: action.openButtonTitle, action: onOpen)
            }
            .offset(x: 14, y: 91)
        }
        .frame(width: 300, height: 153)
        .accessibilityElement(children: .contain)
    }

    private func contactActionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(CardaTheme.pingFang(size: 17, weight: .semibold))
                .foregroundStyle(Color.black)
                .lineLimit(1)
                .frame(width: 130, height: 48)
                .background(
                    Capsule()
                        .fill(Color(red: 225 / 255, green: 225 / 255, blue: 227 / 255))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ShellContactActionPopupBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 32, style: .continuous)
            .fill(Color.white.opacity(0.72))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(Color.white.opacity(0.58), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.08), radius: 38, x: 0, y: 18)
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 1)
    }
}

private struct ShellCardHolderBackgroundShape: Shape {
    let mode: HolderMode
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let progress = min(max(progress, 0), 1)
        let top = rect.minY + 126 * progress
        let bodyY = top + 38 * progress
        let radius = 19 * progress
        let targetTab = targetTabFrame(in: rect)
        let tabMinX = rect.minX + (targetTab.minX - rect.minX) * progress
        let tabMaxX = rect.maxX + (targetTab.maxX - rect.maxX) * progress

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))

        switch mode {
        case .list:
            path.addLine(to: CGPoint(x: rect.minX, y: top + radius))
            addCorner(
                to: &path,
                via: CGPoint(x: rect.minX, y: top),
                end: CGPoint(x: rect.minX + radius, y: top),
                radius: radius
            )
            path.addLine(to: CGPoint(x: tabMaxX - radius, y: top))
            addCorner(
                to: &path,
                via: CGPoint(x: tabMaxX, y: top),
                end: CGPoint(x: tabMaxX, y: top + radius),
                radius: radius
            )
            path.addLine(to: CGPoint(x: tabMaxX, y: bodyY - radius))
            addCorner(
                to: &path,
                via: CGPoint(x: tabMaxX, y: bodyY),
                end: CGPoint(x: tabMaxX + radius, y: bodyY),
                radius: radius
            )

        case .name:
            path.addLine(to: CGPoint(x: rect.minX, y: bodyY + radius))
            addCorner(
                to: &path,
                via: CGPoint(x: rect.minX, y: bodyY),
                end: CGPoint(x: rect.minX + radius, y: bodyY),
                radius: radius
            )
            path.addLine(to: CGPoint(x: tabMinX - radius, y: bodyY))
            addCorner(
                to: &path,
                via: CGPoint(x: tabMinX, y: bodyY),
                end: CGPoint(x: tabMinX, y: bodyY - radius),
                radius: radius
            )
            path.addLine(to: CGPoint(x: tabMinX, y: top + radius))
            addCorner(
                to: &path,
                via: CGPoint(x: tabMinX, y: top),
                end: CGPoint(x: tabMinX + radius, y: top),
                radius: radius
            )
            path.addLine(to: CGPoint(x: tabMaxX - radius, y: top))
            addCorner(
                to: &path,
                via: CGPoint(x: tabMaxX, y: top),
                end: CGPoint(x: tabMaxX, y: top + radius),
                radius: radius
            )
            path.addLine(to: CGPoint(x: tabMaxX, y: bodyY - radius))
            addCorner(
                to: &path,
                via: CGPoint(x: tabMaxX, y: bodyY),
                end: CGPoint(x: tabMaxX + radius, y: bodyY),
                radius: radius
            )

        case .organization:
            path.addLine(to: CGPoint(x: rect.minX, y: bodyY + radius))
            addCorner(
                to: &path,
                via: CGPoint(x: rect.minX, y: bodyY),
                end: CGPoint(x: rect.minX + radius, y: bodyY),
                radius: radius
            )
            path.addLine(to: CGPoint(x: tabMinX - radius, y: bodyY))
            addCorner(
                to: &path,
                via: CGPoint(x: tabMinX, y: bodyY),
                end: CGPoint(x: tabMinX, y: bodyY - radius),
                radius: radius
            )
            path.addLine(to: CGPoint(x: tabMinX, y: top + radius))
            addCorner(
                to: &path,
                via: CGPoint(x: tabMinX, y: top),
                end: CGPoint(x: tabMinX + radius, y: top),
                radius: radius
            )
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: top))
            addCorner(
                to: &path,
                via: CGPoint(x: rect.maxX, y: top),
                end: CGPoint(x: rect.maxX, y: top + radius),
                radius: radius
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
            return path
        }

        path.addLine(to: CGPoint(x: rect.maxX - radius, y: bodyY))
        addCorner(
            to: &path,
            via: CGPoint(x: rect.maxX, y: bodyY),
            end: CGPoint(x: rect.maxX, y: bodyY + radius),
            radius: radius
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }

    private func targetTabFrame(in rect: CGRect) -> CGRect {
        let x: CGFloat
        switch mode {
        case .list:
            x = rect.minX
        case .name:
            x = rect.minX + 134
        case .organization:
            x = rect.minX + 268
        }
        return CGRect(x: x, y: rect.minY + 126, width: 134, height: 38)
    }

    private func addCorner(
        to path: inout Path,
        via corner: CGPoint,
        end: CGPoint,
        radius: CGFloat
    ) {
        guard radius > 0.001 else {
            path.addLine(to: corner)
            path.addLine(to: end)
            return
        }
        path.addArc(
            tangent1End: corner,
            tangent2End: end,
            radius: radius
        )
    }
}
