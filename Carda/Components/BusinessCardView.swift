//
//  BusinessCardView.swift
//  Cardi
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
        let wrappedLines = visible.enumerated().reduce(0) { partial, entry in
            let isLastField = entry.offset == visible.count - 1
            return partial + (
                isLastField
                    ? 0
                    : extraInfoLineCount(for: entry.element)
            )
        }
        return CardaTheme.baseCardHeight
            + CGFloat(extraFields) * 24
            + CGFloat(wrappedLines) * 20
    }

    static func extraInfoLineCount(for field: CardFieldDraft) -> Int {
        max(0, infoLineCount(for: field) - 1)
    }

    static func infoLineCount(for field: CardFieldDraft) -> Int {
        let trimmed = field.displayValue.trimmingCharacters(in: .whitespacesAndNewlines)
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

enum CardExpansionMotion {
    static let shapeDuration: TimeInterval = 0.36
    static let detailsDuration: TimeInterval = 0.18

    static var shapeAnimation: Animation {
        .timingCurve(0.4, 0, 0.2, 1, duration: shapeDuration)
    }

    static func detailsAnimation(isExpanded: Bool) -> Animation {
        .easeOut(duration: isExpanded ? detailsDuration : 0.1)
            .delay(isExpanded ? shapeDuration : 0)
    }
}

struct BusinessCardView: View {
    enum LayerMode: Equatable {
        case complete
        case surface
        case foreground
    }

    enum RenderingMode: Equatable {
        case standard
        case exportedImage
    }

    let data: CardRenderData
    var width: CGFloat = CardaTheme.cardWidth
    var onInfoAction: ((CardFieldDraft) -> Void)?
    var isExpanded = true
    var layerMode: LayerMode = .complete
    var renderingMode: RenderingMode = .standard

    private var scale: CGFloat {
        width / CardaTheme.cardWidth
    }

    private var height: CGFloat {
        (isExpanded ? unscaledHeight : 60) * scale
    }

    private var unscaledHeight: CGFloat {
        CardLayoutCalculator.height(for: data)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if layerMode != .foreground {
                cardBackground
                if renderingMode == .standard {
                    actionButtonBackgroundColumn
                        .opacity(isExpanded ? 1 : 0)
                        .animation(
                            CardExpansionMotion.detailsAnimation(isExpanded: isExpanded),
                            value: isExpanded
                        )
                }
            }

            if layerMode != .surface {
                morphingOrganizationName
                morphingName
                morphingAvatar

                ZStack(alignment: .topLeading) {
                    companyLogo
                    positionText
                    phoneticNameText
                    infoGroup
                    actionButtonColumn
                }
                .opacity(isExpanded ? 1 : 0)
                .allowsHitTesting(isExpanded)
                .animation(
                    CardExpansionMotion.detailsAnimation(isExpanded: isExpanded),
                    value: isExpanded
                )
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .mask {
            cardContentMask
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(data.displayName)
    }

    private var cardBackground: some View {
        let shape = cardBodyShape
        let expandedHeight = unscaledHeight * scale

        return shape
            .fill(Color.white, style: FillStyle(eoFill: true))
            .overlay(alignment: .topLeading) {
                CardPhotoBackground(
                    template: data.backgroundTemplate,
                    width: width,
                    height: expandedHeight
                )
                    .frame(width: width, height: height, alignment: .top)
                    .clipped()
                    .mask {
                        shape.fill(style: FillStyle(eoFill: true))
                    }
                    .opacity(isExpanded ? 1 : 0)
            }
    }

    private var cardBodyShape: BusinessCardBodyShape {
        let isExportedImage = renderingMode == .exportedImage
        return BusinessCardBodyShape(
            cutoutTop: (isExportedImage ? unscaledHeight : cardBodyCutoutTop) * scale,
            cutoutWidth: (isExportedImage ? 0 : cardBodyCutoutWidth) * scale,
            collapsedCornerRadius: (isExportedImage ? 0 : 30) * scale,
            expandedCornerRadius: (isExportedImage ? 0 : cardBodyCornerRadius) * scale,
            expansionProgress: isExpanded ? 1 : 0,
            usesCompactSingleButtonCutout: actionButtonFields.count == 1
        )
    }

    private var cardContentMask: some View {
        ZStack(alignment: .topLeading) {
            cardBodyShape
                .fill(Color.white, style: FillStyle(eoFill: true))

            if isExpanded, renderingMode == .standard {
                VStack(spacing: 5 * scale) {
                    ForEach(actionButtonFields, id: \.id) { _ in
                        Circle()
                            .fill(Color.white)
                            .frame(width: 34 * scale, height: 34 * scale)
                    }
                }
                .frame(
                    width: 34 * scale,
                    height: actionButtonColumnHeight * scale,
                    alignment: .top
                )
                .offset(
                    x: 336 * scale,
                    y: actionButtonColumnTop * scale
                )
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
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
        let collapsedCornerRadius: CGFloat
        let expandedCornerRadius: CGFloat
        var expansionProgress: CGFloat
        let usesCompactSingleButtonCutout: Bool

        var animatableData: CGFloat {
            get { expansionProgress }
            set { expansionProgress = newValue }
        }

        func path(in rect: CGRect) -> Path {
            let progress = min(max(expansionProgress, 0), 1)
            let cornerRadius = collapsedCornerRadius
                + (expandedCornerRadius - collapsedCornerRadius) * progress
            let animatedCutoutWidth = cutoutWidth * progress
            let animatedCutoutTop = rect.height
                + (cutoutTop - rect.height) * progress

            guard
                animatedCutoutWidth > 0.01,
                animatedCutoutTop < rect.height - 0.01
            else {
                return Path(
                    roundedRect: rect,
                    cornerRadius: cornerRadius,
                    style: .circular
                )
            }

            let outerRadius = min(
                cornerRadius,
                rect.width / 2,
                rect.height / 2
            )
            let preferredSlotRadius = min(cornerRadius, animatedCutoutWidth / 2)
            let minCutoutHeight = preferredSlotRadius + outerRadius
            let requestedCutoutY = min(max(0, animatedCutoutTop), rect.height)
            let cutoutY = usesCompactSingleButtonCutout
                ? requestedCutoutY
                : min(requestedCutoutY, max(0, rect.height - minCutoutHeight))
            let cutoutHeight = rect.height - cutoutY
            let cutoutX = rect.maxX - animatedCutoutWidth
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
            path.addCircularCorner(
                via: CGPoint(x: rect.maxX, y: rect.minY),
                to: CGPoint(x: rect.maxX, y: rect.minY + outerRadius),
                radius: outerRadius
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: cutoutY - slotRadius))
            path.addCircularCorner(
                via: CGPoint(x: rect.maxX, y: cutoutY),
                to: CGPoint(x: rect.maxX - slotRadius, y: cutoutY),
                radius: slotRadius
            )
            path.addLine(to: CGPoint(x: cutoutX + slotRadius, y: cutoutY))
            path.addCircularCorner(
                via: CGPoint(x: cutoutX, y: cutoutY),
                to: CGPoint(x: cutoutX, y: cutoutY + slotRadius),
                radius: slotRadius
            )
            path.addLine(to: CGPoint(x: cutoutX, y: rect.maxY - bottomSlotRadius))
            path.addCircularCorner(
                via: CGPoint(x: cutoutX, y: rect.maxY),
                to: CGPoint(x: cutoutX - bottomSlotRadius, y: rect.maxY),
                radius: bottomSlotRadius
            )
            path.addLine(to: CGPoint(x: rect.minX + outerRadius, y: rect.maxY))
            path.addCircularCorner(
                via: CGPoint(x: rect.minX, y: rect.maxY),
                to: CGPoint(x: rect.minX, y: rect.maxY - outerRadius),
                radius: outerRadius
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + outerRadius))
            path.addCircularCorner(
                via: CGPoint(x: rect.minX, y: rect.minY),
                to: CGPoint(x: rect.minX + outerRadius, y: rect.minY),
                radius: outerRadius
            )
            path.closeSubpath()

            return path
        }
    }

    private struct CardPhotoBackground: View {
        let template: CardBackgroundTemplate
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
            if let image = Self.uiImages[template] ?? Self.uiImages[.color1] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.clear
            }
            #elseif canImport(AppKit)
            if let image = Self.nsImages[template] ?? Self.nsImages[.color1] {
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

        private static func resourceURL(for template: CardBackgroundTemplate) -> URL? {
            Bundle.main.url(
                forResource: template.resourceName,
                withExtension: "png",
                subdirectory: "Card photo"
            ) ?? Bundle.main.url(
                forResource: template.resourceName,
                withExtension: "png"
            )
        }

        #if canImport(UIKit)
        private static let uiImages: [CardBackgroundTemplate: UIImage] =
            Dictionary(uniqueKeysWithValues: CardBackgroundTemplate.allCases.compactMap { template in
                guard let resourceURL = resourceURL(for: template),
                      let image = UIImage(contentsOfFile: resourceURL.path) else {
                    return nil
                }
                return (template, image)
            })
        #elseif canImport(AppKit)
        private static let nsImages: [CardBackgroundTemplate: NSImage] =
            Dictionary(uniqueKeysWithValues: CardBackgroundTemplate.allCases.compactMap { template in
                guard let resourceURL = resourceURL(for: template),
                      let image = NSImage(contentsOf: resourceURL) else {
                    return nil
                }
                return (template, image)
            })
        #endif
    }

    private var morphingOrganizationName: some View {
        let expandedX: CGFloat = data.companyLogoImageData == nil ? 23 : 56
        let expandedScale: CGFloat = 14 / 15

        return Text(data.displayOrganizationName)
            .font(CardaTheme.pingFang(size: 15 * scale, weight: .regular))
            .foregroundStyle(Color.black.opacity(isExpanded ? 0.75 : 0.5))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(width: 220 * scale, height: 20 * scale, alignment: .leading)
            .scaleEffect(isExpanded ? expandedScale : 1, anchor: .topLeading)
            .frame(
                width: (isExpanded ? 220 * expandedScale : 220) * scale,
                height: 20 * scale,
                alignment: .topLeading
            )
            .offset(
                x: (isExpanded ? expandedX : 25) * scale,
                y: (isExpanded ? 38 : 6.5) * scale
            )
    }

    @ViewBuilder
    private var companyLogo: some View {
        if data.companyLogoImageData != nil {
            DataImageView(data: data.companyLogoImageData)
                .frame(width: 28 * scale, height: 28 * scale)
                .clipShape(RoundedRectangle(cornerRadius: 2 * scale))
                .offset(x: 23 * scale, y: 34 * scale)
        }
    }

    @ViewBuilder
    private var morphingAvatar: some View {
        if data.avatarImageData != nil {
            DataImageView(data: data.avatarImageData)
                .frame(width: 60 * scale, height: 60 * scale)
                .clipShape(Circle())
                .scaleEffect(isExpanded ? 1 : 44 / 60.0, anchor: .topLeading)
                .offset(
                    x: (isExpanded ? 291 : 318) * scale,
                    y: (isExpanded ? 23 : 8) * scale
                )
        }
    }

    private var morphingName: some View {
        let expandedScale: CGFloat = 33 / 17
        let expandedTracking = 4.8 / expandedScale
        let collapsedWidth: CGFloat = 220
        let expandedWidth: CGFloat = 132

        return Text(data.displayName)
            .font(collapsedNameFont)
            .tracking((isExpanded ? expandedTracking : 0) * scale)
            .foregroundStyle(Color.black)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(
                width: (
                    isExpanded
                        ? expandedWidth / expandedScale
                        : collapsedWidth
                ) * scale,
                height: (
                    isExpanded
                        ? 35 / expandedScale
                        : 22
                ) * scale,
                alignment: .leading
            )
            .scaleEffect(isExpanded ? expandedScale : 1, anchor: .topLeading)
            .frame(
                width: (isExpanded ? expandedWidth : collapsedWidth) * scale,
                height: (isExpanded ? 35 : 22) * scale,
                alignment: .topLeading
            )
            .offset(
                x: (isExpanded ? 23 : 25) * scale,
                y: (
                    isExpanded
                        ? identityGroupTop + 18.5 + expandedIdentityVerticalOffset
                        : 30.5
                ) * scale
            )
    }

    private var positionText: some View {
        cardText(data.displayPosition, size: 14, weight: .regular)
            .frame(width: 132 * scale, height: 20 * scale, alignment: .leading)
            .offset(
                x: 23 * scale,
                y: (identityGroupTop + expandedIdentityVerticalOffset) * scale
            )
    }

    private var phoneticNameText: some View {
        Text(data.displayPhoneticName)
            .font(CardaTheme.sfPro(size: 14 * scale, weight: .regular))
            .foregroundStyle(CardaTheme.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(width: 132 * scale, height: 20 * scale, alignment: .leading)
            .offset(
                x: 23 * scale,
                y: (
                    identityGroupTop
                        + 49
                        + expandedIdentityVerticalOffset
                ) * scale
            )
    }

    private var expandedIdentityVerticalOffset: CGFloat {
        18
    }

    private var collapsedNameFont: Font {
        data.displayName.unicodeScalars.allSatisfy { $0.isASCII }
            ? CardaTheme.sfPro(size: 17 * scale, weight: .semibold)
            : CardaTheme.pingFang(size: 17 * scale, weight: .semibold)
    }

    private var identityGroupTop: CGFloat {
        ((unscaledHeight - 68) / 2) - 16
    }

    @ViewBuilder
    private var infoGroup: some View {
        let fields = data.visibleInfoFields
        if !fields.isEmpty {
            VStack(alignment: .trailing, spacing: 6 * scale) {
                ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
                    let isLastField = index == fields.count - 1
                    let lineCount = infoLineCount(
                        for: field,
                        at: index,
                        fieldCount: fields.count
                    )
                    Text(field.displayValue)
                        .font(infoFont(for: field.kind, size: 14 * scale))
                        .foregroundStyle(CardaTheme.secondaryText)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(isLastField ? 1 : nil)
                        .truncationMode(.tail)
                        .frame(
                            width: 185 * scale,
                            height: CGFloat(lineCount) * 20 * scale,
                            alignment: .trailing
                        )
                }
            }
            .frame(width: 185 * scale, alignment: .trailing)
            .offset(
                x: (renderingMode == .exportedImage ? 137 : 122) * scale,
                y: infoGroupTop * scale
            )
        }
    }

    private var infoGroupTop: CGFloat {
        max(0, unscaledHeight - 20 - infoGroupDepth)
    }

    private var infoGroupDepth: CGFloat {
        let fields = data.visibleInfoFields
        guard !fields.isEmpty else { return 0 }

        let textHeight = fields.enumerated().reduce(CGFloat.zero) { partial, entry in
            let lineCount = infoLineCount(
                for: entry.element,
                at: entry.offset,
                fieldCount: fields.count
            )
            return partial + CGFloat(lineCount) * 20
        }
        let spacing = CGFloat(max(0, fields.count - 1)) * 6
        return textHeight + spacing
    }

    @ViewBuilder
    private var actionButtonColumn: some View {
        if renderingMode == .exportedImage {
            exportedInfoIconColumn
        } else {
            standardActionButtonColumn
        }
    }

    private var standardActionButtonColumn: some View {
        VStack(spacing: 5 * scale) {
            ForEach(actionButtonFields, id: \.id) { field in
                CardActionButton(
                    field: field,
                    scale: scale,
                    action: onInfoAction
                )
            }
        }
        .frame(width: 34 * scale, height: actionButtonColumnHeight * scale, alignment: .top)
        .offset(x: 336 * scale, y: actionButtonColumnTop * scale)
    }

    private var exportedInfoIconColumn: some View {
        let fields = actionButtonFields

        return ZStack(alignment: .topLeading) {
            ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
                CardFieldIconView(kind: field.kind, scale: scale * 0.75)
                    .frame(width: 15 * scale, height: 15 * scale)
                    .frame(width: 34 * scale, height: 20 * scale)
                    .offset(
                        x: -10 * scale,
                        y: infoRowTop(for: index, in: fields) * scale
                    )
            }
        }
        .frame(
            width: 34 * scale,
            height: infoGroupDepth * scale,
            alignment: .topLeading
        )
        .offset(x: 336 * scale, y: infoGroupTop * scale)
    }

    private func infoLineCount(
        for field: CardFieldDraft,
        at index: Int,
        fieldCount: Int
    ) -> Int {
        index == fieldCount - 1
            ? 1
            : CardLayoutCalculator.infoLineCount(for: field)
    }

    private func infoRowTop(for index: Int, in fields: [CardFieldDraft]) -> CGFloat {
        guard index > 0 else { return 0 }

        let precedingRowsHeight = fields.prefix(index).enumerated().reduce(CGFloat.zero) { partial, entry in
            let lineCount = infoLineCount(
                for: entry.element,
                at: entry.offset,
                fieldCount: fields.count
            )
            return partial + CGFloat(lineCount) * 20
        }
        return precedingRowsHeight + CGFloat(index) * 6
    }

    private var actionButtonBackgroundColumn: some View {
        VStack(spacing: 5 * scale) {
            ForEach(Array(actionButtonFields.enumerated()), id: \.element.id) { index, _ in
                actionButtonBackground(row: index)
            }
        }
        .frame(width: 34 * scale, height: actionButtonColumnHeight * scale, alignment: .top)
        .offset(x: 336 * scale, y: actionButtonColumnTop * scale)
    }

    private func actionButtonBackground(row: Int) -> some View {
        let diameter = 34 * scale
        let imageOriginX = 336 * scale
        let imageOriginY = (actionButtonColumnTop + CGFloat(row) * 39) * scale

        return ZStack(alignment: .topLeading) {
            Color.white
            CardPhotoBackground(
                template: data.backgroundTemplate,
                width: width,
                height: unscaledHeight * scale
            )
            .offset(x: -imageOriginX, y: -imageOriginY)
        }
        .frame(width: diameter, height: diameter, alignment: .topLeading)
        .clipped()
        .clipShape(Circle())
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

private extension Path {
    mutating func addCircularCorner(via corner: CGPoint, to end: CGPoint, radius: CGFloat) {
        guard radius > 0 else {
            addLine(to: corner)
            addLine(to: end)
            return
        }

        addArc(tangent1End: corner, tangent2End: end, radius: radius)
    }
}

private struct CardActionButton: View {
    let field: CardFieldDraft
    let scale: CGFloat
    let action: ((CardFieldDraft) -> Void)?

    var body: some View {
        if let action {
            Button {
                action(field)
            } label: {
                buttonContent
            }
            .buttonStyle(.plain)
            .accessibilityLabel(actionAccessibilityLabel)
        } else {
            buttonContent
                .allowsHitTesting(false)
        }
    }

    private var buttonContent: some View {
        Circle()
            .fill(Color.clear)
            .frame(width: 34 * scale, height: 34 * scale)
            .contentShape(Circle())
            .overlay {
                CardFieldIconView(kind: field.kind, scale: scale)
                    .frame(width: 20 * scale, height: 20 * scale)
            }
    }

    private var actionAccessibilityLabel: String {
        switch field.kind {
        case .phone:
            "电话"
        case .email:
            "邮箱"
        case .address:
            "地址"
        case .link:
            "链接"
        case .companyLogo:
            "公司LOGO"
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
    case link

    init?(kind: CardFieldKind) {
        switch kind {
        case .phone:
            self = .phone
        case .address:
            self = .mapPin
        case .email:
            self = .mail
        case .link:
            self = .link
        case .companyLogo:
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
        case .link:
            "Link"
        }
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
