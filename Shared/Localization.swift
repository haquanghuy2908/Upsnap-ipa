import Foundation

/// Ngôn ngữ app: theo máy, Tiếng Việt hoặc English.
/// Lưu trong App Group để widget / Control Center dùng cùng ngôn ngữ với app.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system, vi, en

    static let storageKey = "appLanguage"

    var id: String { rawValue }

    static var current: AppLanguage {
        get {
            let raw = AppConfig.defaults.string(forKey: storageKey)
                ?? UserDefaults.standard.string(forKey: storageKey)
            return raw.flatMap(AppLanguage.init(rawValue:)) ?? .system
        }
        set {
            for d in [AppConfig.defaults, UserDefaults.standard] {
                d.set(newValue.rawValue, forKey: storageKey)
            }
            // Để các thành phần hệ thống (nút Huỷ, bàn phím…) cũng đổi theo sau khi mở lại app.
            if newValue == .system {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set([newValue.rawValue], forKey: "AppleLanguages")
            }
        }
    }

    /// Tên hiển thị — mỗi ngôn ngữ viết bằng chính ngôn ngữ đó.
    var title: String {
        switch self {
        case .system: tr("Theo máy")
        case .vi: "Tiếng Việt"
        case .en: "English"
        }
    }

    /// Mã ngôn ngữ thực sự đang dùng ("vi" hoặc "en").
    var resolvedCode: String {
        switch self {
        case .vi: "vi"
        case .en: "en"
        case .system: Bundle.main.preferredLocalizations.first ?? "vi"
        }
    }

    var locale: Locale { Locale(identifier: resolvedCode) }

    /// Bundle chứa bản dịch của ngôn ngữ đã chọn.
    var bundle: Bundle {
        guard self != .system,
              let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return .main }
        return bundle
    }
}

/// Dịch chuỗi tạo bằng code theo ngôn ngữ đã chọn trong app.
/// (Chuỗi trong Text / Button / Label… được SwiftUI dịch tự động.)
func tr(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: AppLanguage.current.bundle)
}
