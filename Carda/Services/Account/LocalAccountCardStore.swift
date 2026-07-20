//
//  LocalAccountCardStore.swift
//  Cardi
//

import Foundation
import SwiftData

enum LocalAccountCardStoreError: LocalizedError {
    case invalidPhoneNumber
    case invalidArchive
    case invalidProfile
    case backupBelongsToDifferentAccount

    var errorDescription: String? {
        switch self {
        case .invalidPhoneNumber:
            "手机号不能为空。"
        case .invalidArchive:
            "本地账户名片文件已损坏。"
        case .invalidProfile:
            "本地账户资料文件已损坏。"
        case .backupBelongsToDifferentAccount:
            "备份文件不属于当前登录的手机号。"
        }
    }
}

struct LocalAccountProfile: Codable, Hashable {
    let avatarImageData: Data?
    let name: String
    let phoneNumber: String
    let email: String
}

@MainActor
struct LocalAccountCardStore {
    private static let archiveVersion = 1
    private static let archiveFileName = "cards.json"
    private static let profileVersion = 1
    private static let profileFileName = "profile.json"
    private static let portableBackupVersion = 1

    private let fileManager: FileManager
    private let rootDirectoryOverride: URL?

    init(
        fileManager: FileManager = .default,
        rootDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.rootDirectoryOverride = rootDirectory
    }

    static func canonicalPhoneNumber(_ rawValue: String) -> String? {
        let digits = PhoneNumberFormatter.digits(in: rawValue)
        return digits.isEmpty ? nil : digits
    }

    func archiveExists(for phoneNumber: String) throws -> Bool {
        fileManager.fileExists(atPath: try archiveURL(for: phoneNumber).path)
    }

    func removeAccountDirectory(for phoneNumber: String) throws {
        let canonical = try requiredCanonicalPhoneNumber(phoneNumber)
        let directory = try accountDirectoryURL(forCanonicalPhoneNumber: canonical)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
    }

    func removeAllAccountDirectories() throws {
        let root = try rootDirectoryURL()
        if fileManager.fileExists(atPath: root.path) {
            try fileManager.removeItem(at: root)
        }
    }

    @discardableResult
    func removePreviouslyImportedCardsFromAllArchives() throws -> Int {
        let root = try rootDirectoryURL()
        guard fileManager.fileExists(atPath: root.path) else { return 0 }

        let accountDirectories = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var totalRemoved = 0

        for accountDirectory in accountDirectories {
            guard accountDirectory.lastPathComponent.hasPrefix("phone-") else { continue }
            let archiveURL = accountDirectory.appendingPathComponent(Self.archiveFileName)
            guard fileManager.fileExists(atPath: archiveURL.path) else { continue }

            let data = try Data(contentsOf: archiveURL)
            let archive = try JSONDecoder().decode(LocalAccountCardArchive.self, from: data)
            guard archive.version == Self.archiveVersion else { continue }

            let sanitizedArchive = archive.removingPreviouslyImportedCards
            let removedCount = archive.cards.count - sanitizedArchive.cards.count
            guard removedCount > 0 else { continue }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(sanitizedArchive).write(to: archiveURL, options: .atomic)
            try? fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: archiveURL.path
            )
            totalRemoved += removedCount
        }

        return totalRemoved
    }

    func storageSize(for phoneNumber: String) throws -> Int64 {
        let canonical = try requiredCanonicalPhoneNumber(phoneNumber)
        return directorySize(
            at: try accountDirectoryURL(forCanonicalPhoneNumber: canonical)
        )
    }

    func totalStorageSize() throws -> Int64 {
        directorySize(at: try rootDirectoryURL())
    }

    @discardableResult
    func saveProfile(_ profile: LocalAccountProfile) throws -> URL {
        let canonicalPhoneNumber = try requiredCanonicalPhoneNumber(profile.phoneNumber)
        let storedProfile = LocalAccountStoredProfile(
            version: Self.profileVersion,
            avatarImageData: profile.avatarImageData,
            name: profile.name,
            phoneNumber: canonicalPhoneNumber,
            email: profile.email
        )
        let accountDirectory = try accountDirectoryURL(
            forCanonicalPhoneNumber: canonicalPhoneNumber
        )
        try fileManager.createDirectory(
            at: accountDirectory,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(storedProfile)
        let destination = accountDirectory.appendingPathComponent(Self.profileFileName)
        try data.write(to: destination, options: .atomic)
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: destination.path
        )
        return destination
    }

    func loadProfile(for phoneNumber: String) throws -> LocalAccountProfile? {
        let canonicalPhoneNumber = try requiredCanonicalPhoneNumber(phoneNumber)
        let source = try accountDirectoryURL(
            forCanonicalPhoneNumber: canonicalPhoneNumber
        ).appendingPathComponent(Self.profileFileName)
        guard fileManager.fileExists(atPath: source.path) else { return nil }

        let data = try Data(contentsOf: source)
        let storedProfile = try JSONDecoder().decode(LocalAccountStoredProfile.self, from: data)
        guard
            storedProfile.version == Self.profileVersion,
            storedProfile.phoneNumber == canonicalPhoneNumber
        else {
            throw LocalAccountCardStoreError.invalidProfile
        }
        return LocalAccountProfile(
            avatarImageData: storedProfile.avatarImageData,
            name: storedProfile.name,
            phoneNumber: storedProfile.phoneNumber,
            email: storedProfile.email
        )
    }

    @discardableResult
    func saveCurrentDatabase(
        for phoneNumber: String,
        in modelContext: ModelContext
    ) throws -> URL {
        let canonicalPhoneNumber = try requiredCanonicalPhoneNumber(phoneNumber)
        let archive = try makeArchive(
            phoneNumber: canonicalPhoneNumber,
            modelContext: modelContext
        )
        let accountDirectory = try accountDirectoryURL(
            forCanonicalPhoneNumber: canonicalPhoneNumber
        )
        try fileManager.createDirectory(
            at: accountDirectory,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(archive)
        let destination = accountDirectory.appendingPathComponent(Self.archiveFileName)
        try data.write(to: destination, options: .atomic)
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: destination.path
        )
        return destination
    }

    @discardableResult
    func restoreDatabaseIfPresent(
        for phoneNumber: String,
        in modelContext: ModelContext
    ) throws -> Bool {
        let canonicalPhoneNumber = try requiredCanonicalPhoneNumber(phoneNumber)
        let source = try archiveURL(for: canonicalPhoneNumber)
        guard fileManager.fileExists(atPath: source.path) else { return false }

        let data = try Data(contentsOf: source)
        let archive = try JSONDecoder().decode(LocalAccountCardArchive.self, from: data)
        guard
            archive.version == Self.archiveVersion,
            archive.phoneNumber == canonicalPhoneNumber
        else {
            throw LocalAccountCardStoreError.invalidArchive
        }

        let sanitizedArchive = archive.removingPreviouslyImportedCards
        try replaceCurrentDatabase(with: sanitizedArchive, in: modelContext)
        if sanitizedArchive.cards.count != archive.cards.count {
            try saveCurrentDatabase(for: canonicalPhoneNumber, in: modelContext)
        }
        return true
    }

    func clearCurrentDatabase(in modelContext: ModelContext) throws {
        let cards = try modelContext.fetch(FetchDescriptor<BusinessCard>())
        let lists = try modelContext.fetch(FetchDescriptor<BusinessCardList>())

        for card in cards {
            modelContext.delete(card)
        }
        for list in lists {
            modelContext.delete(list)
        }
        try modelContext.save()
    }

    func portableBackupData(
        for phoneNumber: String,
        in modelContext: ModelContext
    ) throws -> Data {
        let canonicalPhoneNumber = try requiredCanonicalPhoneNumber(phoneNumber)
        let archive = try makeArchive(
            phoneNumber: canonicalPhoneNumber,
            modelContext: modelContext
        )
        let profile = try loadProfile(for: canonicalPhoneNumber).map {
            LocalAccountStoredProfile(
                version: Self.profileVersion,
                avatarImageData: $0.avatarImageData,
                name: $0.name,
                phoneNumber: canonicalPhoneNumber,
                email: $0.email
            )
        }
        let backup = LocalAccountPortableBackup(
            version: Self.portableBackupVersion,
            exportedAt: Date(),
            profile: profile,
            archive: archive
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    @discardableResult
    func restorePortableBackup(
        from data: Data,
        for phoneNumber: String,
        in modelContext: ModelContext
    ) throws -> LocalAccountProfile? {
        let canonicalPhoneNumber = try requiredCanonicalPhoneNumber(phoneNumber)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(LocalAccountPortableBackup.self, from: data)
        guard
            backup.version == Self.portableBackupVersion,
            backup.archive.version == Self.archiveVersion
        else {
            throw LocalAccountCardStoreError.invalidArchive
        }
        guard backup.archive.phoneNumber == canonicalPhoneNumber else {
            throw LocalAccountCardStoreError.backupBelongsToDifferentAccount
        }
        if let profile = backup.profile,
           profile.phoneNumber != canonicalPhoneNumber {
            throw LocalAccountCardStoreError.backupBelongsToDifferentAccount
        }

        try replaceCurrentDatabase(
            with: backup.archive.removingPreviouslyImportedCards,
            in: modelContext
        )
        try saveCurrentDatabase(for: canonicalPhoneNumber, in: modelContext)

        guard let storedProfile = backup.profile else { return nil }
        guard storedProfile.version == Self.profileVersion else {
            throw LocalAccountCardStoreError.invalidProfile
        }
        let profile = LocalAccountProfile(
            avatarImageData: storedProfile.avatarImageData,
            name: storedProfile.name,
            phoneNumber: canonicalPhoneNumber,
            email: storedProfile.email
        )
        try saveProfile(profile)
        return profile
    }

    private func makeArchive(
        phoneNumber: String,
        modelContext: ModelContext
    ) throws -> LocalAccountCardArchive {
        let cards = try modelContext.fetch(FetchDescriptor<BusinessCard>())
            .map(LocalAccountCardRecord.init(card:))
            .sorted { $0.createdAt < $1.createdAt }
        let lists = try modelContext.fetch(FetchDescriptor<BusinessCardList>())
            .map(LocalAccountCardListRecord.init(list:))
            .sorted { $0.sortOrder < $1.sortOrder }

        return LocalAccountCardArchive(
            version: Self.archiveVersion,
            phoneNumber: phoneNumber,
            savedAt: Date(),
            cards: cards,
            lists: lists
        )
    }

    private func replaceCurrentDatabase(
        with archive: LocalAccountCardArchive,
        in modelContext: ModelContext
    ) throws {
        let fallbackArchive = try makeArchive(
            phoneNumber: archive.phoneNumber,
            modelContext: modelContext
        )

        do {
            try clearCurrentDatabase(in: modelContext)
            insert(archive, in: modelContext)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            try? clearCurrentDatabase(in: modelContext)
            insert(fallbackArchive, in: modelContext)
            try? modelContext.save()
            throw error
        }
    }

    private func insert(
        _ archive: LocalAccountCardArchive,
        in modelContext: ModelContext
    ) {
        for list in archive.lists {
            modelContext.insert(list.businessCardList)
        }
        for card in archive.cards {
            modelContext.insert(card.businessCard)
        }
    }

    private func requiredCanonicalPhoneNumber(_ rawValue: String) throws -> String {
        guard let canonical = Self.canonicalPhoneNumber(rawValue) else {
            throw LocalAccountCardStoreError.invalidPhoneNumber
        }
        return canonical
    }

    private func archiveURL(for phoneNumber: String) throws -> URL {
        let canonical = try requiredCanonicalPhoneNumber(phoneNumber)
        return try accountDirectoryURL(forCanonicalPhoneNumber: canonical)
            .appendingPathComponent(Self.archiveFileName)
    }

    private func accountDirectoryURL(
        forCanonicalPhoneNumber phoneNumber: String
    ) throws -> URL {
        try rootDirectoryURL()
            .appendingPathComponent("phone-\(phoneNumber)", isDirectory: true)
    }

    private func rootDirectoryURL() throws -> URL {
        if let rootDirectoryOverride {
            return rootDirectoryOverride
        }
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupport
            .appendingPathComponent("Carda", isDirectory: true)
            .appendingPathComponent("Accounts", isDirectory: true)
    }

    private func directorySize(at directory: URL) -> Int64 {
        guard fileManager.fileExists(atPath: directory.path) else { return 0 }
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard
                let values = try? fileURL.resourceValues(
                    forKeys: [.isRegularFileKey, .fileSizeKey]
                ),
                values.isRegularFile == true
            else {
                continue
            }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}

private struct LocalAccountStoredProfile: Codable {
    let version: Int
    let avatarImageData: Data?
    let name: String
    let phoneNumber: String
    let email: String
}

private struct LocalAccountCardArchive: Codable {
    let version: Int
    let phoneNumber: String
    let savedAt: Date
    let cards: [LocalAccountCardRecord]
    let lists: [LocalAccountCardListRecord]

    var removingPreviouslyImportedCards: Self {
        Self(
            version: version,
            phoneNumber: phoneNumber,
            savedAt: Date(),
            cards: cards.filter { !$0.isPreviouslyImportedSample },
            lists: lists
        )
    }
}

private struct LocalAccountPortableBackup: Codable {
    let version: Int
    let exportedAt: Date
    let profile: LocalAccountStoredProfile?
    let archive: LocalAccountCardArchive
}

private struct LocalAccountCardRecord: Codable {
    let id: UUID
    let ownerKind: CardOwnerKind
    let name: String
    let phoneticName: String
    let position: String
    let organizationName: String
    let backgroundTemplateRaw: String?
    let avatarImageData: Data?
    let companyLogoImageData: Data?
    let cardListID: UUID?
    let createdAt: Date
    let updatedAt: Date
    let receivedAt: Date?
    let fields: [LocalAccountCardFieldRecord]

    var isPreviouslyImportedSample: Bool {
        PreviouslyImportedCardCleanup.isPreviouslyImportedSample(
            ownerKind: ownerKind,
            phoneValues: fields
                .filter { $0.kind == .phone }
                .map(\.value)
        )
    }

    init(card: BusinessCard) {
        id = card.id
        ownerKind = card.ownerKind
        name = card.name
        phoneticName = card.phoneticName
        position = card.position
        organizationName = card.organizationName
        backgroundTemplateRaw = card.backgroundTemplate.rawValue
        avatarImageData = card.avatarImageData
        companyLogoImageData = card.companyLogoImageData
        cardListID = card.cardListID
        createdAt = card.createdAt
        updatedAt = card.updatedAt
        receivedAt = card.receivedAt
        fields = card.sortedFields.map { field in
            LocalAccountCardFieldRecord(field: field)
        }
    }

    var businessCard: BusinessCard {
        BusinessCard(
            id: id,
            ownerKind: ownerKind,
            name: name,
            phoneticName: phoneticName,
            position: position,
            organizationName: organizationName,
            backgroundTemplate: CardBackgroundTemplate(
                rawValue: backgroundTemplateRaw ?? ""
            ) ?? .color1,
            avatarImageData: avatarImageData,
            companyLogoImageData: companyLogoImageData,
            cardListID: cardListID,
            fields: fields.map(\.cardInfoField),
            createdAt: createdAt,
            updatedAt: updatedAt,
            receivedAt: receivedAt
        )
    }
}

private struct LocalAccountCardFieldRecord: Codable {
    let id: UUID
    let kind: CardFieldKind
    let value: String
    let sortOrder: Int
    let createdAt: Date

    init(field: CardInfoField) {
        id = field.id
        kind = field.kind
        value = field.value
        sortOrder = field.sortOrder
        createdAt = field.createdAt
    }

    var cardInfoField: CardInfoField {
        CardInfoField(
            id: id,
            kind: kind,
            value: value,
            sortOrder: sortOrder,
            createdAt: createdAt
        )
    }
}

private struct LocalAccountCardListRecord: Codable {
    let id: UUID
    let name: String
    let sortOrder: Int
    let createdAt: Date
    let updatedAt: Date

    init(list: BusinessCardList) {
        id = list.id
        name = list.name
        sortOrder = list.sortOrder
        createdAt = list.createdAt
        updatedAt = list.updatedAt
    }

    var businessCardList: BusinessCardList {
        BusinessCardList(
            id: id,
            name: name,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
