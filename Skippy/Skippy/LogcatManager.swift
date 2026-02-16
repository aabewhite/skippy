import SwiftUI
import AppKit

/// Observable Logcat monitor.
@Observable
@MainActor
class LogcatManager {
    private(set) var entries: [LogcatEntry] = []
    var errorMessage: String?
    var isAtBottom: Bool = true {
        didSet {
            if isAtBottom != oldValue {
                handlePreservationStateChange()
            }
        }
    }
    var isSearchActive: Bool = false {
        didSet {
            if isSearchActive != oldValue {
                handlePreservationStateChange()
            }
        }
    }

    private var shouldPreserveBuffer: Bool { !isAtBottom || isSearchActive }

    @ObservationIgnored
    private var process: Process?
    @ObservationIgnored
    private var outputPipe: Pipe?
    @ObservationIgnored
    private var partialLine: String = ""  // For incomplete lines from stream
    @ObservationIgnored
    private var isPaused = false

    @ObservationIgnored
    @AppStorage("logcatBufferSize") private var normalMaxEntries: Int = 4000
    private let pausedMaxEntries = 20_000

    func startLogcat() {
        // Find adb executable path
        guard let adb = CommandFinder.findAdb() else {
            self.errorMessage = "Error: Could not find adb executable."
            return
        }
        isPaused = false

        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: adb.path)
        process.arguments = ["logcat"]
        process.environment = adb.environment
        process.standardOutput = pipe
        process.standardError = pipe

        self.process = process
        self.outputPipe = pipe

        // Read output asynchronously
        pipe.fileHandleForReading.readabilityHandler = { [weak self] fileHandle in
            let data = fileHandle.availableData
            if data.isEmpty {
                return
            }

            if let output = String(data: data, encoding: .utf8) {
                Task { @MainActor [weak self] in
                    self?.appendOutput(output)
                }
            }
        }

        do {
            try process.run()
        } catch {
            self.errorMessage = "Error starting adb logcat: \(error.localizedDescription)\nADB path used: \(adb.path)\nMake sure adb is properly installed."
        }
    }

    func stopLogcat() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
        outputPipe = nil
    }

    func clearLog() {
        entries.removeAll()
        partialLine = ""
        errorMessage = nil
    }

    private func handlePreservationStateChange() {
        if !shouldPreserveBuffer {
            // No longer need to preserve — resume if paused
            if isPaused {
                isPaused = false

                // Reset buffer to normal size and trim if needed
                if entries.count > normalMaxEntries {
                    entries = Array(entries.suffix(normalMaxEntries))
                }

                startLogcat()
            }
        } else {
            // Need to preserve buffer
            // If buffer is already full, pause immediately
            if !isPaused && entries.count >= pausedMaxEntries {
                isPaused = true
                stopLogcat()
            }
        }
    }

    private func appendOutput(_ output: String) {
        // If we're paused, ignore new output
        if isPaused {
            return
        }

        // Combine with any partial line from previous read
        let fullOutput = partialLine + output
        let lines = fullOutput.split(separator: "\n", omittingEmptySubsequences: false)

        // Check if output ends with newline
        if output.hasSuffix("\n") {
            partialLine = ""
        } else {
            // Last line is incomplete, save for next read
            partialLine = String(lines.last ?? "")
        }

        // Process complete lines
        let completeLines = output.hasSuffix("\n") ? lines : lines.dropLast()

        for line in completeLines {
            let lineStr = String(line)

            if LogcatEntry.isLogcatLine(lineStr) {
                // Start of new entry
                entries.append(LogcatEntry(text: lineStr))
            } else if let lastEntry = entries.last, !lineStr.isEmpty {
                // Continuation of previous entry
                entries[entries.count - 1] = LogcatEntry(text: lastEntry.rawText + "\n" + lineStr)
            }
        }

        // Trim if needed (only when not preserving buffer).
        // We don't trim while preserving because the visible text will jump around.
        if !shouldPreserveBuffer && entries.count > normalMaxEntries {
            let entriesToRemove = entries.count - normalMaxEntries
            entries.removeFirst(entriesToRemove)
        } else if shouldPreserveBuffer && entries.count >= pausedMaxEntries {
            // Buffer is full while preserving - pause listening
            isPaused = true
            outputPipe?.fileHandleForReading.readabilityHandler = nil
        }
    }

}

/// Represents a single logcat entry.
struct LogcatEntry {
    let rawText: String  // May contain multiple lines
    let level: Level?

    enum Level: String, CaseIterable, Comparable {
        case silent = "S"
        case verbose = "V"
        case debug = "D"
        case info = "I"
        case warning = "W"
        case error = "E"
        case fatal = "F"

        var displayName: String {
            switch self {
            case .silent: return "Silent"
            case .verbose: return "Verbose"
            case .debug: return "Debug"
            case .info: return "Info"
            case .warning: return "Warning"
            case .error: return "Error"
            case .fatal: return "Fatal"
            }
        }

        var color: NSColor {
            switch self {
            case .silent: return .clear
            case .verbose: return .systemBlue
            case .debug: return .systemGreen
            case .info: return .labelColor
            case .warning: return .systemOrange
            case .error: return .systemRed
            case .fatal: return .systemPurple
            }
        }

        var priority: Int {
            switch self {
            case .silent: return 0
            case .verbose: return 1
            case .debug: return 2
            case .info: return 3
            case .warning: return 4
            case .error: return 5
            case .fatal: return 6
            }
        }

        static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.priority < rhs.priority
        }
    }

    /// Regular expression pattern to match logcat format
    /// Example: "02-07 23:48:36.411 10115 10119 I artd    : message"
    static let logcatPattern = #"^\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d{3}\s+\d+\s+\d+\s+([VDIWEFS])\s"#
    static let logcatRegex = try? NSRegularExpression(pattern: logcatPattern, options: .anchorsMatchLines)

    init(text: String) {
        self.rawText = text
        self.level = Self.parseLevel(from: text)
    }

    private static func parseLevel(from text: String) -> Level? {
        // Parse the first line to get the level
        guard let firstLine = text.split(separator: "\n", maxSplits: 1).first,
              let regex = logcatRegex,
              let match = regex.firstMatch(in: String(firstLine), range: NSRange(location: 0, length: firstLine.utf16.count)),
              match.numberOfRanges >= 2 else {
            return nil
        }

        let levelRange = match.range(at: 1)
        guard let range = Range(levelRange, in: String(firstLine)) else {
            return nil
        }

        let levelString = String(String(firstLine)[range])
        return Level(rawValue: levelString)
    }

    /// Parse text into log entries (handling multi-line entries)
    static func parseEntries(from text: String) -> [LogcatEntry] {
        var entries: [LogcatEntry] = []
        var currentEntry = ""

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)

        for line in lines {
            let lineStr = String(line)

            // Check if this line starts a new log entry
            if isLogcatLine(lineStr) {
                // Save previous entry if it exists
                if !currentEntry.isEmpty {
                    entries.append(LogcatEntry(text: currentEntry))
                }
                currentEntry = lineStr
            } else {
                // Continuation of previous entry
                if !currentEntry.isEmpty {
                    currentEntry += "\n" + lineStr
                }
            }
        }

        // Don't forget the last entry
        if !currentEntry.isEmpty {
            entries.append(LogcatEntry(text: currentEntry))
        }

        return entries
    }

    /// Check if a line starts a new logcat entry
    static func isLogcatLine(_ line: String) -> Bool {
        guard let regex = logcatRegex else { return false }
        return regex.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) != nil
    }

    /// Returns true if this entry matches the logcat format
    var isLogcatFormat: Bool {
        level != nil
    }
}
