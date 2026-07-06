import AtollExtensionKit
import Foundation

/// Process-lifetime reference to the agent, created lazily on the main actor.
@MainActor let runningAgent = AtollIndicatorAgent()

/// The resident process that talks to Atoll and reacts to commands posted by
/// the `atoll-indicator` CLI. It does no polling: it sits idle on the run loop
/// until a distributed notification arrives.
///
/// Communication with Atoll uses its JSON-RPC WebSocket server on
/// localhost:9020. Atoll also offers an XPC service, but registering its mach
/// service name does not work on current macOS, so RPC is the reliable path.
@MainActor
final class AtollIndicatorAgent {
    private let rpc = AtollRPCClient()
    private let bundleIdentifier = "com.github.bitmap4.atoll-indicator"

    /// Persistent cues currently presented, by cue id.
    private var persistentCues: [String: SetSpec] = [:]

    /// Generation counter so overlapping flashes don't dismiss each other early.
    private var flashGeneration = 0

    private var resyncTask: Task<Void, Never>?

    private static let flashActivityID = "atoll-indicator.flash"

    func start() async {
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

        rpc.onActivityDismiss = { [weak self] activityID in
            guard let self else { return }
            if let cueID = self.persistentCues.keys.first(where: { Self.cueActivityID($0) == activityID }) {
                self.persistentCues.removeValue(forKey: cueID)
                log("Cue '\(cueID)' dismissed from Atoll.")
            }
        }

        // If Atoll quits or restarts, its activities are gone; re-present our
        // persistent cues once it comes back.
        rpc.onDisconnect = { [weak self] in
            self?.scheduleResync()
        }

        log("Agent running (pid \(ProcessInfo.processInfo.processIdentifier)). Waiting for cues.")

        do {
            let version = try await rpc.call("atoll.getVersion")
            try await authorize()
            log("Connected to Atoll \(version["version"] as? String ?? "?") and authorized.")
        } catch {
            log("Atoll not reachable yet (\(error)). Will retry when it appears.")
            scheduleResync()
        }
    }

    private func authorize() async throws {
        let result = try await rpc.call(
            "atoll.requestAuthorization",
            params: ["bundleIdentifier": bundleIdentifier, "appName": "Atoll Indicator"]
        )
        guard result["authorized"] as? Bool == true else {
            throw AtollRPCClient.RPCError.server(
                code: -1,
                message: "not authorized: enable 'Atoll Indicator' in Atoll > Settings > Extensions"
            )
        }
    }

    /// Retries the Atoll connection every few seconds (only while disconnected)
    /// and restores persistent cues once it succeeds.
    private func scheduleResync() {
        guard resyncTask == nil else { return }
        resyncTask = Task { @MainActor in
            defer { resyncTask = nil }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                do {
                    try await authorize()
                    for spec in persistentCues.values {
                        try? await presentOrUpdate(descriptor: descriptor(for: spec), isUpdate: false)
                    }
                    log("Reconnected to Atoll; restored \(persistentCues.count) cue(s).")
                    return
                } catch {
                    continue
                }
            }
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
            reply(to: command, ok: false, message: String(describing: error))
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
            title: spec.title ?? "Indicator",
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

        try await authorize()
        try await presentOrUpdate(descriptor: descriptor, isUpdate: false)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(spec.duration * 1_000_000_000))
            guard generation == self.flashGeneration else { return }
            _ = try? await self.rpc.call(
                "atoll.dismissLiveActivity",
                params: ["activityID": Self.flashActivityID, "bundleIdentifier": self.bundleIdentifier]
            )
        }
    }

    private func set(_ spec: SetSpec) async throws {
        try await authorize()
        try await presentOrUpdate(
            descriptor: descriptor(for: spec),
            isUpdate: persistentCues[spec.id] != nil
        )
        persistentCues[spec.id] = spec
    }

    private func clear(id: String) async throws {
        guard persistentCues.removeValue(forKey: id) != nil else { return }
        _ = try await rpc.call(
            "atoll.dismissLiveActivity",
            params: ["activityID": Self.cueActivityID(id), "bundleIdentifier": bundleIdentifier]
        )
    }

    private func descriptor(for spec: SetSpec) -> AtollLiveActivityDescriptor {
        AtollLiveActivityDescriptor(
            id: Self.cueActivityID(spec.id),
            bundleIdentifier: bundleIdentifier,
            priority: .normal,
            title: spec.title ?? "Indicator",
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
    }

    private func presentOrUpdate(descriptor: AtollLiveActivityDescriptor, isUpdate: Bool) async throws {
        let json = try descriptorJSON(descriptor)
        let method = isUpdate ? "atoll.updateLiveActivity" : "atoll.presentLiveActivity"
        do {
            _ = try await rpc.call(method, params: ["descriptor": json, "bundleIdentifier": bundleIdentifier])
        } catch {
            // Present may fail if the id already exists (or vice versa); try the other verb.
            let fallback = isUpdate ? "atoll.presentLiveActivity" : "atoll.updateLiveActivity"
            _ = try await rpc.call(fallback, params: ["descriptor": json, "bundleIdentifier": bundleIdentifier])
        }
    }

    /// Encodes an AtollExtensionKit descriptor into the JSON object shape that
    /// Atoll's RPC endpoint decodes (identical to the XPC wire format).
    private func descriptorJSON(_ descriptor: AtollLiveActivityDescriptor) throws -> [String: Any] {
        let data = try JSONEncoder().encode(descriptor)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
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
}

func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    print("[\(stamp)] \(message)")
    // LaunchAgent logs are line-buffered into a file; flush so they appear live.
    fflush(stdout)
}
