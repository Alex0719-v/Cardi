//
//  TransparentGradientBlur.swift
//  Carda
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct TransparentGradientBlur: View {
    enum Direction {
        case top
        case bottom
    }

    var width: CGFloat = CardaTheme.canvasWidth
    var height: CGFloat = 140
    var direction: Direction = .bottom

    var body: some View {
        BackdropBlurMaterial()
            .mask(
                LinearGradient(
                    colors: maskColors,
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: width, height: height)
            .allowsHitTesting(false)
    }

    private var maskColors: [Color] {
        switch direction {
        case .top:
            [.black, .black.opacity(0.85), .clear]
        case .bottom:
            [.clear, .black.opacity(0.85), .black]
        }
    }
}

#if canImport(UIKit)
private struct BackdropBlurMaterial: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        view.backgroundColor = .clear
        view.contentView.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: .systemUltraThinMaterial)
        uiView.backgroundColor = .clear
        uiView.contentView.backgroundColor = .clear
    }
}
#else
private struct BackdropBlurMaterial: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
    }
}
#endif
