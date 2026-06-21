//
//  AppShellView.swift
//  Carda
//

import SwiftData
import SwiftUI

struct AppShellView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BusinessCard.createdAt) private var cards: [BusinessCard]
    @Query(sort: \BusinessCardList.sortOrder) private var cardLists: [BusinessCardList]
    @State private var selectedSection: AppSection = .myCards
    @State private var isSearchActive = false
    @State private var isSearchEditing = false
    @State private var searchText = ""
    @State private var isAddListDialogPresented = false
    @State private var newListName = ""
    @State private var isRenameListDialogPresented = false
    @State private var renameListTargetID: UUID?
    @State private var renameListName = ""
    @State private var isDeleteListConfirmationPresented = false
    @State private var deleteListTargetID: UUID?
    @FocusState private var searchFieldFocused: Bool
    @FocusState private var addListNameFocused: Bool
    @FocusState private var renameListNameFocused: Bool

    private var accountAvatarImageData: Data? {
        // Account login/profile storage is not implemented yet, so the shared
        // account avatar intentionally renders as the blank glass state for now.
        nil
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            CardaTheme.pageBackground
                .frame(width: CardaTheme.canvasWidth, height: CardaTheme.canvasHeight)

            if isSearchActive {
                CardSearchView(
                    cardHolderCards: cardHolderCards,
                    searchText: searchText,
                    isEditing: isSearchEditing
                )
            } else {
                switch selectedSection {
                case .myCards:
                    MyCardsView(accountAvatarImageData: accountAvatarImageData)
                case .cardHolder:
                    CardHolderView(
                        cards: cardHolderCards,
                        accountAvatarImageData: accountAvatarImageData,
                        onAddList: presentAddListDialog,
                        onRenameList: presentRenameListDialog,
                        onDeleteList: presentDeleteListConfirmation
                    )
                }
            }

            BottomNavigationBar(
                selectedSection: $selectedSection,
                isSearchActive: $isSearchActive,
                isSearchEditing: $isSearchEditing,
                searchText: $searchText,
                searchFieldFocused: $searchFieldFocused
            )
            .offset(x: 0, y: bottomNavigationTop)
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
        }
        .frame(width: CardaTheme.canvasWidth, height: CardaTheme.canvasHeight)
        .clipped()
        .animation(.snappy(duration: 0.28), value: selectedSection)
        .animation(.snappy(duration: 0.28), value: isSearchActive)
        .animation(.snappy(duration: 0.28), value: isSearchEditing)
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
            deleteListTargetID = nil
            isDeleteListConfirmationPresented = false
        }
        .task {
            ReceivedCardSampleSeeder.seedIfNeeded(in: modelContext, existingCards: cards)
            CardListSeeder.seedIfNeeded(in: modelContext, existingLists: cardLists)
        }
    }

    private var bottomNavigationTop: CGFloat {
        isSearchActive && isSearchEditing ? 448 : 779
    }

    private var cardHolderCards: [BusinessCard] {
        cards.filter { $0.ownerKind == .received }
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
        dismissAddListDialog()
        dismissRenameListDialog()
        deleteListTargetID = list.id
        isDeleteListConfirmationPresented = true
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
