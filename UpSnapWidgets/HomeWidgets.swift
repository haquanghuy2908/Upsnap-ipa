import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Helpers dùng chung

extension DeviceStatus {
    var widgetText: String {
        switch self {
        case .online: tr("Đang bật")
        case .offline: tr("Đang tắt")
        case .pending: tr("Đang xử lý…")
        case .unknown: tr("Không rõ")
        }
    }

    var widgetColor: Color {
        switch self {
        case .online: .green
        case .pending: .orange
        case .offline: .red
        case .unknown: .gray
        }
    }

    var isOn: Bool { self == .online || self == .pending }
}

extension Device {
    /// "Đang bật · 42 ph" tính tại thời điểm `now` của entry.
    func widgetDetail(at now: Date) -> String {
        guard status != .pending, let changed = lastStatusChange else { return status.widgetText }
        return "\(status.widgetText) · \(DeviceControlValue.shortAgo(changed, now: now))"
    }
}

/// Tạo entry mỗi 5 phút trong 1 giờ để "· 42 ph" tự cập nhật;
/// nếu có máy đang xử lý thì hỏi lại server sau 1 phút.
private func makeTimeline<E: TimelineEntry>(
    devices: [Device],
    make: (Date) -> E
) -> Timeline<E> {
    let now = Date()
    let entries = (0..<12).map { make(now.addingTimeInterval(Double($0) * 300)) }
    let pending = devices.contains { $0.status == .pending }
    let next = pending ? now.addingTimeInterval(60) : now.addingTimeInterval(3600)
    return Timeline(entries: pending ? [entries[0]] : entries, policy: .after(next))
}

enum LoadState {
    case ok
    case notLoggedIn
    case offline // dùng dữ liệu cũ đã lưu
}

private func loadDevices() async -> ([Device], LoadState) {
    guard CredentialStore.shared.serverURL != nil else { return ([], .notLoggedIn) }
    do {
        return (try await UpSnapClient().devices(), .ok)
    } catch UpSnapError.notLoggedIn, UpSnapError.sessionExpired {
        return (DeviceCache.load(), .notLoggedIn)
    } catch {
        return (DeviceCache.load(), .offline)
    }
}

/// Nút ⏻ trên widget: chỉ bật máy (không tắt) — giống nút "Bật máy tính" trong Control Center.
private struct WakeButton: View {
    let device: Device
    var size: CGFloat = 36

    var body: some View {
        Button(intent: WakeDeviceIntent(device: DeviceEntity(device))) {
            Image(systemName: "power")
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundStyle(device.status.isOn ? Color.white : Color.green)
                .frame(width: size, height: size)
                .background(Circle().fill(device.status.isOn ? Color.green : Color.green.opacity(0.18)))
        }
        .buttonStyle(.plain)
    }
}

private struct MessageView: View {
    let icon: String
    let text: LocalizedStringKey

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title2).foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Widget 1 máy (màn hình chính nhỏ + màn hình khoá)

struct DeviceEntry: TimelineEntry {
    let date: Date
    let device: Device?
    let configured: Bool
    let state: LoadState
}

struct DeviceWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DeviceEntry {
        DeviceEntry(date: .now, device: Self.sample, configured: true, state: .ok)
    }

    func snapshot(for configuration: SelectDeviceWidgetIntent, in context: Context) async -> DeviceEntry {
        if context.isPreview && configuration.device == nil {
            return placeholder(in: context)
        }
        return await entry(for: configuration, at: .now)
    }

    func timeline(for configuration: SelectDeviceWidgetIntent, in context: Context) async -> Timeline<DeviceEntry> {
        let first = await entry(for: configuration, at: .now)
        return makeTimeline(devices: first.device.map { [$0] } ?? []) { date in
            DeviceEntry(date: date, device: first.device, configured: first.configured, state: first.state)
        }
    }

    private func entry(for configuration: SelectDeviceWidgetIntent, at date: Date) async -> DeviceEntry {
        guard let selected = configuration.device else {
            return DeviceEntry(date: date, device: nil, configured: false, state: .ok)
        }
        let (devices, state) = await loadDevices()
        let device = devices.first { $0.id == selected.id }
            ?? Device(id: selected.id, name: selected.name, ip: selected.ip, status: .unknown)
        return DeviceEntry(date: date, device: device, configured: true, state: state)
    }

    static let sample = Device(id: "sample", name: "Huy PC", ip: "192.168.1.10", status: .online,
                               updated: nil)
}

struct DeviceWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DeviceEntry

    var body: some View {
        if entry.state == .notLoggedIn {
            MessageView(icon: "person.crop.circle.badge.exclamationmark", text: "Mở app UpSnap để đăng nhập")
        } else if !entry.configured {
            MessageView(icon: "desktopcomputer", text: "Nhấn giữ › Sửa tiện ích để chọn máy")
        } else if let device = entry.device {
            switch family {
            case .accessoryCircular: circular(device)
            case .accessoryRectangular: rectangular(device)
            case .accessoryInline: Text("\(device.name) · \(device.status.widgetText)")
            default: small(device)
            }
        }
    }

    private func small(_ device: Device) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(device.status.widgetColor)
                Spacer()
                WakeButton(device: device, size: 40)
            }
            Spacer(minLength: 4)
            Text(device.name)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(device.widgetDetail(at: entry.date))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if entry.state == .offline {
                Label("Mất kết nối", systemImage: "wifi.slash")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func circular(_ device: Device) -> some View {
        Button(intent: WakeDeviceIntent(device: DeviceEntity(device))) {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Image(systemName: device.status.isOn ? "desktopcomputer" : "power")
                        .font(.title3.weight(.semibold))
                    Text(device.status.isOn ? "Bật" : "Tắt")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
        }
        .buttonStyle(.plain)
        .widgetAccentable()
    }

    private func rectangular(_ device: Device) -> some View {
        HStack(spacing: 8) {
            Image(systemName: device.status.isOn ? "desktopcomputer" : "power")
                .font(.title2.weight(.semibold))
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name).font(.headline).lineLimit(1)
                Text(device.widgetDetail(at: entry.date)).font(.caption).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

struct DeviceWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.huy.upsnap.widget.device", intent: SelectDeviceWidgetIntent.self,
                               provider: DeviceWidgetProvider()) { entry in
            DeviceWidgetView(entry: entry)
                .environment(\.locale, AppLanguage.current.locale)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Máy tính")
        .description("Trạng thái một máy và nút bật nhanh.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Widget danh sách thiết bị (vừa / lớn)

struct DeviceListEntry: TimelineEntry {
    let date: Date
    let devices: [Device]
    let state: LoadState
}

struct DeviceListProvider: TimelineProvider {
    func placeholder(in context: Context) -> DeviceListEntry {
        DeviceListEntry(date: .now, devices: [
            DeviceWidgetProvider.sample,
            Device(id: "s2", name: "Media Server", ip: "192.168.1.20", status: .offline),
        ], state: .ok)
    }

    func getSnapshot(in context: Context, completion: @escaping (DeviceListEntry) -> Void) {
        if context.isPreview { return completion(placeholder(in: context)) }
        Task {
            let (devices, state) = await loadDevices()
            completion(DeviceListEntry(date: .now, devices: devices, state: state))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DeviceListEntry>) -> Void) {
        Task {
            let (devices, state) = await loadDevices()
            completion(makeTimeline(devices: devices) { DeviceListEntry(date: $0, devices: devices, state: state) })
        }
    }
}

struct DeviceListWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DeviceListEntry

    private var isLarge: Bool { family == .systemLarge }
    private var maxRows: Int { isLarge ? 6 : 3 }
    private var hiddenCount: Int { max(0, entry.devices.count - maxRows) }

    var body: some View {
        if entry.state == .notLoggedIn {
            MessageView(icon: "person.crop.circle.badge.exclamationmark", text: "Mở app UpSnap để đăng nhập")
        } else if entry.devices.isEmpty {
            MessageView(icon: "desktopcomputer", text: "Chưa có thiết bị")
        } else {
            VStack(alignment: .leading, spacing: isLarge ? 10 : 4) {
                header
                ForEach(entry.devices.prefix(maxRows)) { device in
                    row(device)
                }
                // Cỡ lớn: còn chỗ cho dòng "+N máy khác"; cỡ vừa: số này nằm ở tiêu đề.
                if isLarge && hiddenCount > 0 {
                    Text("+\(hiddenCount) máy khác")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if isLarge { Spacer(minLength: 0) }
            }
            .frame(maxHeight: .infinity, alignment: isLarge ? .top : .center)
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text("UpSnap").font(.caption.bold())
            Spacer()
            if entry.state == .offline {
                Image(systemName: "wifi.slash").font(.caption2).foregroundStyle(.orange)
            }
            Text("\(entry.devices.filter { $0.status == .online }.count)/\(entry.devices.count) đang bật")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if !isLarge && hiddenCount > 0 {
                Text("· +\(hiddenCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ device: Device) -> some View {
        HStack(spacing: 8) {
            Circle().fill(device.status.widgetColor).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(device.name)
                    .font(isLarge ? .subheadline.weight(.semibold) : .footnote.weight(.semibold))
                    .lineLimit(1)
                Text(device.widgetDetail(at: entry.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            WakeButton(device: device, size: isLarge ? 32 : 26)
        }
    }
}

struct DeviceListWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.huy.upsnap.widget.list", provider: DeviceListProvider()) { entry in
            DeviceListWidgetView(entry: entry)
                .environment(\.locale, AppLanguage.current.locale)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Thiết bị")
        .description("Trạng thái tất cả máy và nút bật nhanh.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
