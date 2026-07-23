//
//  CardExchangeDiagnostics.swift
//  Cardi
//

import Combine
import CryptoKit
import Foundation
#if canImport(UIKit)
import UIKit
#endif

extension Notification.Name {
    static let cardExchangeDiagnosticsDidStart = Notification.Name(
        "Cardi.cardExchangeDiagnosticsDidStart"
    )
}

nonisolated enum CardExchangeDiagnosticRole: String, CaseIterable, Codable, Identifiable, Sendable {
    case deviceA = "A"
    case deviceB = "B"

    var id: String { rawValue }

    var title: String {
        "设备 \(rawValue)"
    }
}

nonisolated enum CardExchangeDiagnosticStage: String, Codable, Sendable {
    case session
    case lifecycle
    case gesture
    case discovery
    case connection
    case token
    case ranging
    case targetSelection
    case intent
    case transfer
    case persistence
    case animation
    case failure
}

nonisolated enum CardExchangeDiagnosticLevel: String, Codable, Sendable {
    case debug
    case info
    case warning
    case error
}

nonisolated struct CardExchangeDiagnosticCapabilities: Codable, Equatable, Sendable {
    let preciseDistance: Bool
    let direction: Bool
}

nonisolated struct CardExchangeDiagnosticSource: Codable, Equatable, Sendable {
    let file: String
    let function: String
    let line: UInt
}

nonisolated struct CardExchangeDiagnosticEvent: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let sequence: Int
    let timestamp: Date
    let systemUptime: TimeInterval
    let stage: CardExchangeDiagnosticStage
    let name: String
    let level: CardExchangeDiagnosticLevel
    let exchangeID: UUID?
    let peerIDHash: String?
    let details: [String: String]
    let source: CardExchangeDiagnosticSource
}

nonisolated struct CardExchangeDiagnosticPackage: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    var schemaVersion = Self.schemaVersion
    let sessionID: UUID
    let testCode: String
    let role: CardExchangeDiagnosticRole
    let startedAt: Date
    var endedAt: Date?
    let appVersion: String
    let appBuild: String
    let operatingSystem: String
    let deviceModel: String
    let capabilities: CardExchangeDiagnosticCapabilities
    let privacyNotice: String
    var events: [CardExchangeDiagnosticEvent]
}

nonisolated struct CardExchangeDiagnosticSummary: Equatable, Sendable {
    let testCode: String
    let role: CardExchangeDiagnosticRole
    let startedAt: Date
    let eventCount: Int
}

final class CardExchangeDiagnostics: ObservableObject {
    static let shared = CardExchangeDiagnostics()

    private enum Constants {
        static let maximumEvents = 4_000
        static let persistenceBatchSize = 20
        static let persistenceDelay: TimeInterval = 1
        static let privacyNotice =
            "诊断包不包含姓名、手机号、邮箱、名片文字、图片或 Nearby Interaction 原始令牌。设备与连接对象仅使用不可逆摘要标识。"
    }

    @Published private(set) var isRecording = false
    @Published private(set) var eventCount = 0
    @Published private(set) var latestStage: CardExchangeDiagnosticStage?
    @Published private(set) var latestEventName: String?
    @Published private(set) var activeSummary: CardExchangeDiagnosticSummary?
    @Published private(set) var latestSavedSummary: CardExchangeDiagnosticSummary?

    private let persistenceQueue = DispatchQueue(
        label: "com.Alex.Carda.exchange-diagnostics.persistence",
        qos: .utility
    )
    private var activePackage: CardExchangeDiagnosticPackage?
    private var latestSavedPackage: CardExchangeDiagnosticPackage?
    private var activeFileURL: URL?
    private var eventsSincePersistence = 0
    private var pendingPersistenceWorkItem: DispatchWorkItem?
    #if canImport(UIKit)
    private var backgroundCancellable: AnyCancellable?
    #endif

    private init() {
        latestSavedPackage = loadLatestPackage()
        latestSavedSummary = latestSavedPackage.map(Self.summary(for:))
        eventCount = latestSavedPackage?.events.count ?? 0
        latestStage = latestSavedPackage?.events.last?.stage
        latestEventName = latestSavedPackage?.events.last?.name

        #if canImport(UIKit)
        backgroundCancellable = NotificationCenter.default.publisher(
            for: UIApplication.didEnterBackgroundNotification
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.flush()
        }
        #endif
    }

    @discardableResult
    func start(
        testCode: String,
        role: CardExchangeDiagnosticRole,
        capabilities: CardExchangeDiagnosticCapabilities
    ) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        let normalizedCode = Self.normalizedTestCode(testCode)
        guard normalizedCode.count == 6 else { return false }

        if isRecording {
            stop(reason: "replaced_by_new_session")
        }

        let bundle = Bundle.main
        let package = CardExchangeDiagnosticPackage(
            sessionID: UUID(),
            testCode: normalizedCode,
            role: role,
            startedAt: Date(),
            endedAt: nil,
            appVersion: bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "unknown",
            appBuild: bundle.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String ?? "unknown",
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            deviceModel: Self.hardwareModel,
            capabilities: capabilities,
            privacyNotice: Constants.privacyNotice,
            events: []
        )

        activePackage = package
        activeFileURL = makeFileURL(for: package)
        isRecording = true
        eventCount = 0
        latestStage = .session
        latestEventName = "recording_started"
        activeSummary = Self.summary(for: package)
        eventsSincePersistence = 0

        recordOnMain(
            stage: .session,
            name: "recording_started",
            level: .info,
            exchangeID: nil,
            peerIdentifier: nil,
            details: [
                "preciseDistance": String(capabilities.preciseDistance),
                "direction": String(capabilities.direction)
            ],
            file: #fileID,
            function: #function,
            line: #line
        )
        persistActivePackage()
        return true
    }

    func stop(reason: String = "user_stopped") {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isRecording else { return }
        recordOnMain(
            stage: .session,
            name: "recording_stopped",
            level: .info,
            exchangeID: nil,
            peerIdentifier: nil,
            details: ["reason": reason],
            file: #fileID,
            function: #function,
            line: #line
        )
        activePackage?.endedAt = Date()
        isRecording = false
        if let activePackage {
            latestSavedPackage = activePackage
            latestSavedSummary = Self.summary(for: activePackage)
            activeSummary = Self.summary(for: activePackage)
        }
        persistActivePackage()
    }

    func flush() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard activePackage != nil else { return }
        persistActivePackage()
    }

    func clearSavedSessions() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !isRecording else { return }
        pendingPersistenceWorkItem?.cancel()
        pendingPersistenceWorkItem = nil
        activePackage = nil
        latestSavedPackage = nil
        activeFileURL = nil
        activeSummary = nil
        latestSavedSummary = nil
        eventCount = 0
        latestStage = nil
        latestEventName = nil
        let directory = diagnosticsDirectoryURL
        persistenceQueue.async {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func exportData() throws -> Data {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let package = activePackage ?? latestSavedPackage else {
            throw CardExchangeDiagnosticError.noSession
        }
        return try Self.makeEncoder().encode(package)
    }

    var suggestedExportFilename: String {
        let package = activePackage ?? latestSavedPackage
        let code = package?.testCode ?? "unknown"
        let role = package?.role.rawValue ?? "device"
        return "Cardi-Exchange-Diagnostic-\(code)-\(role)"
    }

    func record(
        stage: CardExchangeDiagnosticStage,
        name: String,
        level: CardExchangeDiagnosticLevel = .info,
        exchangeID: UUID? = nil,
        peerIdentifier: String? = nil,
        details: [String: String] = [:],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        let work: () -> Void = { [weak self] in
            self?.recordOnMain(
                stage: stage,
                name: name,
                level: level,
                exchangeID: exchangeID,
                peerIdentifier: peerIdentifier,
                details: details,
                file: file,
                function: function,
                line: line
            )
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    nonisolated static func normalizedTestCode(_ value: String) -> String {
        String(value.filter(\.isNumber).prefix(6))
    }

    nonisolated static func anonymousIdentifier(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    private func recordOnMain(
        stage: CardExchangeDiagnosticStage,
        name: String,
        level: CardExchangeDiagnosticLevel,
        exchangeID: UUID?,
        peerIdentifier: String?,
        details: [String: String],
        file: String,
        function: String,
        line: UInt
    ) {
        guard isRecording, var package = activePackage else { return }
        let event = CardExchangeDiagnosticEvent(
            id: UUID(),
            sequence: (package.events.last?.sequence ?? 0) + 1,
            timestamp: Date(),
            systemUptime: ProcessInfo.processInfo.systemUptime,
            stage: stage,
            name: name,
            level: level,
            exchangeID: exchangeID,
            peerIDHash: peerIdentifier.map(Self.anonymousIdentifier),
            details: details,
            source: CardExchangeDiagnosticSource(
                file: file,
                function: function,
                line: line
            )
        )
        package.events.append(event)
        if package.events.count > Constants.maximumEvents {
            package.events.removeFirst(package.events.count - Constants.maximumEvents)
        }
        activePackage = package
        eventCount = package.events.count
        latestStage = stage
        latestEventName = name
        activeSummary = Self.summary(for: package)
        eventsSincePersistence += 1

        if level == .error || level == .warning
            || eventsSincePersistence >= Constants.persistenceBatchSize {
            persistActivePackage()
        } else {
            schedulePersistenceIfNeeded()
        }
    }

    private func schedulePersistenceIfNeeded() {
        guard pendingPersistenceWorkItem == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingPersistenceWorkItem = nil
            self.persistActivePackage()
        }
        pendingPersistenceWorkItem = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Constants.persistenceDelay,
            execute: item
        )
    }

    private func persistActivePackage() {
        guard let package = activePackage, let fileURL = activeFileURL else { return }
        pendingPersistenceWorkItem?.cancel()
        pendingPersistenceWorkItem = nil
        eventsSincePersistence = 0
        let directory = diagnosticsDirectoryURL
        persistenceQueue.async {
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                let data = try Self.makeEncoder().encode(package)
                try data.write(to: fileURL, options: .atomic)
                Self.pruneSavedSessions(in: directory)
            } catch {
                // Diagnostics must never interrupt the exchange path.
            }
        }
    }

    private func loadLatestPackage() -> CardExchangeDiagnosticPackage? {
        let directory = diagnosticsDirectoryURL
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        let newest = urls
            .filter { $0.pathExtension == "json" }
            .sorted { lhs, rhs in
                let leftDate = try? lhs.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
                let rightDate = try? rhs.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
                return (leftDate ?? .distantPast) > (rightDate ?? .distantPast)
            }
            .first
        guard let newest, let data = try? Data(contentsOf: newest) else { return nil }
        return try? Self.makeDecoder().decode(CardExchangeDiagnosticPackage.self, from: data)
    }

    private var diagnosticsDirectoryURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return applicationSupport
            .appendingPathComponent("Carda", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
    }

    private func makeFileURL(for package: CardExchangeDiagnosticPackage) -> URL {
        let timestamp = Int(package.startedAt.timeIntervalSince1970)
        return diagnosticsDirectoryURL.appendingPathComponent(
            "exchange-\(timestamp)-\(package.testCode)-\(package.role.rawValue)-\(package.sessionID.uuidString).json"
        )
    }

    nonisolated private static func summary(
        for package: CardExchangeDiagnosticPackage
    ) -> CardExchangeDiagnosticSummary {
        CardExchangeDiagnosticSummary(
            testCode: package.testCode,
            role: package.role,
            startedAt: package.startedAt,
            eventCount: package.events.count
        )
    }

    nonisolated private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    nonisolated private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    nonisolated private static func pruneSavedSessions(in directory: URL) {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        let sorted = urls
            .filter { $0.pathExtension == "json" }
            .sorted { lhs, rhs in
                let leftDate = try? lhs.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
                let rightDate = try? rhs.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
                return (leftDate ?? .distantPast) > (rightDate ?? .distantPast)
            }
        for url in sorted.dropFirst(5) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static var hardwareModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        return machine.isEmpty ? "unknown" : machine
    }
}

enum CardExchangeDiagnosticError: LocalizedError {
    case noSession

    var errorDescription: String? {
        switch self {
        case .noSession:
            "尚无可导出的交换诊断记录"
        }
    }
}
