//
//  CardExchangeMessage.swift
//  Carda
//

import Foundation

struct CardExchangeMessage: Codable {
    enum Kind: String, Codable {
        case nearbyToken
        case proximityConfirmed
        case card
        case ack
        case error
    }

    var kind: Kind
    var exchangeID: UUID?
    var nearbyTokenData: Data?
    var card: CardExchangePayload?
    var cardID: UUID?
    var message: String?

    static func nearbyToken(_ data: Data) -> CardExchangeMessage {
        CardExchangeMessage(kind: .nearbyToken, nearbyTokenData: data)
    }

    static func proximityConfirmed(exchangeID: UUID, cardID: UUID) -> CardExchangeMessage {
        CardExchangeMessage(
            kind: .proximityConfirmed,
            exchangeID: exchangeID,
            cardID: cardID
        )
    }

    static func card(_ payload: CardExchangePayload, exchangeID: UUID) -> CardExchangeMessage {
        CardExchangeMessage(
            kind: .card,
            exchangeID: exchangeID,
            card: payload
        )
    }

    static func ack(exchangeID: UUID) -> CardExchangeMessage {
        CardExchangeMessage(kind: .ack, exchangeID: exchangeID)
    }

    static func error(_ message: String) -> CardExchangeMessage {
        CardExchangeMessage(kind: .error, message: message)
    }
}
