//
//  UserAvatarButton.swift
//  Carda
//

import SwiftUI

struct UserAvatarButton: View {
    var imageData: Data?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                FigmaGlassShape(cornerRadius: 296, interactive: true)

                if imageData != nil {
                    DataImageView(data: imageData)
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("用户头像")
    }
}

struct ScreenHeader: View {
    let title: String
    var avatarImageData: Data?
    var avatarAction: () -> Void = {}

    var body: some View {
        HStack(alignment: .top) {
            Text(title)
                .font(CardaTheme.pingFang(size: 34, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(CardaTheme.primaryText)
                .frame(height: 41, alignment: .leading)
            Spacer()
            UserAvatarButton(imageData: avatarImageData, action: avatarAction)
                .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.top, 62)
        .frame(width: CardaTheme.canvasWidth, height: 116, alignment: .topLeading)
    }
}
