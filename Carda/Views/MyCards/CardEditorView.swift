//
//  CardEditorView.swift
//  Carda
//

import PhotosUI
import SwiftUI

struct CardEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: BusinessCardDraft
    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var logoPickerItem: PhotosPickerItem?

    let onCommit: (BusinessCardDraft) -> Void

    init(initialDraft: BusinessCardDraft, onCommit: @escaping (BusinessCardDraft) -> Void) {
        _draft = State(initialValue: initialDraft)
        self.onCommit = onCommit
    }

    var body: some View {
        FigmaPhoneCanvas {
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
        ScrollView {
            ZStack(alignment: .topLeading) {
                topCardPreview
                    .offset(x: 16, y: 63)

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
        BusinessCardView(data: draft.renderData)
            .onTapGesture {
                // 底图切换页尚未设计；当前固定使用 Card photo/Group 42.png。
            }
    }

    private var avatarPicker: some View {
        PhotosPicker(selection: $avatarPickerItem, matching: .images) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.55))
                if draft.avatarImageData != nil {
                    DataImageView(data: draft.avatarImageData)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 34))
                        .foregroundStyle(Color.white.opacity(0.9))
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
                tracking: 4
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
                tracking: 16
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
                    showsDeleteButton: index > 0
                ) {
                    removeField(field)
                }
                .offset(y: dynamicRowOffset(for: index))

                if index < (draft.fields.indices.last ?? 0) {
                    EditorGroupSeparator()
                        .offset(x: EditorGroupSeparator.horizontalInset)
                        .offset(y: dynamicRowOffset(for: index + 1))
                }
            }
        }
        .frame(width: 370, height: dynamicFieldsHeight, alignment: .topLeading)
        .background(CardaTheme.formFill, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
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
        max(CardaTheme.editorCanvasHeight, addFieldButtonY + 72)
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
                    .fill(Color(red: 120 / 255, green: 120 / 255, blue: 120 / 255))
                RoundedRectangle(cornerRadius: 0)
                    .fill(CardaTheme.separator)
                    .frame(width: 12, height: 2)
                    .offset(x: 8, y: 13)
                RoundedRectangle(cornerRadius: 0)
                    .fill(CardaTheme.separator)
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
        }
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
                .fill(CardaTheme.formFill)

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
                tracking: valueTracking
            )
            .frame(width: 338, height: valueHeight, alignment: .topLeading)
            .offset(x: 16, y: valueTop)

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
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(placeholderFont)
                    .foregroundStyle(placeholderColor)
                    .tracking(tracking)
                    .lineLimit(lineLimit.upperBound)
                    .fixedSize(horizontal: isSingleLine, vertical: false)
                    .allowsHitTesting(false)
            }

            textInput
        }
    }

    private var isSingleLine: Bool {
        lineLimit.upperBound == 1
    }

    @ViewBuilder
    private var textInput: some View {
        if isSingleLine {
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
        }
    }

    private func dismissKeyboard() {
        isFocused = false
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
