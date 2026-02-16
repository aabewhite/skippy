import Foundation

enum CheckupCommand: String {
    case doctor, checkup
}

@Observable
@MainActor
class CheckupManager {
    var commandOutput: String = ""
    var isRunning: Bool = false
    var logFilePath: String?

    func run(_ command: CheckupCommand) {
        guard let skip = CommandFinder.findSkip() else {
            commandOutput = "Error: Could not find skip executable.\n"
            return
        }

        let logFile = NSTemporaryDirectory() + "skippy-\(command.rawValue)-\(ProcessInfo.processInfo.globallyUniqueString).log"
        logFilePath = nil
        isRunning = true

        let arguments = [command.rawValue, "--native", "--log-file", logFile]
        commandOutput = "$ \(skip.formatCommandLine(arguments: arguments))\n"

        Task {
            await runCommandOutputStreaming(skip, arguments: arguments)
            logFilePath = logFile
            isRunning = false
        }
    }

    // MARK: - Private Helpers

    private func runCommandOutputStreaming(_ command: FoundCommand, arguments: [String]) async {
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
