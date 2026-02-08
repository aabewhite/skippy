import SwiftUI
import AppKit

/// Displays the tail of `adb logcat`.
struct LogcatView: View {
    @State private var logcatManager = LogcatManager()
    @AppStorage("logcatMinLevel") private var minLevel: String = "V"
    @State private var filterText: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            if let error = logcatManager.errorMessage {
                Text(error)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.red)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LogcatScrollView(
                    entries: logcatManager.entries,
                    isAtBottom: $logcatManager.isAtBottom,
                    minLevel: minLevel,
                    filterText: filterText
                )
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .navigationTitle("Logcat")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                TextField("Filter", text: $filterText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }

            ToolbarItem(placement: .automatic) {
                Picker("", selection: $minLevel) {
                    ForEach(LogcatEntry.Level.allCases, id: \.rawValue) { level in
                        Text(level.displayName).tag(level.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)
            }
            
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    logcatManager.clearLog()
                }) {
                    Label("Clear", systemImage: "trash")
                }
            }
        }
        .onAppear {
            logcatManager.startLogcat()
        }
        .onDisappear {
            logcatManager.stopLogcat()
        }
    }
}

private struct LogcatScrollView: NSViewRepresentable {
    let entries: [LogcatEntry]
    @Binding var isAtBottom: Bool
    let minLevel: String
    let filterText: String
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        
        // Configure text view
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.backgroundColor = NSColor.textBackgroundColor
        
        // Configure scroll view
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        
        // Track scroll position changes
        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak scrollView] _ in
            guard let scrollView = scrollView else { return }
            context.coordinator.updateScrollPosition(scrollView: scrollView, isAtBotomBinding: $isAtBottom)
        }
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        guard let layoutManager = textView.layoutManager else { return }
        guard let textStorage = textView.textStorage else { return }
        
        // Filter and colorize entries based on minimum log level
        let filtered = filterEntries(entries, minLevel: minLevel, filterText: filterText)
        let attributedString = colorizeEntries(filtered)
        
        // Update text storage
        textStorage.setAttributedString(attributedString)
        
        // If we're at bottom, scroll to show new content
        if isAtBottom {
            layoutManager.ensureLayout(for: textView.textContainer!)
            textView.scrollToEndOfDocument(nil)
        }
        // Otherwise don't adjust scroll - user is reading old content
    }
    
    private func filterEntries(_ entries: [LogcatEntry], minLevel: String, filterText: String) -> [LogcatEntry] {
        let minLogLevel = LogcatEntry.Level(rawValue: minLevel)
        let searchText = filterText.trimmingCharacters(in: .whitespaces)
        return entries.filter { entry in
            if let minLogLevel, let level = entry.level {
                guard level >= minLogLevel else { return false }
            } else if minLogLevel != nil {
                return false
            }
            if !searchText.isEmpty {
                guard entry.rawText.localizedCaseInsensitiveContains(searchText) else { return false }
            }
            return true
        }
    }

    private func colorizeEntries(_ entries: [LogcatEntry]) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let result = NSMutableAttributedString()

        for (index, entry) in entries.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n"))
            }
            let color = entry.level?.color ?? NSColor.labelColor
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            result.append(NSAttributedString(string: entry.rawText, attributes: attrs))
        }

        return result
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        func updateScrollPosition(scrollView: NSScrollView, isAtBotomBinding: Binding<Bool>) {
            guard let textView = scrollView.documentView else { return }
            
            let visibleRect = scrollView.contentView.bounds
            let textHeight = textView.bounds.height
            let scrollPosition = visibleRect.origin.y + visibleRect.height
            
            // Consider "at bottom" if within 10 points of the bottom
            let atBottom = textHeight - scrollPosition < 10
            
            if isAtBotomBinding.wrappedValue != atBottom {
                isAtBotomBinding.wrappedValue = atBottom
            }
        }
    }
}

/// Observable Logcat monitor.
@Observable
@MainActor
class LogcatManager {
    private(set) var entries: [LogcatEntry] = []
    var errorMessage: String?
    var isAtBottom: Bool = true {
        didSet {
            if isAtBottom != oldValue {
                handleScrollPositionChange()
            }
        }
    }

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
        guard let adbPath = findAdb() else {
            self.errorMessage = "Error: Could not find adb executable."
            return
        }
        isPaused = false

        let process = Process()
        let pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: adbPath)
        process.arguments = ["logcat"]
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
            self.errorMessage = "Error starting adb logcat: \(error.localizedDescription)\nADB path used: \(adbPath)\nMake sure adb is properly installed."
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

    private func handleScrollPositionChange() {
        if isAtBottom {
            // User scrolled back to bottom
            if isPaused {
                isPaused = false

                // Restart the process and reset to normal buffer size
                // Reset buffer to normal size and trim if needed
                if entries.count > normalMaxEntries {
                    entries = Array(entries.suffix(normalMaxEntries))
                }

                startLogcat()
            }
        } else {
            // User scrolled away from bottom
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
        
        // Trim if needed (only when at bottom). We don't trim while not at
        // bottom because the visible text will jump around.
        if isAtBottom && entries.count > normalMaxEntries {
            let entriesToRemove = entries.count - normalMaxEntries
            entries.removeFirst(entriesToRemove)
        } else if !isAtBottom && entries.count >= pausedMaxEntries {
            // Buffer is full while not at bottom - pause listening
            isPaused = true
            outputPipe?.fileHandleForReading.readabilityHandler = nil
        }
    }

    private func findAdb() -> String? {
        // First, try using the user's login shell to find adb
        // This will pick up PATH settings from .zshrc, .bash_profile, etc.
        if let shellPath = findAdbViaShell() {
            return shellPath
        }
        
        // Check common installation paths
        let commonPaths = [
            "/opt/homebrew/bin/adb",  // Apple Silicon Homebrew
            "/usr/local/bin/adb",      // Intel Homebrew
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb",
            "\(NSHomeDirectory())/Android/sdk/platform-tools/adb",
            "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/adb"
        ]

        for path in commonPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        
        // Last resort: check if app's environment has ANDROID_HOME set
        // (This will only work if the app was launched from a terminal with the variable set)
        if let androidHome = ProcessInfo.processInfo.environment["ANDROID_HOME"] ??
                             ProcessInfo.processInfo.environment["ANDROID_SDK_ROOT"] {
            let adbPath = "\(androidHome)/platform-tools/adb"
            if FileManager.default.isExecutableFile(atPath: adbPath) {
                return adbPath
            }
        }

        return nil
    }

    private func findAdbViaShell() -> String? {
        let process = Process()
        let pipe = Pipe()
        
        // Use the user's login shell to get their full environment
        // Try zsh first (default on modern macOS), then bash
        let shell = FileManager.default.fileExists(atPath: "\(NSHomeDirectory())/.zshrc") 
            ? "/bin/zsh" 
            : "/bin/bash"
        
        process.executableURL = URL(fileURLWithPath: shell)
        // -l = login shell (loads profile), -c = execute command
        process.arguments = ["-l", "-c", "which adb 2>/dev/null"]
        process.standardOutput = pipe
        process.standardError = Pipe() // Suppress errors

        try? process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Verify the path actually exists and is executable
        if let path = path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        
        return nil
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


#Preview {
    LogcatView()
}
