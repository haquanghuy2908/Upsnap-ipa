import Foundation

enum UpSnapError: LocalizedError {
    case notLoggedIn
    case noDeviceSelected
    case sessionExpired
    case invalidURL
    case server(status: Int, message: String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notLoggedIn: tr("Chưa đăng nhập. Hãy mở app UpSnap để đăng nhập.")
        case .noDeviceSelected: tr("Chưa chọn máy tính. Nhấn giữ nút trong Control Center để chọn.")
        case .sessionExpired: tr("Phiên đăng nhập đã hết hạn. Hãy mở app UpSnap.")
        case .invalidURL: tr("Địa chỉ máy chủ không hợp lệ.")
        case let .server(status, message): tr("Lỗi \(status): \(message)")
        case .badResponse: tr("Phản hồi từ máy chủ không hợp lệ.")
        }
    }
}

/// Client cho API UpSnap (PocketBase).
///  - Đăng nhập: POST /api/collections/{_superusers|users}/auth-with-password
///  - Danh sách máy: GET /api/collections/devices/records
///  - Điều khiển: GET /api/upsnap/{wake|shutdown|sleep|reboot}/{id}
struct UpSnapClient: Sendable {
    private let store = CredentialStore.shared

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    // MARK: - Auth

    /// Chuẩn hoá địa chỉ người dùng nhập: thêm http:// nếu thiếu, bỏ dấu / cuối.
    static func normalizeServerURL(_ input: String) -> URL? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "http://" + s
        }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), url.host != nil else { return nil }
        return url
    }

    /// Đăng nhập giống web UI: thử tài khoản admin trước, sau đó tới user thường.
    func login(_ credentials: Credentials) async throws {
        let (token, collection) = try await authenticate(credentials, preferred: nil)
        store.save(credentials, collection: collection, token: token)
    }

    private func authenticate(_ credentials: Credentials, preferred: AuthCollection?) async throws -> (String, AuthCollection) {
        var order: [AuthCollection] = [.superusers, .users]
        if let preferred {
            order.removeAll { $0 == preferred }
            order.insert(preferred, at: 0)
        }

        var lastError: Error = UpSnapError.badResponse
        for collection in order {
            do {
                let body = try JSONSerialization.data(withJSONObject: [
                    "identity": credentials.identity,
                    "password": credentials.password,
                ])
                let data = try await rawRequest(
                    baseURL: credentials.serverURL,
                    method: "POST",
                    path: "/api/collections/\(collection.rawValue)/auth-with-password",
                    body: body,
                    token: nil
                )
                let auth = try JSONDecoder().decode(PBAuthResponse.self, from: data)
                return (auth.token, collection)
            } catch let error as UpSnapError {
                lastError = error
                // 400 = sai tài khoản ở collection này -> thử collection tiếp theo.
                if case let .server(status, _) = error, status == 400 || status == 404 { continue }
                throw error
            }
        }
        throw lastError
    }

    // MARK: - API

    func devices() async throws -> [Device] {
        let data = try await authorizedRequest(
            path: "/api/collections/devices/records",
            query: [
                URLQueryItem(name: "perPage", value: "500"),
                URLQueryItem(name: "sort", value: "name"),
            ]
        )
        let devices = try JSONDecoder().decode(PBList<Device>.self, from: data).items
        DeviceCache.save(devices)
        return devices
    }

    func device(id: String) async throws -> Device {
        let data = try await authorizedRequest(path: "/api/collections/devices/records/\(id)")
        return try JSONDecoder().decode(Device.self, from: data)
    }

    /// Gửi lệnh nguồn. Dùng `async=true` để server trả về ngay
    /// (không chờ máy khởi động xong) — quan trọng cho Control Center.
    func power(_ action: PowerAction, id: String) async throws {
        _ = try await authorizedRequest(
            path: "/api/upsnap/\(action.rawValue)/\(id)",
            query: [URLQueryItem(name: "async", value: "true")]
        )
    }

    var isSuperuser: Bool { store.collection == .superusers }

    // MARK: - Generic helpers (PocketBase records)

    func get<T: Decodable>(_ type: T.Type, path: String, query: [URLQueryItem] = []) async throws -> T {
        let data = try await authorizedRequest(path: path, query: query)
        return try JSONDecoder().decode(T.self, from: data)
    }

    @discardableResult
    func send<Body: Encodable>(_ method: String, path: String, body: Body) async throws -> Data {
        let data = try JSONEncoder().encode(body)
        return try await authorizedRequest(method: method, path: path, body: data)
    }

    func delete(path: String) async throws {
        _ = try await authorizedRequest(method: "DELETE", path: path)
    }

    // MARK: - Networking

    func authorizedRequest(
        method: String = "GET",
        path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil
    ) async throws -> Data {
        guard let serverURL = store.serverURL else { throw UpSnapError.notLoggedIn }

        // Chỉ cần token là gọi được API (widget có thể không đọc được mật khẩu trong Keychain).
        if let token = store.token {
            do {
                return try await rawRequest(baseURL: serverURL, method: method, path: path, query: query, body: body, token: token)
            } catch let UpSnapError.server(status, _) where status == 401 {
                // Token hết hạn -> đăng nhập lại bằng mật khẩu bên dưới.
            }
        }

        guard let credentials = store.credentials else { throw UpSnapError.sessionExpired }
        let (token, collection) = try await authenticate(credentials, preferred: store.collection)
        store.token = token
        store.collection = collection
        return try await rawRequest(baseURL: serverURL, method: method, path: path, query: query, body: body, token: token)
    }

    /// Gia hạn token (gọi mỗi khi mở app) để widget Control Center luôn có token còn hạn.
    func refreshSession() async {
        guard let serverURL = store.serverURL, let collection = store.collection else { return }
        if let token = store.token,
           let data = try? await rawRequest(baseURL: serverURL, method: "POST",
                                            path: "/api/collections/\(collection.rawValue)/auth-refresh",
                                            body: nil, token: token),
           let auth = try? JSONDecoder().decode(PBAuthResponse.self, from: data) {
            store.token = auth.token
            return
        }
        // Không gia hạn được (token hết hạn) -> đăng nhập lại bằng mật khẩu đã lưu.
        if let credentials = store.credentials,
           let (token, collection) = try? await authenticate(credentials, preferred: collection) {
            store.token = token
            store.collection = collection
        }
    }

    private func rawRequest(
        baseURL: URL,
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: Data?,
        token: String?
    ) async throws -> Data {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw UpSnapError.invalidURL
        }
        components.path = (components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path) + path
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw UpSnapError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token {
            request.setValue(token, forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpSnapError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(PBErrorResponse.self, from: data))?.message
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw UpSnapError.server(status: http.statusCode, message: message)
        }
        return data
    }
}
