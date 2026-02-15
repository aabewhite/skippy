import Foundation

/// Shared utility for locating command-line tools on the system.
enum CommandFinder {

    /// Common directories where CLI tools may be installed.
    private static let generalBinDirectories = [
        "~/bin",
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin", "/bin", "/usr/sbin", "/sbin",
    ]

    /// Candidate Android SDK root directories derived from environment
    /// variables and common install locations.
    private static let androidSDKRoots: [String] = {
        var roots: [String] = []
        if let home = ProcessInfo.processInfo.environment["ANDROID_HOME"] {
            roots.append(home)
        }
        if let root = ProcessInfo.processInfo.environment["ANDROID_SDK_ROOT"],
           root != ProcessInfo.processInfo.environment["ANDROID_HOME"] {
            roots.append(root)
        }
        roots.append("\(NSHomeDirectory())/Library/Android/sdk")
        roots.append("\(NSHomeDirectory())/Android/sdk")
        return roots
    }()

    /// All candidate directories where tools might be found, combining
    /// general bin directories and Android SDK subdirectories.
    static let candidateDirectories: [String] = {
        var dirs = generalBinDirectories
        for root in androidSDKRoots {
            dirs.append("\(root)/platform-tools")
            dirs.append("\(root)/cmdline-tools/latest/bin")
        }
        dirs.append("/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin")
        return dirs
    }()

    /// Uses the user's login shell to locate a command via `which`.
    static func findViaShell(_ command: String) -> String? {
        let process = Process()
        let pipe = Pipe()

        let shell = FileManager.default.fileExists(atPath: "\(NSHomeDirectory())/.zshrc")
            ? "/bin/zsh"
            : "/bin/bash"

        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "which \(command) 2>/dev/null"]
        process.standardOutput = pipe
        process.standardError = Pipe()

        try? process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    /// Searches for a command by name via shell lookup, then candidate directories.
    static func find(_ command: String) -> String? {
        if let shellPath = findViaShell(command) {
            return shellPath
        }
        for dir in candidateDirectories {
            let path = "\(dir)/\(command)"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    static func findAdb() -> String? { find("adb") }
    static func findSkip() -> String? { find("skip") }
    static func findAvdmanager() -> String? { find("avdmanager") }
    static func findSdkmanager() -> String? { find("sdkmanager") }

    /// PATH string for spawned processes, combining candidate directories
    /// with directories from shell-found tools and standard system paths.
    static let toolPATH: String = {
        var dirs: [String] = []
        // Include directories from shell-found tools (may be in non-standard locations)
        for command in ["skip", "adb", "avdmanager", "sdkmanager"] {
            if let path = findViaShell(command) {
                dirs.append((path as NSString).deletingLastPathComponent)
            }
        }
        dirs += candidateDirectories
        return dirs.joined(separator: ":")
    }()
}
