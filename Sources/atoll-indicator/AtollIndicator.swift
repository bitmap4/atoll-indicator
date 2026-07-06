import ArgumentParser
import Foundation

@main
struct AtollIndicator: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "atoll-indicator",
        abstract: "Trigger visual cues in the notch via Atoll.",
        discussion: """
            atoll-indicator turns anything that can run a shell command (hotkeys, \
            scripts, other apps) into a source of visual cues rendered by Atoll: \
            transient icon flashes next to the notch, and persistent state \
            indicators that stay next to the notch until cleared.
            """,
        version: "0.1.0",
        subcommands: [
            Agent.self, Flash.self, Set.self, Clear.self, List.self, Status.self,
            InstallAgent.self, UninstallAgent.self,
        ]
    )
}

// MARK: - Shared options

struct ColorOption: ParsableArguments {
    @Option(name: .long, help: "Cue color: a name (red, green, ...), hex (#ff5500), or 'accent'.")
    var color: String = "accent"

    func parsed() throws -> ColorSpec? {
        try ColorSpec.parse(color)
    }
}

// MARK: - Subcommands

extension AtollIndicator {
    struct Agent: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run the resident agent that talks to Atoll (usually via launchd)."
        )

        func run() throws {
            Task { @MainActor in
                await runningAgent.start()
            }
            // Idle on the main run loop; work only happens when a command arrives.
            RunLoop.main.run()
        }
    }

    struct Flash: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Flash an icon next to the notch, then auto-dismiss.",
            discussion: "Example: atoll-indicator flash --icon mic.slash.fill --color red --title \"Mic muted\""
        )

        @Option(name: .long, help: "SF Symbol name (e.g. mic.slash.fill, bell.fill).")
        var icon: String

        @OptionGroup var colorOption: ColorOption

        @Option(name: .long, help: "Optional title (shown only with --hud).")
        var title: String?

        @Option(name: .long, help: "Optional subtitle (shown only with --hud).")
        var subtitle: String?

        @Option(name: .long, help: "Seconds before the cue disappears.")
        var duration: Double = 1.5

        @Flag(name: .long, help: "Also show the title/subtitle in Atoll's HUD below the notch.")
        var hud = false

        func run() throws {
            let spec = FlashSpec(
                icon: icon,
                color: try colorOption.parsed(),
                title: title,
                subtitle: subtitle,
                duration: duration,
                hud: hud
            )
            _ = try AtollIndicatorClient.send(
                AtollIndicatorCommand(kind: .flash, requestID: UUID().uuidString, flash: spec)
            )
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Set a persistent cue: an icon that stays next to the notch until cleared.",
            discussion: "Example: atoll-indicator set --id mic-muted --icon mic.slash.fill --color red --title \"Mic muted\""
        )

        @Option(name: .long, help: "Stable identifier for this cue (used by 'clear').")
        var id: String

        @Option(name: .long, help: "SF Symbol name (e.g. mic.slash.fill).")
        var icon: String

        @OptionGroup var colorOption: ColorOption

        @Option(name: .long, help: "Optional title (shown only with --hud).")
        var title: String?

        @Option(name: .long, help: "Optional subtitle (shown only with --hud).")
        var subtitle: String?

        @Flag(name: .long, help: "Announce the cue in Atoll's HUD below the notch when it appears.")
        var hud = false

        func run() throws {
            let spec = SetSpec(
                id: id,
                icon: icon,
                color: try colorOption.parsed(),
                title: title,
                subtitle: subtitle,
                hud: hud
            )
            _ = try AtollIndicatorClient.send(
                AtollIndicatorCommand(kind: .set, requestID: UUID().uuidString, set: spec)
            )
        }
    }

    struct Clear: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove a persistent cue by id."
        )

        @Option(name: .long, help: "Identifier passed to 'set'.")
        var id: String

        func run() throws {
            _ = try AtollIndicatorClient.send(
                AtollIndicatorCommand(kind: .clear, requestID: UUID().uuidString, clearID: id)
            )
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List active persistent cues."
        )

        func run() throws {
            let reply = try AtollIndicatorClient.send(
                AtollIndicatorCommand(kind: .list, requestID: UUID().uuidString)
            )
            print(reply.message ?? "")
        }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Check whether the agent is running and reachable."
        )

        func run() throws {
            _ = try AtollIndicatorClient.send(
                AtollIndicatorCommand(kind: .ping, requestID: UUID().uuidString),
                timeout: 1.5
            )
            print("agent is running")
        }
    }

    struct InstallAgent: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "install-agent",
            abstract: "Install and start the agent as a login item (launchd)."
        )

        func run() throws {
            try LaunchAgentManager.install()
            print("Agent installed and started. Logs: \(LaunchAgentManager.logPath)")
        }
    }

    struct UninstallAgent: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "uninstall-agent",
            abstract: "Stop and remove the launchd agent."
        )

        func run() throws {
            try LaunchAgentManager.uninstall()
            print("Agent stopped and removed.")
        }
    }
}
