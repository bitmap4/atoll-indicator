import Foundation

/// Minimal JSON-RPC 2.0 client for Atoll's WebSocket extension server
/// (ws://127.0.0.1:9020). Atoll exposes this alongside its XPC service; unlike
/// XPC it needs no mach-service registration, which does not work for Atoll on
/// macOS 15.
@MainActor
final class AtollRPCClient {
    static let endpoint = URL(string: "ws://127.0.0.1:9020")!

    enum RPCError: Error, CustomStringConvertible {
        case timeout
        case server(code: Int, message: String)
        case transport(Error)

        var description: String {
            switch self {
            case .timeout:
                return "timed out waiting for Atoll's RPC server"
            case .server(let code, let message):
                return "Atoll error \(code): \(message)"
            case .transport(let error):
                return "cannot reach Atoll's RPC server (is Atoll running?): \(error.localizedDescription)"
            }
        }
    }

    /// Called when Atoll reports that the user dismissed an activity.
    var onActivityDismiss: ((String) -> Void)?

    /// Called when the socket drops, so owners can reset session state.
    var onDisconnect: (() -> Void)?

    private var task: URLSessionWebSocketTask?
    private var pending: [String: CheckedContinuation<[String: Any], Error>] = [:]

    func call(_ method: String, params: [String: Any] = [:], timeout: TimeInterval = 5) async throws -> [String: Any] {
        let task = ensureTask()
        let id = UUID().uuidString

        var request: [String: Any] = ["jsonrpc": "2.0", "method": method, "id": id]
        if !params.isEmpty {
            request["params"] = params
        }
        let data = try JSONSerialization.data(withJSONObject: request)

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation

            task.send(.string(String(decoding: data, as: UTF8.self))) { [weak self] error in
                guard let error else { return }
                Task { @MainActor in
                    self?.failPending(id: id, with: .transport(error))
                    self?.task = nil
                }
            }

            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.failPending(id: id, with: .timeout)
            }
        }
    }

    // MARK: - Connection lifecycle

    private func ensureTask() -> URLSessionWebSocketTask {
        if let task {
            return task
        }
        let newTask = URLSession.shared.webSocketTask(with: Self.endpoint)
        newTask.resume()
        task = newTask
        receiveLoop(on: newTask)
        return newTask
    }

    private func receiveLoop(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.task === task else { return }
                switch result {
                case .failure(let error):
                    self.teardown(error: error)
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handleMessage(Data(text.utf8))
                    case .data(let data):
                        self.handleMessage(data)
                    @unknown default:
                        break
                    }
                    self.receiveLoop(on: task)
                }
            }
        }
    }

    private func teardown(error: Error) {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        let waiting = pending
        pending = [:]
        for continuation in waiting.values {
            continuation.resume(throwing: RPCError.transport(error))
        }
        onDisconnect?()
    }

    // MARK: - Message handling

    private func handleMessage(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let id = object["id"] as? String, let continuation = pending.removeValue(forKey: id) {
            if let error = object["error"] as? [String: Any] {
                continuation.resume(throwing: RPCError.server(
                    code: error["code"] as? Int ?? -1,
                    message: error["message"] as? String ?? "unknown error"
                ))
            } else {
                continuation.resume(returning: object["result"] as? [String: Any] ?? [:])
            }
            return
        }

        // Server-initiated notification (no id).
        if object["method"] as? String == "atoll.activityDidDismiss",
           let params = object["params"] as? [String: Any],
           let activityID = params["activityID"] as? String {
            onActivityDismiss?(activityID)
        }
    }

    private func failPending(id: String, with error: RPCError) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(throwing: error)
    }
}
