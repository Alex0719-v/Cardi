//
//  CardiApp.swift
//  Cardi
//
//  Created by Alex Lyn on 2026/6/7.
//

import SwiftUI
import SwiftData

@main
struct CardiApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            BusinessCard.self,
            BusinessCardList.self,
            CardInfoField.self,
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
