//
//  BottomNavigationBar.swift
//  Cardi
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
    private static let searchMorphDuration: TimeInterval = 0.68
    private static let searchLiftDuration: TimeInterval = 0.52
    private static let selectionSliderDuration: TimeInterval = 0.24
    // Keep neighboring controls visually independent at rest. The interactive
    // glass variant still supplies the native press response on actual touch.
    private static let glassMergeSpacing: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.cardaReduceMotion) private var settingsReduceMotion
    @Binding var selectedSection: AppSection
    @Binding var isSearchActive: Bool
    @Binding var isSearchEditing: Bool
    @Binding var searchText: String
    @FocusState.Binding var searchFieldFocused: Bool
    @Namespace private var searchBarTransitionNamespace
    @State private var isSearchNavigationMorphing = false
    @State private var searchNavigationMorphGeneration = 0

    var body: some View {
        navigationControls
            .frame(width: CardaTheme.canvasWidth, height: 95, alignment: .topLeading)
            .modifier(BottomNavigationSwitchFeedback(trigger: selectedSection))
    }

    private var navigationControls: some View {
        ZStack(alignment: .topLeading) {
            liquidGlassSurfaceLayer

            if isSearchActive && !isSearchNavigationMorphing {
                searchActiveControls
                    .transition(.identity)
            } else {
                morphingIdleControls
                    .transition(.identity)
            }
        }
    }

    @ViewBuilder
    private var liquidGlassSurfaceLayer: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: Self.glassMergeSpacing) {
                activeGlassSurfaces
            }
        } else {
            activeGlassSurfaces
        }
    }

    @ViewBuilder
    private var activeGlassSurfaces: some View {
        if isSearchActive && !isSearchNavigationMorphing {
            searchActiveGlassSurfaces
                .transition(.identity)
        } else {
            morphingIdleGlassSurfaces
                .transition(.identity)
        }
    }

    private var morphingIdleGlassSurfaces: some View {
        ZStack(alignment: .topLeading) {
            BottomNavigationGlassShape(cornerRadius: 296, interactive: true)
                .frame(width: isSearchActive ? 62 : 191, height: 62)
                .offset(x: isSearchActive ? 20.5 : 21, y: 12)

            BottomNavigationGlassShape(cornerRadius: 296, interactive: true)
                .frame(width: isSearchActive ? 279 : 62, height: 62)
                .matchedGeometryEffect(
                    id: "search-bar-background",
                    in: searchBarTransitionNamespace
                )
                .offset(x: isSearchActive ? 103 : 319, y: 12)
        }
        .allowsHitTesting(false)
        .animation(navigationMorphAnimation, value: isSearchActive)
    }

    private var searchActiveGlassSurfaces: some View {
        ZStack(alignment: .topLeading) {
            if !isSearchEditing && !hasSearchText {
                BottomNavigationGlassShape(cornerRadius: 296, interactive: true)
                    .frame(width: 62, height: 62)
                    .offset(x: 20.5, y: 12)
            }

            BottomNavigationGlassShape(cornerRadius: 296, interactive: true)
                .frame(width: usesWideSearchLayout ? 293 : 279, height: 62)
                .matchedGeometryEffect(
                    id: "search-bar-background",
                    in: searchBarTransitionNamespace
                )
                .offset(x: usesWideSearchLayout ? 16 : 103, y: 12)
                .animation(searchLiftAnimation, value: usesWideSearchLayout)

            if isSearchEditing || hasSearchText {
                BottomNavigationGlassShape(cornerRadius: 296, interactive: true)
                    .frame(width: 61, height: 62)
                    .offset(x: 325, y: 12)
            }
        }
        .allowsHitTesting(false)
        .frame(width: CardaTheme.canvasWidth, height: 95, alignment: .topLeading)
    }

    private var morphingIdleControls: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 100, style: .continuous)
                .fill(CardaTheme.selectedTabFill)
                .frame(width: isSearchActive ? 54 : 98, height: 54)
                .offset(
                    x: isSearchActive
                        ? 24.5
                        : (selectedSection == .myCards ? 25 : 109),
                    y: 16
                )
                .opacity(isSearchActive ? 0 : 1)
                .animation(selectionSliderAnimation, value: selectedSection)
                .allowsHitTesting(false)

            MyCardsTabIcon(isSelected: selectedSection == .myCards)
                .modifier(
                    TabIconSwitchFeedback(
                        isSelected: selectedSection == .myCards,
                        trigger: selectedSection
                    )
                )
                .offset(x: isSearchActive ? 5 : 27, y: 16)
                .opacity(
                    isSearchActive && selectedSection != .myCards ? 0 : 1
                )
                .animation(unselectedIconAnimation, value: isSearchActive)

            CardHolderTabIcon(isSelected: selectedSection == .cardHolder)
                .modifier(
                    TabIconSwitchFeedback(
                        isSelected: selectedSection == .cardHolder,
                        trigger: selectedSection
                    )
                )
                .offset(x: isSearchActive ? 1 : 113, y: 16)
                .opacity(
                    isSearchActive && selectedSection != .cardHolder ? 0 : 1
                )
                .animation(unselectedIconAnimation, value: isSearchActive)

            if isSearchActive {
                Button {
                    deactivateSearchPage()
                } label: {
                    NavigationHitArea()
                        .frame(width: 62, height: 62)
                }
                .buttonStyle(.plain)
                .offset(x: 20.5, y: 12)
                .accessibilityLabel(selectedSection.title)
            } else {
                Button {
                    selectedSection = .myCards
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
                    isSearchEditing = false
                } label: {
                    NavigationHitArea()
                        .frame(width: 94, height: 54)
                }
                .buttonStyle(.plain)
                .offset(x: 113, y: 16)
                .accessibilityLabel("名片夹")
            }

            SearchGlyph()
                .stroke(
                    CardaTheme.primaryText,
                    style: StrokeStyle(lineWidth: isSearchActive ? 2.2 : 2.6, lineCap: .round)
                )
                .frame(
                    width: isSearchActive ? 20 : 23,
                    height: isSearchActive ? 20 : 23
                )
                .matchedGeometryEffect(
                    id: "search-bar-glyph",
                    in: searchBarTransitionNamespace
                )
                .position(x: isSearchActive ? 131 : 350, y: 43)
                .allowsHitTesting(false)

            if isSearchActive {
                TextField("", text: $searchText)
                    .font(CardaTheme.pingFang(size: 17))
                    .disableAutocorrection(true)
                    .submitLabel(.done)
                    .allowsHitTesting(false)
                    .frame(width: 213, height: 62, alignment: .leading)
                    .offset(x: 151, y: 12)

                Button(action: activateSearchField) {
                    NavigationHitArea()
                        .frame(width: 279, height: 62)
                }
                .buttonStyle(.plain)
                .offset(x: 103, y: 12)
                .accessibilityLabel("搜索")
            } else {
                Button {
                    activateSearchPage()
                } label: {
                    NavigationHitArea()
                        .frame(width: 62, height: 62)
                }
                .buttonStyle(.plain)
                .offset(x: 319, y: 12)
                .accessibilityLabel("搜索")
            }
        }
        .animation(navigationMorphAnimation, value: isSearchActive)
    }

    private var searchActiveControls: some View {
        ZStack(alignment: .topLeading) {
            if !isSearchEditing && !hasSearchText {
                Button {
                    deactivateSearchPage()
                } label: {
                    ZStack {
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
                    .matchedGeometryEffect(
                        id: "search-bar-glyph",
                        in: searchBarTransitionNamespace
                    )
                TextField("", text: $searchText)
                    .focused($searchFieldFocused)
                    .font(CardaTheme.pingFang(size: 17))
                    .disableAutocorrection(true)
                    .submitLabel(.done)
                    .onSubmit {
                        searchFieldFocused = false
                        withAnimation(searchLiftAnimation) {
                            isSearchEditing = false
                        }
                    }
                    .allowsHitTesting(isSearchEditing)
                    .onTapGesture {
                        activateSearchField()
                    }
                    .onChange(of: searchFieldFocused) { _, focused in
                        if focused && !isSearchEditing {
                            withAnimation(searchLiftAnimation) {
                                isSearchEditing = true
                            }
                        }
                    }
            }
            .padding(.horizontal, 18)
            .frame(width: usesWideSearchLayout ? 293 : 279, height: 62)
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
            .animation(searchLiftAnimation, value: usesWideSearchLayout)

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

    private var navigationMorphAnimation: Animation {
        .timingCurve(0.2, 0.72, 0.18, 1, duration: Self.searchMorphDuration)
    }

    private var searchLiftAnimation: Animation {
        .timingCurve(0.2, 0.72, 0.18, 1, duration: Self.searchLiftDuration)
    }

    private var selectionSliderAnimation: Animation? {
        guard !systemReduceMotion, !settingsReduceMotion else { return nil }
        return .smooth(duration: Self.selectionSliderDuration, extraBounce: 0)
    }

    private var unselectedIconAnimation: Animation {
        let animation = Animation.timingCurve(0.2, 0.72, 0.18, 1, duration: 0.42)
        return isSearchActive ? animation : animation.delay(0.26)
    }

    private func activateSearchField() {
        withAnimation(searchLiftAnimation) {
            isSearchEditing = true
        }
        DispatchQueue.main.async {
            searchFieldFocused = true
        }
    }

    private func activateSearchPage() {
        searchNavigationMorphGeneration += 1
        let generation = searchNavigationMorphGeneration
        isSearchNavigationMorphing = true

        withAnimation(navigationMorphAnimation) {
            isSearchActive = true
            isSearchEditing = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.searchMorphDuration) {
            guard
                searchNavigationMorphGeneration == generation,
                isSearchActive
            else {
                return
            }
            completeSearchNavigationMorph()
        }
    }

    private func deactivateSearchPage() {
        searchNavigationMorphGeneration += 1
        let generation = searchNavigationMorphGeneration

        var handoffTransaction = Transaction()
        handoffTransaction.disablesAnimations = true
        withTransaction(handoffTransaction) {
            isSearchNavigationMorphing = true
        }

        DispatchQueue.main.async {
            guard searchNavigationMorphGeneration == generation else { return }

            withAnimation(navigationMorphAnimation) {
                isSearchActive = false
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + Self.searchMorphDuration) {
                guard searchNavigationMorphGeneration == generation else { return }
                completeSearchNavigationMorph()
            }
        }
    }

    private func completeSearchNavigationMorph() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isSearchNavigationMorphing = false
        }
    }

    private func clearSearch() {
        withAnimation(navigationMorphAnimation) {
            searchText = ""
            searchFieldFocused = false
            isSearchEditing = false
        }
    }
}

private enum TabIconFeedbackPhase: CaseIterable {
    case idle
    case compressed
    case expanded
    case settled

    var scale: CGFloat {
        switch self {
        case .compressed:
            0.90
        case .expanded:
            1.045
        case .idle, .settled:
            1
        }
    }

    var verticalOffset: CGFloat {
        switch self {
        case .compressed:
            0.8
        case .expanded:
            -0.4
        case .idle, .settled:
            0
        }
    }

    var animation: Animation {
        switch self {
        case .idle:
            .linear(duration: 0)
        case .compressed:
            .easeOut(duration: 0.08)
        case .expanded:
            .spring(duration: 0.17, bounce: 0.28)
        case .settled:
            .spring(duration: 0.15, bounce: 0.10)
        }
    }
}

private struct TabIconSwitchFeedback: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.cardaReduceMotion) private var settingsReduceMotion
    let isSelected: Bool
    let trigger: AppSection

    private var reduceMotion: Bool {
        systemReduceMotion || settingsReduceMotion
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.phaseAnimator(TabIconFeedbackPhase.allCases, trigger: trigger) { view, phase in
                view
                    .scaleEffect(isSelected ? phase.scale : 1)
                    .offset(y: isSelected ? phase.verticalOffset : 0)
            } animation: { phase in
                phase.animation
            }
        }
    }
}

private enum BottomNavigationFeedbackPhase: CaseIterable {
    case idle
    case compressed
    case expanded
    case settled

    var horizontalScale: CGFloat {
        switch self {
        case .compressed:
            0.996
        case .expanded:
            1.002
        case .idle, .settled:
            1
        }
    }

    var verticalScale: CGFloat {
        switch self {
        case .compressed:
            0.978
        case .expanded:
            1.006
        case .idle, .settled:
            1
        }
    }

    var verticalOffset: CGFloat {
        switch self {
        case .compressed:
            0.6
        case .expanded:
            -0.2
        case .idle, .settled:
            0
        }
    }

    var animation: Animation {
        switch self {
        case .idle:
            .linear(duration: 0)
        case .compressed:
            .easeOut(duration: 0.08)
        case .expanded:
            .spring(duration: 0.18, bounce: 0.20)
        case .settled:
            .spring(duration: 0.16, bounce: 0.08)
        }
    }
}

private struct BottomNavigationSwitchFeedback: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.cardaReduceMotion) private var settingsReduceMotion
    let trigger: AppSection

    private var reduceMotion: Bool {
        systemReduceMotion || settingsReduceMotion
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.phaseAnimator(BottomNavigationFeedbackPhase.allCases, trigger: trigger) { view, phase in
                view
                    .scaleEffect(
                        x: phase.horizontalScale,
                        y: phase.verticalScale,
                        anchor: .center
                    )
                    .offset(y: phase.verticalOffset)
            } animation: { phase in
                phase.animation
            }
        }
    }
}

private struct BottomNavigationGlassShape: View {
    var cornerRadius: CGFloat
    var interactive = false

    var body: some View {
        ZStack {
            figmaFillAndShadow
            nativeGlassEffect
        }
    }

    private var figmaFillAndShadow: some View {
        ZStack {
            glassShape
                .fill(Color.white.opacity(0.44))

            glassShape
                .fill(
                    Color(red: 221 / 255, green: 221 / 255, blue: 221 / 255)
                        .opacity(0.48)
                )
                .blendMode(.colorBurn)

            glassShape
                .fill(
                    Color(red: 247 / 255, green: 247 / 255, blue: 247 / 255)
                        .opacity(0.42)
                )
                .blendMode(.darken)
        }
        .clipShape(glassShape)
        .shadow(color: .black.opacity(0.16), radius: 44, x: 0, y: 10)
    }

    @ViewBuilder
    private var nativeGlassEffect: some View {
        if #available(iOS 26.0, *) {
            if interactive {
                glassEffectBase
                    .glassEffect(
                        .regular.interactive(),
                        in: .rect(cornerRadius: cornerRadius)
                    )
            } else {
                glassEffectBase
                    .glassEffect(
                        .regular,
                        in: .rect(cornerRadius: cornerRadius)
                    )
            }
        } else {
            glassEffectBase
                .background(.ultraThinMaterial, in: glassShape)
                .overlay {
                    glassShape
                        .stroke(Color.white.opacity(0.8), lineWidth: 0.8)
                }
        }
    }

    private var glassShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var glassEffectBase: some View {
        glassShape
            .fill(Color.black.opacity(0.004))
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
                        .regular.interactive(),
                        in: .rect(cornerRadius: cornerRadius)
                    )
                    .shadow(color: .black.opacity(0.16), radius: 26, x: 0, y: 10)
            } else {
                glassBase
                    .glassEffect(
                        .regular,
                        in: .rect(cornerRadius: cornerRadius)
                    )
                    .shadow(color: .black.opacity(0.16), radius: 26, x: 0, y: 10)
            }
        } else {
            glassBase
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.22))
                )
                .shadow(color: .black.opacity(0.16), radius: 26, x: 0, y: 10)
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
