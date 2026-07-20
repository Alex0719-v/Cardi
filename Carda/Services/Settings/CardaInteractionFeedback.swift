//
//  CardaInteractionFeedback.swift
//  Cardi
//

import AudioToolbox
import UIKit

@MainActor
enum CardaInteractionFeedback {
    static func incomingCard(haptics: Bool, sound: Bool) {
        if haptics {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        if sound {
            AudioServicesPlaySystemSound(1103)
        }
    }

    static func targetLocked(haptics: Bool) {
        guard haptics else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func exchangeSucceeded(isMutual: Bool, haptics: Bool, sound: Bool) {
        if haptics {
            if isMutual {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred(intensity: 0.85)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    generator.impactOccurred(intensity: 0.85)
                }
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
        if sound {
            AudioServicesPlaySystemSound(isMutual ? 1105 : 1104)
        }
    }

    static func softImpact(enabled: Bool) {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
    }
}
