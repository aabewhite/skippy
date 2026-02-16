import Foundation

/// The result of locating a command, bundling its path with the
/// environment variables needed to run it and its child processes.
struct FoundCommand {
    let path: String
    let environment: [String: String]
}

/// Shared utility for locating command-line tools on the system.
enum CommandFinder {
    /// User's personal bin directory
    private static let personalBinDirectory = ("~/bin" as NSString).expandingTildeInPath

    /// Common directories where CLI tools may be installed.
    private static let generalBinDirectories = [
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
        var dirs = [personalBinDirectory]
        if let androidHome {
            dirs.append("\(androidHome)/platform-tools")
            dirs.append("\(androidHome)/cmdline-tools/latest/bin")
        }
        dirs.append("/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin")
        dirs += generalBinDirectories
        return dirs
    }()

    /// The first candidate Android SDK root that actually exists on disk.
    static let androidHome: String? = {
        androidSDKRoots.first { FileManager.default.fileExists(atPath: $0) }
    }()

    /// Environment dictionary for spawned processes, with PATH and ANDROID_HOME set.
    /// Uses `candidateDirectories` for PATH. When `find()` locates a command via
    /// the user's shell in a non-standard directory, that directory is added too.
    private static var _environment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = candidateDirectories.joined(separator: ":")
        if let androidHome {
            env["ANDROID_HOME"] = androidHome
        }
        return env
    }()

    /// Returns the tool environment, including directories of any previously found commands.
    static var toolEnvironment: [String: String] { _environment }

    /// Records the directory of a shell-found command into the PATH if not already present.
    private static func addToEnvironmentPATH(_ dir: String) {
        guard let currentPATH = _environment["PATH"], !currentPATH.contains(dir) else { return }
        _environment["PATH"] = dir + ":" + currentPATH
    }

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
    /// Returns a `FoundCommand` with the path and environment for spawning.
    static func find(_ command: String) -> FoundCommand? {
        if let shellPath = findViaShell(command) {
            let dir = (shellPath as NSString).deletingLastPathComponent
            addToEnvironmentPATH(dir)
            return FoundCommand(path: shellPath, environment: toolEnvironment)
        }
        for dir in candidateDirectories {
            let path = "\(dir)/\(command)"
            if FileManager.default.isExecutableFile(atPath: path) {
                return FoundCommand(path: path, environment: toolEnvironment)
            }
        }
        return nil
    }

    static func findAdb() -> FoundCommand? { find("adb") }
    static func findSkip() -> FoundCommand? { find("skip") }
    static func findAvdmanager() -> FoundCommand? { find("avdmanager") }
    static func findSdkmanager() -> FoundCommand? { find("sdkmanager") }
}
