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

    static func install() throws {
        let raw = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let executable = URL(fileURLWithPath: raw).resolvingSymlinksInPath().path

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
