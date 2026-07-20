//
//  PreviouslyImportedCardCleanup.swift
//  Cardi
//

import Foundation
import SwiftData

@MainActor
enum PreviouslyImportedCardCleanup {
    private static let importedPhoneNumbers = Set(
        (1...30).map { String(format: "1380001%04d", $0) }
    )

    @discardableResult
    static func removeFromCurrentDatabase(in modelContext: ModelContext) throws -> Int {
        let cards = try modelContext.fetch(FetchDescriptor<BusinessCard>())
        let importedCards = cards.filter(isPreviouslyImportedSample)
        guard !importedCards.isEmpty else { return 0 }

        for card in importedCards {
            modelContext.delete(card)
        }
        do {
            try modelContext.save()
            return importedCards.count
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    static func isPreviouslyImportedSample(
        ownerKind: CardOwnerKind,
        phoneValues: [String]
    ) -> Bool {
        guard ownerKind == .received else { return false }
        return phoneValues.contains { value in
            importedPhoneNumbers.contains(PhoneNumberFormatter.digits(in: value))
        }
    }

    private static func isPreviouslyImportedSample(_ card: BusinessCard) -> Bool {
        isPreviouslyImportedSample(
            ownerKind: card.ownerKind,
            phoneValues: card.fields
                .filter { $0.kind == .phone }
                .map(\.value)
        )
    }
}
