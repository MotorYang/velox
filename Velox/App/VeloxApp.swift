//
//  VeloxApp.swift
//  Velox
//
//  Created by yangxy on 2026/6/28.
//

import SwiftUI

@main
struct VeloxApp: App {
    @StateObject private var settings = VeloxSettings.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
        }
        .commands {
            VeloxCommands()
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
        }
    }
}
