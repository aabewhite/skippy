//
//  LogcatView.swift
//  Skippy
//
//  Created by Abe White on 2/7/26.
//

import SwiftUI
import AppKit

struct LogcatView: View {
    @State private var logcatManager = LogcatManager()
    
    var body: some View {
        VStack(spacing: 0) {
            LogcatScrollView(text: logcatManager.logText)
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
        
        // Configure scroll view
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        
        // Scroll to bottom initially
        DispatchQueue.main.async {
            scrollView.documentView?.scroll(NSPoint(x: 0, y: (scrollView.documentView?.bounds.height ?? 0)))
        }
        
        context.coordinator.scrollView = scrollView
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        
        let wasAtBottom = context.coordinator.isScrolledToBottom(scrollView: scrollView)
        
        // Get current scroll position and content height before updating text
        let currentScrollPosition = scrollView.contentView.bounds.origin
        let heightBefore = textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? 0
        
        // Update the text
        textView.string = text
        
        // Get content height after updating text
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let heightAfter = textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? 0
        
        // Calculate height change
        let contentHeightChange = heightAfter - heightBefore
        
        // Adjust scroll position if content height decreased and we're not at bottom
        if contentHeightChange < 0 && !wasAtBottom {
            DispatchQueue.main.async {
                // Add the negative height change to maintain position
                let adjustedY = max(0, currentScrollPosition.y + contentHeightChange)
                scrollView.contentView.scroll(to: NSPoint(x: currentScrollPosition.x, y: adjustedY))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
        // Auto-scroll only if we were already at the bottom
        else if wasAtBottom || context.coordinator.isFirstUpdate {
            DispatchQueue.main.async {
                textView.scrollToEndOfDocument(nil)
            }
            context.coordinator.isFirstUpdate = false
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var isFirstUpdate = true
        weak var scrollView: NSScrollView?
        
        func isScrolledToBottom(scrollView: NSScrollView) -> Bool {
            guard let documentView = scrollView.documentView else { return false }
            
            let visibleRect = scrollView.contentView.bounds
            let documentHeight = documentView.bounds.height
            let scrollPosition = visibleRect.origin.y + visibleRect.height
            
            // Consider "at bottom" if within 10 points of the bottom
            return documentHeight - scrollPosition < 10
        }
    }
}

@Observable
@MainActor
class LogcatManager {
    var logText: String = ""
    
    private var process: Process?
    private var outputPipe: Pipe?
    private let maxLines = 4000
    private var lines: [String] = []
    
    func startLogcat() {
        // Find adb executable path
        guard let adbPath = findAdb() else {
            self.logText = "Error: Could not find adb executable."
            return
        }
        
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
    
    private func appendOutput(_ output: String) {
        let newLines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        
        for line in newLines {
            if !line.isEmpty || lines.last != "" {
                lines.append(line)
            }
        }
        
        // Keep only the last maxLines
        if lines.count > maxLines {
            let linesToRemove = lines.count - maxLines
            lines.removeFirst(linesToRemove)
        }
        
        logText = lines.joined(separator: "\n")
    }
    
    func clearLog() {
        lines.removeAll()
        logText = ""
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
