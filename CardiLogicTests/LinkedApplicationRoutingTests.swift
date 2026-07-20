import Foundation

@main
private enum LinkedApplicationRoutingTests {
    static func main() {
        keepsTheRequestedBrowserOrder()
        keepsBrowserLaunchMetadataCentralized()
        buildsChromeAndEdgeURLsForHTTPAndHTTPS()
        buildsEveryBrowserCandidateForComplexHTTPAndHTTPSURLs()
        encodesNestedURLsForQuarkAndQQBrowser()
        keepsAHomeFallbackForBrowsersWithoutStablePublicDeepLinks()
        rejectsUnsupportedSchemesForSchemeReplacementBrowsers()
        fallsBackFromInvalidOrCrossCategoryStoredValues()
        print("LinkedApplicationRoutingTests: PASS")
    }

    private static func keepsTheRequestedBrowserOrder() {
        precondition(
            LinkedApplicationID.applications(for: .browser) == [
                .systemBrowser,
                .chrome,
                .quarkBrowser,
                .qqBrowser,
                .edge,
                .ucBrowser
            ]
        )
    }

    private static func keepsBrowserLaunchMetadataCentralized() {
        precondition(
            LinkedApplicationID.quarkBrowser.launchStrategy.browserHomeURLs
                .map(\.absoluteString) == ["quark://"]
        )
        precondition(
            LinkedApplicationID.qqBrowser.launchStrategy.browserHomeURLs
                .map(\.absoluteString) == ["mqqbrowser://", "mttbrowser://"]
        )
        precondition(
            LinkedApplicationID.ucBrowser.launchStrategy.browserHomeURLs
                .map(\.absoluteString) == ["ucbrowser://"]
        )
        precondition(
            LinkedApplicationID.applications(for: .browser)
                .filter { $0 != .systemBrowser }
                .allSatisfy { $0.launchStrategy.fallsBackToSystemDefault }
        )
    }

    private static func buildsChromeAndEdgeURLsForHTTPAndHTTPS() {
        let httpURL = requiredURL("http://example.com/path?q=carda")
        let httpsURL = requiredURL("https://example.com/path?q=carda")

        precondition(
            firstCandidate(for: .chrome, url: httpURL).scheme == "googlechrome"
        )
        precondition(
            firstCandidate(for: .chrome, url: httpsURL).scheme == "googlechromes"
        )
        precondition(
            firstCandidate(for: .edge, url: httpURL).scheme == "microsoft-edge-http"
        )
        precondition(
            firstCandidate(for: .edge, url: httpsURL).scheme == "microsoft-edge-https"
        )
    }

    private static func buildsEveryBrowserCandidateForComplexHTTPAndHTTPSURLs() {
        let urls = [
            requiredURL("http://example.com/搜索?q=名片&next=%2Fa%2Bb%3Fc%3Dd"),
            requiredURL("https://example.com/搜索?q=名片&token=a%2Bb%3Dc#结果")
        ]

        for application in LinkedApplicationID.applications(for: .browser) {
            for url in urls {
                let candidates = LinkedApplicationRouter.browserCandidateURLs(
                    for: application,
                    webURL: url
                )
                precondition(
                    !candidates.isEmpty,
                    "Missing complex URL candidate for \(application.displayName): \(url)"
                )
            }
        }
    }

    private static func encodesNestedURLsForQuarkAndQQBrowser() {
        let url = requiredURL("https://example.com/搜索?q=名片&next=/a+b")
        let quarkURL = firstCandidate(for: .quarkBrowser, url: url).absoluteString
        let qqURL = firstCandidate(for: .qqBrowser, url: url).absoluteString

        precondition(quarkURL.hasPrefix("quark://url=https%3A%2F%2F"))
        precondition(qqURL.hasPrefix("mqqbrowser://url=https%3A%2F%2F"))
        precondition(quarkURL.contains("%26next%3D"))
        precondition(qqURL.contains("%26next%3D"))
    }

    private static func keepsAHomeFallbackForBrowsersWithoutStablePublicDeepLinks() {
        let url = requiredURL("https://example.com")

        let quarkURLs = LinkedApplicationRouter.browserCandidateURLs(
            for: .quarkBrowser,
            webURL: url
        )
        let qqURLs = LinkedApplicationRouter.browserCandidateURLs(
            for: .qqBrowser,
            webURL: url
        )
        let ucURLs = LinkedApplicationRouter.browserCandidateURLs(
            for: .ucBrowser,
            webURL: url
        )

        precondition(quarkURLs.last?.absoluteString == "quark://")
        precondition(qqURLs.suffix(2).map(\.absoluteString) == ["mqqbrowser://", "mttbrowser://"])
        precondition(ucURLs.last?.absoluteString == "ucbrowser://")
        precondition(
            [
                LinkedApplicationID.quarkBrowser,
                .qqBrowser,
                .ucBrowser
            ].allSatisfy {
                $0.launchStrategy.copiesInputBeforeOpening
            }
        )
    }

    private static func rejectsUnsupportedSchemesForSchemeReplacementBrowsers() {
        let ftpURL = requiredURL("ftp://example.com/file")
        precondition(
            LinkedApplicationRouter.browserCandidateURLs(for: .chrome, webURL: ftpURL).isEmpty
        )
        precondition(
            LinkedApplicationRouter.browserCandidateURLs(for: .edge, webURL: ftpURL).isEmpty
        )
    }

    private static func fallsBackFromInvalidOrCrossCategoryStoredValues() {
        precondition(
            LinkedApplicationID.resolved(rawValue: "browser.removed", for: .browser)
                == .systemBrowser
        )
        precondition(
            LinkedApplicationID.resolved(rawValue: LinkedApplicationID.gmail.rawValue, for: .browser)
                == .systemBrowser
        )
        precondition(
            LinkedApplicationID.resolved(rawValue: "mail.removed", for: .mail)
                == .systemMail
        )
        precondition(
            LinkedApplicationID.resolved(rawValue: "maps.removed", for: .maps)
                == .appleMaps
        )
    }

    private static func firstCandidate(
        for application: LinkedApplicationID,
        url: URL
    ) -> URL {
        guard let candidate = LinkedApplicationRouter.browserCandidateURLs(
            for: application,
            webURL: url
        ).first else {
            preconditionFailure("Missing browser URL for \(application.displayName)")
        }
        return candidate
    }

    private static func requiredURL(_ value: String) -> URL {
        guard let url = URL(string: value) else {
            preconditionFailure("Invalid test URL: \(value)")
        }
        return url
    }
}
