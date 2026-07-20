//
//  CardListSeeder.swift
//  Cardi
//

import SwiftData

@MainActor
enum CardListSeeder {
    static func seedIfNeeded(
        in modelContext: ModelContext,
        existingLists: [BusinessCardList]
    ) {
        guard existingLists.isEmpty else { return }

        for (index, name) in ["同学", "xx讲座", "招聘", "见面会"].enumerated() {
            modelContext.insert(BusinessCardList(name: name, sortOrder: index))
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
        }
    }
}
