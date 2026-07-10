//
//  CollapsedCardRow.swift
//  Carda
//

import SwiftUI

struct CollapsedCardRow: View {
    let data: CardRenderData
    var namespace: Namespace.ID?

    var body: some View {
        ZStack(alignment: .topLeading) {
            cardBackground

            Text(data.displayOrganizationName)
                .font(CardaTheme.pingFang(size: 15, weight: .regular))
                .foregroundStyle(Color.black.opacity(0.5))
                .lineLimit(1)
                .frame(width: 220, height: 20, alignment: .leading)
                .offset(x: 25, y: 5.5)

            Text(data.displayName)
                .font(displayNameFont)
                .foregroundStyle(Color.black)
                .lineLimit(1)
                .frame(width: 220, height: 22, alignment: .leading)
                .offset(x: 25, y: 30.5)

            if data.avatarImageData != nil {
                DataImageView(data: data.avatarImageData)
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                    .position(x: 340, y: 30)
            }
        }
        .frame(width: 370, height: 60)
        // The matched-geometry snapshot must carry the runway silhouette itself.
        // A rounded background alone still leaves a rectangular snapshot boundary.
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .circular))
        .compositingGroup()
        .modifier(CollapsedCardMatchModifier(id: data.id, namespace: namespace))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(data.displayName)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 30, style: .circular)
            .fill(Color.white)
    }

    private var displayNameFont: Font {
        data.displayName.unicodeScalars.allSatisfy { $0.isASCII }
            ? CardaTheme.sfPro(size: 17, weight: .semibold)
            : CardaTheme.pingFang(size: 17, weight: .semibold)
    }
}

private struct CollapsedCardMatchModifier: ViewModifier {
    let id: UUID
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: "holder-card-\(id)", in: namespace)
        } else {
            content
        }
    }
}
