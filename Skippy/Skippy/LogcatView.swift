import SwiftUI
import AppKit

/// Displays the tail of `adb logcat`.
struct LogcatView: View {
    @State private var logcatManager = LogcatManager()
    @AppStorage("logcatMinLevel") private var minLevel: String = "V"
    
    var body: some View {
        VStack(spacing: 0) {
            // Filter control
            HStack {
                Text("Min Level:")
                    .font(.system(size: 11))
                
                Picker("", selection: $minLevel) {
                    Text("Silent").tag("S")
                    Text("Verbose").tag("V")
                    Text("Debug").tag("D")
                    Text("Info").tag("I")
                    Text("Warning").tag("W")
                    Text("Error").tag("E")
                    Text("Fatal").tag("F")
                }
                .pickerStyle(.menu)
                .frame(width: 120)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            LogcatScrollView(
                text: logcatManager.logText,
                isAtBottom: $logcatManager.isAtBottom,
                minLevel: minLevel
            )
        }
        .frame(minWidth: 600, minHeight: 400)
        .navigationTitle("Logcat")
        .toolbar {
            ToolbarItem {
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

struct LogcatScrollView: NSViewRepresentable {
    let text: String
    @Binding var isAtBottom: Bool
    let minLevel: String
    
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
        
        // Filter and colorize text based on minimum log level
        let filteredText = filterLogcat(text, minLevel: minLevel)
        let attributedString = colorizeLogcat(filteredText)
        
        // Update text storage
        textStorage.setAttributedString(attributedString)
        
        // If we're at bottom, scroll to show new content
        if isAtBottom {
            layoutManager.ensureLayout(for: textView.textContainer!)
            textView.scrollToEndOfDocument(nil)
        }
        // Otherwise don't adjust scroll - user is reading old content
    }
    
    private func filterLogcat(_ text: String, minLevel: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let minPriority = logLevelPriority(minLevel)
        
        let filteredLines = lines.filter { line in
            // Extract log level from line
            let pattern = #"^\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d{3}\s+\d+\s+\d+\s+([VDIWEFS])\s"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: String(line), range: NSRange(location: 0, length: line.utf16.count)),
                  match.numberOfRanges >= 2 else {
                // If line doesn't match logcat format, include it (might be continuation)
                return true
            }
            
            let levelRange = match.range(at: 1)
            if let range = Range(levelRange, in: String(line)) {
                let level = String(String(line)[range])
                let priority = logLevelPriority(level)
                return priority >= minPriority
            }
            
            return true
        }
        
        return filteredLines.joined(separator: "\n")
    }
    
    private func logLevelPriority(_ level: String) -> Int {
        switch level {
        case "S": return 0  // Silent (lowest)
        case "V": return 1  // Verbose
        case "D": return 2  // Debug
        case "I": return 3  // Info
        case "W": return 4  // Warning
        case "E": return 5  // Error
        case "F": return 6  // Fatal (highest)
        default: return 0
        }
    }
    
    private func colorizeLogcat(_ text: String) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: text)
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        
        // Apply default font to entire string
        attributedString.addAttribute(.font, value: font, range: NSRange(location: 0, length: attributedString.length))
        
        // Regular expression to match log level in logcat format
        // Matches: timestamp pid tid LEVEL tag : message
        // Example: "02-07 23:48:36.411 10115 10119 I artd    : message"
        let pattern = #"^\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d{3}\s+\d+\s+\d+\s+([VDIWEFS])\s"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else {
            return attributedString
        }
        
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
        
        for match in matches {
            // Get the log level character
            if match.numberOfRanges >= 2 {
                let levelRange = match.range(at: 1)
                if let range = Range(levelRange, in: text) {
                    let level = String(text[range])
                    
                    // Get the color for this log level
                    let color = colorForLogLevel(level)
                    
                    // Apply color to the entire line
                    // Find the end of this line
                    let lineStart = match.range.location
                    var lineEnd = text.utf16.count
                    
                    let newlineRange = (text as NSString).rangeOfCharacter(
                        from: .newlines,
                        options: [],
                        range: NSRange(location: lineStart, length: text.utf16.count - lineStart)
                    )
                    if newlineRange.location != NSNotFound {
                        lineEnd = newlineRange.location
                    }
                    
                    let lineRange = NSRange(location: lineStart, length: lineEnd - lineStart)
                    attributedString.addAttribute(.foregroundColor, value: color, range: lineRange)
                }
            }
        }
        
        return attributedString
    }
    
    private func colorForLogLevel(_ level: String) -> NSColor {
        switch level {
        case "V": // Verbose
            return NSColor.systemBlue
        case "D": // Debug
            return NSColor.systemGreen
        case "I": // Info
            return NSColor.labelColor
        case "W": // Warning
            return NSColor.systemOrange
        case "E": // Error
            return NSColor.systemRed
        case "F": // Fatal
            return NSColor.systemPurple
        case "S": // Silent
            return NSColor.clear
        default:
            return NSColor.labelColor
        }
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
    var logText: String = ""
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
    private var lines: [String] = []
    @ObservationIgnored
    private var isPaused = false

    private let normalMaxLines = 4000
    private let pausedMaxLines = 50_000

    func startLogcat() {
        // Find adb executable path
        guard let adbPath = findAdb() else {
            self.logText = "Error: Could not find adb executable."
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
            self.logText = "Error starting adb logcat: \(error.localizedDescription)\n"
            self.logText += "ADB path used: \(adbPath)\n"
            self.logText += "Make sure adb is properly installed."
        }
    }
    
    func stopLogcat() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
        outputPipe = nil
    }

    func clearLog() {
        lines.removeAll()
        logText = ""
    }

    private func handleScrollPositionChange() {
        if isAtBottom {
            // User scrolled back to bottom
            if isPaused {
                isPaused = false

                // Restart the process and reset to normal buffer size
                // Reset buffer to normal size and trim if needed
                if lines.count > normalMaxLines {
                    lines = Array(lines.suffix(normalMaxLines))
                }
                logText = lines.joined(separator: "\n")

                startLogcat()
            }
        } else {
            // User scrolled away from bottom
            // If buffer is already full, pause immediately
            if !isPaused && lines.count >= pausedMaxLines {
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
        
        let newLines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        
        for line in newLines {
            if !line.isEmpty || lines.last != "" {
                lines.append(line)
            }
        }
        
        // Trim if needed (only when at bottom). We don't trim while not at
        // bottom because the visible text will jump around, despite our best
        // efforts at finding a way to maintain the viewport.
        if isAtBottom && lines.count > normalMaxLines {
            let linesToRemove = lines.count - normalMaxLines
            lines.removeFirst(linesToRemove)
        } else if !isAtBottom && lines.count >= pausedMaxLines {
            // Buffer is full while not at bottom - pause listening
            isPaused = true
            outputPipe?.fileHandleForReading.readabilityHandler = nil
        }
        
        logText = lines.joined(separator: "\n")
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

#Preview {
    LogcatView()
}
