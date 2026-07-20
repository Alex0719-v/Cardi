//
//  LocalAccountAuthenticationPage.swift
//  Cardi
//

import SwiftUI
import UIKit

struct LocalAccountAuthenticationPage: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case login = "登录"
        case register = "注册"

        var id: Self { self }
    }

    private enum FocusField: Hashable {
        case phone
        case password
        case passwordConfirmation
    }

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .login
    @State private var phoneNumber = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var errorMessage: String?
    @FocusState private var focusedField: FocusField?

    let onAuthenticated: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            accountToolbar
                .zIndex(1)

            Form {
                Section {
                    Picker("登录或注册", selection: $mode) {
                        ForEach(Mode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 9, leading: 16, bottom: 9, trailing: 16))
                    .accessibilityLabel("登录或注册")
                }

                Section {
                    authenticationRow(title: "手机号") {
                        TextField("请输入手机号", text: $phoneNumber)
                            .font(CardaTheme.sfPro(size: 17))
                            .multilineTextAlignment(.trailing)
                            .textContentType(.telephoneNumber)
                            .keyboardType(.phonePad)
                            .focused($focusedField, equals: .phone)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .password }
                            .onChange(of: phoneNumber) { _, newValue in
                                let formatted = PhoneNumberFormatter.format(newValue)
                                if phoneNumber != formatted {
                                    phoneNumber = formatted
                                }
                            }
                            .accessibilityLabel("手机号")
                    }

                    authenticationRow(title: "密码") {
                        SecureField("请输入密码", text: $password)
                            .font(CardaTheme.sfPro(size: 17))
                            .multilineTextAlignment(.trailing)
                            .textContentType(mode == .login ? .password : .newPassword)
                            .focused($focusedField, equals: .password)
                            .submitLabel(mode == .register ? .next : .done)
                            .onSubmit {
                                if mode == .register {
                                    focusedField = .passwordConfirmation
                                } else {
                                    authenticate()
                                }
                            }
                            .accessibilityLabel("密码")
                    }

                    if mode == .register {
                        authenticationRow(title: "确认密码") {
                            SecureField("请再次输入密码", text: $passwordConfirmation)
                                .font(CardaTheme.sfPro(size: 17))
                                .multilineTextAlignment(.trailing)
                                .textContentType(.newPassword)
                                .focused($focusedField, equals: .passwordConfirmation)
                                .submitLabel(.done)
                                .onSubmit(authenticate)
                                .accessibilityLabel("确认密码")
                        }
                    }
                } footer: {
                    Text(mode == .login ? "使用已在本机注册的手机号登录。" : "注册后，手机号将作为该本地账户的唯一标识。")
                        .font(CardaTheme.pingFang(size: 13))
                }

                Section {
                    Button(mode.rawValue, action: authenticate)
                        .font(CardaTheme.pingFang(size: 17, weight: .medium))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .disabled(!canSubmit)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(CardaTheme.systemSelectionBlue.opacity(canSubmit ? 1 : 0.35))
                        )
                        .accessibilityLabel(mode == .login ? "登录账户" : "注册账户")
                } footer: {
                    localLoginNotice
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(CardaTheme.pageBackground)
            .environment(\.defaultMinListRowHeight, 52)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CardaTheme.pageBackground)
        .onChange(of: mode) { _, _ in
            password = ""
            passwordConfirmation = ""
            errorMessage = nil
            focusedField = .phone
        }
        .alert(
            mode == .login ? "登录失败" : "注册失败",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "请稍后重试。")
        }
    }

    private var localLoginNotice: some View {
        Text("软件目前暂未开放登录功能，该登录仅为本地登录，暂时无法跨设备同步")
            .font(CardaTheme.pingFang(size: 13))
            .foregroundStyle(Color.black.opacity(0.5))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .lineLimit(1)
            .minimumScaleFactor(0.68)
            .padding(.bottom, 12)
            .accessibilityLabel("本地登录说明")
    }

    private var accountToolbar: some View {
        ZStack(alignment: .top) {
            Button(action: dismiss.callAsFunction) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.black)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(CardaTheme.searchBackground.opacity(0.5)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16)
            .padding(.top, 16)
            .accessibilityLabel("返回")

            Text("登录 / 注册")
                .font(CardaTheme.pingFang(size: 17, weight: .medium))
                .foregroundStyle(Color.black)
                .frame(height: 22)
                .padding(.top, 29)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 54, alignment: .top)
        .background(CardaTheme.pageBackground)
    }

    private func authenticationRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(CardaTheme.pingFang(size: 17))
                .foregroundStyle(Color.black)
                .frame(width: 76, alignment: .leading)

            content()
                .foregroundStyle(Color.black)
        }
        .frame(minHeight: 36)
    }

    private var canSubmit: Bool {
        LocalAccountCardStore.canonicalPhoneNumber(phoneNumber) != nil
            && !password.isEmpty
            && (mode == .login || !passwordConfirmation.isEmpty)
    }

    private func authenticate() {
        guard
            canSubmit,
            let canonicalPhoneNumber = LocalAccountCardStore.canonicalPhoneNumber(phoneNumber)
        else {
            return
        }

        focusedField = nil
        let credentialStore = LocalAccountCredentialStore()
        do {
            switch mode {
            case .login:
                guard try credentialStore.authenticate(
                    phoneNumber: canonicalPhoneNumber,
                    password: password
                ) else {
                    errorMessage = "手机号或密码错误。"
                    return
                }
            case .register:
                guard password == passwordConfirmation else {
                    errorMessage = "两次输入的密码不一致。"
                    return
                }
                try credentialStore.register(
                    phoneNumber: canonicalPhoneNumber,
                    password: password
                )
            }
            password = ""
            passwordConfirmation = ""
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
            Task { @MainActor in
                await Task.yield()
                onAuthenticated(canonicalPhoneNumber)
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "无法访问本机账户凭据，请稍后重试。"
        }
    }
}
