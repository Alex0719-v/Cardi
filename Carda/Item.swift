//
//  Item.swift
//  Cardi
//
//  Created by Alex Lyn on 2026/6/7.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
