import Foundation

enum CardFieldKind: String, Codable, Hashable {
    case phone
    case email
    case address
    case link
}

struct CardFieldDraft {
    var kind: CardFieldKind
    var value: String
    var sortOrder: Int
}

struct CardInfoField {
    var kind: CardFieldKind
    var value: String
    var sortOrder: Int
}

struct CardRenderData {
    var id: UUID
    var name: String
    var phoneticName: String
    var position: String
    var organizationName: String
    var avatarImageData: Data?
    var companyLogoImageData: Data?
    var fields: [CardFieldDraft]
}

enum BusinessCardOwnerKind {
    case received
}

final class BusinessCard {
    init(
        id: UUID,
        ownerKind: BusinessCardOwnerKind,
        name: String,
        phoneticName: String,
        position: String,
        organizationName: String,
        avatarImageData: Data?,
        companyLogoImageData: Data?,
        fields: [CardInfoField],
        createdAt: Date,
        updatedAt: Date,
        receivedAt: Date
    ) {}
}

@main
@MainActor
private enum CardExchangePayloadValidationTests {
    private static let imageLimit = 6 * 1_024 * 1_024
    private static let transportMessageLimit = 14 * 1_024 * 1_024

    static func main() throws {
        acceptsExactDocumentedFieldAndImageLimits()
        rejectsEveryValueBeyondItsDocumentedLimit()
        try confirmsValidatedMaximumCanExceedTransportMessageLimit()
        print("CardExchangePayloadValidationTests: PASS")
    }

    private static func acceptsExactDocumentedFieldAndImageLimits() {
        let payload = maximumValidatedPayload()
        precondition(payload.isValidForExchange)
    }

    private static func rejectsEveryValueBeyondItsDocumentedLimit() {
        assertInvalid(replacing(maximumValidatedPayload(), name: repeated("n", count: 257)))
        assertInvalid(
            replacing(maximumValidatedPayload(), phoneticName: repeated("p", count: 257))
        )
        assertInvalid(replacing(maximumValidatedPayload(), position: repeated("p", count: 257)))
        assertInvalid(
            replacing(maximumValidatedPayload(), organizationName: repeated("o", count: 513))
        )
        assertInvalid(
            replacing(maximumValidatedPayload(), avatarImageData: Data(count: imageLimit + 1))
        )
        assertInvalid(
            replacing(maximumValidatedPayload(), companyLogoImageData: Data(count: imageLimit + 1))
        )

        var tooManyFields = maximumValidatedPayload().fields
        tooManyFields.append(
            CardExchangeFieldPayload(
                field: CardFieldDraft(kind: .phone, value: "1", sortOrder: 0)
            )
        )
        assertInvalid(replacing(maximumValidatedPayload(), fields: tooManyFields))

        var oversizedValue = maximumValidatedPayload().fields
        oversizedValue[0].value = repeated("v", count: 2_049)
        assertInvalid(replacing(maximumValidatedPayload(), fields: oversizedValue))

        var negativeOrder = maximumValidatedPayload().fields
        negativeOrder[0].sortOrder = -1
        assertInvalid(replacing(maximumValidatedPayload(), fields: negativeOrder))

        var excessiveOrder = maximumValidatedPayload().fields
        excessiveOrder[0].sortOrder = 32
        assertInvalid(replacing(maximumValidatedPayload(), fields: excessiveOrder))
    }

    private static func confirmsValidatedMaximumCanExceedTransportMessageLimit() throws {
        let payload = maximumValidatedPayload()
        precondition(payload.isValidForExchange)
        let encodedSize = try JSONEncoder().encode(payload).count
        precondition(
            encodedSize > transportMessageLimit,
            "The diagnostic fixture should expose the validator/transport size mismatch"
        )
        print(
            "KNOWN_RISK validated_payload_bytes=\(encodedSize) "
                + "transport_limit_bytes=\(transportMessageLimit)"
        )
    }

    private static func maximumValidatedPayload() -> CardExchangePayload {
        let fields = (0..<32).map { index in
            CardFieldDraft(
                kind: .phone,
                value: repeated("v", count: 2_048),
                sortOrder: index
            )
        }
        return CardExchangePayload(
            data: CardRenderData(
            id: UUID(),
            name: repeated("n", count: 256),
            phoneticName: repeated("p", count: 256),
            position: repeated("j", count: 256),
            organizationName: repeated("o", count: 512),
            avatarImageData: Data(count: imageLimit),
            companyLogoImageData: Data(count: imageLimit),
            fields: fields
            )
        )
    }

    private static func replacing(
        _ payload: CardExchangePayload,
        name: String? = nil,
        phoneticName: String? = nil,
        position: String? = nil,
        organizationName: String? = nil,
        avatarImageData: Data? = nil,
        companyLogoImageData: Data? = nil,
        fields: [CardExchangeFieldPayload]? = nil
    ) -> CardExchangePayload {
        var copy = payload
        copy.name = name ?? payload.name
        copy.phoneticName = phoneticName ?? payload.phoneticName
        copy.position = position ?? payload.position
        copy.organizationName = organizationName ?? payload.organizationName
        copy.avatarImageData = avatarImageData ?? payload.avatarImageData
        copy.companyLogoImageData = companyLogoImageData ?? payload.companyLogoImageData
        copy.fields = fields ?? payload.fields
        return copy
    }

    private static func assertInvalid(_ payload: CardExchangePayload) {
        precondition(!payload.isValidForExchange)
    }

    private static func repeated(_ value: Character, count: Int) -> String {
        String(repeating: String(value), count: count)
    }
}
