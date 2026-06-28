//
//  VeloxApp.swift
//  Velox
//
//  Created by yangxy on 2026/6/28.
//

import SwiftUI

@main
struct VeloxApp: App {
    @NSApplicationDelegateAdaptor(VeloxAppDelegate.self) private var appDelegate
    @StateObject private var settings = VeloxSettings.shared

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(settings)
        }
        .commands {
            VeloxCommands()
        }
    }
}
