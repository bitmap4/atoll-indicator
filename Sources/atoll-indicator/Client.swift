import Foundation

/// Thin client used by CLI subcommands: posts a command to the resident agent
/// and waits briefly for an acknowledgement.
enum AtollIndicatorClient {
    static func send(_ command: AtollIndicatorCommand, timeout: TimeInterval = 3.0) throws -> AtollIndicatorReply {
        let center = DistributedNotificationCenter.default()
        var reply: AtollIndicatorReply?

        let observer = center.addObserver(
            forName: IPC.replyNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let json = notification.userInfo?[IPC.payloadKey] as? String,
                  let decoded = try? AtollIndicatorReply(jsonString: json),
                  decoded.requestID == command.requestID else { return }
            reply = decoded
        }
        defer { center.removeObserver(observer) }

        center.postNotificationName(
            IPC.commandNotification,
            object: nil,
            userInfo: [IPC.payloadKey: try command.jsonString()],
            deliverImmediately: true
        )

        let deadline = Date().addingTimeInterval(timeout)
        while reply == nil && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        guard let reply else { throw AtollIndicatorError.agentUnreachable }
        guard reply.ok else { throw AtollIndicatorError.agentError(reply.message ?? "unknown agent error") }
        return reply
    }
}
