import SwiftUI

/// Tab bar dưới cùng — giống thanh Home / Users / Settings / Logs trên web.
/// Build bằng SDK iOS 26 nên trên iOS 26 tab bar tự có hiệu ứng Liquid Glass.
struct RootTabView: View {
    @EnvironmentObject private var session: SessionModel
    @State private var selection = Self.initialTab

    var body: some View {
        TabView(selection: $selection) {
            Tab("Trang chủ", systemImage: "house.fill", value: 0) {
                DeviceListView()
            }
            if session.isSuperuser {
                Tab("Người dùng", systemImage: "person.2.fill", value: 1) {
                    UsersView()
                }
            }
            Tab("Cài đặt", systemImage: "gearshape.fill", value: 2) {
                SettingsView()
            }
            if session.isSuperuser {
                Tab("Nhật ký", systemImage: "list.bullet.rectangle.fill", value: 3) {
                    LogsView()
                }
            }
        }
        .minimizeTabBarOnScroll()
    }

    /// Bản Debug: `-debugTab <0-3>` để mở thẳng một tab khi kiểm thử.
    private static var initialTab: Int {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-debugTab"), args.count > i + 1, let tab = Int(args[i + 1]) {
            return tab
        }
        #endif
        return 0
    }
}

private extension View {
    /// iOS 26: thu nhỏ tab bar Liquid Glass khi cuộn xuống.
    @ViewBuilder
    func minimizeTabBarOnScroll() -> some View {
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}
