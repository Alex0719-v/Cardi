//
//  CardSearchView.swift
//  Carda
//

import SwiftUI

struct CardSearchView: View {
    let cards: [BusinessCard]
    let searchText: String
    let isEditing: Bool

    @State private var expandedCardID: UUID?
    @Namespace private var searchCardNamespace

    var body: some View {
        ZStack(alignment: .topLeading) {
            CardaTheme.pageBackground
                .frame(width: CardaTheme.canvasWidth, height: CardaTheme.canvasHeight)

            ScrollView {
                if query.isEmpty {
                    recentSection
                } else {
                    resultSections
                }
            }
            .scrollIndicators(.hidden)
            .zIndex(1)

            if query.isEmpty {
                TransparentGradientBlur(height: 119, direction: .top)
                    .offset(y: 0)
                    .zIndex(2)
            }

            TransparentGradientBlur(height: 140)
                .offset(y: isEditing ? 433 : 737)
                .zIndex(2)

            searchHeader
                .zIndex(3)
        }
    }

    @ViewBuilder
    private var searchHeader: some View {
        if query.isEmpty {
            Text("最近添加")
                .font(CardaTheme.pingFang(size: 22, weight: .semibold))
                .foregroundStyle(Color.black)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 112, height: 28, alignment: .topLeading)
                .offset(x: 16, y: 71)
                .allowsHitTesting(false)
        } else {
            Text("名片搜索")
                .font(CardaTheme.pingFang(size: 22, weight: .semibold))
                .foregroundStyle(Color.black)
                .lineLimit(1)
                .frame(width: 120, height: 28, alignment: .center)
                .position(x: CardaTheme.canvasWidth / 2, y: 90)
                .allowsHitTesting(false)
        }
    }

    private var recentSection: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(recentCards) { card in
                searchCardRow(card)
            }
            if recentCards.isEmpty {
                emptyState("暂无最近添加")
                    .padding(.top, 80)
            }
        }
        .frame(width: CardaTheme.canvasWidth, alignment: .leading)
        .padding(.top, 119)
        .padding(.bottom, isEditing ? 430 : 120)
    }

    private var resultSections: some View {
        LazyVStack(alignment: .leading, spacing: 13) {
            searchResultSection(title: "姓名", cards: nameMatches)
            searchResultSection(title: "单位", cards: organizationMatches)
            searchResultSection(title: "其他信息", cards: fieldMatches)
        }
        .frame(width: CardaTheme.canvasWidth, alignment: .leading)
        .padding(.top, 130)
        .padding(.bottom, isEditing ? 430 : 120)
    }

    private var recentCards: [BusinessCard] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
        return cards
            .filter { $0.ownerKind != .mine && ($0.receivedAt ?? $0.createdAt) >= weekAgo }
            .sorted { ($0.receivedAt ?? $0.createdAt) > ($1.receivedAt ?? $1.createdAt) }
    }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nameMatches: [BusinessCard] {
        cards.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.phoneticName.localizedCaseInsensitiveContains(query)
        }
    }

    private var organizationMatches: [BusinessCard] {
        cards.filter { $0.organizationName.localizedCaseInsensitiveContains(query) }
    }

    private var fieldMatches: [BusinessCard] {
        cards.filter { card in
            card.fields.contains { field in
                field.value.localizedCaseInsensitiveContains(query)
            }
        }
    }

    @ViewBuilder
    private func searchResultSection(title: String, cards: [BusinessCard]) -> some View {
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(CardaTheme.pingFang(size: 15, weight: .regular))
                    .foregroundStyle(Color.black)
                    .frame(width: 90, height: 20, alignment: .leading)
                    .padding(.leading, 16)

                LazyVStack(spacing: 8) {
                    ForEach(cards) { card in
                        searchCardRow(card)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func searchCardRow(_ card: BusinessCard) -> some View {
        if expandedCardID == card.id {
            BusinessCardView(data: card.renderData, width: CardaTheme.cardWidth)
                .matchedGeometryEffect(id: "search-card-\(card.id)", in: searchCardNamespace)
                .onTapGesture {
                    withAnimation(.snappy(duration: 0.32)) {
                        expandedCardID = nil
                    }
                }
                .frame(width: CardaTheme.canvasWidth, alignment: .center)
        } else {
            CollapsedCardRow(data: card.renderData)
                .matchedGeometryEffect(id: "search-card-\(card.id)", in: searchCardNamespace)
                .onTapGesture {
                    withAnimation(.snappy(duration: 0.36)) {
                        expandedCardID = card.id
                    }
                }
                .frame(width: CardaTheme.canvasWidth, alignment: .center)
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(CardaTheme.pingFang(size: 17))
            .foregroundStyle(CardaTheme.formSecondaryText)
            .frame(maxWidth: .infinity)
    }
}
