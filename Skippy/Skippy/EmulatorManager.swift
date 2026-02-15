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
    var isLoadingList: Bool = false
    var isLoadingProfiles: Bool = false
    var isLoadingLevels: Bool = false
    var listError: String?
    var profilesError: String?
    var levelsError: String?

    @ObservationIgnored
    @AppStorage("lastUsedEmulator") private var lastUsedEmulator: String = ""

    // MARK: - Emulator List

    func refreshEmulatorList() {
        guard let skipPath = CommandFinder.findSkip() else {
            listError = "Could not find skip executable."
            return
        }

        isLoadingList = true
        listError = nil

        Task {
            do {
                let output = try await runProcess(skipPath, arguments: ["android", "emulator", "list"])
                let names = output.split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                emulators = names
                // Clear selection if the selected emulator was deleted
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
        guard let avdmanagerPath = CommandFinder.findAvdmanager() else {
            profilesError = "Could not find avdmanager executable."
            return
        }

        isLoadingProfiles = true
        profilesError = nil

        Task {
            do {
                let output = try await runProcess(avdmanagerPath, arguments: ["list", "device"])
                deviceProfiles = parseDeviceProfiles(output)
            } catch {
                profilesError = "Failed to load device profiles: \(error.localizedDescription)"
            }
            isLoadingProfiles = false
        }
    }

    // MARK: - API Levels

    func loadAPILevels() {
        guard let avdmanagerPath = CommandFinder.findAvdmanager() else {
            levelsError = "Could not find avdmanager executable."
            return
        }

        isLoadingLevels = true
        levelsError = nil

        Task {
            do {
                let output = try await runProcess(avdmanagerPath, arguments: ["list", "target"])
                apiLevels = parseAPILevels(output)
            } catch {
                levelsError = "Failed to load API levels: \(error.localizedDescription)"
            }
            isLoadingLevels = false
        }
    }

    // MARK: - Create Emulator

    func createEmulator(name: String, deviceProfile: DeviceProfile, apiLevel: APILevel) {
        guard let skipPath = CommandFinder.findSkip() else {
            createOutput = "Error: Could not find skip executable."
            return
        }

        isCreating = true

        let arguments = [
            "android", "emulator", "create",
            "--name", name,
            "--device-profile", deviceProfile.id,
            "--android-api-level", String(apiLevel.level)
        ]

        let commandLine = ([skipPath] + arguments).map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
        createOutput = "$ \(commandLine)\n"

        Task {
            await runProcessStreaming(skipPath, arguments: arguments)
            isCreating = false
            refreshEmulatorList()
        }
    }

    // MARK: - Delete Emulator

    func deleteEmulator(_ name: String) {
        guard let avdmanagerPath = CommandFinder.findAvdmanager() else {
            listError = "Could not find avdmanager executable."
            return
        }

        Task {
            do {
                _ = try await runProcess(avdmanagerPath, arguments: ["delete", "avd", "-n", name])
                refreshEmulatorList()
            } catch {
                listError = "Failed to delete emulator: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Launch Emulator

    func launchEmulator(_ name: String) {
        guard let skipPath = CommandFinder.findSkip() else { return }

        lastUsedEmulator = name

        Task {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: skipPath)
            process.arguments = ["android", "emulator", "launch", "--name", name]
            process.environment = Self.processEnvironment
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
        }
    }

    func launchLastUsedEmulator() -> Bool {
        guard !lastUsedEmulator.isEmpty, emulators.contains(lastUsedEmulator) else {
            return false
        }
        launchEmulator(lastUsedEmulator)
        return true
    }

    // MARK: - Private Helpers

    private static let processEnvironment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = CommandFinder.toolPATH
        return env
    }()

    private func runProcess(_ path: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.environment = Self.processEnvironment
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

    private func runProcessStreaming(_ path: String, arguments: [String]) async {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.environment = Self.processEnvironment
            process.standardOutput = pipe
            process.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { [weak self] fileHandle in
                let data = fileHandle.availableData
                guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor [weak self] in
                    self?.createOutput += output
                }
            }

            process.terminationHandler = { _ in
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume()
            }

            do {
                try process.run()
            } catch {
                Task { @MainActor [weak self] in
                    self?.createOutput += "Error: \(error.localizedDescription)\n"
                }
                continuation.resume()
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
