//
//  UnstuckApp.swift
//  Unstuck
//
//  Created byDeniz MacBook on 30.05.2026.
//

import SwiftUI
import SwiftData
import AppIntents

@main
struct UnstuckApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Cluster.self,
            BrainItem.self,
            CoachingNote.self,
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
                .onAppear {
                    // Register Action Button shortcut so it appears in Settings → Action Button
                    UnstuckShortcuts.updateAppShortcutParameters()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
