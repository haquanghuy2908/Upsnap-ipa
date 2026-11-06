import Foundation

/// Cấu hình dùng chung giữa app và widget extension.
/// Nếu đổi Bundle ID / App Group, nhớ sửa cả trong Config/*.entitlements.
enum AppConfig {
    /// App Group mặc định (khi ký bằng Xcode).
    static let defaultAppGroup = "group.com.huy.upsnap"

    /// App Group thực tế. AltStore / SideStore đổi tên group khi ký lại
    /// (vd. "group.com.huy.upsnap.ABCDE12345") và ghi tên mới vào khoá `ALTAppGroups` trong Info.plist.
    /// Widget extension đọc thêm Info.plist của app chứa nó (PlugIns/X.appex -> X.app).
    static let appGroup: String = {
        var bundles = [Bundle.main]
        let appURL = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        if Bundle.main.bundleURL.pathExtension == "appex", let app = Bundle(url: appURL) {
            bundles.append(app)
        }
        for bundle in bundles {
            if let groups = bundle.object(forInfoDictionaryKey: "ALTAppGroups") as? [String],
               let group = groups.first(where: { $0.hasPrefix(defaultAppGroup) }) ?? groups.first {
                return group
            }
        }
        return defaultAppGroup
    }()
    static let keychainService = "com.huy.upsnap.credentials"
    /// Repo GitHub của app (link "bởi huy" trong Cài đặt).
    static let repoURL = URL(string: "https://github.com/haquanghuy2908/Upsnap-ipa")!

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }
}
