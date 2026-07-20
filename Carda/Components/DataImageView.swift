//
//  DataImageView.swift
//  Cardi
//

import SwiftUI

struct DataImageView: View {
    let data: Data?
    let contentMode: ContentMode

    init(data: Data?, contentMode: ContentMode = .fill) {
        self.data = data
        self.contentMode = contentMode
    }

    var body: some View {
        #if canImport(UIKit)
        if let data, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            EmptyView()
        }
        #else
        EmptyView()
        #endif
    }
}
