import Foundation

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
class CreateEmulatorManager {
    var deviceProfiles: [DeviceProfile] = []
    var apiLevels: [APILevel] = []
    var isCreating: Bool = false
    var createOutput: String = ""
    var createSucceeded: Bool = false
    var isLoadingProfiles: Bool = false
    var isLoadingLevels: Bool = false
    var profilesError: String?
    var levelsError: String?

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
                let output = try await avdmanager.run(arguments: ["list", "device"])
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
                let output = try await avdmanager.run(arguments: ["list", "target"])
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

        createOutput = "$ \(skip.formatCommandLine(arguments: arguments))\n"

        Task {
            let success = await runProcessStreaming(skip, arguments: arguments)
            isCreating = false
            if success {
                createSucceeded = true
            }
        }
    }

    // MARK: - Private Helpers

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
                if let id = currentId, let name = currentName {
                    profiles.append(DeviceProfile(id: id, name: name))
                }
                currentId = extractQuoted(from: trimmed) ?? trimmed.replacingOccurrences(of: "id:", count: 1).trimmingCharacters(in: .whitespaces)
                currentName = nil
            } else if trimmed.hasPrefix("Name:") {
                currentName = trimmed.replacingOccurrences(of: "Name:", count: 1).trimmingCharacters(in: .whitespaces)
            }
        }

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
