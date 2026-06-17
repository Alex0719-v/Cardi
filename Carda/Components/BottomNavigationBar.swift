//
//  BottomNavigationBar.swift
//  Carda
//

import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case myCards
    case cardHolder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .myCards:
            "我的名片"
        case .cardHolder:
            "名片夹"
        }
    }
}

struct BottomNavigationBar: View {
    @Binding var selectedSection: AppSection
    @Binding var isSearchActive: Bool
    @Binding var isSearchEditing: Bool
    @Binding var searchText: String
    @FocusState.Binding var searchFieldFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if isSearchActive {
                searchActiveControls
            } else {
                normalControls
            }
        }
        .frame(width: CardaTheme.canvasWidth, height: 95, alignment: .topLeading)
    }

    private var normalControls: some View {
        ZStack(alignment: .topLeading) {
            FigmaGlassShape(cornerRadius: 296)
                .frame(width: 191, height: 62)
                .offset(x: 21, y: 12)
                .allowsHitTesting(false)

            RoundedRectangle(cornerRadius: 100, style: .continuous)
                .fill(CardaTheme.selectedTabFill)
                .frame(width: 98, height: 54)
                .offset(x: selectedSection == .myCards ? 25 : 109, y: 16)
                .allowsHitTesting(false)

            MyCardsTabIcon(isSelected: selectedSection == .myCards)
                .offset(x: 27, y: 16)

            CardHolderTabIcon(isSelected: selectedSection == .cardHolder)
                .offset(x: 113, y: 16)

            Button {
                selectedSection = .myCards
                isSearchActive = false
                isSearchEditing = false
            } label: {
                NavigationHitArea()
                    .frame(width: 94, height: 54)
            }
            .buttonStyle(.plain)
            .offset(x: 27, y: 16)
            .accessibilityLabel("我的名片")

            Button {
                selectedSection = .cardHolder
                isSearchActive = false
                isSearchEditing = false
            } label: {
                NavigationHitArea()
                    .frame(width: 94, height: 54)
            }
            .buttonStyle(.plain)
            .offset(x: 113, y: 16)
            .accessibilityLabel("名片夹")

            Button {
                isSearchActive = true
                isSearchEditing = false
            } label: {
                ZStack {
                    FigmaGlassShape(cornerRadius: 296, interactive: true)
                        .frame(width: 62, height: 62)
                    SearchGlyph()
                        .stroke(CardaTheme.primaryText, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                        .frame(width: 23, height: 23)
                        .frame(width: 54, height: 54)
                }
                .frame(width: 62, height: 62)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .offset(x: 319, y: 12)
            .accessibilityLabel("搜索")
        }
    }

    private var searchActiveControls: some View {
        ZStack(alignment: .topLeading) {
            if !isSearchEditing && !hasSearchText {
                Button {
                    isSearchActive = false
                } label: {
                    ZStack {
                        FigmaGlassShape(cornerRadius: 296, interactive: true)
                            .frame(width: 62, height: 62)
                        if selectedSection == .myCards {
                            MyIconSVGView(icon: .myCardsSelected)
                        } else {
                            MyIconSVGView(icon: .cardHolderSelected)
                        }
                    }
                    .frame(width: 62, height: 62)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .offset(x: 20.5, y: 12)
            }

            HStack(spacing: 10) {
                SearchGlyph()
                    .stroke(CardaTheme.primaryText, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .frame(width: 20, height: 20)
                TextField("", text: $searchText)
                    .focused($searchFieldFocused)
                    .font(CardaTheme.pingFang(size: 17))
                    .disableAutocorrection(true)
                    .submitLabel(.done)
                    .onSubmit {
                        searchFieldFocused = false
                        isSearchEditing = false
                    }
                    .allowsHitTesting(isSearchEditing)
                    .onTapGesture {
                        activateSearchField()
                    }
                    .onChange(of: searchFieldFocused) { _, focused in
                        if focused && !isSearchEditing {
                            isSearchEditing = true
                        }
                    }
            }
            .padding(.horizontal, 18)
            .frame(width: usesWideSearchLayout ? 293 : 279, height: 62)
            .background(FigmaGlassShape(cornerRadius: 296, interactive: true))
            .contentShape(RoundedRectangle(cornerRadius: 296, style: .continuous))
            .overlay {
                if !isSearchEditing && !hasSearchText {
                    RoundedRectangle(cornerRadius: 296, style: .continuous)
                        .fill(Color.white.opacity(0.001))
                        .contentShape(RoundedRectangle(cornerRadius: 296, style: .continuous))
                        .onTapGesture {
                            activateSearchField()
                        }
                }
            }
            .onTapGesture {
                if !isSearchEditing {
                    activateSearchField()
                }
            }
            .offset(x: usesWideSearchLayout ? 16 : 103, y: 12)

            if isSearchEditing || hasSearchText {
                Button {
                    clearSearch()
                } label: {
                    XMarkGlyph()
                        .stroke(CardaTheme.primaryText, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                        .frame(width: 18, height: 18)
                        .frame(width: 61, height: 62)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .background(FigmaGlassShape(cornerRadius: 296, interactive: true))
                .offset(x: 325, y: 12)
                .accessibilityLabel("清空搜索")
            }
        }
        .frame(width: CardaTheme.canvasWidth, height: 95, alignment: .topLeading)
    }

    private var hasSearchText: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var usesWideSearchLayout: Bool {
        isSearchEditing || hasSearchText
    }

    private func activateSearchField() {
        isSearchEditing = true
        DispatchQueue.main.async {
            searchFieldFocused = true
        }
    }

    private func clearSearch() {
        searchText = ""
        searchFieldFocused = false
        isSearchEditing = false
    }
}

struct FigmaGlassShape: View {
    var cornerRadius: CGFloat
    var interactive = false

    var body: some View {
        if #available(iOS 26.0, *) {
            if interactive {
                glassBase
                    .glassEffect(
                        .regular.tint(Color.white.opacity(0.28)).interactive(),
                        in: .rect(cornerRadius: cornerRadius)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 8)
            } else {
                glassBase
                    .glassEffect(
                        .regular.tint(Color.white.opacity(0.28)),
                        in: .rect(cornerRadius: cornerRadius)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 8)
            }
        } else {
            glassBase
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.34))
                )
                .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 8)
        }
    }

    private var glassBase: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.01))
    }
}

private struct NavigationHitArea: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.001))
            .contentShape(Rectangle())
    }
}

private struct MyCardsTabIcon: View {
    var isSelected: Bool

    var body: some View {
        MyIconSVGView(icon: isSelected ? .myCardsSelected : .myCardsNormal)
            .position(x: 46.5, y: 27)
            .frame(width: 94, height: 54)
            .allowsHitTesting(false)
    }
}

private struct CardHolderTabIcon: View {
    var isSelected: Bool

    var body: some View {
        MyIconSVGView(icon: isSelected ? .cardHolderSelected : .cardHolderNormal)
            .position(x: 50.5, y: 27)
            .frame(width: 94, height: 54)
            .allowsHitTesting(false)
    }
}

private enum MyIconFile {
    case myCardsNormal
    case myCardsSelected
    case cardHolderNormal
    case cardHolderSelected

    var fileName: String {
        switch self {
        case .myCardsNormal:
            "mycard-1"
        case .myCardsSelected:
            "mycard-2"
        case .cardHolderNormal:
            "cards-1"
        case .cardHolderSelected:
            "cards-2"
        }
    }

    var size: CGSize {
        switch self {
        case .myCardsNormal:
            CGSize(width: 36, height: 27)
        case .myCardsSelected:
            CGSize(width: 35, height: 26)
        case .cardHolderNormal:
            CGSize(width: 36, height: 30)
        case .cardHolderSelected:
            CGSize(width: 35, height: 28)
        }
    }
}

private struct MyIconSVGView: View {
    let icon: MyIconFile

    var body: some View {
        LocalSVGIconView(fileName: icon.fileName)
            .frame(width: icon.size.width, height: icon.size.height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct SearchGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) * 0.33
        let center = CGPoint(x: rect.midX - rect.width * 0.08, y: rect.midY - rect.height * 0.08)
        path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        path.move(to: CGPoint(x: center.x + radius * 0.72, y: center.y + radius * 0.72))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.maxY - rect.height * 0.12))
        return path
    }
}

private struct XMarkGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 2, y: rect.minY + 2))
        path.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.maxY - 2))
        path.move(to: CGPoint(x: rect.maxX - 2, y: rect.minY + 2))
        path.addLine(to: CGPoint(x: rect.minX + 2, y: rect.maxY - 2))
        return path
    }
}
