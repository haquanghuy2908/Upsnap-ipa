import AppIntents
import SwiftUI
import WidgetKit

@main
struct UpSnapApp: App {
    @StateObject private var session = SessionModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system

    var body: some Scene {
        WindowGroup {
            Group {
                if session.isLoggedIn {
                    RootTabView()
                } else {
                    LoginView()
                }
            }
            .environmentObject(session)
            .preferredColorScheme(appearance.colorScheme)
            // Đổi ngôn ngữ: SwiftUI dịch theo locale, .id dựng lại giao diện để chuỗi tr() cập nhật.
            .environment(\.locale, language.locale)
            .id(language)
            #if DEBUG
            .task {
                // Chỉ dùng khi phát triển: `-debugLogin <server> <user> <pass>` để tự đăng nhập.
                let args = ProcessInfo.processInfo.arguments
                if let i = args.firstIndex(of: "-debugLogin"), args.count > i + 3 {
                    try? await session.login(server: args[i + 1], identity: args[i + 2], password: args[i + 3])
                }
            }
            #endif
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            // iOS có thể hỏi widget trước khi kịp đọc metadata App Intents (sau khi cài/cập nhật)
            // -> nút Control Center bị trống. Mỗi lần mở app, yêu cầu tải lại cho chắc.
            if phase == .active {
                Task {
                    if session.isLoggedIn { await UpSnapClient().refreshSession() }
                    reloadAllDeviceWidgets()
                }
            }
        }
    }
}

@MainActor
final class SessionModel: ObservableObject {
    @Published private(set) var isLoggedIn = CredentialStore.shared.isLoggedIn

    var serverURL: URL? { CredentialStore.shared.serverURL }
    var identity: String? { CredentialStore.shared.identity }
    var isSuperuser: Bool { CredentialStore.shared.collection == .superusers }

    func login(server: String, identity: String, password: String) async throws {
        guard let url = UpSnapClient.normalizeServerURL(server) else { throw UpSnapError.invalidURL }
        try await UpSnapClient().login(Credentials(serverURL: url, identity: identity, password: password))
        isLoggedIn = true
        reloadAllDeviceWidgets()
        UpSnapShortcuts.updateAppShortcutParameters()
    }

    func logout() {
        CredentialStore.shared.clear()
        isLoggedIn = false
        reloadAllDeviceWidgets()
    }
}

/// Siri & Shortcuts: "Bật <máy> bằng UpSnap".
struct UpSnapShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WakeDeviceIntent(),
            phrases: [
                "Turn on computer with \(.applicationName)",
                "Wake computer with \(.applicationName)",
            ],
            shortTitle: "Bật máy tính",
            systemImageName: "power"
        )
        AppShortcut(
            intent: ShutdownDeviceIntent(),
            phrases: [
                "Shut down computer with \(.applicationName)",
            ],
            shortTitle: "Tắt máy tính",
            systemImageName: "power.circle"
        )
    }
}

/// Giao diện app: theo máy, luôn sáng, hoặc luôn tối.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: tr("Theo máy")
        case .light: tr("Sáng")
        case .dark: tr("Tối")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
