//
//  CardExchangePayload.swift
//  Cardi
//

import Foundation

struct CardExchangeFieldPayload: Codable, Hashable {
    var kind: CardFieldKind
    var value: String
    var sortOrder: Int

    @MainActor
    init(field: CardFieldDraft) {
        self.kind = field.kind
        self.value = field.value
        self.sortOrder = field.sortOrder
    }

    @MainActor
    var cardInfoField: CardInfoField {
        CardInfoField(
            kind: kind,
            value: value,
            sortOrder: sortOrder
        )
    }
}

struct CardExchangePayload: Codable, Hashable {
    var sourceCardID: UUID
    var name: String
    var phoneticName: String
    var position: String
    var organizationName: String
    var backgroundTemplateRaw: String?
    var avatarImageData: Data?
    var companyLogoImageData: Data?
    var fields: [CardExchangeFieldPayload]

    @MainActor
    init(data: CardRenderData) {
        self.sourceCardID = data.id
        self.name = data.name
        self.phoneticName = data.phoneticName
        self.position = data.position
        self.organizationName = data.organizationName
        self.backgroundTemplateRaw = data.backgroundTemplate.rawValue
        self.avatarImageData = data.avatarImageData
        self.companyLogoImageData = data.companyLogoImageData
        self.fields = data.fields
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(CardExchangeFieldPayload.init(field:))
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "对方" : trimmed
    }

    var isValidForExchange: Bool {
        let maximumImageBytes = 6 * 1_024 * 1_024
        guard
            name.count <= 256,
            phoneticName.count <= 256,
            position.count <= 256,
            organizationName.count <= 512,
            fields.count <= 32,
            backgroundTemplateRaw?.count ?? 0 <= 64,
            avatarImageData?.count ?? 0 <= maximumImageBytes,
            companyLogoImageData?.count ?? 0 <= maximumImageBytes
        else {
            return false
        }

        return fields.allSatisfy { field in
            field.value.count <= 2_048 && (0..<32).contains(field.sortOrder)
        }
    }

    @MainActor
    func receivedBusinessCard() -> BusinessCard {
        let now = Date()
        return BusinessCard(
            id: UUID(),
            ownerKind: .received,
            name: name,
            phoneticName: phoneticName,
            position: position,
            organizationName: organizationName,
            backgroundTemplate: CardBackgroundTemplate(
                rawValue: backgroundTemplateRaw ?? ""
            ) ?? .color1,
            avatarImageData: avatarImageData,
            companyLogoImageData: companyLogoImageData,
            fields: fields.map(\.cardInfoField),
            createdAt: now,
            updatedAt: now,
            receivedAt: now
        )
    }
}
