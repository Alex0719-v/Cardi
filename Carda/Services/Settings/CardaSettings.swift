//
//  CardaSettings.swift
//  Cardi
//

import Foundation
import SwiftUI

private struct CardaReduceMotionEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var cardaReduceMotion: Bool {
        get { self[CardaReduceMotionEnvironmentKey.self] }
        set { self[CardaReduceMotionEnvironmentKey.self] = newValue }
    }
}

enum CardaSettingsPreferenceKeys {
    static let allowsNearbyDiscovery = "settings.exchange.allowsNearbyDiscovery"
    static let confirmsIncomingCards = "settings.exchange.confirmsIncomingCards"
    static let exchangeHaptics = "settings.exchange.haptics"
    static let exchangeSound = "settings.exchange.sound"
    static let defaultReceivedListID = "settings.cards.defaultReceivedListID"
    static let defaultCardSort = "settings.cards.defaultSort"
    static let duplicatePolicy = "settings.cards.duplicatePolicy"
    static let confirmsCardDeletion = "settings.cards.confirmsDeletion"
    static let interactionHaptics = "settings.interaction.haptics"
    static let interactionSound = "settings.interaction.sound"
    static let motionPreference = "settings.interaction.motionPreference"
    static let followsSystemFontSize = "settings.interaction.followsSystemFontSize"
    static let allowsCardPaging = "settings.interaction.allowsCardPaging"

    static let allKeys = [
        allowsNearbyDiscovery,
        confirmsIncomingCards,
        exchangeHaptics,
        exchangeSound,
        defaultReceivedListID,
        defaultCardSort,
        duplicatePolicy,
        confirmsCardDeletion,
        interactionHaptics,
        interactionSound,
        motionPreference,
        followsSystemFontSize,
        allowsCardPaging
    ]

    static func reset(in defaults: UserDefaults = .standard) {
        for key in allKeys {
            defaults.removeObject(forKey: key)
        }
    }
}

enum CardaDefaultCardSort: String, CaseIterable, Identifiable {
    case recent
    case name
    case organization

    static let defaultValue: Self = .name

    var id: Self { self }

    var title: String {
        switch self {
        case .recent:
            "最近添加"
        case .name:
            "姓名"
        case .organization:
            "公司"
        }
    }
}

enum CardaDuplicateCardPolicy: String, CaseIterable, Identifiable {
    case ask
    case replace
    case keepBoth

    var id: Self { self }

    var title: String {
        switch self {
        case .ask:
            "询问"
        case .replace:
            "覆盖原名片"
        case .keepBoth:
            "保留两张"
        }
    }
}

enum CardaMotionPreference: String, CaseIterable, Identifiable {
    case followSystem
    case reduce

    var id: Self { self }

    var title: String {
        switch self {
        case .followSystem:
            "跟随系统"
        case .reduce:
            "减少动画"
        }
    }
}
