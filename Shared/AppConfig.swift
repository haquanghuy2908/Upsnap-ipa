import Foundation

/// Cấu hình dùng chung giữa app và widget extension.
/// Nếu đổi Bundle ID / App Group, nhớ sửa cả trong Config/*.entitlements.
enum AppConfig {
    static let appGroup = "group.com.huy.upsnap"
    static let keychainService = "com.huy.upsnap.credentials"
    /// Repo GitHub của app (link "bởi huy" trong Cài đặt).
    static let repoURL = URL(string: "https://github.com/")!

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }
}
