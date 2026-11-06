import AppIntents
import SwiftUI
import WidgetKit

@main
struct UpSnapWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WakeDeviceControl()
        DevicePowerControl()
        DeviceWidget()
        DeviceListWidget()
    }
}

/// Trạng thái máy cho các control — đọc từ UpSnap mỗi khi Control Center cần vẽ lại.
struct DeviceControlValue {
    var status: DeviceStatus?
    var device: DeviceEntity?
    /// Thời điểm đổi trạng thái gần nhất ("Last status change" trên web).
    var lastChange: Date? = nil

    /// "Đang bật · 42 ph" — ngắn gọn để vừa ô Control Center.
    var detailText: String {
        guard let lastChange, status != .pending, device != nil else { return statusText }
        return "\(statusText) · \(Self.shortAgo(lastChange))"
    }

    static func shortAgo(_ date: Date, now: Date = .now) -> String {
        let s = max(0, now.timeIntervalSince(date))
        switch s {
        case ..<60: return tr("vừa xong")
        case ..<3600: return tr("\(Int(s / 60)) ph")
        case ..<86400: return tr("\(Int(s / 3600)) giờ")
        default: return tr("\(Int(s / 86400)) ngày")
        }
    }

    var isOn: Bool { status == .online || status == .pending }

    var statusText: String {
        switch status {
        case .online: tr("Đang bật")
        case .pending: tr("Đang xử lý…")
        case .offline: tr("Đang tắt")
        case .unknown, .none: device == nil ? tr("Chạm để chọn máy") : tr("Không rõ")
        }
    }

    var color: Color {
        switch status {
        case .online: .green
        case .pending: .orange
        default: .gray
        }
    }

    var symbol: String {
        switch status {
        case .online: "desktopcomputer"
        case .pending: "hourglass"
        default: "power"
        }
    }
}

struct DeviceStatusProvider: AppIntentControlValueProvider {
    func previewValue(configuration: SelectDeviceIntent) -> DeviceControlValue {
        DeviceControlValue(status: .offline, device: configuration.device)
    }

    func currentValue(configuration: SelectDeviceIntent) async throws -> DeviceControlValue {
        guard let device = configuration.device else {
            return DeviceControlValue(status: nil, device: nil)
        }
        let info = try? await UpSnapClient().device(id: device.id)
        return DeviceControlValue(status: info?.status ?? .unknown, device: device, lastChange: info?.lastStatusChange)
    }
}

/// Nút "Bật máy" trong Control Center / màn hình khoá / nút Action.
/// Biểu tượng, chữ và màu đổi theo trạng thái máy (bật = xanh lá).
struct WakeDeviceControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: ControlKind.wake, provider: DeviceStatusProvider()) { value in
            ControlWidgetButton(action: WakeDeviceIntent(device: value.device)) {
                Label {
                    Text(value.device?.name ?? tr("Bật máy"))
                    Text(value.detailText)
                } icon: {
                    Image(systemName: value.symbol)
                }
            }
            .tint(value.color)
        }
        .displayName("Bật máy tính")
        .description("Gửi Wake-on-LAN qua UpSnap. Màu nút cho biết máy đang bật hay tắt.")
        .promptsForUserConfiguration()
    }
}

/// Công tắc bật/tắt, hiển thị trạng thái online/offline của máy.
struct DevicePowerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: ControlKind.toggle, provider: DeviceStatusProvider()) { value in
            ControlWidgetToggle(
                value.device?.name ?? tr("Máy tính"),
                isOn: value.isOn,
                action: SetDevicePowerIntent(device: value.device)
            ) { isOn in
                Label(value.detailText, systemImage: isOn ? "desktopcomputer" : "power")
            }
            .tint(value.status == .pending ? .orange : .green)
        }
        .displayName("Công tắc máy tính")
        .description("Bật/tắt máy tính qua UpSnap. Tắt máy cần cấu hình Shutdown command.")
        .promptsForUserConfiguration()
    }
}
