//
//  ContentView.swift
//  Carda
//
//  Created by Alex Lyn on 2026/6/7.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        FigmaPhoneCanvas {
            AppShellView()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [BusinessCard.self, CardInfoField.self, Item.self], inMemory: true)
}
