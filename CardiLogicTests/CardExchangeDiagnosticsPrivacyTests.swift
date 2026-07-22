import Foundation

@main
private enum CardExchangeDiagnosticsPrivacyTests {
    static func main() throws {
        validatesTestCodeNormalization()
        try validatesAnonymousPeerEncoding()
        print("CardExchangeDiagnosticsPrivacyTests: PASS")
    }

    private static func validatesTestCodeNormalization() {
        precondition(CardExchangeDiagnostics.normalizedTestCode("12a 34-567") == "123456")
        precondition(CardExchangeDiagnostics.normalizedTestCode("abc") == "")
    }

    private static func validatesAnonymousPeerEncoding() throws {
        let rawPeerID = "Cardi-sensitive-peer"
        let hash = CardExchangeDiagnostics.anonymousIdentifier(rawPeerID)
        precondition(hash.count == 12)
        precondition(hash == CardExchangeDiagnostics.anonymousIdentifier(rawPeerID))
        precondition(!hash.contains(rawPeerID))

        let package = CardExchangeDiagnosticPackage(
            sessionID: UUID(),
            testCode: "123456",
            role: .deviceA,
            startedAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 2),
            appVersion: "1.0",
            appBuild: "1",
            operatingSystem: "testOS",
            deviceModel: "testDevice",
            capabilities: CardExchangeDiagnosticCapabilities(
                preciseDistance: true,
                direction: false
            ),
            privacyNotice: "test",
            events: [
                CardExchangeDiagnosticEvent(
                    id: UUID(),
                    sequence: 1,
                    timestamp: Date(timeIntervalSince1970: 1),
                    systemUptime: 10,
                    stage: .connection,
                    name: "peer_state_changed",
                    level: .info,
                    exchangeID: nil,
                    peerIDHash: hash,
                    details: ["state": "connected"],
                    source: CardExchangeDiagnosticSource(
                        file: "Test.swift",
                        function: "test",
                        line: 1
                    )
                )
            ]
        )

        let data = try JSONEncoder().encode(package)
        let json = String(decoding: data, as: UTF8.self)
        precondition(json.contains(hash))
        precondition(!json.contains(rawPeerID))
    }
}
