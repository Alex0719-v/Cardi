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

    let cards: [BusinessCard]

    @State private var mode: HolderMode = .name
    @State private var expandedCardID: UUID?
    @State private var expandedListID: String?
    @State private var editorMode: HolderCardEditorMode?
    @State private var isAddSheetPresented = false
    @State private var isContextMenuVisible = false
    @State private var saveMessage: String?
    @Namespace private var cardExpansionNamespace

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

                if mode != .list && !cards.isEmpty {
                    ContactAlphabetIndex()
                        .position(x: 394, y: CardaTheme.canvasHeight / 2)
                        .zIndex(4)
                }

                if mode != .list && !cards.isEmpty {
                    bottomScrollFade
                        .offset(y: 734)
                        .zIndex(4)
                }

                topModeBar
                    .zIndex(5)

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

    private var currentUserAvatarImageData: Data? {
        myCards.first?.avatarImageData
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
                listToolbarButton(title: "编辑", width: 72, textLeading: 19)
                    .position(x: 52, y: 90)

                listToolbarButton(title: "添加列表", width: 112, textLeading: 21.5)
                    .position(x: 330, y: 90)
            } else {
                UserAvatarButton(imageData: currentUserAvatarImageData) {
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

    private func listToolbarButton(title: String, width: CGFloat, textLeading: CGFloat) -> some View {
        Button {
        } label: {
            ZStack(alignment: .topLeading) {
                FigmaGlassShape(cornerRadius: 296, interactive: true)
                    .shadow(color: .black.opacity(0.045), radius: 9, x: 0, y: 2)

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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(groupedCards, id: \.title) { group in
                    cardGroup(title: group.title, cards: group.cards)
                }
            }
            .padding(.top, 172)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
    }

    private func cardGroup(title: String, cards: [BusinessCard]) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title)
                .font(groupTitleFont(for: title))
                .foregroundStyle(Color.black)
                .frame(height: 20, alignment: .leading)
                .padding(.leading, 16)

            VStack(spacing: 8) {
                ForEach(cards) { card in
                    cardRowOrExpanded(card)
                }
            }
        }
        .frame(width: CardaTheme.canvasWidth, alignment: .leading)
    }

    @ViewBuilder
    private func cardRowOrExpanded(_ card: BusinessCard) -> some View {
        if expandedCardID == card.id {
            BusinessCardView(data: card.renderData, width: CardaTheme.cardWidth)
                .matchedGeometryEffect(id: "holder-card-\(card.id)", in: cardExpansionNamespace)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.45)
                        .onEnded { _ in isContextMenuVisible = true }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(listRows.enumerated()), id: \.element.id) { index, row in
                    listModeRow(row, showsTopSeparator: index > 0)

                    if expandedListID == row.id {
                        VStack(spacing: 8) {
                            ForEach(cardsForList(row)) { card in
                                CollapsedCardRow(data: card.renderData)
                                    .frame(width: CardaTheme.canvasWidth, alignment: .center)
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .frame(width: CardaTheme.canvasWidth, alignment: .leading)
            .padding(.top, 187)
            .padding(.bottom, 160)
        }
        .scrollIndicators(.hidden)
    }

    private func listModeRow(_ row: HolderListRow, showsTopSeparator: Bool) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.28)) {
                expandedListID = expandedListID == row.id ? nil : row.id
            }
        } label: {
            HStack(spacing: 0) {
                Text(row.title)
                    .font(CardaTheme.pingFang(size: 17, weight: .regular))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.22))
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
    }

    private var emptyState: some View {
        Text("暂无收到的名片")
            .font(CardaTheme.pingFang(size: 17))
            .foregroundStyle(CardaTheme.formSecondaryText)
    }

    private var bottomScrollFade: some View {
        TransparentGradientBlur(height: 140)
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

    private var groupedCards: [(title: String, cards: [BusinessCard])] {
        switch mode {
        case .list:
            return []
        case .name:
            let sorted = cards.sorted { pinyinSortKey(for: $0.name) < pinyinSortKey(for: $1.name) }
            return Dictionary(grouping: sorted) { card in
                pinyinInitial(for: card.name)
            }
            .map { ($0.key.isEmpty ? "#" : $0.key, $0.value) }
            .sorted { $0.title < $1.title }
        case .organization:
            let sorted = cards.sorted { lhs, rhs in
                let leftOrg = pinyinSortKey(for: lhs.organizationName)
                let rightOrg = pinyinSortKey(for: rhs.organizationName)
                if leftOrg == rightOrg {
                    return pinyinSortKey(for: lhs.name) < pinyinSortKey(for: rhs.name)
                }
                return leftOrg < rightOrg
            }
            return Dictionary(grouping: sorted) { card in
                card.organizationName.isEmpty ? "未命名单位" : card.organizationName
            }
            .map { ($0.key, $0.value) }
            .sorted { $0.title < $1.title }
        }
    }

    private var listRows: [HolderListRow] {
        [
            HolderListRow(id: "classmates", title: "同学（20）", range: 0..<min(20, cards.count)),
            HolderListRow(id: "lecture", title: "xx讲座（15）", range: 0..<min(15, cards.count)),
            HolderListRow(id: "recruit", title: "招聘（6）", range: 0..<min(6, cards.count)),
            HolderListRow(id: "meeting", title: "见面会（12）", range: 0..<min(12, cards.count))
        ]
    }

    private func cardsForList(_ row: HolderListRow) -> [BusinessCard] {
        let sorted = cards.sorted { $0.createdAt > $1.createdAt }
        return row.range.compactMap { index in
            sorted.indices.contains(index) ? sorted[index] : nil
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
}

private struct HolderListRow: Identifiable {
    let id: String
    let title: String
    let range: Range<Int>
}

private struct ContactAlphabetIndex: View {
    private let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ#").map(String.init)

    var body: some View {
        VStack(spacing: 1) {
            ForEach(letters, id: \.self) { letter in
                Text(letter)
                    .font(CardaTheme.sfPro(size: 11, weight: .semibold))
                    .tracking(0.06)
                    .foregroundStyle(Color.black)
                    .frame(width: 10, height: 13)
            }
        }
        .frame(width: 12, height: 770, alignment: .center)
        .allowsHitTesting(false)
    }
}

private func pinyinInitial(for text: String) -> String {
    guard let first = text.trimmingCharacters(in: .whitespacesAndNewlines).first else { return "#" }
    let key = pinyinSortKey(for: String(first))
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
