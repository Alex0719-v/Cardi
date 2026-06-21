//
//  CardaTheme.swift
//  Carda
//

import SwiftUI

enum CardaTheme {
    static let canvasWidth: CGFloat = 402
    static let canvasHeight: CGFloat = 874
    static let editorCanvasHeight: CGFloat = 1044
    static let cardWidth: CGFloat = 370
    static let baseCardHeight: CGFloat = 222
    static let cardCornerRadius: CGFloat = 24

    static let pageBackground = Color(red: 249 / 255, green: 248 / 255, blue: 251 / 255)
    static let myCardsBackground = Color(red: 225 / 255, green: 224 / 255, blue: 227 / 255)
    static let editorBackground = pageBackground
    static let mainAccent = Color(red: 0.996, green: 0.475, blue: 0.235)
    static let selectedTabFill = Color(red: 0.929, green: 0.929, blue: 0.929)
    static let primaryText = Color(red: 0.102, green: 0.102, blue: 0.102)
    static let secondaryText = Color.black.opacity(0.75)
    static let formFill = Color(red: 0.47, green: 0.47, blue: 0.47).opacity(0.2)
    static let formSecondaryText = Color(red: 0.235, green: 0.235, blue: 0.263).opacity(0.6)
    static let formGroupSeparator = Color(red: 0.902, green: 0.902, blue: 0.902)
    static let separator = Color(red: 0.902, green: 0.902, blue: 0.902)
    static let destructive = Color(red: 1, green: 56 / 255, blue: 60 / 255)

    static func pingFang(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch weight {
        case .semibold, .bold, .heavy, .black:
            .custom("PingFangSC-Semibold", size: size)
        case .medium:
            .custom("PingFangSC-Medium", size: size)
        default:
            .custom("PingFangSC-Regular", size: size)
        }
    }

    static func sfPro(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

extension CGFloat {
    func scaled(from designWidth: CGFloat, to actualWidth: CGFloat) -> CGFloat {
        self * actualWidth / designWidth
    }
}

extension View {
    func glassBackground(cornerRadius: CGFloat = 296) -> some View {
        background(FigmaGlassShape(cornerRadius: cornerRadius, interactive: true))
    }
}
