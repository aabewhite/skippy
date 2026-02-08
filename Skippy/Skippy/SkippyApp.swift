//
//  SkippyApp.swift
//  Skippy
//
//  Created by Abe White on 2/7/26.
//

import SwiftUI

@main
struct SkippyApp: App {
    @Environment(\.openWindow) private var openWindow
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(before: .windowList) {
                Button("Logcat") {
                    openWindow(id: "logcat")
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                
                Divider()
            }
        }
        
        WindowGroup("Logcat", id: "logcat") {
            LogcatView()
        }
        .defaultSize(width: 800, height: 600)
        
        Settings {
            SettingsView()
        }
    }
}
