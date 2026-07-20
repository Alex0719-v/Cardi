//
//  ContentView.swift
//  Cardi
//
//  Created by Alex Lyn on 2026/6/7.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.dynamicTypeSize) private var systemDynamicTypeSize
    @AppStorage(CardaSettingsPreferenceKeys.motionPreference)
    private var motionPreferenceRawValue = CardaMotionPreference.followSystem.rawValue
    @AppStorage(CardaSettingsPreferenceKeys.followsSystemFontSize)
    private var followsSystemFontSize = true

    var body: some View {
        FigmaPhoneCanvas {
            AppShellView()
        }
        .environment(\.cardaReduceMotion, prefersReducedMotion)
        .environment(\.dynamicTypeSize, appliedDynamicTypeSize)
        .preferredColorScheme(.light)
    }

    private var prefersReducedMotion: Bool {
        CardaMotionPreference(rawValue: motionPreferenceRawValue) == .reduce
    }

    private var appliedDynamicTypeSize: DynamicTypeSize {
        followsSystemFontSize ? systemDynamicTypeSize : .large
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [BusinessCard.self, CardInfoField.self, Item.self], inMemory: true)
}
