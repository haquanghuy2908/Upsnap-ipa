import Foundation

// MARK: - Device (form sửa)

/// Các trường có thể sửa của một device — tương ứng trang /device/{id} trên web.
struct DeviceDetail: Codable, Equatable {
    var id: String = ""
    var name: String = ""
    var description: String = ""
    var ip: String = ""
    var mac: String = ""
    var netmask: String = ""
    var link: String = ""
    var pingCmd: String = ""
    var wakeCmd: String = ""
    var shutdownCmd: String = ""
    var wakeCron: String = ""
    var wakeCronEnabled: Bool = false
    var shutdownCron: String = ""
    var shutdownCronEnabled: Bool = false
    var wakeConfirm: Bool = false
    var shutdownConfirm: Bool = false
    var wakeTimeout: Double = 0
    var shutdownTimeout: Double = 0

    enum CodingKeys: String, CodingKey {
        case id, name, description, ip, mac, netmask, link
        case pingCmd = "ping_cmd"
        case wakeCmd = "wake_cmd"
        case shutdownCmd = "shutdown_cmd"
        case wakeCron = "wake_cron"
        case wakeCronEnabled = "wake_cron_enabled"
        case shutdownCron = "shutdown_cron"
        case shutdownCronEnabled = "shutdown_cron_enabled"
        case wakeConfirm = "wake_confirm"
        case shutdownConfirm = "shutdown_confirm"
        case wakeTimeout = "wake_timeout"
        case shutdownTimeout = "shutdown_timeout"
    }

    init() {}

    // Trường nào thiếu (do phiên bản UpSnap cũ) thì dùng giá trị mặc định.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func str(_ k: CodingKeys) -> String { (try? c.decodeIfPresent(String.self, forKey: k)) ?? "" }
        func bool(_ k: CodingKeys) -> Bool { (try? c.decodeIfPresent(Bool.self, forKey: k)) ?? false }
        func num(_ k: CodingKeys) -> Double { (try? c.decodeIfPresent(Double.self, forKey: k)) ?? 0 }
        id = str(.id); name = str(.name); description = str(.description)
        ip = str(.ip); mac = str(.mac); netmask = str(.netmask); link = str(.link)
        pingCmd = str(.pingCmd); wakeCmd = str(.wakeCmd); shutdownCmd = str(.shutdownCmd)
        wakeCron = str(.wakeCron); wakeCronEnabled = bool(.wakeCronEnabled)
        shutdownCron = str(.shutdownCron); shutdownCronEnabled = bool(.shutdownCronEnabled)
        wakeConfirm = bool(.wakeConfirm); shutdownConfirm = bool(.shutdownConfirm)
        wakeTimeout = num(.wakeTimeout); shutdownTimeout = num(.shutdownTimeout)
    }
}

// MARK: - Users & permissions

struct PBUser: Codable, Identifiable, Hashable {
    let id: String
    var username: String?
    var email: String?
    var created: String?

    var displayName: String {
        if let username, !username.isEmpty { return username }
        return email ?? id
    }
}

struct NewUser: Encodable {
    var username: String
    var password: String
    var passwordConfirm: String
}

struct PBPermission: Codable, Identifiable, Equatable {
    var id: String?
    var user: String
    var create: Bool = false
    var read: [String] = []
    var update: [String] = []
    var delete: [String] = []
    var power: [String] = []

    enum CodingKeys: String, CodingKey { case id, user, create, read, update, delete, power }

    init(user: String) { self.user = user }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        user = try c.decode(String.self, forKey: .user)
        create = (try? c.decodeIfPresent(Bool.self, forKey: .create)) ?? false
        read = (try? c.decodeIfPresent([String].self, forKey: .read)) ?? []
        update = (try? c.decodeIfPresent([String].self, forKey: .update)) ?? []
        delete = (try? c.decodeIfPresent([String].self, forKey: .delete)) ?? []
        power = (try? c.decodeIfPresent([String].self, forKey: .power)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(user, forKey: .user)
        try c.encode(create, forKey: .create)
        try c.encode(read, forKey: .read)
        try c.encode(update, forKey: .update)
        try c.encode(delete, forKey: .delete)
        try c.encode(power, forKey: .power)
    }
}

// MARK: - Settings

struct PrivateSettings: Codable, Equatable {
    var id: String
    var interval: String?
    var trackIpInterval: String?
    var lazyPing: Bool?

    enum CodingKeys: String, CodingKey {
        case id, interval
        case trackIpInterval = "track_ip_interval"
        case lazyPing = "lazy_ping"
    }
}

struct PublicSettings: Codable, Equatable {
    var id: String
    var websiteTitle: String?

    enum CodingKeys: String, CodingKey {
        case id
        case websiteTitle = "website_title"
    }
}

// MARK: - Logs

struct PBLog: Decodable, Identifiable {
    let id: String
    let created: String
    let level: Int
    let message: String
    let data: JSONValue?

    var date: Date? { PBDate.parse(created) }

    var levelName: String {
        switch level {
        case ..<0: "DEBUG"
        case 0..<4: "INFO"
        case 4..<8: "WARN"
        default: "ERROR"
        }
    }
}

struct PBPage<T: Decodable>: Decodable {
    let page: Int
    let totalPages: Int
    let totalItems: Int
    let items: [T]
}

/// JSON tuỳ ý (trường `data` của log).
enum JSONValue: Decodable, CustomStringConvertible {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    var description: String {
        switch self {
        case let .string(s): s
        case let .number(n): n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n)
        case let .bool(b): b ? "true" : "false"
        case .null: "null"
        case let .array(a): "[" + a.map(\.description).joined(separator: ", ") + "]"
        case let .object(o): "{" + o.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: ", ") + "}"
        }
    }

    var objectEntries: [(String, JSONValue)] {
        if case let .object(o) = self { return o.sorted { $0.key < $1.key } }
        return []
    }
}
