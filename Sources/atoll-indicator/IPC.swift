import Foundation

/// Distributed-notification based IPC between the `atoll-indicator` CLI and the resident agent.
enum IPC {
    static let commandNotification = Notification.Name("com.github.bitmap4.atoll-indicator.command")
    static let replyNotification = Notification.Name("com.github.bitmap4.atoll-indicator.reply")
    static let payloadKey = "payload"
}

/// An RGBA color. `nil` values elsewhere mean "system accent".
struct ColorSpec: Codable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1.0

    static let named: [String: ColorSpec] = [
        "red": .init(red: 1, green: 0, blue: 0),
        "green": .init(red: 0, green: 1, blue: 0),
        "blue": .init(red: 0, green: 0, blue: 1),
        "yellow": .init(red: 1, green: 1, blue: 0),
        "orange": .init(red: 1, green: 0.6, blue: 0),
        "purple": .init(red: 0.6, green: 0, blue: 1),
        "pink": .init(red: 1, green: 0, blue: 0.6),
        "white": .init(red: 1, green: 1, blue: 1),
        "gray": .init(red: 0.5, green: 0.5, blue: 0.5),
        "black": .init(red: 0, green: 0, blue: 0),
    ]

    /// Parses "red", "ff0000", or "#ff0000". Returns nil for "accent".
    static func parse(_ string: String) throws -> ColorSpec? {
        let lowered = string.lowercased()
        if lowered == "accent" { return nil }
        if let named = named[lowered] { return named }

        var hex = lowered
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else {
            throw AtollIndicatorError.invalidColor(string)
        }
        return ColorSpec(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// A transient cue: an icon that pops up next to the notch and disappears.
struct FlashSpec: Codable {
    var icon: String
    var color: ColorSpec?
    var title: String?
    var subtitle: String?
    var duration: Double
    var hud: Bool
}

/// A persistent cue: an icon that stays next to the notch until cleared.
struct SetSpec: Codable {
    var id: String
    var icon: String
    var color: ColorSpec?
    var title: String?
    var subtitle: String?
    var hud: Bool
}

struct AtollIndicatorCommand: Codable {
    enum Kind: String, Codable {
        case ping, flash, set, clear, list
    }

    var kind: Kind
    var requestID: String
    var flash: FlashSpec?
    var set: SetSpec?
    var clearID: String?
}

struct AtollIndicatorReply: Codable {
    var requestID: String
    var ok: Bool
    var message: String?
}

enum AtollIndicatorError: Error, CustomStringConvertible {
    case invalidColor(String)
    case agentUnreachable
    case agentError(String)

    var description: String {
        switch self {
        case .invalidColor(let value):
            return "invalid color '\(value)' (use a name like red/green/blue, a hex value like #ff5500, or 'accent')"
        case .agentUnreachable:
            return "atoll-indicator agent is not reachable. Start it with `atoll-indicator agent`, or install it as a login item with `atoll-indicator install-agent`."
        case .agentError(let message):
            return message
        }
    }
}

extension Encodable {
    func jsonString() throws -> String {
        let data = try JSONEncoder().encode(self)
        return String(decoding: data, as: UTF8.self)
    }
}

extension Decodable {
    init(jsonString: String) throws {
        self = try JSONDecoder().decode(Self.self, from: Data(jsonString.utf8))
    }
}
