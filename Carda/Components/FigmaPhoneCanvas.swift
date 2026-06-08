//
//  FigmaPhoneCanvas.swift
//  Carda
//

import SwiftUI

struct FigmaPhoneCanvas<Content: View>: View {
    var height: CGFloat = CardaTheme.canvasHeight
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            let scale = min(
                proxy.size.width / CardaTheme.canvasWidth,
                proxy.size.height / height
            )

            ZStack {
                CardaTheme.pageBackground
                    .ignoresSafeArea()

                content()
                    .frame(width: CardaTheme.canvasWidth, height: height)
                    .scaleEffect(scale, anchor: .center)
                    .frame(
                        width: CardaTheme.canvasWidth * scale,
                        height: height * scale
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
    }
}
