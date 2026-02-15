import Foundation

/// Shared utility for locating command-line tools on the system.
enum CommandFinder {

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

    /// Locates the `adb` executable by searching the shell, common paths, and environment variables.
    static func findAdb() -> String? {
        if let shellPath = findViaShell("adb") {
            return shellPath
        }

        let commonPaths = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb",
            "\(NSHomeDirectory())/Android/sdk/platform-tools/adb",
            "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/adb"
        ]

        for path in commonPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        if let androidHome = ProcessInfo.processInfo.environment["ANDROID_HOME"] ??
                             ProcessInfo.processInfo.environment["ANDROID_SDK_ROOT"] {
            let adbPath = "\(androidHome)/platform-tools/adb"
            if FileManager.default.isExecutableFile(atPath: adbPath) {
                return adbPath
            }
        }

        return nil
    }

    /// Locates the `skip` CLI tool.
    static func findSkip() -> String? {
        if let shellPath = findViaShell("skip") {
            return shellPath
        }

        let commonPaths = [
            "/opt/homebrew/bin/skip",
            "/usr/local/bin/skip"
        ]

        for path in commonPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }

    /// Locates the `sdkmanager` tool from the Android SDK command-line tools.
    static func findSdkmanager() -> String? {
        if let shellPath = findViaShell("sdkmanager") {
            return shellPath
        }

        if let androidHome = ProcessInfo.processInfo.environment["ANDROID_HOME"] ??
                             ProcessInfo.processInfo.environment["ANDROID_SDK_ROOT"] {
            let latestPath = "\(androidHome)/cmdline-tools/latest/bin/sdkmanager"
            if FileManager.default.isExecutableFile(atPath: latestPath) {
                return latestPath
            }
        }

        let commonPaths = [
            "\(NSHomeDirectory())/Library/Android/sdk/cmdline-tools/latest/bin/sdkmanager",
            "\(NSHomeDirectory())/Android/sdk/cmdline-tools/latest/bin/sdkmanager"
        ]

        for path in commonPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }

    /// Builds a PATH string from the directories of all located tools
    /// (skip, avdmanager, sdkmanager, adb) so that spawned processes can
    /// find sibling commands.
    static let toolPATH: String = {
        var dirs = Set<String>()
        for path in [findSkip(), findAvdmanager(), findSdkmanager(), findAdb()] {
            if let path {
                let dir = (path as NSString).deletingLastPathComponent
                dirs.insert(dir)
            }
        }
        // Append standard system paths as fallback
        let systemPaths = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        for p in systemPaths { dirs.insert(p) }
        return dirs.joined(separator: ":")
    }()

    /// Locates the `avdmanager` tool from the Android SDK command-line tools.
    static func findAvdmanager() -> String? {
        if let shellPath = findViaShell("avdmanager") {
            return shellPath
        }

        // Check ANDROID_HOME / ANDROID_SDK_ROOT for cmdline-tools
        if let androidHome = ProcessInfo.processInfo.environment["ANDROID_HOME"] ??
                             ProcessInfo.processInfo.environment["ANDROID_SDK_ROOT"] {
            let latestPath = "\(androidHome)/cmdline-tools/latest/bin/avdmanager"
            if FileManager.default.isExecutableFile(atPath: latestPath) {
                return latestPath
            }
        }

        let commonPaths = [
            "\(NSHomeDirectory())/Library/Android/sdk/cmdline-tools/latest/bin/avdmanager",
            "\(NSHomeDirectory())/Android/sdk/cmdline-tools/latest/bin/avdmanager"
        ]

        for path in commonPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }
}
