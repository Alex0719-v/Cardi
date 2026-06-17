//
//  BusinessCardView.swift
//  Carda
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum CardLayoutCalculator {
    static func height(for data: CardRenderData) -> CGFloat {
        let visible = data.visibleInfoFields
        let extraFields = max(0, visible.count - 3)
        let wrappedLines = visible.reduce(0) { partial, field in
            partial + extraInfoLineCount(for: field)
        }
        return CardaTheme.baseCardHeight
            + CGFloat(extraFields) * 24
            + CGFloat(wrappedLines) * 20
    }

    static func extraInfoLineCount(for field: CardFieldDraft) -> Int {
        max(0, infoLineCount(for: field) - 1)
    }

    static func infoLineCount(for field: CardFieldDraft) -> Int {
        let trimmed = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 1 }

        #if canImport(UIKit)
        return measuredLineCount(for: trimmed, kind: field.kind)
        #else
        return estimatedLineCount(for: trimmed)
        #endif
    }

    static func estimatedLineCount(for text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 1 }
        let maxCharactersPerLine = 18
        return trimmed
            .components(separatedBy: .newlines)
            .reduce(0) { partial, line in
                partial + max(1, Int(ceil(Double(max(line.count, 1)) / Double(maxCharactersPerLine))))
            }
    }

    #if canImport(UIKit)
    private static func measuredLineCount(for text: String, kind: CardFieldKind) -> Int {
        let font = infoFont(for: kind)
        let lineHeight = max(font.lineHeight, 1)

        return text
            .components(separatedBy: .newlines)
            .reduce(0) { partial, line in
                let measuredText = line.isEmpty ? " " : line
                let rect = (measuredText as NSString).boundingRect(
                    with: CGSize(width: 185, height: CGFloat.greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: font],
                    context: nil
                )
                return partial + max(1, Int(ceil(rect.height / lineHeight)))
            }
    }

    private static func infoFont(for kind: CardFieldKind) -> UIFont {
        switch kind {
        case .address:
            UIFont(name: "PingFangSC-Regular", size: 14) ?? .systemFont(ofSize: 14, weight: .regular)
        case .phone, .email, .link, .companyLogo:
            .systemFont(ofSize: 14, weight: .regular)
        }
    }
    #endif
}

struct BusinessCardView: View {
    let data: CardRenderData
    var width: CGFloat = CardaTheme.cardWidth

    private var scale: CGFloat {
        width / CardaTheme.cardWidth
    }

    private var height: CGFloat {
        CardLayoutCalculator.height(for: data) * scale
    }

    private var unscaledHeight: CGFloat {
        CardLayoutCalculator.height(for: data)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            cardBackground
            companyGroup
            avatar
            identityGroup
            infoGroup
            actionButtonColumn
        }
        .frame(width: width, height: height)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(data.displayName)
    }

    private var cardBackground: some View {
        let shape = BusinessCardBodyShape(
            cutoutTop: cardBodyCutoutTop * scale,
            cutoutWidth: cardBodyCutoutWidth * scale,
            cornerRadius: cardBodyCornerRadius * scale,
            usesCompactSingleButtonCutout: actionButtonFields.count == 1
        )

        return shape
            .fill(Color.white, style: FillStyle(eoFill: true))
            .shadow(color: .black.opacity(0.25), radius: 2 * scale, x: 0, y: 0)
            .overlay {
                CardPhotoBackground(width: width, height: height)
                    .mask {
                        shape.fill(style: FillStyle(eoFill: true))
                    }
            }
    }

    private var cardBodyCutoutWidth: CGFloat {
        actionButtonFields.isEmpty ? 0 : 41
    }

    private var cardBodyCornerRadius: CGFloat {
        CardaTheme.cardCornerRadius + 2
    }

    private var cardBodyCutoutTop: CGFloat {
        guard !actionButtonFields.isEmpty else { return unscaledHeight }
        return max(0, actionButtonColumnTop - 7)
    }

    private struct BusinessCardBodyShape: Shape {
        let cutoutTop: CGFloat
        let cutoutWidth: CGFloat
        let cornerRadius: CGFloat
        let usesCompactSingleButtonCutout: Bool

        func path(in rect: CGRect) -> Path {
            guard cutoutWidth > 0, cutoutTop < rect.height else {
                return Path(
                    roundedRect: rect,
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
            }

            let outerRadius = min(
                cornerRadius,
                rect.width / 2,
                rect.height / 2
            )
            let preferredSlotRadius = min(cornerRadius, cutoutWidth / 2)
            let minCutoutHeight = preferredSlotRadius + outerRadius
            let requestedCutoutY = min(max(0, cutoutTop), rect.height)
            let cutoutY = usesCompactSingleButtonCutout
                ? requestedCutoutY
                : min(requestedCutoutY, max(0, rect.height - minCutoutHeight))
            let cutoutHeight = rect.height - cutoutY
            let cutoutX = rect.maxX - cutoutWidth
            let slotRadius = min(
                preferredSlotRadius,
                cutoutHeight / 2,
                max(cutoutY - outerRadius, 0)
            )
            let bottomSlotRadius = min(
                outerRadius,
                cutoutHeight - slotRadius,
                rect.width / 2,
                rect.height / 2
            )

            var path = Path()
            path.move(to: CGPoint(x: rect.minX + outerRadius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - outerRadius, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + outerRadius),
                control: CGPoint(x: rect.maxX, y: rect.minY)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: cutoutY - slotRadius))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - slotRadius, y: cutoutY),
                control: CGPoint(x: rect.maxX, y: cutoutY)
            )
            path.addLine(to: CGPoint(x: cutoutX + slotRadius, y: cutoutY))
            path.addQuadCurve(
                to: CGPoint(x: cutoutX, y: cutoutY + slotRadius),
                control: CGPoint(x: cutoutX, y: cutoutY)
            )
            path.addLine(to: CGPoint(x: cutoutX, y: rect.maxY - bottomSlotRadius))
            path.addQuadCurve(
                to: CGPoint(x: cutoutX - bottomSlotRadius, y: rect.maxY),
                control: CGPoint(x: cutoutX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX + outerRadius, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - outerRadius),
                control: CGPoint(x: rect.minX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + outerRadius))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + outerRadius, y: rect.minY),
                control: CGPoint(x: rect.minX, y: rect.minY)
            )
            path.closeSubpath()

            return path
        }
    }

    private struct CardPhotoBackground: View {
        let width: CGFloat
        let height: CGFloat

        var body: some View {
            content
                .frame(width: width, height: height)
                .clipped()
        }

        @ViewBuilder
        private var content: some View {
            #if canImport(UIKit)
            if let image = Self.uiImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.clear
            }
            #elseif canImport(AppKit)
            if let image = Self.nsImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.clear
            }
            #else
            Color.clear
            #endif
        }

        private static var resourceURL: URL? {
            Bundle.main.url(forResource: "Group 42", withExtension: "png", subdirectory: "Card photo")
                ?? Bundle.main.url(forResource: "Group 42", withExtension: "png")
        }

        #if canImport(UIKit)
        private static var uiImage: UIImage? {
            guard let resourceURL else { return nil }
            return UIImage(contentsOfFile: resourceURL.path)
        }
        #elseif canImport(AppKit)
        private static var nsImage: NSImage? {
            guard let resourceURL else { return nil }
            return NSImage(contentsOfFile: resourceURL.path)
        }
        #endif
    }

    @ViewBuilder
    private var companyGroup: some View {
        let logoX: CGFloat = 23
        let top: CGFloat = 34
        if data.companyLogoImageData != nil {
            DataImageView(data: data.companyLogoImageData)
                .frame(width: 28 * scale, height: 28 * scale)
                .clipShape(RoundedRectangle(cornerRadius: 2 * scale))
                .offset(x: logoX * scale, y: top * scale)
            cardText(data.displayOrganizationName, size: 14, weight: .regular)
                .frame(height: 20 * scale, alignment: .leading)
                .offset(x: 56 * scale, y: 38 * scale)
        } else {
            cardText(data.displayOrganizationName, size: 14, weight: .regular)
                .frame(height: 20 * scale, alignment: .leading)
                .offset(x: logoX * scale, y: 38 * scale)
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if data.avatarImageData != nil {
            DataImageView(data: data.avatarImageData)
                .frame(width: 60 * scale, height: 60 * scale)
                .clipShape(Circle())
                .offset(x: 291 * scale, y: 23 * scale)
        }
    }

    private var identityGroup: some View {
        ZStack(alignment: .topLeading) {
            cardText(data.displayPosition, size: 14, weight: .regular)
                .frame(height: 20 * scale, alignment: .leading)
                .offset(y: 0)

            Text(data.displayName)
                .font(CardaTheme.pingFang(size: 33 * scale, weight: .semibold))
                .tracking(4.8 * scale)
                .foregroundStyle(Color.black)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 35 * scale, alignment: .leading)
                .offset(y: 18.5 * scale)

            Text(data.displayPhoneticName)
                .font(CardaTheme.sfPro(size: 14 * scale, weight: .regular))
                .foregroundStyle(CardaTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(height: 20 * scale, alignment: .leading)
                .offset(y: 49 * scale)
        }
        .frame(width: 132 * scale, height: 74 * scale, alignment: .leading)
        .offset(x: 23 * scale, y: identityGroupTop * scale)
    }

    private var identityGroupTop: CGFloat {
        ((unscaledHeight - 68) / 2) - 16
    }

    @ViewBuilder
    private var infoGroup: some View {
        let fields = data.visibleInfoFields
        if !fields.isEmpty {
            VStack(alignment: .trailing, spacing: 6 * scale) {
                ForEach(fields, id: \.id) { field in
                    let lineCount = CardLayoutCalculator.infoLineCount(for: field)
                    Text(field.value)
                        .font(infoFont(for: field.kind, size: 14 * scale))
                        .foregroundStyle(CardaTheme.secondaryText)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(nil)
                        .frame(
                            width: 185 * scale,
                            height: CGFloat(lineCount) * 20 * scale,
                            alignment: .trailing
                        )
                }
            }
            .frame(width: 185 * scale, alignment: .trailing)
            .offset(x: 122 * scale, y: infoGroupTop * scale)
        }
    }

    private var infoGroupTop: CGFloat {
        max(0, unscaledHeight - 20 - infoGroupDepth)
    }

    private var infoGroupDepth: CGFloat {
        let fields = data.visibleInfoFields
        guard !fields.isEmpty else { return 0 }

        let textHeight = fields.reduce(CGFloat.zero) { partial, field in
            partial + CGFloat(CardLayoutCalculator.infoLineCount(for: field)) * 20
        }
        let spacing = CGFloat(max(0, fields.count - 1)) * 6
        return textHeight + spacing
    }

    private var actionButtonColumn: some View {
        VStack(spacing: 5 * scale) {
            ForEach(actionButtonFields, id: \.id) { field in
                CardActionButton(kind: field.kind, scale: scale)
            }
        }
        .frame(width: 34 * scale, height: actionButtonColumnHeight * scale, alignment: .top)
        .offset(x: 336 * scale, y: actionButtonColumnTop * scale)
    }

    private var actionButtonFields: [CardFieldDraft] {
        data.visibleInfoFields
    }

    private var actionButtonColumnHeight: CGFloat {
        let count = actionButtonFields.count
        guard count > 0 else { return 0 }
        return CGFloat(count) * 34 + CGFloat(count - 1) * 5
    }

    private var actionButtonColumnTop: CGFloat {
        max(0, unscaledHeight - actionButtonColumnHeight)
    }

    private func cardText(_ value: String, size: CGFloat, weight: Font.Weight) -> some View {
        Text(value)
            .font(CardaTheme.pingFang(size: size * scale, weight: weight))
            .foregroundStyle(CardaTheme.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private func infoFont(for kind: CardFieldKind, size: CGFloat) -> Font {
        switch kind {
        case .address:
            CardaTheme.pingFang(size: size, weight: .regular)
        case .phone, .email, .link, .companyLogo:
            CardaTheme.sfPro(size: size, weight: .regular)
        }
    }
}

private struct CardActionButton: View {
    let kind: CardFieldKind
    let scale: CGFloat

    var body: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 34 * scale, height: 34 * scale)
            .shadow(color: .black.opacity(0.25), radius: 2 * scale, x: 0, y: 0)
            .overlay {
                CardFieldIconView(kind: kind, scale: scale)
                    .frame(width: 20 * scale, height: 20 * scale)
            }
    }
}

private struct CardFieldIconView: View {
    let kind: CardFieldKind
    let scale: CGFloat

    @ViewBuilder
    var body: some View {
        if let svgIcon = CardInfoSVGIcon(kind: kind) {
            LocalSVGIconView(fileName: svgIcon.fileName)
                .frame(width: 20 * scale, height: 20 * scale)
        } else if kind == .link {
            LinkIconShape()
                .stroke(CardaTheme.secondaryText, style: iconStroke)
        } else {
            CompanyLogoIconShape()
                .stroke(CardaTheme.secondaryText, style: iconStroke)
        }
    }

    private var iconStroke: StrokeStyle {
        StrokeStyle(lineWidth: 1.67 * scale, lineCap: .round, lineJoin: .round)
    }
}

private enum CardInfoSVGIcon {
    case phone
    case mapPin
    case mail

    init?(kind: CardFieldKind) {
        switch kind {
        case .phone:
            self = .phone
        case .address:
            self = .mapPin
        case .email:
            self = .mail
        case .link, .companyLogo:
            return nil
        }
    }

    var fileName: String {
        switch self {
        case .phone:
            "Phone"
        case .mapPin:
            "Map pin"
        case .mail:
            "Mail"
        }
    }
}

private struct LinkIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.42, y: rect.height * 0.35))
        path.addCurve(to: CGPoint(x: rect.width * 0.62, y: rect.height * 0.28), control1: CGPoint(x: rect.width * 0.48, y: rect.height * 0.25), control2: CGPoint(x: rect.width * 0.55, y: rect.height * 0.23))
        path.addCurve(to: CGPoint(x: rect.width * 0.80, y: rect.height * 0.48), control1: CGPoint(x: rect.width * 0.75, y: rect.height * 0.36), control2: CGPoint(x: rect.width * 0.84, y: rect.height * 0.38))
        path.addCurve(to: CGPoint(x: rect.width * 0.64, y: rect.height * 0.67), control1: CGPoint(x: rect.width * 0.75, y: rect.height * 0.58), control2: CGPoint(x: rect.width * 0.71, y: rect.height * 0.66))
        path.move(to: CGPoint(x: rect.width * 0.58, y: rect.height * 0.65))
        path.addCurve(to: CGPoint(x: rect.width * 0.38, y: rect.height * 0.72), control1: CGPoint(x: rect.width * 0.52, y: rect.height * 0.75), control2: CGPoint(x: rect.width * 0.45, y: rect.height * 0.77))
        path.addCurve(to: CGPoint(x: rect.width * 0.20, y: rect.height * 0.52), control1: CGPoint(x: rect.width * 0.25, y: rect.height * 0.64), control2: CGPoint(x: rect.width * 0.16, y: rect.height * 0.62))
        path.addCurve(to: CGPoint(x: rect.width * 0.36, y: rect.height * 0.33), control1: CGPoint(x: rect.width * 0.25, y: rect.height * 0.42), control2: CGPoint(x: rect.width * 0.29, y: rect.height * 0.34))
        path.move(to: CGPoint(x: rect.width * 0.38, y: rect.height * 0.58))
        path.addLine(to: CGPoint(x: rect.width * 0.62, y: rect.height * 0.42))
        return path
    }
}

private struct CompanyLogoIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(CGRect(x: rect.width * 0.2, y: rect.height * 0.2, width: rect.width * 0.6, height: rect.height * 0.6))
        return path
    }
}

#Preview {
    BusinessCardView(
        data: BusinessCardDraft(
            name: "林瑞鸿",
            phoneticName: "Alex Lyn",
            position: "职位",
            organizationName: "公司",
            fields: [
                CardFieldDraft(kind: .phone, value: "189-0986-9651", sortOrder: 0),
                CardFieldDraft(kind: .address, value: "大连市甘井子区凌工路2号612", sortOrder: 1),
                CardFieldDraft(kind: .email, value: "3598654461@qq.com", sortOrder: 2)
            ]
        ).renderData
    )
    .padding()
    .background(CardaTheme.pageBackground)
}
