//
//  AccountProfilePage.swift
//  Cardi
//

import PhotosUI
import SwiftUI
import UIKit

struct AccountProfilePage: View {
    private enum FocusField: Hashable {
        case name
        case email
    }

    private enum ProfileAlert: Identifiable {
        case saveFailure

        var id: String {
            switch self {
            case .saveFailure: "saveFailure"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var avatarImageData: Data?
    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var name: String
    @State private var email: String
    @State private var presentedAlert: ProfileAlert?
    @FocusState private var focusedField: FocusField?

    private let phoneNumber: String
    let onSave: (Data?, String, String, String) -> Bool
    let onCompletion: () -> Void

    init(
        initialAvatarImageData: Data?,
        initialName: String?,
        initialPhoneNumber: String?,
        initialEmail: String?,
        onSave: @escaping (Data?, String, String, String) -> Bool,
        onCompletion: @escaping () -> Void
    ) {
        _avatarImageData = State(initialValue: initialAvatarImageData)
        _name = State(initialValue: initialName ?? "")
        _email = State(initialValue: initialEmail ?? "")
        phoneNumber = LocalAccountCardStore.canonicalPhoneNumber(initialPhoneNumber ?? "") ?? ""
        self.onSave = onSave
        self.onCompletion = onCompletion
    }

    var body: some View {
        VStack(spacing: 0) {
            accountToolbar
                .zIndex(1)

            Form {
                Section {
                    avatarPicker
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 14, leading: 0, bottom: 14, trailing: 0))
                .listRowSeparator(.hidden)

                Section {
                    accountTextRow(
                        title: "昵称",
                        placeholder: "请输入昵称",
                        text: $name,
                        focusField: .name,
                        contentType: .nickname,
                        keyboardType: .default,
                        submitLabel: .next
                    ) {
                        focusedField = .email
                    }

                    accountValueRow(
                        title: "手机号",
                        value: PhoneNumberFormatter.format(phoneNumber)
                    )

                    accountTextRow(
                        title: "邮箱",
                        placeholder: "请输入邮箱",
                        text: $email,
                        focusField: .email,
                        contentType: .emailAddress,
                        keyboardType: .emailAddress,
                        submitLabel: .done
                    ) {
                        if canSave {
                            requestSave()
                        } else {
                            focusedField = nil
                        }
                    }
                }
                .listRowBackground(Color.white)
            }
            .formStyle(.grouped)
            .listSectionSpacing(4)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(CardaTheme.pageBackground)
            .environment(\.defaultMinListRowHeight, 52)

            Text("软件目前暂未开放登录功能，该登录仅为本地登录，暂时无法跨设备同步")
                .font(CardaTheme.pingFang(size: 13))
                .foregroundStyle(Color.black.opacity(0.5))
                .multilineTextAlignment(.center)
                .frame(width: 338)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .accessibilityLabel("本地登录说明")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CardaTheme.pageBackground)
        .task(id: avatarPickerItem) {
            guard
                let avatarPickerItem,
                let sourceData = try? await avatarPickerItem.loadTransferable(type: Data.self)
            else {
                return
            }
            avatarImageData = AccountAvatarImageProcessor.normalizedData(from: sourceData)
                ?? sourceData
        }
        .alert(item: $presentedAlert) { alert in
            switch alert {
            case .saveFailure:
                Alert(
                    title: Text("无法保存账户资料"),
                    message: Text("请确认设备仍有可用存储空间后重试。"),
                    dismissButton: .default(Text("好"))
                )
            }
        }
    }

    private var accountToolbar: some View {
        ZStack(alignment: .top) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.black)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(CardaTheme.searchBackground.opacity(0.5))
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16)
            .padding(.top, 16)
            .accessibilityLabel("返回")

            Text("修改信息")
                .font(CardaTheme.pingFang(size: 17, weight: .medium))
                .foregroundStyle(Color.black)
                .frame(height: 22)
                .padding(.top, 29)
                .accessibilityAddTraits(.isHeader)

            Button("完成", action: requestSave)
                .font(CardaTheme.pingFang(size: 17, weight: .medium))
                .foregroundStyle(CardaTheme.systemSelectionBlue)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.35)
                .frame(width: 52, height: 44)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 16)
                .padding(.top, 16)
                .accessibilityLabel("保存账户资料")
        }
        .frame(maxWidth: .infinity)
        .frame(height: 54, alignment: .top)
        .background(CardaTheme.pageBackground)
    }

    private var avatarPicker: some View {
        HStack {
            Spacer(minLength: 0)

            PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                VStack(spacing: 8) {
                    ZStack(alignment: .bottomTrailing) {
                        Group {
                            if avatarImageData != nil {
                                DataImageView(data: avatarImageData)
                            } else {
                                Circle()
                                    .fill(Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255))
                                    .overlay {
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 42, weight: .regular))
                                            .foregroundStyle(Color.white.opacity(0.9))
                                    }
                            }
                        }
                        .frame(width: 92, height: 92)
                        .clipShape(Circle())

                        Image(systemName: "camera.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(CardaTheme.systemSelectionBlue))
                            .overlay {
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                            }
                    }

                    Text(avatarImageData == nil ? "添加头像" : "更换头像")
                        .font(CardaTheme.pingFang(size: 15))
                        .foregroundStyle(CardaTheme.systemSelectionBlue)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(avatarImageData == nil ? "添加头像" : "更换头像")

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 126)
    }

    private func accountTextRow(
        title: String,
        placeholder: String,
        text: Binding<String>,
        focusField: FocusField,
        contentType: UITextContentType?,
        keyboardType: UIKeyboardType,
        submitLabel: SubmitLabel,
        onSubmit: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(CardaTheme.pingFang(size: 17))
                .foregroundStyle(Color.black)
                .frame(width: 52, alignment: .leading)

            TextField(placeholder, text: text)
                .font(
                    focusField == .email
                        ? CardaTheme.sfPro(size: 17)
                        : CardaTheme.pingFang(size: 17)
                )
                .foregroundStyle(Color.black)
                .multilineTextAlignment(.trailing)
                .textContentType(contentType)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(
                    focusField == .name ? .sentences : .never
                )
                .autocorrectionDisabled(focusField != .name)
                .submitLabel(submitLabel)
                .focused($focusedField, equals: focusField)
                .onSubmit(onSubmit)
                .accessibilityLabel(title)
        }
        .frame(minHeight: 36)
    }

    private func accountValueRow(title: String, value: String) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(CardaTheme.pingFang(size: 17))
                .foregroundStyle(Color.black)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 60, alignment: .leading)

            Spacer(minLength: 0)

            Text(verbatim: value)
                .font(CardaTheme.sfPro(size: 17))
                .foregroundStyle(Color.black.opacity(0.5))
                .accessibilityLabel(title)
                .accessibilityValue(value)
        }
        .frame(minHeight: 36)
    }

    private var canSave: Bool {
        !normalizedName.isEmpty
            && normalizedPhoneNumber != nil
            && !normalizedEmail.isEmpty
    }

    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedPhoneNumber: String? {
        LocalAccountCardStore.canonicalPhoneNumber(phoneNumber)
    }

    private func requestSave() {
        guard canSave else { return }
        focusedField = nil
        saveAndComplete()
    }

    private func saveAndComplete() {
        guard canSave, let normalizedPhoneNumber else { return }
        focusedField = nil
        if onSave(avatarImageData, normalizedName, normalizedEmail, normalizedPhoneNumber) {
            onCompletion()
        } else {
            presentedAlert = .saveFailure
        }
    }
}

private enum AccountAvatarImageProcessor {
    static func normalizedData(from sourceData: Data) -> Data? {
        guard let sourceImage = UIImage(data: sourceData) else { return nil }

        let outputSize = CGSize(width: 512, height: 512)
        let widthScale = outputSize.width / max(sourceImage.size.width, 1)
        let heightScale = outputSize.height / max(sourceImage.size.height, 1)
        let scale = max(widthScale, heightScale)
        let drawingSize = CGSize(
            width: sourceImage.size.width * scale,
            height: sourceImage.size.height * scale
        )
        let drawingRect = CGRect(
            x: (outputSize.width - drawingSize.width) / 2,
            y: (outputSize.height - drawingSize.height) / 2,
            width: drawingSize.width,
            height: drawingSize.height
        )

        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)
        let normalizedImage = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: outputSize))
            sourceImage.draw(in: drawingRect)
        }
        return normalizedImage.jpegData(compressionQuality: 0.86)
    }
}
