import AppIntents
import WidgetKit

enum ControlKind {
    static let wake = "com.huy.upsnap.control.wake"
    static let toggle = "com.huy.upsnap.control.toggle"
}

/// Bật máy (Wake-on-LAN). Dùng cho nút Control Center, Shortcuts và Siri.
struct WakeDeviceIntent: AppIntent {
    static let title: LocalizedStringResource = "Bật máy tính"
    static let description = IntentDescription("Gửi lệnh Wake-on-LAN tới máy tính qua UpSnap.")

    @Parameter(title: "Máy tính")
    var device: DeviceEntity?

    init() {}
    init(device: DeviceEntity?) { self.device = device }

    static var parameterSummary: some ParameterSummary {
        Summary("Bật \(\.$device)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let device else { throw UpSnapError.noDeviceSelected }
        try await UpSnapClient().power(.wake, id: device.id)
        reloadAllDeviceWidgets()
        return .result(dialog: "Đã gửi lệnh bật \(device.name).")
    }
}

/// Tắt máy (cần cấu hình shutdown command trong UpSnap).
struct ShutdownDeviceIntent: AppIntent {
    static let title: LocalizedStringResource = "Tắt máy tính"
    static let description = IntentDescription("Gửi lệnh tắt máy qua UpSnap (cần cấu hình Shutdown command).")

    @Parameter(title: "Máy tính")
    var device: DeviceEntity?

    init() {}
    init(device: DeviceEntity?) { self.device = device }

    static var parameterSummary: some ParameterSummary {
        Summary("Tắt \(\.$device)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let device else { throw UpSnapError.noDeviceSelected }
        try await UpSnapClient().power(.shutdown, id: device.id)
        reloadAllDeviceWidgets()
        return .result(dialog: "Đã gửi lệnh tắt \(device.name).")
    }
}

/// Intent cho công tắc bật/tắt trong Control Center.
struct SetDevicePowerIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Bật/Tắt máy tính"
    static let isDiscoverable = false

    @Parameter(title: "Máy tính")
    var device: DeviceEntity?

    @Parameter(title: "Bật")
    var value: Bool

    init() {}
    init(device: DeviceEntity?) { self.device = device }

    func perform() async throws -> some IntentResult {
        guard let device else { throw UpSnapError.noDeviceSelected }
        try await UpSnapClient().power(value ? .wake : .shutdown, id: device.id)
        reloadAllDeviceWidgets()
        return .result()
    }
}

/// Cấu hình cho control: chọn máy tính nào sẽ được điều khiển.
struct SelectDeviceIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Chọn máy tính"
    static let isDiscoverable = false

    @Parameter(title: "Máy tính")
    var device: DeviceEntity?

    init() {}

    func perform() async throws -> some IntentResult { .result() }
}

/// Cấu hình cho widget màn hình chính / màn hình khoá: chọn máy tính.
struct SelectDeviceWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Chọn máy tính"
    static let description = IntentDescription("Chọn máy tính hiển thị trên widget.")
    static let isDiscoverable = false

    @Parameter(title: "Máy tính")
    var device: DeviceEntity?

    init() {}
}

/// Tải lại Control Center + widget sau khi trạng thái máy thay đổi.
func reloadAllDeviceWidgets() {
    ControlCenter.shared.reloadAllControls()
    WidgetCenter.shared.reloadAllTimelines()
}
