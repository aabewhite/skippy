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
    @FocusedValue(\.searchCommands) private var searchCommands
    @State private var emulatorManager = EmulatorManager()
    @State private var showNoEmulatorAlert = false

    init() {
        // Prevent macOS from restoring secondary windows (e.g. Logcat) on relaunch
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .alert("No Emulators", isPresented: $showNoEmulatorAlert) {
                    Button("Manage Emulators...") {
                        openWindow(id: "emulators")
                    }
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("No emulators are available. Create one in the Emulators window.")
                }
        }
        .commands {
            CommandMenu("Debug") {
                Button("Logcat") {
                    openWindow(id: "logcat")
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }

            CommandMenu("Emulator") {
                Button("Manage Emulators...") {
                    openWindow(id: "emulators")
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("Launch") {
                    if !emulatorManager.launchLastUsedEmulator() {
                        showNoEmulatorAlert = true
                    }
                }
            }

            CommandGroup(after: .pasteboard) {
                Menu("Find") {
                    Button("Find...") {
                        searchCommands?.activate()
                    }
                    .keyboardShortcut("f", modifiers: .command)
                    .disabled(searchCommands == nil)

                    Button("Find Next") {
                        searchCommands?.next()
                    }
                    .keyboardShortcut("g", modifiers: .command)
                    .disabled(searchCommands?.hasMatches != true)

                    Button("Find Previous") {
                        searchCommands?.previous()
                    }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(searchCommands?.hasMatches != true)
                }
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

        WindowGroup("Emulators", id: "emulators") {
            EmulatorView()
                .environment(emulatorManager)
        }
        .defaultSize(width: 400, height: 300)

        WindowGroup("New Emulator", id: "newEmulator") {
            NewEmulatorView()
                .environment(emulatorManager)
        }
        .defaultSize(width: 550, height: 500)

        Settings {
            SettingsView()
        }
    }
}
