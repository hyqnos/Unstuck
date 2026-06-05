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

        // Preferred: the real on-disk store.
        let persistent = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        if let container = try? ModelContainer(for: schema, configurations: [persistent]) {
            return container
        }

        // Persistent store failed — almost always a failed migration (a changed @Model
        // between builds) or a corrupt store. Crashing on launch would lock the user out
        // PERMANENTLY (a brick, not a bug). Far better: open on a fresh in-memory store so
        // the app still works this session. They lose old local data, not the whole app.
        if let memory = try? ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ) {
            return memory
        }

        // Truly impossible (the schema itself is invalid) — keep a last-resort crash with context.
        fatalError("Could not create any ModelContainer for schema: \(schema)")
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
