//
//  CardBackgroundTemplate.swift
//  Cardi
//

import Foundation

enum CardBackgroundTemplate: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case color1
    case color2
    case color3

    var id: String { rawValue }

    var resourceName: String {
        switch self {
        case .color1:
            "Group 42"
        case .color2:
            "color2"
        case .color3:
            "color3"
        }
    }

    var accessibilityName: String {
        switch self {
        case .color1:
            "名片底图一"
        case .color2:
            "名片底图二"
        case .color3:
            "名片底图三"
        }
    }
}
