//
//  MosaicApp.swift
//  Mosaic
//
//  Created by Jonathan Gaytan on 3/21/26.
//

import SwiftUI
import SwiftData

@main
struct MosaicApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            MosaicCollection.self,
            MosaicTile.self,
            FieldDefinition.self,
            FieldValue.self,
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
