//
//  BusinessCard.swift
//  Cardi
//

import Foundation
import SwiftData

@Model
final class BusinessCard {
    @Attribute(.unique) var id: UUID
    var ownerKindRaw: String
    var name: String
    var phoneticName: String
    var position: String
    var organizationName: String
    var backgroundTemplateRaw: String?
    @Attribute(.externalStorage) var avatarImageData: Data?
    @Attribute(.externalStorage) var companyLogoImageData: Data?
    var cardListID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var receivedAt: Date?
    @Relationship(deleteRule: .cascade) var fields: [CardInfoField]

    init(
        id: UUID = UUID(),
        ownerKind: CardOwnerKind = .mine,
        name: String,
        phoneticName: String,
        position: String,
        organizationName: String,
        backgroundTemplate: CardBackgroundTemplate = .color1,
        avatarImageData: Data? = nil,
        companyLogoImageData: Data? = nil,
        cardListID: UUID? = nil,
        fields: [CardInfoField] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        receivedAt: Date? = nil
    ) {
        self.id = id
        self.ownerKindRaw = ownerKind.rawValue
        self.name = name
        self.phoneticName = phoneticName
        self.position = position
        self.organizationName = organizationName
        self.backgroundTemplateRaw = backgroundTemplate.rawValue
        self.avatarImageData = avatarImageData
        self.companyLogoImageData = companyLogoImageData
        self.cardListID = cardListID
        self.fields = fields
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.receivedAt = receivedAt
    }

    convenience init(draft: BusinessCardDraft) {
        self.init(
            id: draft.id,
            ownerKind: draft.ownerKind,
            name: draft.name,
            phoneticName: draft.phoneticName,
            position: draft.position,
            organizationName: draft.organizationName,
            backgroundTemplate: draft.backgroundTemplate,
            avatarImageData: draft.avatarImageData,
            companyLogoImageData: draft.companyLogoImageData,
            fields: draft.fields.map(CardInfoField.init(draft:))
        )
    }

    var ownerKind: CardOwnerKind {
        get { CardOwnerKind(rawValue: ownerKindRaw) ?? .mine }
        set { ownerKindRaw = newValue.rawValue }
    }

    var backgroundTemplate: CardBackgroundTemplate {
        get {
            CardBackgroundTemplate(rawValue: backgroundTemplateRaw ?? "") ?? .color1
        }
        set {
            backgroundTemplateRaw = newValue.rawValue
        }
    }

    var sortedFields: [CardInfoField] {
        fields.sorted { $0.sortOrder < $1.sortOrder }
    }

    var renderData: CardRenderData {
        CardRenderData(
            id: id,
            name: name,
            phoneticName: phoneticName,
            position: position,
            organizationName: organizationName,
            backgroundTemplate: backgroundTemplate,
            avatarImageData: avatarImageData,
            companyLogoImageData: companyLogoImageData,
            fields: sortedFields.map {
                CardFieldDraft(
                    id: $0.id,
                    kind: $0.kind,
                    value: $0.value,
                    sortOrder: $0.sortOrder
                )
            }
        )
    }

    func applyMetadata(from draft: BusinessCardDraft) {
        ownerKind = draft.ownerKind
        name = draft.name
        phoneticName = draft.phoneticName
        position = draft.position
        organizationName = draft.organizationName
        backgroundTemplate = draft.backgroundTemplate
        avatarImageData = draft.avatarImageData
        companyLogoImageData = draft.companyLogoImageData
        updatedAt = Date()
    }
}

@Model
final class CardInfoField {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var value: String
    var sortOrder: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        kind: CardFieldKind,
        value: String,
        sortOrder: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.value = value
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    convenience init(draft: CardFieldDraft) {
        self.init(
            id: draft.id,
            kind: draft.kind,
            value: draft.value,
            sortOrder: draft.sortOrder
        )
    }

    var kind: CardFieldKind {
        get { CardFieldKind(rawValue: kindRaw) ?? .phone }
        set { kindRaw = newValue.rawValue }
    }
}
