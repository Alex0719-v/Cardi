//
//  AppShellView.swift
//  Cardi
//

import Observation
import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum AccountPreferenceKeys {
    static let avatarImageData = "accountProfile.avatarImageData"
    static let name = "accountProfile.name"
    static let phoneNumber = "accountProfile.phoneNumber"
    static let email = "accountProfile.email"
    static let hasActivatedLocalAccountStorage = "accountProfile.hasActivatedLocalAccountStorage"
}

struct AppShellView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \BusinessCard.createdAt) private var cards: [BusinessCard]
    @Query(sort: \BusinessCardList.sortOrder) private var cardLists: [BusinessCardList]
    @AppStorage(LinkedApplicationPreferenceKeys.browser)
    private var selectedBrowserApplication = LinkedApplicationCategory.browser.defaultApplicationID.rawValue
    @AppStorage(LinkedApplicationPreferenceKeys.mail)
    private var selectedMailApplication = LinkedApplicationCategory.mail.defaultApplicationID.rawValue
    @AppStorage(LinkedApplicationPreferenceKeys.maps)
    private var selectedMapsApplication = LinkedApplicationCategory.maps.defaultApplicationID.rawValue
    @AppStorage(AccountPreferenceKeys.avatarImageData)
    private var storedAccountAvatarImageData = Data()
    @AppStorage(AccountPreferenceKeys.name)
    private var storedAccountName = ""
    @AppStorage(AccountPreferenceKeys.phoneNumber)
    private var storedAccountPhoneNumber = ""
    @AppStorage(AccountPreferenceKeys.email)
    private var storedAccountEmail = ""
    @AppStorage(AccountPreferenceKeys.hasActivatedLocalAccountStorage)
    private var hasActivatedLocalAccountStorage = false
    @AppStorage(CardaSettingsPreferenceKeys.defaultCardSort)
    private var defaultCardSortRawValue = CardaDefaultCardSort.defaultValue.rawValue
    @State private var selectedSection: AppSection = .myCards
    @State private var isSearchActive = false
    @State private var isSearchEditing = false
    @State private var searchText = ""
    @State private var holderMode: HolderMode = .name
    @State private var cardHolderHeaderCollapseState = CardHolderHeaderCollapseState()
    @State private var isAddListDialogPresented = false
    @State private var newListName = ""
    @State private var isRenameListDialogPresented = false
    @State private var renameListTargetID: UUID?
    @State private var renameListName = ""
    @State private var isDeleteListConfirmationPresented = false
    @State private var deleteListTargetID: UUID?
    @State private var selectedContactAction: ShellContactAction?
    @State private var contactActionMessage: String?
    @State private var hasFinishedInitialDataSetup = false
    @FocusState private var searchFieldFocused: Bool
    @FocusState private var addListNameFocused: Bool
    @FocusState private var renameListNameFocused: Bool

    private var accountAvatarImageData: Data? {
        storedAccountAvatarImageData.isEmpty ? nil : storedAccountAvatarImageData
    }

    private var accountName: String? {
        normalizedAccountValue(storedAccountName)
    }

    private var accountEmail: String? {
        normalizedAccountValue(storedAccountEmail)
    }

    private var accountPhoneNumber: String? {
        LocalAccountCardStore.canonicalPhoneNumber(storedAccountPhoneNumber)
    }

    private var isAccountLoggedIn: Bool {
        normalizedAccountValue(accountName) != nil
            && accountPhoneNumber != nil
            && normalizedAccountValue(accountEmail) != nil
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            activePageBackground

            ZStack(alignment: .topLeading) {
                activePageContent
            }
            .animation(.easeInOut(duration: 0.24), value: selectedSection)
            .animation(
                .timingCurve(0.2, 0.72, 0.18, 1, duration: 0.42),
                value: isSearchActive
            )

            BottomNavigationBar(
                selectedSection: $selectedSection,
                isSearchActive: $isSearchActive,
                isSearchEditing: $isSearchEditing,
                searchText: $searchText,
                searchFieldFocused: $searchFieldFocused
            )
            .offset(x: 0, y: bottomNavigationTop)
            .animation(searchLiftAnimation, value: bottomNavigationTop)
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
            resetCardHolderHeaderCollapseOffset()
            dismissAddListDialog()
            dismissRenameListDialog()
            dismissContactAction()
            deleteListTargetID = nil
            isDeleteListConfirmationPresented = false
        }
        .onChange(of: isSearchActive) { _, _ in
            resetCardHolderHeaderCollapseOffset()
            dismissContactAction()
        }
        .onChange(of: defaultCardSortRawValue) { _, _ in
            applyDefaultCardSort()
        }
        .onChange(of: localAccountDataFingerprint) { _, _ in
            guard hasFinishedInitialDataSetup else { return }
            archiveCurrentAccountIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .inactive || newPhase == .background {
                archiveCurrentAccountIfNeeded()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .cardExchangeDiagnosticsDidStart
            )
        ) { _ in
            isSearchActive = false
            selectedSection = .myCards
        }
        .task {
            #if DEBUG && targetEnvironment(simulator)
            resetDefaultCardSortForUITestsIfNeeded()
            #endif
            applyDefaultCardSort()
            #if DEBUG && targetEnvironment(simulator)
            resetAccountProfileForUITestsIfNeeded()
            seedAccountAvatarForUITestsIfNeeded()
            let didPrepareLocalAccountUITestData = prepareLocalAccountUITestDataIfNeeded()
            #else
            let didPrepareLocalAccountUITestData = false
            #endif
            if !didPrepareLocalAccountUITestData && !hasActivatedLocalAccountStorage {
                CardListSeeder.seedIfNeeded(in: modelContext, existingLists: cardLists)
            }
            initializeLocalAccountStorage()
            removePreviouslyImportedCardsForRelease()
            hasFinishedInitialDataSetup = true
        }
    }

    private var bottomNavigationTop: CGFloat {
        isSearchActive && isSearchEditing ? 448 : 779
    }

    private var searchLiftAnimation: Animation {
        .timingCurve(0.2, 0.72, 0.18, 1, duration: 0.52)
    }

    private func applyDefaultCardSort() {
        let preference = CardaDefaultCardSort(rawValue: defaultCardSortRawValue) ?? .defaultValue
        switch preference {
        case .recent:
            holderMode = .list
        case .name:
            holderMode = .name
        case .organization:
            holderMode = .organization
        }
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
                    accountPhoneNumber: accountPhoneNumber,
                    accountEmail: accountEmail,
                    isAccountLoggedIn: isAccountLoggedIn,
                    onUpdateAccount: updateAccountProfile,
                    onLogout: logoutCurrentAccount,
                    showsPageBackground: false
                )
                .transition(.opacity)
            case .cardHolder:
                CardHolderView(
                    cards: cardHolderCards,
                    accountAvatarImageData: accountAvatarImageData,
                    accountName: accountName,
                    accountPhoneNumber: accountPhoneNumber,
                    accountEmail: accountEmail,
                    isAccountLoggedIn: isAccountLoggedIn,
                    onUpdateAccount: updateAccountProfile,
                    onLogout: logoutCurrentAccount,
                    onAddList: presentAddListDialog,
                    onRenameList: presentRenameListDialog,
                    onDeleteList: presentDeleteListConfirmation,
                    onInfoAction: presentContactAction,
                    mode: $holderMode,
                    headerCollapseState: cardHolderHeaderCollapseState,
                    showsPageBackground: false
                )
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var activePageBackground: some View {
        AppShellCardHolderBackground(
            mode: holderMode,
            showsPanel: showsCardHolderPanelBackground,
            collapseState: cardHolderHeaderCollapseState,
            panelColor: holderPanelColor
        )
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

    private func normalizedAccountValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func updateAccountProfile(
        avatarImageData: Data?,
        name: String,
        email: String,
        phoneNumber: String
    ) -> Bool {
        guard
            let newPhoneNumber = LocalAccountCardStore.canonicalPhoneNumber(phoneNumber)
        else {
            return false
        }

        let store = LocalAccountCardStore()
        let previousPhoneNumber = accountPhoneNumber
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            if previousPhoneNumber != newPhoneNumber {
                if let previousPhoneNumber {
                    try store.saveCurrentDatabase(
                        for: previousPhoneNumber,
                        in: modelContext
                    )
                }

                if try store.archiveExists(for: newPhoneNumber) {
                    try store.restoreDatabaseIfPresent(
                        for: newPhoneNumber,
                        in: modelContext
                    )
                } else if previousPhoneNumber != nil {
                    try store.clearCurrentDatabase(in: modelContext)
                    try store.saveCurrentDatabase(
                        for: newPhoneNumber,
                        in: modelContext
                    )
                } else {
                    try store.saveCurrentDatabase(
                        for: newPhoneNumber,
                        in: modelContext
                    )
                }
            } else {
                try store.saveCurrentDatabase(
                    for: newPhoneNumber,
                    in: modelContext
                )
            }

            try store.saveProfile(
                LocalAccountProfile(
                    avatarImageData: avatarImageData,
                    name: normalizedName,
                    phoneNumber: newPhoneNumber,
                    email: normalizedEmail
                )
            )

            storedAccountAvatarImageData = avatarImageData ?? Data()
            storedAccountName = normalizedName
            storedAccountPhoneNumber = newPhoneNumber
            storedAccountEmail = normalizedEmail
            hasActivatedLocalAccountStorage = true
            return true
        } catch {
            return false
        }
    }

    private func logoutCurrentAccount() -> Bool {
        guard let accountPhoneNumber else { return false }

        do {
            let store = LocalAccountCardStore()
            try store.saveCurrentDatabase(for: accountPhoneNumber, in: modelContext)
            try store.clearCurrentDatabase(in: modelContext)

            storedAccountAvatarImageData = Data()
            storedAccountName = ""
            storedAccountPhoneNumber = ""
            storedAccountEmail = ""
            hasActivatedLocalAccountStorage = true
            return true
        } catch {
            return false
        }
    }

    private func initializeLocalAccountStorage() {
        guard let accountPhoneNumber else { return }

        do {
            let store = LocalAccountCardStore()
            if cards.isEmpty,
               cardLists.isEmpty,
               try store.archiveExists(for: accountPhoneNumber) {
                try store.restoreDatabaseIfPresent(
                    for: accountPhoneNumber,
                    in: modelContext
                )
            } else {
                try store.saveCurrentDatabase(
                    for: accountPhoneNumber,
                    in: modelContext
                )
            }
        } catch {
            // Keep the live SwiftData database untouched when a backup cannot be read or written.
        }
    }

    private func removePreviouslyImportedCardsForRelease() {
        let store = LocalAccountCardStore()
        let removedFromCurrentDatabase = (
            try? PreviouslyImportedCardCleanup.removeFromCurrentDatabase(in: modelContext)
        ) ?? 0

        if removedFromCurrentDatabase > 0, let accountPhoneNumber {
            _ = try? store.saveCurrentDatabase(
                for: accountPhoneNumber,
                in: modelContext
            )
        }

        _ = try? store.removePreviouslyImportedCardsFromAllArchives()
    }

    private func archiveCurrentAccountIfNeeded() {
        guard let accountPhoneNumber else { return }
        _ = try? LocalAccountCardStore().saveCurrentDatabase(
            for: accountPhoneNumber,
            in: modelContext
        )
    }

    private var localAccountDataFingerprint: Int {
        var hasher = Hasher()
        for card in cards.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            card.id.hash(into: &hasher)
            card.ownerKindRaw.hash(into: &hasher)
            card.name.hash(into: &hasher)
            card.phoneticName.hash(into: &hasher)
            card.position.hash(into: &hasher)
            card.organizationName.hash(into: &hasher)
            card.avatarImageData?.hash(into: &hasher)
            card.companyLogoImageData?.hash(into: &hasher)
            card.cardListID?.hash(into: &hasher)
            card.createdAt.hash(into: &hasher)
            card.updatedAt.hash(into: &hasher)
            card.receivedAt?.hash(into: &hasher)
            for field in card.sortedFields {
                field.id.hash(into: &hasher)
                field.kindRaw.hash(into: &hasher)
                field.value.hash(into: &hasher)
                field.sortOrder.hash(into: &hasher)
                field.createdAt.hash(into: &hasher)
            }
        }
        for list in cardLists.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            list.id.hash(into: &hasher)
            list.name.hash(into: &hasher)
            list.sortOrder.hash(into: &hasher)
            list.createdAt.hash(into: &hasher)
            list.updatedAt.hash(into: &hasher)
        }
        return hasher.finalize()
    }

    #if DEBUG && targetEnvironment(simulator)
    private func resetDefaultCardSortForUITestsIfNeeded() {
        guard ProcessInfo.processInfo.environment["CARDA_RESET_DEFAULT_CARD_SORT"] == "1" else {
            return
        }

        UserDefaults.standard.removeObject(forKey: CardaSettingsPreferenceKeys.defaultCardSort)
        defaultCardSortRawValue = CardaDefaultCardSort.defaultValue.rawValue
    }

    private func resetAccountProfileForUITestsIfNeeded() {
        guard ProcessInfo.processInfo.environment["CARDA_RESET_ACCOUNT_PROFILE"] == "1" else {
            return
        }
        storedAccountAvatarImageData = Data()
        storedAccountName = ""
        storedAccountPhoneNumber = ""
        storedAccountEmail = ""
    }

    private func seedAccountAvatarForUITestsIfNeeded() {
        guard
            ProcessInfo.processInfo.environment["CARDA_SEED_ACCOUNT_AVATAR"] == "1",
            let avatarImageData = UIImage(named: "TemporaryHolderAvatar")?.pngData()
        else {
            return
        }

        storedAccountAvatarImageData = avatarImageData
        storedAccountName = "头像验证"
        storedAccountPhoneNumber = "13800019999"
        storedAccountEmail = "avatar@cardi.local"
    }

    private func prepareLocalAccountUITestDataIfNeeded() -> Bool {
        guard
            ProcessInfo.processInfo.environment["CARDA_SEED_LOCAL_ACCOUNT_TEST_DATA"] == "1",
            let phoneNumber = ProcessInfo.processInfo.environment["CARDA_LOCAL_ACCOUNT_TEST_PHONE"],
            LocalAccountCardStore.canonicalPhoneNumber(phoneNumber) != nil
        else {
            return false
        }

        let store = LocalAccountCardStore()
        do {
            try store.removeAccountDirectory(for: phoneNumber)
            try LocalAccountCredentialStore().removeCredential(for: phoneNumber)
            try store.clearCurrentDatabase(in: modelContext)

            let listID = UUID()
            modelContext.insert(
                BusinessCardList(
                    id: listID,
                    name: "本地归档测试列表",
                    sortOrder: 0
                )
            )
            modelContext.insert(
                BusinessCard(
                    ownerKind: .mine,
                    name: ProcessInfo.processInfo.environment[
                        "CARDA_LOCAL_ACCOUNT_TEST_CARD_NAME"
                    ] ?? "本地归档测试名片",
                    phoneticName: "Local Archive",
                    position: "测试",
                    organizationName: "Cardi",
                    fields: [
                        CardInfoField(
                            kind: .phone,
                            value: phoneNumber,
                            sortOrder: 0
                        )
                    ]
                )
            )
            modelContext.insert(
                BusinessCard(
                    ownerKind: .received,
                    name: "本地归档测试联系人",
                    phoneticName: "Local Contact",
                    position: "测试",
                    organizationName: "Cardi",
                    cardListID: listID,
                    fields: [
                        CardInfoField(
                            kind: .email,
                            value: "archive@carda.local",
                            sortOrder: 0
                        )
                    ],
                    receivedAt: Date()
                )
            )
            if ProcessInfo.processInfo.environment[
                "CARDA_SEED_CARD_HOLDER_BATCH_TEST_DATA"
            ] == "1" {
                let batchCards = [
                    ("批量移动测试甲", "Batch Move A", "batch-a@carda.local"),
                    ("批量移动测试乙", "Batch Move B", "batch-b@carda.local")
                ]
                for (index, card) in batchCards.enumerated() {
                    modelContext.insert(
                        BusinessCard(
                            ownerKind: .received,
                            name: card.0,
                            phoneticName: card.1,
                            position: "拖放测试",
                            organizationName: "Batch",
                            fields: [
                                CardInfoField(
                                    kind: .email,
                                    value: card.2,
                                    sortOrder: 0
                                )
                            ],
                            receivedAt: Date().addingTimeInterval(
                                -TimeInterval(index + 1)
                            )
                        )
                    )
                }
            }
            try modelContext.save()

            storedAccountAvatarImageData = Data()
            storedAccountName = ""
            storedAccountPhoneNumber = ""
            storedAccountEmail = ""
            hasActivatedLocalAccountStorage = false
            return true
        } catch {
            return false
        }
    }
    #endif

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

    private func resetCardHolderHeaderCollapseOffset() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            cardHolderHeaderCollapseState.offset = 0
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
        if action.kind == .phone {
            guard let url = phoneURL(for: action.value) else {
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
            return
        }

        guard action.kind != .companyLogo else {
            dismissContactAction()
            showContactActionMessage("内容无效")
            return
        }

        dismissContactAction()
        Task { @MainActor in
            let outcome = await LinkedApplicationRouter.open(
                kind: action.kind,
                value: action.value,
                selectedBrowserRawValue: selectedBrowserApplication,
                selectedMailRawValue: selectedMailApplication,
                selectedMapsRawValue: selectedMapsApplication
            )
            if let message = outcome.message {
                showContactActionMessage(message)
            }
        }
    }

    private func phoneURL(for value: String) -> URL? {
        let allowedCharacters = CharacterSet(charactersIn: "+0123456789*#")
        let sanitized = value.unicodeScalars
            .filter { allowedCharacters.contains($0) }
            .map(String.init)
            .joined()
        guard !sanitized.isEmpty else { return nil }
        return URL(string: "tel://\(sanitized.replacingOccurrences(of: "#", with: "%23"))")
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

private struct AppShellCardHolderBackground: View {
    let mode: HolderMode
    let showsPanel: Bool
    let collapseState: CardHolderHeaderCollapseState
    let panelColor: Color

    private var collapseOffset: CGFloat {
        min(max(collapseState.offset, 0), 110)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            Color(red: 48 / 255, green: 49 / 255, blue: 54 / 255)
                .opacity(0.06)

            HolderModeTabsBackground(mode: mode)
                .offset(y: -collapseOffset)
                .mask(alignment: .topLeading) {
                    headerVisibilityMask
                }

            // Moving the 874pt Union upward can expose at most 110pt at the
            // bottom. Fill that fixed region without enlarging the Shape frame;
            // enlarging it changes the parent's vertical alignment by 55pt.
            Rectangle()
                .fill(panelColor)
                .frame(width: CardaTheme.canvasWidth, height: 110)
                .offset(y: CardaTheme.canvasHeight - 110)

            ShellCardHolderBackgroundShape(
                mode: mode,
                progress: showsPanel ? 1 : 0
            )
            .fill(panelColor)
            // The Union and the CardHolder sticky module now use the same
            // external translation primitive. Keeping collapse offset out of
            // Shape animatableData prevents fast scroll samples from being
            // interpolated on a second, independent geometry timeline.
            .frame(
                width: CardaTheme.canvasWidth,
                height: CardaTheme.canvasHeight,
                alignment: .topLeading
            )
            .offset(y: showsPanel ? -collapseOffset : 0)
            .animation(.easeInOut(duration: 0.32), value: showsPanel)

            AnimatedHolderPanelCapShape(selectionPosition: mode.selectionPosition)
                .fill(panelColor)
                .frame(width: CardaTheme.canvasWidth, height: 45)
                .offset(y: 126 - collapseOffset)
                .mask(alignment: .topLeading) {
                    headerVisibilityMask
                }
                .animation(.snappy(duration: 0.28), value: mode)
        }
    }

    private var headerVisibilityMask: some View {
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
            .frame(height: 62)

            Rectangle()
                .fill(Color.black)
                .frame(height: CardaTheme.canvasHeight - 62)
        }
        .frame(
            width: CardaTheme.canvasWidth,
            height: CardaTheme.canvasHeight,
            alignment: .topLeading
        )
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
