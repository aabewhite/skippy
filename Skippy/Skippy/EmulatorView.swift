import SwiftUI

struct EmulatorView: View {
    @Environment(EmulatorManager.self) private var manager
    @Environment(\.openWindow) private var openWindow
    @AppStorage("fontSizeOffset") private var fontSizeOffset: Int = 0
    @State private var showDeleteConfirmation = false

    private static let baseFontSize: CGFloat = 11
    private var fontSize: CGFloat {
        max(6, min(30, Self.baseFontSize + CGFloat(fontSizeOffset)))
    }

    var body: some View {
        @Bindable var manager = manager

        VStack(spacing: 0) {
            Group {
                if let error = manager.listError {
                    ContentUnavailableView {
                        Label("Error", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    }
                } else if manager.emulators.isEmpty && !manager.isLoadingList {
                    ContentUnavailableView {
                        Label("No Emulators", systemImage: "iphone.slash")
                    } description: {
                        Text("Create an emulator to get started.")
                    } actions: {
                        Button("Create Emulator") {
                            openWindow(id: "newEmulator")
                        }
                    }
                } else {
                    List(manager.emulators, id: \.self, selection: $manager.selectedEmulator) { name in
                        Text(name)
                    }
                }
            }

            if !manager.commandOutput.isEmpty || manager.isCommandRunning {
                Divider()
                AnimatedCommandOutputView(text: manager.commandOutput, fontSize: fontSize, isExecuting: manager.isCommandRunning)
                    .frame(maxHeight: 200)
            }
        }
        .frame(minWidth: 500, minHeight: 200)
        .background(WindowFrameSaver(name: "emulatorsWindow"))
        .navigationTitle("Emulators")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    openWindow(id: "newEmulator")
                }) {
                    Label("Create", systemImage: "plus")
                }
            }

            ToolbarItem(placement: .automatic) {
                Button(action: {
                    manager.refreshEmulatorList()
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(manager.isLoadingList)
            }

            ToolbarItem(placement: .automatic) {
                Button(action: {
                    if let name = manager.selectedEmulator {
                        manager.launchEmulator(name)
                    }
                }) {
                    Label("Launch", systemImage: "play.fill")
                }
                .disabled(manager.selectedEmulator == nil)
            }

            ToolbarItem(placement: .automatic) {
                Button(action: {
                    showDeleteConfirmation = true
                }) {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(manager.selectedEmulator == nil)
            }
        }
        .confirmationDialog(
            "Delete Emulator",
            isPresented: $showDeleteConfirmation,
            presenting: manager.selectedEmulator
        ) { name in
            Button("Delete \"\(name)\"", role: .destructive) {
                manager.deleteEmulator(name)
            }
        } message: { name in
            Text("Are you sure you want to delete the emulator \"\(name)\"? This cannot be undone.")
        }
        .onAppear {
            manager.refreshEmulatorList()
        }
    }
}
