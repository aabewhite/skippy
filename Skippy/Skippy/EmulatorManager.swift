import Foundation
import SwiftUI

struct DeviceProfile: Identifiable, Hashable {
    let id: String
    let name: String
}

struct APILevel: Identifiable, Hashable {
    let id: String
    let name: String
    let level: Int
}

@Observable
@MainActor
class EmulatorManager {
    var emulators: [String] = []
    var selectedEmulator: String?
    var deviceProfiles: [DeviceProfile] = []
    var apiLevels: [APILevel] = []
    var isCreating: Bool = false
    var createOutput: String = ""
    var createSucceeded: Bool = false
    var isLoadingList: Bool = false
    var isLoadingProfiles: Bool = false
    var isLoadingLevels: Bool = false
    var commandOutput: String = ""
    var listError: String?
    var profilesError: String?
    var levelsError: String?


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
                let output = try await runProcess(skip, arguments: ["android", "emulator", "list"])
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

    // MARK: - Device Profiles

    func loadDeviceProfiles() {
        guard let avdmanager = CommandFinder.findAvdmanager() else {
            profilesError = "Could not find avdmanager executable."
            return
        }

        isLoadingProfiles = true
        profilesError = nil

        Task {
            do {
                let output = try await runProcess(avdmanager, arguments: ["list", "device"])
                deviceProfiles = parseDeviceProfiles(output)
            } catch {
                profilesError = "Failed to load device profiles: \(error.localizedDescription)"
            }
            isLoadingProfiles = false
        }
    }

    // MARK: - API Levels

    func loadAPILevels() {
        guard let avdmanager = CommandFinder.findAvdmanager() else {
            levelsError = "Could not find avdmanager executable."
            return
        }

        isLoadingLevels = true
        levelsError = nil

        Task {
            do {
                let output = try await runProcess(avdmanager, arguments: ["list", "target"])
                apiLevels = ensureDefaultAPILevels(parseAPILevels(output))
            } catch {
                levelsError = "Failed to load API levels: \(error.localizedDescription)"
            }
            isLoadingLevels = false
        }
    }

    // MARK: - Create Emulator

    func createEmulator(name: String, deviceProfile: DeviceProfile, apiLevel: APILevel) {
        guard let skip = CommandFinder.findSkip() else {
            createOutput = "Error: Could not find skip executable."
            return
        }

        isCreating = true
        createSucceeded = false

        let arguments = [
            "android", "emulator", "create",
            "--name", name,
            "--device-profile", deviceProfile.id,
            "--android-api-level", String(apiLevel.level)
        ]

        createOutput = "$ \(formatCommandLine(skip.path, arguments: arguments))\n"

        Task {
            let success = await runProcessStreaming(skip, arguments: arguments)
            isCreating = false
            refreshEmulatorList()
            if success {
                createSucceeded = true
            }
        }
    }

    // MARK: - Delete Emulator

    func deleteEmulator(_ name: String) {
        guard let avdmanager = CommandFinder.findAvdmanager() else {
            listError = "Could not find avdmanager executable."
            return
        }

        let arguments = ["delete", "avd", "-n", name]
        appendCommand(avdmanager.path, arguments: arguments)

        Task {
            do {
                let output = try await runProcess(avdmanager, arguments: arguments)
                appendOutput(output)
                refreshEmulatorList()
            } catch {
                appendOutput(error.localizedDescription + "\n")
                listError = "Failed to delete emulator: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Launch Emulator

    func launchEmulator(_ name: String? = nil, showOutput: Bool = true) {
        guard let skip = CommandFinder.findSkip() else { return }

        var arguments = ["android", "emulator", "launch"]
        if let name {
            arguments += ["--name", name]
        }
        if showOutput {
            appendCommand(skip.path, arguments: arguments)
        }

        Task {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: skip.path)
            process.arguments = arguments
            process.environment = skip.environment
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
        }
    }

    // MARK: - Command Output Logging

    private func formatCommandLine(_ path: String, arguments: [String]) -> String {
        ([path] + arguments).map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
    }

    private func appendCommand(_ path: String, arguments: [String]) {
        commandOutput = "$ \(formatCommandLine(path, arguments: arguments))\n"
    }

    private func appendOutput(_ text: String) {
        commandOutput += text
        if !text.hasSuffix("\n") { commandOutput += "\n" }
    }

    // MARK: - Private Helpers

    private func runProcess(_ command: FoundCommand, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: command.path)
            process.arguments = arguments
            process.environment = command.environment
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            Task.detached {
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "EmulatorManager",
                        code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: output.isEmpty ? "Process exited with code \(process.terminationStatus)" : output]
                    ))
                }
            }
        }
    }

    private func runProcessStreaming(_ command: FoundCommand, arguments: [String]) async -> Bool {
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
                    self?.createOutput += output
                }
            }

            process.terminationHandler = { process in
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: process.terminationStatus == 0)
            }

            do {
                try process.run()
            } catch {
                Task { @MainActor [weak self] in
                    self?.createOutput += "Error: \(error.localizedDescription)\n"
                }
                continuation.resume(returning: false)
            }
        }
    }

    private func parseDeviceProfiles(_ output: String) -> [DeviceProfile] {
        var profiles: [DeviceProfile] = []
        var currentId: String?
        var currentName: String?

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("id:") {
                // Save previous profile if complete
                if let id = currentId, let name = currentName {
                    profiles.append(DeviceProfile(id: id, name: name))
                }
                currentId = extractQuoted(from: trimmed) ?? trimmed.replacingOccurrences(of: "id:", count: 1).trimmingCharacters(in: .whitespaces)
                currentName = nil
            } else if trimmed.hasPrefix("Name:") {
                currentName = trimmed.replacingOccurrences(of: "Name:", count: 1).trimmingCharacters(in: .whitespaces)
            }
        }

        // Don't forget the last one
        if let id = currentId, let name = currentName {
            profiles.append(DeviceProfile(id: id, name: name))
        }

        return profiles
    }

    private func parseAPILevels(_ output: String) -> [APILevel] {
        var levels: [APILevel] = []
        var currentId: String?
        var currentName: String?
        var currentLevel: Int?

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("id:") {
                // Save previous level if complete
                if let id = currentId, let name = currentName, let level = currentLevel {
                    levels.append(APILevel(id: id, name: name, level: level))
                }
                currentId = extractQuoted(from: trimmed) ?? trimmed.replacingOccurrences(of: "id:", count: 1).trimmingCharacters(in: .whitespaces)
                currentName = nil
                currentLevel = nil
            } else if trimmed.hasPrefix("Name:") {
                currentName = trimmed.replacingOccurrences(of: "Name:", count: 1).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("API level:") {
                let levelStr = trimmed.replacingOccurrences(of: "API level:", count: 1).trimmingCharacters(in: .whitespaces)
                currentLevel = Int(levelStr)
            }
        }

        if let id = currentId, let name = currentName, let level = currentLevel {
            levels.append(APILevel(id: id, name: name, level: level))
        }

        return levels
    }

    private static let defaultAPILevels = [33, 34, 35, 36]

    private func ensureDefaultAPILevels(_ parsed: [APILevel]) -> [APILevel] {
        let existingLevels = Set(parsed.map(\.level))
        var result = parsed
        for level in Self.defaultAPILevels where !existingLevels.contains(level) {
            result.append(APILevel(id: "android-\(level)", name: "Android API \(level)", level: level))
        }
        return result.sorted { $0.level < $1.level }
    }

    private func extractQuoted(from text: String) -> String? {
        guard let start = text.firstIndex(of: "\"") else { return nil }
        let afterStart = text.index(after: start)
        guard afterStart < text.endIndex, let end = text[afterStart...].firstIndex(of: "\"") else { return nil }
        return String(text[afterStart..<end])
    }
}

private extension String {
    func replacingOccurrences(of target: String, count: Int) -> String {
        guard let range = self.range(of: target) else { return self }
        return self.replacingCharacters(in: range, with: "")
    }
}
