//
//  TransparentGradientBlur.swift
//  Cardi
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

    enum MaterialStyle {
        case chrome
        case ultraThinLight
    }

    var width: CGFloat = CardaTheme.canvasWidth
    var height: CGFloat = 140
    var direction: Direction = .bottom
    var materialStyle: MaterialStyle = .chrome
    var tintColor: Color = CardaTheme.pageBackground
    var tintOpacity: Double = 0.5
    var matchesOpaqueEdgeColor = false

    var body: some View {
        ZStack {
            ZStack {
                MaximumBackdropBlurMaterial(style: materialStyle)

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

/// A screen-positioned fallback for Figma's `Scroll Edge Effect - Soft`.
///
/// Cardi's card-holder scroll viewport deliberately extends below the canvas
/// to keep its sticky-header geometry stable, which puts the native bottom
/// scroll-edge effect off screen. This view preserves the Figma layer recipe
/// without changing the scroll view's physical size or content geometry.
struct FigmaScrollEdgeSoftOverlay: View {
    var width: CGFloat = CardaTheme.canvasWidth
    var height: CGFloat = 140
    var direction: TransparentGradientBlur.Direction = .bottom

    var body: some View {
        ZStack {
            // Figma outer progressive backdrop blur. Public UIKit does not
            // expose an arbitrary blur radius, so the lighter system material
            // supplies the soft 0 -> 10 transition through the alpha mask.
            MaximumBackdropBlurMaterial(style: .ultraThinLight)

            // Figma child "Blur": 90% opacity, black Screen fill, and the
            // stronger backdrop sample that corresponds to its radius 60.
            ZStack {
                MaximumBackdropBlurMaterial(style: .chrome)

                Color.black
                    .blendMode(.screen)
            }
            .opacity(0.9)
        }
        .mask(alphaMask)
        .frame(width: width, height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var alphaMask: some View {
        LinearGradient(
            colors: direction == .bottom
                ? [.clear, .black]
                : [.black, .clear],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

#if canImport(UIKit)
private struct MaximumBackdropBlurMaterial: UIViewRepresentable {
    let style: TransparentGradientBlur.MaterialStyle

    func makeUIView(context: Context) -> UIVisualEffectView {
        makeBlurView()
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: blurStyle)
        uiView.backgroundColor = .clear
        uiView.contentView.backgroundColor = .clear
    }

    private func makeBlurView() -> UIVisualEffectView {
        let view = UIVisualEffectView(
            effect: UIBlurEffect(style: blurStyle)
        )
        view.backgroundColor = .clear
        view.contentView.backgroundColor = .clear
        return view
    }

    private var blurStyle: UIBlurEffect.Style {
        switch style {
        case .chrome:
            return .systemChromeMaterial
        case .ultraThinLight:
            return .systemUltraThinMaterialLight
        }
    }
}
#else
private struct MaximumBackdropBlurMaterial: View {
    let style: TransparentGradientBlur.MaterialStyle

    var body: some View {
        Rectangle()
            .fill(style == .chrome ? .thickMaterial : .ultraThinMaterial)
    }
}
#endif
