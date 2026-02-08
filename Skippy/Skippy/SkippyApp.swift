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
    @AppStorage("fontSizeOffset") private var fontSizeOffset: Int = 0

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

            CommandGroup(after: .toolbar) {
                Section {
                    Button("Make Text Bigger") {
                        fontSizeOffset += 1
                    }
                    .keyboardShortcut("+", modifiers: .command)

                    Button("Make Text Normal Size") {
                        fontSizeOffset = 0
                    }
                    .keyboardShortcut("0", modifiers: [.command, .option])

                    Button("Make Text Smaller") {
                        fontSizeOffset -= 1
                    }
                    .keyboardShortcut("-", modifiers: .command)
                }
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
