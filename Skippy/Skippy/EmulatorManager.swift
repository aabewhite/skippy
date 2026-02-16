import Foundation
import SwiftUI

@Observable
@MainActor
class EmulatorManager {
    var emulators: [String] = []
    var selectedEmulator: String?
    var isLoadingList: Bool = false
    var commandOutput: String = ""
    var isCommandRunning: Bool = false
    var listError: String?
    var showDeviceAlreadyRunning: Bool = false

    // MARK: - Emulator List

    func refreshEmulatorList() {
        guard let skip = CommandFinder.findSkip() else {
            listError = "Could not find skip executable."
            return
        }

        isLoadingList = true
        listError = nil

        Task {
            do {
                let output = try await skip.run(arguments: ["android", "emulator", "list"])
                let names = output.split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                emulators = names
                if let selected = selectedEmulator, !names.contains(selected) {
                    selectedEmulator = nil
                }
            } catch {
                listError = "Failed to list emulators: \(error.localizedDescription)"
            }
            isLoadingList = false
        }
    }

    // MARK: - Delete Emulator

    func deleteEmulator(_ name: String) {
        guard let avdmanager = CommandFinder.findAvdmanager() else {
            listError = "Could not find avdmanager executable."
            return
        }

        let arguments = ["delete", "avd", "-n", name]
        appendCommand(avdmanager, arguments: arguments)
        isCommandRunning = true

        Task {
            do {
                let output = try await avdmanager.run(arguments: arguments)
                appendOutput(output)
                isCommandRunning = false
                refreshEmulatorList()
            } catch {
                appendOutput(error.localizedDescription + "\n")
                listError = "Failed to delete emulator: \(error.localizedDescription)"
                isCommandRunning = false
            }
        }
    }

    // MARK: - Launch Emulator

    func launchEmulator(_ name: String? = nil) {
        guard let skip = CommandFinder.findSkip() else { return }

        Task {
            if await isDeviceRunning() {
                showDeviceAlreadyRunning = true
                return
            }

            var arguments = ["android", "emulator", "launch", "--background"]
            if let name {
                arguments += ["--name", name]
            }

            appendCommand(skip, arguments: arguments)
            isCommandRunning = true
            await runCommandOutputStreaming(skip, arguments: arguments, timeout: .seconds(3))
            isCommandRunning = false
        }
    }

    private func isDeviceRunning() async -> Bool {
        guard let adb = CommandFinder.findAdb() else { return false }
        do {
            let output = try await adb.run(arguments: ["devices"])
            let devices = output.split(separator: "\n")
                .dropFirst() // skip "List of devices attached" header
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return !devices.isEmpty
        } catch {
            return false
        }
    }

    // MARK: - Command Output Logging

    private func appendCommand(_ command: FoundCommand, arguments: [String]) {
        commandOutput = "$ \(command.formatCommandLine(arguments: arguments))\n"
    }

    private func appendOutput(_ text: String) {
        commandOutput += text
        if !text.hasSuffix("\n") { commandOutput += "\n" }
    }

    // MARK: - Private Helpers

    private func runCommandOutputStreaming(_ command: FoundCommand, arguments: [String], timeout: Duration? = nil) async {
        let once = OnceFlag()
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: command.path)
            process.arguments = arguments
            process.environment = command.environment
            process.standardOutput = pipe
            process.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { [weak self] fileHandle in
                let data = fileHandle.availableData
                guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor [weak self] in
                    self?.commandOutput += output
                }
            }

            process.terminationHandler = { _ in
                pipe.fileHandleForReading.readabilityHandler = nil
                Task { @MainActor in
                    if once.tryFire() { continuation.resume() }
                }
            }

            do {
                try process.run()
            } catch {
                Task { @MainActor [weak self] in
                    self?.commandOutput += "Error: \(error.localizedDescription)\n"
                }
                if once.tryFire() { continuation.resume() }
                return
            }

            if let timeout {
                Task {
                    try? await Task.sleep(for: timeout)
                    pipe.fileHandleForReading.readabilityHandler = nil
                    if once.tryFire() { continuation.resume() }
                }
            }
        }
    }
}

/// Thread-safe flag ensuring a one-shot action fires exactly once.
private final class OnceFlag: @unchecked Sendable {
    private var fired = false
    private let lock = NSLock()

    func tryFire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}
