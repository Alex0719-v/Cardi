//
//  BusinessCardDraft.swift
//  Cardi
//

import Foundation

struct CardFieldDraft: Identifiable, Hashable {
    var id: UUID
    var kind: CardFieldKind
    var value: String
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        kind: CardFieldKind,
        value: String = "",
        sortOrder: Int
    ) {
        self.id = id
        self.kind = kind
        self.value = value
        self.sortOrder = sortOrder
    }
}

struct BusinessCardDraft: Identifiable, Hashable {
    var id: UUID
    var ownerKind: CardOwnerKind
    var name: String
    var phoneticName: String
    var position: String
    var organizationName: String
    var backgroundTemplate: CardBackgroundTemplate
    var avatarImageData: Data?
    var companyLogoImageData: Data?
    var fields: [CardFieldDraft]

    init(
        id: UUID = UUID(),
        ownerKind: CardOwnerKind = .mine,
        name: String = "",
        phoneticName: String = "",
        position: String = "",
        organizationName: String = "",
        backgroundTemplate: CardBackgroundTemplate = .color1,
        avatarImageData: Data? = nil,
        companyLogoImageData: Data? = nil,
        fields: [CardFieldDraft] = BusinessCardDraft.defaultFields
    ) {
        self.id = id
        self.ownerKind = ownerKind
        self.name = name
        self.phoneticName = phoneticName
        self.position = position
        self.organizationName = organizationName
        self.backgroundTemplate = backgroundTemplate
        self.avatarImageData = avatarImageData
        self.companyLogoImageData = companyLogoImageData
        self.fields = fields
    }

    init(card: BusinessCard) {
        self.id = card.id
        self.ownerKind = card.ownerKind
        self.name = card.name
        self.phoneticName = card.phoneticName
        self.position = card.position
        self.organizationName = card.organizationName
        self.backgroundTemplate = card.backgroundTemplate
        self.avatarImageData = card.avatarImageData
        self.companyLogoImageData = card.companyLogoImageData
        self.fields = card.sortedFields.map {
            CardFieldDraft(
                id: $0.id,
                kind: $0.kind,
                value: $0.kind == .phone
                    ? PhoneNumberFormatter.format($0.value)
                    : $0.value,
                sortOrder: $0.sortOrder
            )
        }
    }

    static let defaultFields: [CardFieldDraft] = [
        CardFieldDraft(kind: .phone, sortOrder: 0),
        CardFieldDraft(kind: .email, sortOrder: 1),
        CardFieldDraft(kind: .address, sortOrder: 2),
        CardFieldDraft(kind: .link, sortOrder: 3)
    ]

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
            fields: fields.sorted { $0.sortOrder < $1.sortOrder }
        )
    }
}

struct CardRenderData: Identifiable, Hashable {
    var id: UUID
    var name: String
    var phoneticName: String
    var position: String
    var organizationName: String
    var backgroundTemplate: CardBackgroundTemplate = .color1
    var avatarImageData: Data?
    var companyLogoImageData: Data?
    var fields: [CardFieldDraft]

    var visibleInfoFields: [CardFieldDraft] {
        fields
            .filter { $0.kind.isRenderedInfoField && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "姓名" : trimmed
    }

    var displayPhoneticName: String {
        let trimmed = phoneticName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Xing Ming" : trimmed
    }

    var displayPosition: String {
        let trimmed = position.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "职位" : trimmed
    }

    var displayOrganizationName: String {
        let trimmed = organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "公司" : trimmed
    }
}

extension CardFieldDraft {
    var displayValue: String {
        kind == .phone ? PhoneNumberFormatter.format(value) : value
    }
}
