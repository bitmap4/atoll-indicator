import Foundation

/// Manages the launchd job that keeps the agent running across logins.
enum LaunchAgentManager {
    static let label = "com.github.bitmap4.atoll-indicator"

    static var plistPath: String {
        NSString(string: "~/Library/LaunchAgents/\(label).plist").expandingTildeInPath
    }

    static var logPath: String {
        NSString(string: "~/Library/Logs/atoll-indicator.log").expandingTildeInPath
    }

    /// Real path of the running binary (resolving the ~/.local/bin symlink), so
    /// launchd runs the copy inside AtollIndicator.app. Atoll identifies XPC clients via
    /// LaunchServices, which requires the agent to run from an app bundle.
    static var resolvedExecutablePath: String {
        let raw = Bundle.main.executablePath ?? CommandLine.arguments[0]
        return URL(fileURLWithPath: raw).resolvingSymlinksInPath().path
    }

    static func install() throws {
        let executable = resolvedExecutablePath
        guard executable.contains(".app/Contents/MacOS/") else {
            throw AtollIndicatorError.agentError(
                "the atoll-indicator binary must live inside AtollIndicator.app for Atoll to accept it. Install with `make install` from the atoll-indicator repo."
            )
        }

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable, "agent"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "StandardOutPath": logPath,
            "StandardErrorPath": logPath,
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(
            atPath: (plistPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try data.write(to: URL(fileURLWithPath: plistPath))

        let domain = "gui/\(getuid())"
        _ = launchctl("bootout", "\(domain)/\(label)") // ignore failure: may not be loaded
        let result = launchctl("bootstrap", domain, plistPath)
        guard result == 0 else {
            throw AtollIndicatorError.agentError("launchctl bootstrap failed (exit \(result))")
        }
    }

    static func uninstall() throws {
        _ = launchctl("bootout", "gui/\(getuid())/\(label)")
        try? FileManager.default.removeItem(atPath: plistPath)
    }

    @discardableResult
    private static func launchctl(_ arguments: String...) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
