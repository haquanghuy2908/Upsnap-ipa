import Foundation

enum DeviceStatus: String, Codable, Sendable {
    case online, offline, pending, unknown

    init(from decoder: Decoder) throws {
        let raw = try? decoder.singleValueContainer().decode(String.self)
        self = DeviceStatus(rawValue: raw ?? "") ?? .unknown
    }
}

struct Device: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var ip: String?
    var mac: String?
    var status: DeviceStatus
    var link: String?
    var shutdownCmd: String?
    var solEnabled: Bool?
    var description: String?
    /// Thời điểm record được cập nhật lần cuối = "Last status change" trên web.
    var updated: String?

    enum CodingKeys: String, CodingKey {
        case id, name, ip, mac, status, link, description, updated
        case shutdownCmd = "shutdown_cmd"
        case solEnabled = "sol_enabled"
    }

    /// UpSnap chỉ tắt/khởi động lại được khi máy có "shutdown command".
    var canShutdown: Bool { !(shutdownCmd ?? "").isEmpty }
    /// Sleep-on-LAN.
    var canSleep: Bool { solEnabled ?? false }

    var lastStatusChange: Date? { updated.flatMap(PBDate.parse) }
}

/// PocketBase trả ngày dạng "2026-11-06 04:09:20.021Z" (UTC).
enum PBDate {
    private static let formatters: [DateFormatter] = ["yyyy-MM-dd HH:mm:ss.SSSX", "yyyy-MM-dd HH:mm:ssX"].map {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = $0
        return f
    }
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func parse(_ string: String) -> Date? {
        for f in formatters { if let d = f.date(from: string) { return d } }
        return iso.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}

enum PowerAction: String, Sendable {
    case wake, shutdown, sleep, reboot

    var title: String {
        switch self {
        case .wake: tr("Bật máy")
        case .shutdown: tr("Tắt máy")
        case .sleep: tr("Ngủ")
        case .reboot: tr("Khởi động lại")
        }
    }
}

struct PBList<T: Decodable>: Decodable {
    let items: [T]
}

struct PBAuthResponse: Decodable {
    let token: String
}

struct PBErrorResponse: Decodable {
    let message: String
}
