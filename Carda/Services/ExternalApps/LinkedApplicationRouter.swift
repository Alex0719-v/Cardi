//
//  LinkedApplicationRouter.swift
//  Cardi
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum LinkedApplicationCategory: String, CaseIterable, Hashable, Identifiable {
    case browser
    case mail
    case maps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .browser:
            "浏览器"
        case .mail:
            "邮箱"
        case .maps:
            "地图"
        }
    }

    var pickerTitle: String {
        "选择\(title)"
    }

    var preferenceKey: String {
        switch self {
        case .browser:
            LinkedApplicationPreferenceKeys.browser
        case .mail:
            LinkedApplicationPreferenceKeys.mail
        case .maps:
            LinkedApplicationPreferenceKeys.maps
        }
    }

    var defaultApplicationID: LinkedApplicationID {
        switch self {
        case .browser:
            .systemBrowser
        case .mail:
            .systemMail
        case .maps:
            .appleMaps
        }
    }

    var fallbackName: String {
        defaultApplicationID.displayName
    }
}

enum LinkedApplicationPreferenceKeys {
    static let browser = "linkedApplications.browser"
    static let mail = "linkedApplications.mail"
    static let maps = "linkedApplications.maps"
}

enum LinkedApplicationID: String, CaseIterable, Hashable, Identifiable {
    case systemBrowser = "browser.system"
    case chrome = "browser.chrome"
    case quarkBrowser = "browser.quark"
    case qqBrowser = "browser.qq"
    case edge = "browser.edge"
    case ucBrowser = "browser.uc"

    case systemMail = "mail.system"
    case qqMail = "mail.qq"
    case neteaseMailMaster = "mail.neteaseMailMaster"
    case outlook = "mail.outlook"
    case gmail = "mail.gmail"

    case appleMaps = "maps.apple"
    case amap = "maps.amap"
    case baiduMaps = "maps.baidu"
    case googleMaps = "maps.google"
    case waze = "maps.waze"

    var id: String { rawValue }

    var category: LinkedApplicationCategory {
        switch self {
        case .systemBrowser, .chrome, .quarkBrowser, .qqBrowser, .edge, .ucBrowser:
            .browser
        case .systemMail, .qqMail, .neteaseMailMaster, .outlook, .gmail:
            .mail
        case .appleMaps, .amap, .baiduMaps, .googleMaps, .waze:
            .maps
        }
    }

    var displayName: String {
        switch self {
        case .systemBrowser:
            "Safari"
        case .chrome:
            "Google Chrome"
        case .quarkBrowser:
            "夸克浏览器"
        case .qqBrowser:
            "QQ浏览器"
        case .edge:
            "Microsoft Edge"
        case .ucBrowser:
            "UC浏览器"
        case .systemMail:
            "邮件"
        case .qqMail:
            "QQ 邮箱"
        case .neteaseMailMaster:
            "网易邮箱大师"
        case .outlook:
            "Outlook"
        case .gmail:
            "Gmail"
        case .appleMaps:
            "Apple 地图"
        case .amap:
            "高德地图"
        case .baiduMaps:
            "百度地图"
        case .googleMaps:
            "Google 地图"
        case .waze:
            "Waze"
        }
    }

    var systemImage: String {
        switch self {
        case .systemBrowser:
            "globe"
        case .chrome:
            "globe"
        case .quarkBrowser, .qqBrowser, .edge, .ucBrowser:
            "globe"
        case .systemMail:
            "envelope"
        case .qqMail:
            "envelope.fill"
        case .neteaseMailMaster:
            "envelope.open.fill"
        case .outlook:
            "envelope.badge.fill"
        case .gmail:
            "envelope.fill"
        case .appleMaps:
            "map.fill"
        case .amap:
            "location.fill"
        case .baiduMaps:
            "pawprint.fill"
        case .googleMaps:
            "mappin.and.ellipse"
        case .waze:
            "car.fill"
        }
    }

    var localIconFileName: String? {
        switch self {
        case .chrome:
            "Browser Chrome"
        case .quarkBrowser:
            "Browser Quark"
        case .qqBrowser:
            "Browser QQ"
        case .edge:
            "Browser Edge"
        case .ucBrowser:
            "Browser UC"
        default:
            nil
        }
    }

    var launchStrategy: LinkedApplicationLaunchStrategy {
        switch self {
        case .systemBrowser:
            .systemBrowser
        case .systemMail, .appleMaps:
            .systemDefault
        case .chrome:
            .browser(
                probeSchemes: ["googlechrome", "googlechromes"],
                directURLTemplates: [
                    .replacingWebScheme(
                        httpScheme: "googlechrome",
                        httpsScheme: "googlechromes"
                    )
                ]
            )
        case .quarkBrowser:
            .browser(
                probeSchemes: ["quark"],
                directURLTemplates: [.encodedNestedURL(scheme: "quark")],
                homeSchemes: ["quark"],
                copiesInputBeforeOpening: true
            )
        case .qqBrowser:
            .browser(
                probeSchemes: ["mqqbrowser", "mttbrowser"],
                directURLTemplates: [
                    .encodedNestedURL(scheme: "mqqbrowser"),
                    .encodedNestedURL(scheme: "mttbrowser")
                ],
                homeSchemes: ["mqqbrowser", "mttbrowser"],
                copiesInputBeforeOpening: true
            )
        case .edge:
            .browser(
                probeSchemes: ["microsoft-edge", "microsoft-edge-http", "microsoft-edge-https"],
                directURLTemplates: [
                    .replacingWebScheme(
                        httpScheme: "microsoft-edge-http",
                        httpsScheme: "microsoft-edge-https"
                    )
                ]
            )
        case .ucBrowser:
            .browser(
                probeSchemes: ["ucbrowser"],
                directURLTemplates: [.prefixedAbsoluteURL(scheme: "ucbrowser")],
                homeSchemes: ["ucbrowser"],
                copiesInputBeforeOpening: true
            )
        case .qqMail:
            .thirdParty(probeSchemes: ["qqmail"], copiesInputBeforeOpening: true)
        case .neteaseMailMaster:
            .thirdParty(probeSchemes: ["mailmaster"], copiesInputBeforeOpening: true)
        case .outlook:
            .thirdParty(probeSchemes: ["ms-outlook"], copiesInputBeforeOpening: false)
        case .gmail:
            .thirdParty(probeSchemes: ["googlegmail"], copiesInputBeforeOpening: false)
        case .amap:
            .thirdParty(probeSchemes: ["iosamap"], copiesInputBeforeOpening: false)
        case .baiduMaps:
            .thirdParty(probeSchemes: ["baidumap"], copiesInputBeforeOpening: false)
        case .googleMaps:
            .thirdParty(probeSchemes: ["comgooglemaps"], copiesInputBeforeOpening: false)
        case .waze:
            .thirdParty(probeSchemes: ["waze"], copiesInputBeforeOpening: false)
        }
    }

    var isAlwaysAvailable: Bool {
        launchStrategy.availabilityProbeURLs.isEmpty
    }

    static func applications(for category: LinkedApplicationCategory) -> [LinkedApplicationID] {
        allCases.filter { $0.category == category }
    }

    static func resolved(
        rawValue: String,
        for category: LinkedApplicationCategory
    ) -> LinkedApplicationID {
        guard
            let application = LinkedApplicationID(rawValue: rawValue),
            application.category == category
        else {
            return category.defaultApplicationID
        }
        return application
    }
}

enum LinkedApplicationBrowserURLTemplate {
    case original
    case replacingWebScheme(httpScheme: String, httpsScheme: String)
    case encodedNestedURL(scheme: String)
    case prefixedAbsoluteURL(scheme: String)

    func url(for webURL: URL) -> URL? {
        switch self {
        case .original:
            return webURL
        case let .replacingWebScheme(httpScheme, httpsScheme):
            guard
                let scheme = webURL.scheme?.lowercased(),
                scheme == "http" || scheme == "https",
                var components = URLComponents(url: webURL, resolvingAgainstBaseURL: false)
            else {
                return nil
            }
            components.scheme = scheme == "https" ? httpsScheme : httpScheme
            return components.url
        case let .encodedNestedURL(scheme):
            let allowedCharacters = CharacterSet.alphanumerics.union(
                CharacterSet(charactersIn: "-._~")
            )
            guard let encodedURL = webURL.absoluteString.addingPercentEncoding(
                withAllowedCharacters: allowedCharacters
            ) else {
                return nil
            }
            return URL(string: "\(scheme)://url=\(encodedURL)")
        case let .prefixedAbsoluteURL(scheme):
            return URL(string: "\(scheme)://\(webURL.absoluteString)")
        }
    }
}

struct LinkedApplicationLaunchStrategy {
    let availabilityProbeURLs: [URL]
    let browserDirectURLTemplates: [LinkedApplicationBrowserURLTemplate]
    let browserHomeURLs: [URL]
    let copiesInputBeforeOpening: Bool
    let fallsBackToSystemDefault: Bool

    static let systemBrowser = LinkedApplicationLaunchStrategy(
        availabilityProbeURLs: [],
        browserDirectURLTemplates: [.original],
        browserHomeURLs: [],
        copiesInputBeforeOpening: false,
        fallsBackToSystemDefault: false
    )

    static let systemDefault = LinkedApplicationLaunchStrategy(
        availabilityProbeURLs: [],
        browserDirectURLTemplates: [],
        browserHomeURLs: [],
        copiesInputBeforeOpening: false,
        fallsBackToSystemDefault: false
    )

    static func thirdParty(
        probeSchemes: [String],
        copiesInputBeforeOpening: Bool
    ) -> LinkedApplicationLaunchStrategy {
        LinkedApplicationLaunchStrategy(
            availabilityProbeURLs: probeSchemes.compactMap { URL(string: "\($0)://") },
            browserDirectURLTemplates: [],
            browserHomeURLs: [],
            copiesInputBeforeOpening: copiesInputBeforeOpening,
            fallsBackToSystemDefault: true
        )
    }

    static func browser(
        probeSchemes: [String],
        directURLTemplates: [LinkedApplicationBrowserURLTemplate],
        homeSchemes: [String] = [],
        copiesInputBeforeOpening: Bool = false
    ) -> LinkedApplicationLaunchStrategy {
        LinkedApplicationLaunchStrategy(
            availabilityProbeURLs: probeSchemes.compactMap { URL(string: "\($0)://") },
            browserDirectURLTemplates: directURLTemplates,
            browserHomeURLs: homeSchemes.compactMap { URL(string: "\($0)://") },
            copiesInputBeforeOpening: copiesInputBeforeOpening,
            fallsBackToSystemDefault: true
        )
    }

    func browserURLs(for webURL: URL) -> [URL] {
        browserDirectURLTemplates.compactMap { $0.url(for: webURL) } + browserHomeURLs
    }
}

enum LinkedApplicationAvailability {
    @MainActor
    static func isAvailable(_ application: LinkedApplicationID) -> Bool {
        guard !application.isAlwaysAvailable else { return true }

        #if DEBUG
        if ProcessInfo.processInfo.environment["CARDA_SIMULATE_LINKED_APPS"] == "1" {
            return true
        }
        #endif

        #if canImport(UIKit)
        return application.launchStrategy.availabilityProbeURLs.contains {
            UIApplication.shared.canOpenURL($0)
        }
        #else
        return false
        #endif
    }

    @MainActor
    static func availableApplications(
        for category: LinkedApplicationCategory
    ) -> [LinkedApplicationID] {
        LinkedApplicationID.applications(for: category).filter(isAvailable)
    }
}

struct LinkedApplicationOpenOutcome {
    let didOpen: Bool
    let message: String?
}

private struct LinkedApplicationOpenRequest {
    let selectedApplication: LinkedApplicationID
    let selectedApplicationURLs: [URL]
    let systemFallbackURL: URL?
    let copiesInputBeforeOpening: Bool
    let copiedValue: String?
    let copyMessage: String?
}

enum LinkedApplicationRouter {
    @MainActor
    static func open(
        kind: CardFieldKind,
        value: String,
        selectedBrowserRawValue: String,
        selectedMailRawValue: String,
        selectedMapsRawValue: String
    ) async -> LinkedApplicationOpenOutcome {
        guard let request = openRequest(
            kind: kind,
            value: value,
            selectedBrowserRawValue: selectedBrowserRawValue,
            selectedMailRawValue: selectedMailRawValue,
            selectedMapsRawValue: selectedMapsRawValue
        ) else {
            return LinkedApplicationOpenOutcome(didOpen: false, message: "内容无效")
        }

        let applicationIsAvailable = LinkedApplicationAvailability.isAvailable(
            request.selectedApplication
        )
        #if canImport(UIKit)
        if applicationIsAvailable,
           request.copiesInputBeforeOpening,
           let copiedValue = request.copiedValue {
            UIPasteboard.general.string = copiedValue
        }
        #endif

        if applicationIsAvailable {
            for url in request.selectedApplicationURLs {
                if await openURL(url) {
                    return LinkedApplicationOpenOutcome(
                        didOpen: true,
                        message: request.copyMessage
                    )
                }
            }
        }

        if let fallbackURL = request.systemFallbackURL,
           await openURL(fallbackURL) {
            let reason = applicationIsAvailable ? "无法打开" : "不可用"
            return LinkedApplicationOpenOutcome(
                didOpen: true,
                message: "\(request.selectedApplication.displayName)\(reason)，已使用\(request.selectedApplication.category.fallbackName)"
            )
        }

        return LinkedApplicationOpenOutcome(
            didOpen: false,
            message: failureMessage(for: kind)
        )
    }

    private static func openRequest(
        kind: CardFieldKind,
        value: String,
        selectedBrowserRawValue: String,
        selectedMailRawValue: String,
        selectedMapsRawValue: String
    ) -> LinkedApplicationOpenRequest? {
        switch kind {
        case .link:
            guard let systemURL = normalizedWebURL(from: value) else { return nil }
            let application = LinkedApplicationID.resolved(
                rawValue: selectedBrowserRawValue,
                for: .browser
            )
            let applicationURLs = browserCandidateURLs(for: application, webURL: systemURL)
            return LinkedApplicationOpenRequest(
                selectedApplication: application,
                selectedApplicationURLs: applicationURLs,
                systemFallbackURL: application.launchStrategy.fallsBackToSystemDefault
                    ? systemURL
                    : nil,
                copiesInputBeforeOpening: application.launchStrategy.copiesInputBeforeOpening,
                copiedValue: application.launchStrategy.copiesInputBeforeOpening
                    ? systemURL.absoluteString
                    : nil,
                copyMessage: application.launchStrategy.copiesInputBeforeOpening
                    ? "网址已复制；若未直接打开，请在\(application.displayName)中粘贴"
                    : nil
            )

        case .email:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let fallbackURL = mailtoURL(recipient: trimmed) else { return nil }
            let application = LinkedApplicationID.resolved(
                rawValue: selectedMailRawValue,
                for: .mail
            )
            let primaryURL = mailURL(for: application, recipient: trimmed) ?? fallbackURL
            return LinkedApplicationOpenRequest(
                selectedApplication: application,
                selectedApplicationURLs: [primaryURL],
                systemFallbackURL: application.launchStrategy.fallsBackToSystemDefault
                    ? fallbackURL
                    : nil,
                copiesInputBeforeOpening: application.launchStrategy.copiesInputBeforeOpening,
                copiedValue: trimmed,
                copyMessage: application.launchStrategy.copiesInputBeforeOpening
                    ? "已复制邮箱地址，请在\(application.displayName)中粘贴"
                    : nil
            )

        case .address:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let fallbackURL = appleMapsURL(query: trimmed) else { return nil }
            let application = LinkedApplicationID.resolved(
                rawValue: selectedMapsRawValue,
                for: .maps
            )
            let primaryURL = mapsURL(for: application, query: trimmed) ?? fallbackURL
            return LinkedApplicationOpenRequest(
                selectedApplication: application,
                selectedApplicationURLs: [primaryURL],
                systemFallbackURL: application.launchStrategy.fallsBackToSystemDefault
                    ? fallbackURL
                    : nil,
                copiesInputBeforeOpening: false,
                copiedValue: nil,
                copyMessage: nil
            )

        case .phone, .companyLogo:
            return nil
        }
    }

    static func browserCandidateURLs(
        for application: LinkedApplicationID,
        webURL: URL
    ) -> [URL] {
        application.launchStrategy.browserURLs(for: webURL)
    }

    private static func mailURL(
        for application: LinkedApplicationID,
        recipient: String
    ) -> URL? {
        switch application {
        case .systemMail:
            return mailtoURL(recipient: recipient)
        case .qqMail:
            return URL(string: "qqmail://")
        case .neteaseMailMaster:
            return URL(string: "mailmaster://")
        case .outlook:
            return customURL(
                scheme: "ms-outlook",
                host: "compose",
                queryItems: [URLQueryItem(name: "to", value: recipient)]
            )
        case .gmail:
            return customURL(
                scheme: "googlegmail",
                host: "",
                path: "/co",
                queryItems: [URLQueryItem(name: "to", value: recipient)]
            )
        default:
            return nil
        }
    }

    private static func mapsURL(
        for application: LinkedApplicationID,
        query: String
    ) -> URL? {
        switch application {
        case .appleMaps:
            return appleMapsURL(query: query)
        case .amap:
            return customURL(
                scheme: "iosamap",
                host: "path",
                queryItems: [
                    URLQueryItem(name: "sourceApplication", value: "Cardi"),
                    URLQueryItem(name: "dname", value: query),
                    URLQueryItem(name: "dev", value: "0"),
                    URLQueryItem(name: "t", value: "0")
                ]
            )
        case .baiduMaps:
            return customURL(
                scheme: "baidumap",
                host: "map",
                path: "/geocoder",
                queryItems: [
                    URLQueryItem(name: "address", value: query),
                    URLQueryItem(name: "src", value: "ios.Alex.Carda")
                ]
            )
        case .googleMaps:
            return customURL(
                scheme: "comgooglemaps",
                host: "",
                queryItems: [URLQueryItem(name: "q", value: query)]
            )
        case .waze:
            return customURL(
                scheme: "https",
                host: "waze.com",
                path: "/ul",
                queryItems: [
                    URLQueryItem(name: "q", value: query),
                    URLQueryItem(name: "utm_source", value: "Cardi")
                ]
            )
        default:
            return nil
        }
    }

    private static func normalizedWebURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(trimmed)")
    }

    private static func mailtoURL(recipient: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        return components.url
    }

    private static func appleMapsURL(query: String) -> URL? {
        customURL(
            scheme: "https",
            host: "maps.apple.com",
            path: "/",
            queryItems: [URLQueryItem(name: "q", value: query)]
        )
    }

    private static func customURL(
        scheme: String,
        host: String,
        path: String = "",
        queryItems: [URLQueryItem]
    ) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path
        components.queryItems = queryItems
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    @MainActor
    private static func openURL(_ url: URL) async -> Bool {
        #if canImport(UIKit)
        return await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { success in
                continuation.resume(returning: success)
            }
        }
        #else
        return false
        #endif
    }

    private static func failureMessage(for kind: CardFieldKind) -> String {
        switch kind {
        case .email:
            "无法打开邮件应用"
        case .address:
            "无法打开地图应用"
        case .link:
            "无法打开浏览器"
        case .phone:
            "无法拨打电话"
        case .companyLogo:
            "无法打开"
        }
    }
}
