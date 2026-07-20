//
//  BusinessCardList.swift
//  Cardi
//

import Foundation
import SwiftData

@Model
final class BusinessCardList {
    @Attribute(.unique) var id: UUID
    var name: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        sortOrder: Int,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
