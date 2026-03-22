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
    private static let uiTestingLaunchArgument = "UI_TESTING"

    var sharedModelContainer: ModelContainer = {
        let isUITesting = ProcessInfo.processInfo.arguments.contains(uiTestingLaunchArgument)
        let schema = Schema([
            MosaicCollection.self,
            MosaicTile.self,
            FieldDefinition.self,
            FieldValue.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITesting)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        if ProcessInfo.processInfo.arguments.contains(Self.uiTestingLaunchArgument) {
            UserDefaults.standard.removeObject(forKey: "hasSeededDefaultCollections")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
