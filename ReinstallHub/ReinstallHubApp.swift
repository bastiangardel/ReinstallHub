//
//  ReinstallHubApp.swift
//  ReinstallHub
//
//  Created by Bastian Gardel on 11.11.2024.
//

import SwiftUI

@main
struct ReinstallHubApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
