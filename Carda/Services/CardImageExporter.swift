//
//  CardImageExporter.swift
//  Cardi
//

import SwiftUI

enum CardImageExporter {
    @MainActor
    static func savePNG(for data: CardRenderData) -> Bool {
        #if canImport(UIKit)
        let width = CardaTheme.cardWidth
        let renderer = ImageRenderer(
            content: BusinessCardView(
                data: data,
                width: width,
                renderingMode: .exportedImage
            )
        )
        renderer.scale = 3
        guard let image = renderer.uiImage else { return false }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        return true
        #else
        return false
        #endif
    }
}
