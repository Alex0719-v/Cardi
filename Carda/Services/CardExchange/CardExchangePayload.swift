//
//  CardExchangePayload.swift
//  Carda
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
            avatarImageData: avatarImageData,
            companyLogoImageData: companyLogoImageData,
            fields: fields.map(\.cardInfoField),
            createdAt: now,
            updatedAt: now,
            receivedAt: now
        )
    }
}
