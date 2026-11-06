import Foundation
import Security

/// Collection PocketBase dùng để đăng nhập: admin (superuser) hoặc user thường.
enum AuthCollection: String, Sendable {
    case superusers = "_superusers"
    case users
}

struct Credentials: Sendable {
    var serverURL: URL
    var identity: String
    var password: String
}

/// Lưu thông tin đăng nhập trong App Group (để widget Control Center dùng chung).
/// Mật khẩu nằm trong Keychain; token nằm trong UserDefaults của App Group.
final class CredentialStore: @unchecked Sendable {
    static let shared = CredentialStore()

    private enum Key {
        static let serverURL = "serverURL"
        static let identity = "identity"
        static let collection = "authCollection"
        static let token = "token"
        static let passwordFallback = "passwordFallback"
    }

    // Ghi vào CẢ App Group (để widget đọc) VÀ UserDefaults riêng của app.
    // Nếu App Group không hoạt động (vd. sideload bằng Apple ID miễn phí), app vẫn nhớ đăng nhập.
    private var group: UserDefaults { AppConfig.defaults }
    private var local: UserDefaults { .standard }

    private func string(_ key: String) -> String? {
        group.string(forKey: key) ?? local.string(forKey: key)
    }

    private func set(_ value: String?, _ key: String) {
        for d in [group, local] {
            if let value { d.set(value, forKey: key) } else { d.removeObject(forKey: key) }
        }
    }

    var credentials: Credentials? {
        guard
            let urlString = string(Key.serverURL),
            let url = URL(string: urlString),
            let identity = string(Key.identity),
            let password = readPassword()
        else { return nil }
        return Credentials(serverURL: url, identity: identity, password: password)
    }

    var serverURL: URL? { string(Key.serverURL).flatMap(URL.init(string:)) }

    var identity: String? { string(Key.identity) }

    var token: String? {
        get { string(Key.token) }
        set { set(newValue, Key.token) }
    }

    var collection: AuthCollection? {
        get { string(Key.collection).flatMap(AuthCollection.init(rawValue:)) }
        set { set(newValue?.rawValue, Key.collection) }
    }

    /// Đã đăng nhập nếu có server + tài khoản và (token hoặc mật khẩu).
    var isLoggedIn: Bool {
        serverURL != nil && identity != nil && (token != nil || readPassword() != nil)
    }

    func save(_ credentials: Credentials, collection: AuthCollection, token: String) {
        set(credentials.serverURL.absoluteString, Key.serverURL)
        set(credentials.identity, Key.identity)
        self.collection = collection
        self.token = token
        writePassword(credentials.password)
    }

    func clear() {
        for key in [Key.serverURL, Key.identity, Key.collection, Key.token, Key.passwordFallback] {
            set(nil, key)
        }
        SecItemDelete(keychainQuery(shared: true) as CFDictionary)
        SecItemDelete(keychainQuery(shared: false) as CFDictionary)
        DeviceCache.clear()
    }

    // MARK: - Keychain

    /// shared = true: keychain dùng chung với widget qua App Group.
    /// shared = false: keychain riêng của app (dự phòng khi không có App Group).
    private func keychainQuery(shared: Bool) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppConfig.keychainService,
            kSecAttrAccount as String: "password",
        ]
        if shared { q[kSecAttrAccessGroup as String] = AppConfig.appGroup }
        return q
    }

    private func writePassword(_ password: String) {
        let data = Data(password.utf8)
        var savedShared = false
        for shared in [true, false] {
            let base = keychainQuery(shared: shared)
            SecItemDelete(base as CFDictionary)
            var add = base
            add[kSecValueData as String] = data
            // Cho phép widget đọc khi máy đã mở khoá ít nhất 1 lần sau khi khởi động.
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let ok = SecItemAdd(add as CFDictionary, nil) == errSecSuccess
            if shared { savedShared = ok }
        }
        // Widget chạy tiến trình riêng: nếu keychain dùng chung không được thì để widget đọc qua App Group.
        if savedShared {
            set(nil, Key.passwordFallback)
        } else {
            set(password, Key.passwordFallback)
        }
    }

    private func readPassword() -> String? {
        for shared in [true, false] {
            var query = keychainQuery(shared: shared)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: AnyObject?
            if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
               let data = result as? Data,
               let password = String(data: data, encoding: .utf8) {
                return password
            }
        }
        return string(Key.passwordFallback)
    }
}

/// Lưu tạm danh sách máy để chọn trong Control Center khi mất mạng.
enum DeviceCache {
    private static let key = "cachedDevices"

    static func save(_ devices: [Device]) {
        if let data = try? JSONEncoder().encode(devices) {
            AppConfig.defaults.set(data, forKey: key)
        }
    }

    static func load() -> [Device] {
        guard let data = AppConfig.defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Device].self, from: data)) ?? []
    }

    static func clear() {
        AppConfig.defaults.removeObject(forKey: key)
    }
}
