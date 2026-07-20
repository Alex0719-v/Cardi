//
//  CardEditorView.swift
//  Cardi
//

import PhotosUI
import SwiftUI
import UIKit

struct CardEditorView: View {
    private static let backgroundPageStride = CardaTheme.canvasWidth
    fileprivate static let backgroundPageAnimationDuration: TimeInterval = 0.18

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var draft: BusinessCardDraft
    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var logoPickerItem: PhotosPickerItem?
    @State private var editorScrollPosition = ScrollPosition()
    @State private var editorScrollOffsetY: CGFloat = 0
    @State private var focusedDynamicFieldID: UUID?
    @State private var scrollOffsetBeforeDynamicEditing: CGFloat?
    @State private var dynamicFieldScrollRequest = 0
    @State private var backgroundDragOffset: CGFloat = 0
    @State private var isSettlingBackgroundPage = false
    @State private var backgroundIndicatorIndex: Int

    let onCommit: (BusinessCardDraft) -> Void

    init(initialDraft: BusinessCardDraft, onCommit: @escaping (BusinessCardDraft) -> Void) {
        _draft = State(initialValue: initialDraft)
        _backgroundIndicatorIndex = State(
            initialValue: CardBackgroundTemplate.allCases.firstIndex(of: initialDraft.backgroundTemplate) ?? 0
        )
        self.onCommit = onCommit
    }

    var body: some View {
        FigmaPhoneCanvas(background: CardaTheme.editorBackground) {
            editorPage
        }
        .task(id: avatarPickerItem) {
            guard let avatarPickerItem,
                  let data = try? await avatarPickerItem.loadTransferable(type: Data.self) else { return }
            draft.avatarImageData = data
        }
        .task(id: logoPickerItem) {
            guard let logoPickerItem,
                  let data = try? await logoPickerItem.loadTransferable(type: Data.self) else { return }
            draft.companyLogoImageData = data
        }
    }

    private var editorPage: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    topCardPreview
                        .offset(y: 63)

                    avatarPicker
                        .offset(x: 43, y: 240)

                    identityFields
                        .offset(x: 16, y: 340)

                    fixedInfoGroup
                        .offset(x: 16, y: 425)

                    dynamicFieldsGroup
                        .offset(x: 16, y: 654)

                    addFieldButton
                        .offset(x: 187, y: addFieldButtonY)
                }
                .frame(width: CardaTheme.canvasWidth, height: editorContentHeight, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
            .scrollPosition($editorScrollPosition)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offsetY in
                editorScrollOffsetY = max(0, offsetY)
            }
            .onChange(of: focusedDynamicFieldID) { oldID, newID in
                guard oldID != nil, newID == nil else { return }
                restoreScrollAfterDynamicFieldEditing()
            }
            .onChange(of: dynamicFieldScrollRequest) {
                scrollFocusedDynamicField(with: scrollProxy)
            }
        }
        .frame(width: CardaTheme.canvasWidth, height: CardaTheme.canvasHeight)
        .background(CardaTheme.editorBackground)
        .overlay(alignment: .topLeading) {
            editorToolbar
        }
    }

    private var editorToolbar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(CardaTheme.primaryText)
                    .frame(width: 44, height: 44)
                    .glassBackground()
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                normalizeFieldOrdering()
                onCommit(draft)
                dismiss()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(CardaTheme.primaryText)
                    .frame(width: 44, height: 44)
                    .glassBackground()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 63)
        .frame(width: CardaTheme.canvasWidth, height: 107, alignment: .top)
    }

    private var topCardPreview: some View {
        let previewHeight = CardLayoutCalculator.height(for: draft.renderData)

        return ZStack(alignment: .top) {
            ZStack {
                ForEach(CardBackgroundTemplate.allCases) { template in
                    BusinessCardView(
                        data: previewRenderData(for: template),
                        layerMode: .surface
                    )
                    .offset(x: backgroundPageOffset(for: template))
                    .allowsHitTesting(false)
                }

                BusinessCardView(
                    data: draft.renderData,
                    layerMode: .foreground
                )
                .allowsHitTesting(false)
            }
            .frame(width: CardaTheme.canvasWidth, height: previewHeight)
            .clipped()

            CardBackgroundPageIndicator(
                count: CardBackgroundTemplate.allCases.count,
                selectedIndex: backgroundIndicatorIndex
            )
            .offset(y: previewHeight + 12)
        }
        .frame(
            width: CardaTheme.canvasWidth,
            height: previewHeight + 32,
            alignment: .top
        )
        .contentShape(Rectangle())
        .simultaneousGesture(backgroundPageSwipeGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("card-background-picker")
        .accessibilityLabel("名片底图")
        .accessibilityValue(draft.backgroundTemplate.accessibilityName)
        .accessibilityHint("左右轻扫可切换名片底图")
    }

    private func backgroundPageOffset(for template: CardBackgroundTemplate) -> CGFloat {
        guard
            let templateIndex = CardBackgroundTemplate.allCases.firstIndex(of: template),
            let selectedIndex = CardBackgroundTemplate.allCases.firstIndex(of: draft.backgroundTemplate)
        else {
            return backgroundDragOffset
        }

        return CGFloat(templateIndex - selectedIndex) * Self.backgroundPageStride
            + backgroundDragOffset
    }

    private var backgroundPageSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .local)
            .onChanged { value in
                guard canHandleBackgroundPageSwipe(value) else { return }
                backgroundDragOffset = resistedBackgroundDragOffset(value.translation.width)
            }
            .onEnded { value in
                guard canHandleBackgroundPageSwipe(value) else {
                    resetBackgroundDragOffset()
                    return
                }

                let measured = value.translation.width
                let predicted = value.predictedEndTranslation.width
                if measured < -35 || predicted < -85 {
                    settleBackgroundPage(step: 1)
                } else if measured > 35 || predicted > 85 {
                    settleBackgroundPage(step: -1)
                } else {
                    resetBackgroundDragOffset()
                }
            }
    }

    private func canHandleBackgroundPageSwipe(_ value: DragGesture.Value) -> Bool {
        guard !isSettlingBackgroundPage else { return false }
        return abs(value.translation.width) >= abs(value.translation.height)
    }

    private func resistedBackgroundDragOffset(_ translation: CGFloat) -> CGFloat {
        let selectedIndex = CardBackgroundTemplate.allCases.firstIndex(of: draft.backgroundTemplate) ?? 0
        let isDraggingPastFirst = selectedIndex == 0 && translation > 0
        let isDraggingPastLast = selectedIndex == CardBackgroundTemplate.allCases.count - 1 && translation < 0
        return (isDraggingPastFirst || isDraggingPastLast) ? translation * 0.18 : translation
    }

    private func settleBackgroundPage(step: Int) {
        guard !isSettlingBackgroundPage else { return }
        let templates = CardBackgroundTemplate.allCases
        let selectedIndex = templates.firstIndex(of: draft.backgroundTemplate) ?? 0
        let targetIndex = selectedIndex + step
        guard templates.indices.contains(targetIndex) else {
            resetBackgroundDragOffset()
            return
        }

        isSettlingBackgroundPage = true
        let targetOffset = CGFloat(-step) * Self.backgroundPageStride
        backgroundIndicatorIndex = targetIndex

        if accessibilityReduceMotion {
            completeBackgroundPageSelection(templates[targetIndex])
            return
        }

        withAnimation(.snappy(duration: Self.backgroundPageAnimationDuration)) {
            backgroundDragOffset = targetOffset
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.backgroundPageAnimationDuration) {
            completeBackgroundPageSelection(templates[targetIndex])
        }
    }

    private func completeBackgroundPageSelection(_ template: CardBackgroundTemplate) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            draft.backgroundTemplate = template
            backgroundDragOffset = 0
        }
        isSettlingBackgroundPage = false
    }

    private func resetBackgroundDragOffset() {
        guard backgroundDragOffset != 0 else { return }
        if accessibilityReduceMotion {
            backgroundDragOffset = 0
        } else {
            withAnimation(.snappy(duration: 0.14)) {
                backgroundDragOffset = 0
            }
        }
    }

    private func previewRenderData(for template: CardBackgroundTemplate) -> CardRenderData {
        var data = draft.renderData
        data.backgroundTemplate = template
        return data
    }

    private var avatarPicker: some View {
        PhotosPicker(selection: $avatarPickerItem, matching: .images) {
            Group {
                if draft.avatarImageData != nil {
                    DataImageView(data: draft.avatarImageData)
                        .clipShape(Circle())
                } else {
                    Image("EditorDefaultAvatar")
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(width: 88, height: 88)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("选择头像")
    }

    private var identityFields: some View {
        ZStack(alignment: .topLeading) {
            FigmaEditorTextField(
                placeholder: "姓        名   ",
                text: $draft.name,
                font: CardaTheme.pingFang(size: 34, weight: .bold),
                placeholderFont: CardaTheme.pingFang(size: 34, weight: .bold),
                color: .black,
                placeholderColor: .black,
                lineLimit: 1...1,
                tracking: 4,
                focusedPlaceholderOpacity: 0.4,
                secondNameGlyphOffsetX: -36
            )
            .frame(width: 210, height: 41, alignment: .leading)

            FigmaEditorTextField(
                placeholder: "Xing Ming",
                text: $draft.phoneticName,
                font: CardaTheme.sfPro(size: 17),
                placeholderFont: CardaTheme.sfPro(size: 17),
                color: .black,
                placeholderColor: .black,
                lineLimit: 1...1,
                tracking: 16,
                focusedPlaceholderOpacity: 0.4
            )
            .frame(width: 247, height: 22, alignment: .leading)
            .offset(y: 45)
        }
        .frame(width: 247, height: 67, alignment: .topLeading)
    }

    private var fixedInfoGroup: some View {
        FixedInfoGroup(
            organizationName: $draft.organizationName,
            position: $draft.position,
            logoPickerItem: $logoPickerItem,
            logoData: draft.companyLogoImageData
        )
    }

    private var dynamicFieldsGroup: some View {
        ZStack(alignment: .topLeading) {
            ForEach(draft.fields.indices, id: \.self) { index in
                let field = draft.fields[index]
                EditableCardFieldRow(
                    field: $draft.fields[index],
                    showsDeleteButton: index > 0,
                    onEditingWillBegin: {
                        beginDynamicFieldEditing(field.id)
                    },
                    onEditingChanged: { isEditing in
                        if isEditing {
                            if focusedDynamicFieldID != field.id {
                                beginDynamicFieldEditing(field.id)
                            }
                        } else if focusedDynamicFieldID == field.id {
                            focusedDynamicFieldID = nil
                        }
                    }
                ) {
                    removeField(field)
                }
                .id(field.id)
                .offset(y: dynamicRowOffset(for: index))

                Color.clear
                    .frame(width: 1, height: 1)
                    .id(dynamicFieldScrollAnchorID(for: field.id))
                    .offset(x: 16, y: dynamicRowOffset(for: index) + 35)

                if index < (draft.fields.indices.last ?? 0) {
                    EditorGroupSeparator()
                        .offset(x: EditorGroupSeparator.horizontalInset)
                        .offset(y: dynamicRowOffset(for: index + 1))
                }
            }
        }
        .frame(width: 370, height: dynamicFieldsHeight, alignment: .topLeading)
        .background(CardaTheme.editorFormFill, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func dynamicRowOffset(for index: Int) -> CGFloat {
        draft.fields
            .prefix(index)
            .reduce(CGFloat.zero) { partial, field in
                partial + Self.dynamicRowHeight(for: field)
            }
    }

    private var dynamicFieldsHeight: CGFloat {
        draft.fields.reduce(CGFloat.zero) { partial, field in
            partial + Self.dynamicRowHeight(for: field)
        }
    }

    private var addFieldButtonY: CGFloat {
        654 + dynamicFieldsHeight + 42
    }

    private var editorContentHeight: CGFloat {
        let baseHeight = max(CardaTheme.editorCanvasHeight, addFieldButtonY + 72)
        let keyboardClearance: CGFloat = focusedDynamicFieldID == nil ? 0 : 360
        return baseHeight + keyboardClearance
    }

    private static func dynamicRowHeight(for field: CardFieldDraft) -> CGFloat {
        68 + CGFloat(max(0, editorLineCount(for: field.value) - 1)) * 20
    }

    fileprivate static func editorLineCount(for text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 1 }

        return trimmed
            .components(separatedBy: .newlines)
            .reduce(0) { partial, line in
                partial + CardLayoutCalculator.estimatedLineCount(for: line)
            }
    }

    private var addFieldButton: some View {
        Button {
            draft.fields.append(
                CardFieldDraft(
                    kind: .phone,
                    sortOrder: draft.fields.count
                )
            )
        } label: {
            ZStack(alignment: .topLeading) {
                Circle()
                    .fill(CardaTheme.editorAddButtonFill)
                RoundedRectangle(cornerRadius: 0)
                    .fill(CardaTheme.editorAddButtonGlyph)
                    .frame(width: 12, height: 2)
                    .offset(x: 8, y: 13)
                RoundedRectangle(cornerRadius: 0)
                    .fill(CardaTheme.editorAddButtonGlyph)
                    .frame(width: 2, height: 12)
                    .offset(x: 13, y: 8)
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("新增文本框")
    }

    private func removeField(_ field: CardFieldDraft) {
        draft.fields.removeAll { $0.id == field.id }
        normalizeFieldOrdering()
    }

    private func normalizeFieldOrdering() {
        for index in draft.fields.indices {
            draft.fields[index].sortOrder = index
            if draft.fields[index].kind == .phone {
                draft.fields[index].value = PhoneNumberFormatter.format(draft.fields[index].value)
            }
        }
    }

    private func beginDynamicFieldEditing(_ fieldID: UUID) {
        prepareDynamicFieldEditing(fieldID)
        focusedDynamicFieldID = fieldID
        dynamicFieldScrollRequest &+= 1
    }

    private func scrollFocusedDynamicField(with scrollProxy: ScrollViewProxy) {
        guard let fieldID = focusedDynamicFieldID else { return }
        let request = dynamicFieldScrollRequest

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard focusedDynamicFieldID == fieldID,
                  dynamicFieldScrollRequest == request else {
                return
            }

            withAnimation(.snappy(duration: 0.24)) {
                scrollProxy.scrollTo(
                    dynamicFieldScrollAnchorID(for: fieldID),
                    anchor: UnitPoint(x: 0.5, y: 0.35)
                )
            }
        }
    }

    private func restoreScrollAfterDynamicFieldEditing() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard focusedDynamicFieldID == nil,
                  let originalOffset = scrollOffsetBeforeDynamicEditing else {
                return
            }

            withAnimation(.snappy(duration: 0.28)) {
                editorScrollPosition.scrollTo(y: originalOffset)
            }
            scrollOffsetBeforeDynamicEditing = nil
        }
    }

    private func prepareDynamicFieldEditing(_ fieldID: UUID) {
        guard focusedDynamicFieldID == nil,
              scrollOffsetBeforeDynamicEditing == nil else {
            return
        }
        scrollOffsetBeforeDynamicEditing = editorScrollOffsetY
    }

    private func dynamicFieldScrollAnchorID(for fieldID: UUID) -> String {
        "dynamic-field-input-\(fieldID.uuidString)"
    }
}

private struct CardBackgroundPageIndicator: View {
    let count: Int
    let selectedIndex: Int

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 12) {
                ForEach(0..<count, id: \.self) { _ in
                    Circle()
                        .fill(CardaTheme.pageIndicatorFill)
                        .frame(width: 8, height: 8)
                }
            }

            Circle()
                .fill(CardaTheme.pageIndicatorActiveDot)
                .frame(width: 8, height: 8)
                .offset(x: CGFloat(activeIndex) * 20)
                .animation(
                    .snappy(duration: CardEditorView.backgroundPageAnimationDuration),
                    value: activeIndex
                )
        }
        .frame(width: indicatorWidth, height: 8, alignment: .leading)
        .accessibilityHidden(true)
    }

    private var activeIndex: Int {
        min(max(selectedIndex, 0), max(count - 1, 0))
    }

    private var indicatorWidth: CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * 8 + CGFloat(count - 1) * 12
    }
}

private struct FixedInfoGroup: View {
    @Binding var organizationName: String
    @Binding var position: String
    @Binding var logoPickerItem: PhotosPickerItem?
    let logoData: Data?

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(CardaTheme.editorFormFill)

            FixedInfoTextRow(title: "公司", text: $organizationName)
                .offset(y: 0)

            FixedInfoTextRow(title: "职位", text: $position)
                .offset(y: 68)

            FixedInfoLogoRow(logoData: logoData)
                .offset(y: 136)

            EditorGroupSeparator()
                .offset(x: EditorGroupSeparator.horizontalInset, y: 68)

            EditorGroupSeparator()
                .offset(x: EditorGroupSeparator.horizontalInset, y: 136)

            PhotosPicker(selection: $logoPickerItem, matching: .images) {
                Color.clear
                    .frame(width: 370, height: 68)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(y: 136)
        }
        .frame(width: 370, height: 204, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

private struct FixedInfoTextRow: View {
    let title: String
    @Binding var text: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(title)
                .font(CardaTheme.pingFang(size: 15))
                .foregroundStyle(Color.black)
                .frame(width: 338, height: 22, alignment: .leading)
                .offset(x: 16, y: 13)

            FigmaEditorTextField(
                placeholder: "请输入文本",
                text: $text,
                font: CardaTheme.pingFang(size: 17),
                placeholderFont: CardaTheme.pingFang(size: 17),
                color: CardaTheme.formSecondaryText,
                placeholderColor: CardaTheme.formSecondaryText,
                lineLimit: 1...1
            )
            .frame(width: 338, height: 20, alignment: .topLeading)
            .offset(x: 16, y: 35)
        }
        .frame(width: 370, height: 68, alignment: .topLeading)
    }
}

private struct FixedInfoLogoRow: View {
    let logoData: Data?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text("LOGO")
                .font(CardaTheme.pingFang(size: 15))
                .foregroundStyle(Color.black)
                .frame(width: 338, height: 22, alignment: .leading)
                .offset(x: 16, y: 13)

            Text(logoData == nil ? "上传公司LOGO" : "已上传")
                .font(CardaTheme.pingFang(size: 17))
                .foregroundStyle(CardaTheme.formSecondaryText)
                .frame(width: 338, height: 20, alignment: .leading)
                .offset(x: 16, y: 35)

            if let logoData {
                DataImageView(data: logoData)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .offset(x: 300, y: 20)
            }

            ChevronRightShape()
                .stroke(CardaTheme.formSecondaryText, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                .frame(width: 6, height: 11)
                .offset(x: 334, y: 29)
        }
        .frame(width: 370, height: 68, alignment: .topLeading)
    }
}

private struct EditorGroupSeparator: View {
    static let horizontalInset: CGFloat = 16

    var body: some View {
        Rectangle()
            .fill(CardaTheme.formGroupSeparator)
            .frame(width: CardaTheme.cardWidth - Self.horizontalInset * 2, height: 1)
    }
}

private struct EditableCardFieldRow: View {
    @Binding var field: CardFieldDraft
    let showsDeleteButton: Bool
    let onEditingWillBegin: () -> Void
    let onEditingChanged: (Bool) -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Menu {
                ForEach(CardFieldKind.allCases) { kind in
                    Button {
                        field.kind = kind
                    } label: {
                        Text(kind.title)
                            .font(CardaTheme.pingFang(size: 15))
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(displayKind.title)
                        .font(CardaTheme.pingFang(size: 15))
                        .foregroundStyle(CardaTheme.primaryText)
                        .frame(height: 22, alignment: .leading)
                    ChevronDownShape()
                        .stroke(CardaTheme.primaryText, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                        .frame(width: 10, height: 10)
                }
                .frame(height: 22, alignment: .leading)
            }
            .tint(CardaTheme.primaryText)
            .offset(x: 16, y: titleTop)

            FigmaEditorTextField(
                placeholder: valuePlaceholder,
                text: $field.value,
                font: valueFont,
                placeholderFont: valueFont,
                color: CardaTheme.formSecondaryText,
                placeholderColor: CardaTheme.formSecondaryText,
                lineLimit: 1...5,
                tracking: valueTracking,
                formatsPhoneNumber: field.kind == .phone,
                onEditingWillBegin: onEditingWillBegin,
                onEditingChanged: onEditingChanged
            )
            .frame(width: 338, height: valueHeight, alignment: .topLeading)
            .offset(x: 16, y: valueTop)
            .onChange(of: field.kind) { _, newKind in
                guard newKind == .phone else { return }
                field.value = PhoneNumberFormatter.format(field.value)
            }

            if showsDeleteButton {
                Button(action: onDelete) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 1, green: 18 / 255, blue: 18 / 255))
                        RoundedRectangle(cornerRadius: 0)
                            .fill(CardaTheme.separator)
                            .frame(width: 12, height: 2)
                    }
                    .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除文本框")
                .offset(x: 326, y: deleteTop)
            }
        }
        .frame(width: 370, height: rowHeight, alignment: .topLeading)
    }

    private var titleTop: CGFloat {
        13
    }

    private var valueTop: CGFloat {
        35
    }

    private var valueHeight: CGFloat {
        22 + CGFloat(max(0, editorLineCount - 1)) * 20
    }

    private var deleteTop: CGFloat {
        (rowHeight - 28) / 2
    }

    private var rowHeight: CGFloat {
        68 + CGFloat(max(0, editorLineCount - 1)) * 20
    }

    private var editorLineCount: Int {
        CardEditorView.editorLineCount(for: field.value)
    }

    private var valueFont: Font {
        switch displayKind {
        case .phone, .email:
            CardaTheme.sfPro(size: 17)
        case .address, .link, .companyLogo:
            CardaTheme.pingFang(size: 17)
        }
    }

    private var valueTracking: CGFloat {
        switch displayKind {
        case .phone, .email:
            -0.43
        case .address, .link, .companyLogo:
            0
        }
    }

    private var valuePlaceholder: String {
        switch displayKind {
        case .phone:
            "请输入手机号"
        case .email:
            "请输入邮箱"
        case .address:
            "请输入地址"
        case .link:
            "https：//"
        case .companyLogo:
            ""
        }
    }

    private var displayKind: CardFieldKind {
        CardFieldKind.allCases.contains(field.kind) ? field.kind : .phone
    }
}

private struct FigmaEditorTextField: View {
    let placeholder: String
    @Binding var text: String
    let font: Font
    let placeholderFont: Font
    let color: Color
    let placeholderColor: Color
    let lineLimit: ClosedRange<Int>
    var tracking: CGFloat = 0
    var focusedPlaceholderOpacity = 1.0
    var secondNameGlyphOffsetX: CGFloat?
    var formatsPhoneNumber = false
    var onEditingWillBegin: () -> Void = {}
    var onEditingChanged: (Bool) -> Void = { _ in }
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                placeholderContent
                    .opacity(isFocused ? focusedPlaceholderOpacity : 1)
                    .animation(.easeOut(duration: 0.15), value: isFocused)
            }

            textInput
        }
        .onChange(of: isFocused) { _, focused in
            guard !formatsPhoneNumber else { return }
            onEditingChanged(focused)
        }
        .simultaneousGesture(
            TapGesture()
                .onEnded(onEditingWillBegin)
        )
    }

    private var isSingleLine: Bool {
        lineLimit.upperBound == 1
    }

    @ViewBuilder
    private var placeholderContent: some View {
        if let secondNameGlyphOffsetX {
            HStack(spacing: 0) {
                Text("姓        ")
                    .font(placeholderFont)
                    .foregroundStyle(placeholderColor)
                    .tracking(tracking)

                Text("名")
                    .font(placeholderFont)
                    .foregroundStyle(placeholderColor)
                    .tracking(tracking)
                    .offset(x: secondNameGlyphOffsetX)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .allowsHitTesting(false)
        } else {
            Text(placeholder)
                .font(placeholderFont)
                .foregroundStyle(placeholderColor)
                .tracking(tracking)
                .lineLimit(lineLimit.upperBound)
                .fixedSize(horizontal: isSingleLine, vertical: false)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var textInput: some View {
        if formatsPhoneNumber {
            PhoneNumberEditorTextField(
                text: $text,
                color: color,
                tracking: tracking,
                onEditingWillBegin: onEditingWillBegin,
                onEditingChanged: onEditingChanged
            )
        } else if isSingleLine {
            TextField("", text: $text)
                .focused($isFocused)
                .font(font)
                .foregroundStyle(color)
                .tracking(tracking)
                .textFieldStyle(.plain)
                .lineLimit(1)
                .disableAutocorrection(true)
                .submitLabel(.done)
                .onSubmit(dismissKeyboard)
        } else {
            TextField("", text: $text, axis: .vertical)
                .focused($isFocused)
                .font(font)
                .foregroundStyle(color)
                .tracking(tracking)
                .textFieldStyle(.plain)
                .lineLimit(lineLimit)
                .disableAutocorrection(true)
                .submitLabel(.done)
                .onSubmit(dismissKeyboard)
                .onChange(of: text) { oldValue, newValue in
                    handleMultilineSubmission(from: oldValue, to: newValue)
                }
        }
    }

    private func handleMultilineSubmission(from oldValue: String, to newValue: String) {
        guard newValue.contains(where: \.isNewline) else { return }

        let valueWithoutLineBreaks = String(newValue.filter { !$0.isNewline })
        if valueWithoutLineBreaks == oldValue {
            text = oldValue
        } else {
            text = newValue
                .components(separatedBy: .newlines)
                .joined(separator: " ")
        }

        dismissKeyboard()
    }

    private func dismissKeyboard() {
        isFocused = false
    }
}

private struct PhoneNumberEditorTextField: UIViewRepresentable {
    @Binding var text: String
    let color: Color
    let tracking: CGFloat
    let onEditingWillBegin: () -> Void
    let onEditingChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            onEditingWillBegin: onEditingWillBegin,
            onEditingChanged: onEditingChanged
        )
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textDidChange(_:)),
            for: .editingChanged
        )
        textField.font = .systemFont(ofSize: 17, weight: .regular)
        textField.textColor = UIColor(color)
        textField.tintColor = UIColor(CardaTheme.primaryText)
        textField.backgroundColor = .clear
        textField.borderStyle = .none
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.returnKeyType = .done
        textField.clearButtonMode = .never
        textField.defaultTextAttributes[.kern] = tracking
        textField.text = PhoneNumberFormatter.format(text)
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        let formatted = PhoneNumberFormatter.format(text)
        guard textField.text != formatted else { return }
        textField.text = formatted
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding private var text: String
        private let onEditingWillBegin: () -> Void
        private let onEditingChanged: (Bool) -> Void

        init(
            text: Binding<String>,
            onEditingWillBegin: @escaping () -> Void,
            onEditingChanged: @escaping (Bool) -> Void
        ) {
            _text = text
            self.onEditingWillBegin = onEditingWillBegin
            self.onEditingChanged = onEditingChanged
        }

        @objc
        func textDidChange(_ textField: UITextField) {
            let enteredText = textField.text ?? ""
            let cursorOffset = textField.selectedTextRange
                .map { textField.offset(from: textField.beginningOfDocument, to: $0.start) }
                ?? enteredText.count
            let digitsBeforeCursor = enteredText
                .prefix(cursorOffset)
                .filter(\.isNumber)
                .count
            let formatted = PhoneNumberFormatter.format(enteredText)

            textField.text = formatted
            text = formatted

            let restoredOffset = cursorPosition(
                afterDigitCount: digitsBeforeCursor,
                in: formatted
            )
            if let position = textField.position(
                from: textField.beginningOfDocument,
                offset: restoredOffset
            ) {
                textField.selectedTextRange = textField.textRange(
                    from: position,
                    to: position
                )
            }
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return false
        }

        func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
            onEditingWillBegin()
            return true
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            onEditingChanged(true)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            onEditingChanged(false)
        }

        private func cursorPosition(afterDigitCount digitCount: Int, in value: String) -> Int {
            guard digitCount > 0 else { return 0 }

            var seenDigits = 0
            for (offset, character) in value.enumerated() {
                if character.isNumber {
                    seenDigits += 1
                    if seenDigits == digitCount {
                        return offset + 1
                    }
                }
            }
            return value.count
        }
    }
}

private struct ChevronRightShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}

private struct ChevronDownShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.3))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.15))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.3))
        return path
    }
}
