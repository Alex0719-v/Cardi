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
    var tintColor: Color = CardaTheme.pageBackground
    var tintOpacity: Double = 0.5
    var matchesOpaqueEdgeColor = false

    var body: some View {
        ZStack {
            ZStack {
                MaximumBackdropBlurMaterial()

                tintColor
                    .opacity(tintOpacity)
            }
            .mask(
                LinearGradient(
                    stops: maskStops,
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            if matchesOpaqueEdgeColor {
                LinearGradient(
                    stops: edgeColorStops,
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }

    private var maskStops: [Gradient.Stop] {
        let topStops = [
            Gradient.Stop(color: .black, location: 0),
            Gradient.Stop(color: .black, location: 0.3),
            Gradient.Stop(color: .black.opacity(0.78), location: 0.55),
            Gradient.Stop(color: .black.opacity(0.35), location: 0.78),
            Gradient.Stop(color: .clear, location: 1)
        ]

        switch direction {
        case .top:
            return topStops
        case .bottom:
            return Array(topStops.map {
                Gradient.Stop(color: $0.color, location: 1 - $0.location)
            }
            .reversed())
        }
    }

    private var edgeColorStops: [Gradient.Stop] {
        let bottomStops = [
            Gradient.Stop(color: .clear, location: 0),
            Gradient.Stop(color: .clear, location: 0.76),
            Gradient.Stop(color: tintColor.opacity(0.28), location: 0.9),
            Gradient.Stop(color: tintColor, location: 1)
        ]

        switch direction {
        case .top:
            return Array(bottomStops.map {
                Gradient.Stop(color: $0.color, location: 1 - $0.location)
            }
            .reversed())
        case .bottom:
            return bottomStops
        }
    }
}

#if canImport(UIKit)
private struct MaximumBackdropBlurMaterial: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        makeBlurView()
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: .systemChromeMaterial)
        uiView.backgroundColor = .clear
        uiView.contentView.backgroundColor = .clear
    }

    private func makeBlurView() -> UIVisualEffectView {
        let view = UIVisualEffectView(
            effect: UIBlurEffect(style: .systemChromeMaterial)
        )
        view.backgroundColor = .clear
        view.contentView.backgroundColor = .clear
        return view
    }
}
#else
private struct MaximumBackdropBlurMaterial: View {
    var body: some View {
        Rectangle()
            .fill(.thickMaterial)
    }
}
#endif
