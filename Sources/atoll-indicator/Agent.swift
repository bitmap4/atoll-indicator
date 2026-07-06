import AtollExtensionKit
import Foundation

/// Process-lifetime reference to the agent, created lazily on the main actor.
@MainActor let runningAgent = AtollIndicatorAgent()

/// The resident process that owns the XPC connection to Atoll and reacts to
/// commands posted by the `atoll-indicator` CLI. It does no polling: it sits idle on the
/// run loop until a distributed notification arrives.
@MainActor
final class AtollIndicatorAgent {
    private let client = AtollClient.shared
    private let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.github.bitmap4.atoll-indicator"

    /// Persistent cues currently presented, by cue id.
    private var persistentCues: [String: SetSpec] = [:]

    /// Generation counter so overlapping flashes don't dismiss each other early.
    private var flashGeneration = 0

    private static let flashActivityID = "atoll-indicator.flash"

    func start() async {
        guard client.isAtollInstalled else {
            log("Atoll is not installed (https://github.com/Ebullioscopic/Atoll). Exiting.")
            exit(1)
        }

        // Listen for commands first: the authorization request below can stay
        // pending until the user approves the prompt inside Atoll.
        DistributedNotificationCenter.default().addObserver(
            forName: IPC.commandNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let json = notification.userInfo?[IPC.payloadKey] as? String,
                  let command = try? AtollIndicatorCommand(jsonString: json) else {
                log("Ignoring malformed command payload.")
                return
            }
            Task { @MainActor in
                await self.handle(command)
            }
        }

        client.onAuthorizationChange { isAuthorized in
            log("Atoll authorization changed: \(isAuthorized)")
        }

        log("Agent running (pid \(ProcessInfo.processInfo.processIdentifier)). Waiting for cues.")

        do {
            let authorized = try await client.requestAuthorization()
            if authorized {
                log("Authorized with Atoll.")
            } else {
                log("Not authorized. Approve 'AtollIndicator' in Atoll → Settings → Extensions, then cues will start working.")
            }
        } catch {
            log("Could not reach Atoll for authorization: \(error). Will retry on first cue.")
        }
    }

    private func handle(_ command: AtollIndicatorCommand) async {
        do {
            switch command.kind {
            case .ping:
                reply(to: command, ok: true, message: "pong")

            case .flash:
                guard let spec = command.flash else { return }
                try await flash(spec)
                reply(to: command, ok: true)

            case .set:
                guard let spec = command.set else { return }
                try await set(spec)
                reply(to: command, ok: true)

            case .clear:
                guard let id = command.clearID else { return }
                try await clear(id: id)
                reply(to: command, ok: true)

            case .list:
                let ids = persistentCues.keys.sorted().joined(separator: "\n")
                reply(to: command, ok: true, message: ids.isEmpty ? "(no persistent cues)" : ids)
            }
        } catch {
            reply(to: command, ok: false, message: friendlyMessage(for: error))
        }
    }

    // MARK: - Cues

    private func flash(_ spec: FlashSpec) async throws {
        flashGeneration += 1
        let generation = flashGeneration

        let descriptor = AtollLiveActivityDescriptor(
            id: Self.flashActivityID,
            bundleIdentifier: bundleIdentifier,
            priority: .high,
            title: spec.title ?? "AtollIndicator",
            subtitle: spec.subtitle,
            leadingIcon: .symbol(name: spec.icon, size: 16, weight: .semibold),
            trailingContent: .none,
            accentColor: color(from: spec.color),
            allowsMusicCoexistence: true,
            sneakPeekConfig: spec.hud
                ? AtollSneakPeekConfig(enabled: true, duration: spec.duration, style: .standard, showOnUpdate: true)
                : .disabled,
            sneakPeekTitle: spec.title,
            sneakPeekSubtitle: spec.subtitle
        )

        // Re-presenting with the same id replaces the previous flash smoothly.
        do {
            try await client.presentLiveActivity(descriptor)
        } catch {
            try await client.updateLiveActivity(descriptor)
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(spec.duration * 1_000_000_000))
            guard generation == self.flashGeneration else { return }
            try? await self.client.dismissLiveActivity(activityID: Self.flashActivityID)
        }
    }

    private func set(_ spec: SetSpec) async throws {
        let activityID = Self.cueActivityID(spec.id)

        let descriptor = AtollLiveActivityDescriptor(
            id: activityID,
            bundleIdentifier: bundleIdentifier,
            priority: .normal,
            title: spec.title ?? "AtollIndicator",
            subtitle: spec.subtitle,
            leadingIcon: .symbol(name: spec.icon, size: 16, weight: .semibold),
            trailingContent: .none,
            accentColor: color(from: spec.color),
            allowsMusicCoexistence: true,
            sneakPeekConfig: spec.hud
                ? AtollSneakPeekConfig(enabled: true, style: .standard, showOnUpdate: true)
                : .disabled,
            sneakPeekTitle: spec.title,
            sneakPeekSubtitle: spec.subtitle
        )

        if persistentCues[spec.id] != nil {
            try await client.updateLiveActivity(descriptor)
        } else {
            try await client.presentLiveActivity(descriptor)
            client.onActivityDismiss(activityID: activityID) { [weak self] in
                Task { @MainActor in
                    self?.persistentCues.removeValue(forKey: spec.id)
                    log("Cue '\(spec.id)' dismissed from Atoll.")
                }
            }
        }
        persistentCues[spec.id] = spec
    }

    private func clear(id: String) async throws {
        guard persistentCues.removeValue(forKey: id) != nil else { return }
        try await client.dismissLiveActivity(activityID: Self.cueActivityID(id))
    }

    private static func cueActivityID(_ id: String) -> String {
        "atoll-indicator.cue.\(id)"
    }

    // MARK: - Helpers

    private func color(from spec: ColorSpec?) -> AtollColorDescriptor {
        guard let spec else { return .accent }
        return AtollColorDescriptor(red: spec.red, green: spec.green, blue: spec.blue, alpha: spec.alpha)
    }

    private func reply(to command: AtollIndicatorCommand, ok: Bool, message: String? = nil) {
        let reply = AtollIndicatorReply(requestID: command.requestID, ok: ok, message: message)
        guard let json = try? reply.jsonString() else { return }
        DistributedNotificationCenter.default().postNotificationName(
            IPC.replyNotification,
            object: nil,
            userInfo: [IPC.payloadKey: json],
            deliverImmediately: true
        )
    }

    private func friendlyMessage(for error: Error) -> String {
        if let atollError = error as? AtollExtensionKitError {
            switch atollError {
            case .notAuthorized:
                return "not authorized: approve 'AtollIndicator' in Atoll → Settings → Extensions"
            case .atollNotInstalled:
                return "Atoll is not installed"
            case .serviceUnavailable:
                return "Atoll is not running"
            default:
                return String(describing: atollError)
            }
        }
        return String(describing: error)
    }
}

func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    print("[\(stamp)] \(message)")
    // LaunchAgent logs are line-buffered into a file; flush so they appear live.
    fflush(stdout)
}
