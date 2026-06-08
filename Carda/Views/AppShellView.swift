//
//  AppShellView.swift
//  Carda
//

import SwiftData
import SwiftUI

struct AppShellView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BusinessCard.createdAt) private var cards: [BusinessCard]
    @State private var selectedSection: AppSection = .myCards
    @State private var isSearchActive = false
    @State private var isSearchEditing = false
    @State private var searchText = ""
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            CardaTheme.pageBackground
                .frame(width: CardaTheme.canvasWidth, height: CardaTheme.canvasHeight)

            if isSearchActive {
                CardSearchView(
                    cards: cards,
                    searchText: searchText,
                    isEditing: isSearchEditing
                )
            } else {
                switch selectedSection {
                case .myCards:
                    MyCardsView()
                case .cardHolder:
                    CardHolderView(cards: cards.filter { $0.ownerKind == .received })
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
        }
        .frame(width: CardaTheme.canvasWidth, height: CardaTheme.canvasHeight)
        .clipped()
        .animation(.snappy(duration: 0.28), value: selectedSection)
        .animation(.snappy(duration: 0.28), value: isSearchActive)
        .animation(.snappy(duration: 0.28), value: isSearchEditing)
        .task {
            ReceivedCardSampleSeeder.seedIfNeeded(in: modelContext, existingCards: cards)
        }
    }

    private var bottomNavigationTop: CGFloat {
        isSearchActive && isSearchEditing ? 448 : 779
    }
}
