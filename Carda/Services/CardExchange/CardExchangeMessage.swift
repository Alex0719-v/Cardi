//
//  CardExchangeMessage.swift
//  Cardi
//

import Foundation

struct CardExchangeMessage: Codable {
    enum Kind: String, Codable {
        case hello
        case nearbyToken
        case throwIntent
        case card
        case persistedAck
        case rejected
        case error
    }

    var protocolVersion = 2
    var kind: Kind
    var exchangeID: UUID?
    var nearbyTokenData: Data?
    var card: CardExchangePayload?
    var cardID: UUID?
    var intentCreatedAt: Date?
    var transferMode: CardExchangeTransferMode?
    var message: String?

    static func nearbyToken(_ data: Data) -> CardExchangeMessage {
        CardExchangeMessage(kind: .nearbyToken, nearbyTokenData: data)
    }

    static func hello(displayName: String) -> CardExchangeMessage {
        CardExchangeMessage(kind: .hello, message: displayName)
    }

    static func throwIntent(
        exchangeID: UUID,
        cardID: UUID,
        createdAt: Date
    ) -> CardExchangeMessage {
        CardExchangeMessage(
            kind: .throwIntent,
            exchangeID: exchangeID,
            cardID: cardID,
            intentCreatedAt: createdAt
        )
    }

    static func card(
        _ payload: CardExchangePayload,
        exchangeID: UUID,
        mode: CardExchangeTransferMode
    ) -> CardExchangeMessage {
        CardExchangeMessage(
            kind: .card,
            exchangeID: exchangeID,
            card: payload,
            transferMode: mode
        )
    }

    static func persistedAck(exchangeID: UUID) -> CardExchangeMessage {
        CardExchangeMessage(kind: .persistedAck, exchangeID: exchangeID)
    }

    static func rejected(exchangeID: UUID, reason: String? = nil) -> CardExchangeMessage {
        CardExchangeMessage(
            kind: .rejected,
            exchangeID: exchangeID,
            message: reason
        )
    }

    static func error(_ message: String) -> CardExchangeMessage {
        CardExchangeMessage(kind: .error, message: message)
    }
}
