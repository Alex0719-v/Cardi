//
//  BusinessCardView.swift
//  Carda
//

import SwiftUI
import WebKit
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
            partial + max(0, estimatedLineCount(for: field.value) - 1)
        }
        return CardaTheme.baseCardHeight
            + CGFloat(extraFields) * 24
            + CGFloat(wrappedLines) * 20
    }

    static func estimatedLineCount(for text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 1 }
        let maxCharactersPerLine = 18
        return max(1, Int(ceil(Double(trimmed.count) / Double(maxCharactersPerLine))))
    }
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
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 24 * scale, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 2 * scale, x: 0, y: 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(data.displayName)
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24 * scale, style: .continuous)
                .fill(Color.white)

            CardPhotoBackground(width: width, height: height)
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
                .offset(x: 291 * scale, y: 19 * scale)
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
        .offset(x: 23 * scale, y: (((unscaledHeight - 68) / 2) - 16) * scale)
    }

    private var infoGroup: some View {
        let fields = data.visibleInfoFields
        return VStack(alignment: .leading, spacing: 5 * scale) {
            ForEach(fields) { field in
                HStack(alignment: .top, spacing: 0) {
                    Text(field.value)
                        .font(infoFont(for: field.kind, size: 14 * scale))
                        .foregroundStyle(CardaTheme.secondaryText)
                        .lineLimit(nil)
                        .frame(width: 185 * scale, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    CardFieldIconView(kind: field.kind, scale: scale)
                        .frame(width: 20 * scale, height: 20 * scale)
                        .padding(.top, 0)
                }
                .frame(width: 223 * scale, alignment: .top)
                .frame(minHeight: 20 * scale, alignment: .top)
            }
        }
        .frame(width: 223 * scale, alignment: .leading)
        .offset(x: 127 * scale, y: (unscaledHeight - 20 - CGFloat(max(data.visibleInfoFields.count, 1)) * 25 + 6) * scale)
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

private struct CardFieldIconView: View {
    let kind: CardFieldKind
    let scale: CGFloat

    @ViewBuilder
    var body: some View {
        if let svgIcon = CardInfoSVGIcon(kind: kind) {
            LocalCardSVGView(icon: svgIcon)
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

    var resourceURL: URL? {
        Bundle.main.url(forResource: fileName, withExtension: "svg", subdirectory: "My icon")
            ?? Bundle.main.url(forResource: fileName, withExtension: "svg")
    }
}

private struct LocalCardSVGView: UIViewRepresentable {
    let icon: CardInfoSVGIcon

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isUserInteractionEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedFileName != icon.fileName else { return }
        context.coordinator.loadedFileName = icon.fileName

        guard let url = icon.resourceURL else {
            webView.loadHTMLString("", baseURL: nil)
            return
        }

        let html = """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
        html, body {
          width: 100%;
          height: 100%;
          margin: 0;
          padding: 0;
          overflow: hidden;
          background: transparent;
        }
        body {
          display: flex;
          align-items: center;
          justify-content: center;
        }
        img {
          display: block;
          width: 100%;
          height: 100%;
          object-fit: contain;
        }
        </style>
        </head>
        <body>
        <img src="\(url.absoluteString)" alt="">
        </body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
    }

    final class Coordinator {
        var loadedFileName: String?
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
