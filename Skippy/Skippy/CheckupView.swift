import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CheckupView: View {
    let command: CheckupCommand

    @State private var manager = CheckupManager()
    @AppStorage("fontSizeOffset") private var fontSizeOffset: Int = 0

    private static let baseFontSize: CGFloat = 11
    private var fontSize: CGFloat {
        max(6, min(30, Self.baseFontSize + CGFloat(fontSizeOffset)))
    }

    var body: some View {
        AnimatedCommandOutputView(
            text: manager.commandOutput,
            fontSize: fontSize,
            isExecuting: manager.isRunning,
            colorizeCheckupLines: true,
            logFileURL: manager.isRunning ? nil : manager.logFilePath.map { URL(fileURLWithPath: $0) }
        )
        .frame(minWidth: 600, minHeight: 400)
        .background(WindowFrameSaver(name: "\(command.rawValue)Window"))
        .navigationTitle(command == .doctor ? "Doctor" : "Checkup")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: copyOutput) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }

            ToolbarItem(placement: .automatic) {
                Button(action: saveOutput) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
            }
        }
        .onAppear {
            manager.run(command)
        }
    }

    private func copyOutput() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(manager.commandOutput, forType: .string)
    }

    private func saveOutput() {
        let text = manager.commandOutput
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(command.rawValue).txt"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
