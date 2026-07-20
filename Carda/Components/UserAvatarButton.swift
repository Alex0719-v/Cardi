//
//  UserAvatarButton.swift
//  Cardi
//

import SwiftUI

struct UserAvatarButton: View {
    var imageData: Data?
    var isLoggedIn = false
    var action: () -> Void

    var body: some View {
        let hasAvatarImage = isLoggedIn && imageData != nil

        Button(action: action) {
            AccountAvatarGlassSurface(
                width: 44,
                height: 44,
                cornerRadius: 22,
                interactive: true
            )
            .opacity(hasAvatarImage ? 0 : 1)
            .overlay {
                if hasAvatarImage {
                    DataImageView(data: imageData)
                        .frame(width: 44, height: 44)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 22,
                                style: .circular
                            )
                        )
                }
            }
            .contentShape(
                RoundedRectangle(
                    cornerRadius: 22,
                    style: .circular
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("用户头像")
        .accessibilityValue(hasAvatarImage ? "已设置头像" : "未设置头像")
        .accessibilityIdentifier("my-cards-account-avatar-button")
    }
}

/// Shared native-glass surface used by the static account avatar and the
/// card-holder avatar-to-list morph. The frame is fixed before glass sampling
/// so overlay content can never widen the visible glass outline.
struct AccountAvatarGlassSurface: View {
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat
    var interactive: Bool

    var body: some View {
        if #available(iOS 26.0, *) {
            if interactive {
                glassBase
                    .glassEffect(
                        .regular.interactive(),
                        in: RoundedRectangle(
                            cornerRadius: cornerRadius,
                            style: .circular
                        )
                    )
                    .shadow(color: .black.opacity(0.16), radius: 26, x: 0, y: 10)
            } else {
                glassBase
                    .glassEffect(
                        .regular,
                        in: RoundedRectangle(
                            cornerRadius: cornerRadius,
                            style: .circular
                        )
                    )
                    .shadow(color: .black.opacity(0.16), radius: 26, x: 0, y: 10)
            }
        } else {
            glassBase
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(
                        cornerRadius: cornerRadius,
                        style: .circular
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: cornerRadius,
                        style: .circular
                    )
                    .fill(Color.white.opacity(0.22))
                }
                .shadow(color: .black.opacity(0.16), radius: 26, x: 0, y: 10)
        }
    }

    private var glassBase: some View {
        RoundedRectangle(
            cornerRadius: cornerRadius,
            style: .circular
        )
        .fill(Color.white.opacity(0.01))
        .frame(width: width, height: height)
    }
}

struct ScreenHeader: View {
    let title: String
    var avatarImageData: Data?
    var isAccountLoggedIn = false
    var avatarAction: () -> Void = {}

    var body: some View {
        HStack(alignment: .top) {
            Text(title)
                .font(CardaTheme.pingFang(size: 34, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(CardaTheme.primaryText)
                .frame(height: 41, alignment: .leading)
            Spacer()
            UserAvatarButton(
                imageData: avatarImageData,
                isLoggedIn: isAccountLoggedIn,
                action: avatarAction
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 62)
        .frame(width: CardaTheme.canvasWidth, height: 116, alignment: .topLeading)
    }
}
