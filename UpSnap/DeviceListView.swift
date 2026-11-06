import SwiftUI
import WidgetKit

@MainActor
final class DeviceListModel: ObservableObject {
    @Published var devices: [Device] = DeviceCache.load()
    @Published var errorMessage: String?
    @Published var hasLoaded = false

    private let client = UpSnapClient()

    func refresh() async {
        do {
            devices = try await client.devices()
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        hasLoaded = true
    }

    /// Cập nhật trạng thái định kỳ khi màn hình đang mở.
    func poll() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(3))
        }
    }

    func perform(_ action: PowerAction, on device: Device) async {
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index].status = .pending
        }
        do {
            try await client.power(action, id: device.id)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
        await refresh()
        reloadAllDeviceWidgets()
    }
}

struct DeviceListView: View {
    @EnvironmentObject private var session: SessionModel
    @StateObject private var model = DeviceListModel()
    @State private var editing: Device?
    @State private var pendingConfirm: (PowerAction, Device)?

    var body: some View {
        NavigationStack {
            List {
                if let error = model.errorMessage {
                    Section {
                        Label(error, systemImage: "wifi.exclamationmark")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    ForEach(model.devices) { device in
                        DeviceRow(device: device, onEdit: { editing = device }) { action in
                            if action == .wake {
                                Task { await model.perform(action, on: device) }
                            } else {
                                pendingConfirm = (action, device)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Sửa", systemImage: "pencil") { editing = device }
                                .tint(.accentColor)
                        }
                    }
                } footer: {
                    if !model.devices.isEmpty {
                        Text("Mẹo: thêm nút bật máy vào Control Center — mở Control Center › nhấn giữ › Thêm điều khiển › tìm \"UpSnap\".")
                    }
                }
            }
            .overlay {
                if model.devices.isEmpty {
                    if model.hasLoaded {
                        ContentUnavailableView(
                            "Chưa có máy nào",
                            systemImage: "desktopcomputer",
                            description: Text("Thêm máy trên giao diện web UpSnap, hoặc kiểm tra quyền của tài khoản.")
                        )
                    } else {
                        ProgressView()
                    }
                }
            }
            .navigationTitle("Thiết bị")
            .refreshable { await model.refresh() }
            .task { await model.poll() }
            .navigationDestination(item: $editing) { device in
                DeviceEditView(deviceID: device.id, deviceName: device.name) {
                    Task { await model.refresh() }
                }
            }
            .confirmationDialog(
                confirmTitle,
                isPresented: Binding(get: { pendingConfirm != nil }, set: { if !$0 { pendingConfirm = nil } }),
                titleVisibility: .visible
            ) {
                if let (action, device) = pendingConfirm {
                    Button(action.title, role: .destructive) {
                        Task { await model.perform(action, on: device) }
                    }
                }
            }
        }
    }

    private var confirmTitle: String {
        guard let (action, device) = pendingConfirm else { return "" }
        return "\(action.title) \(device.name)?"
    }
}

struct DeviceRow: View {
    let device: Device
    var onEdit: () -> Void = {}
    let onAction: (PowerAction) -> Void

    var body: some View {
        HStack(spacing: 14) {
            StatusDot(status: device.status)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).font(.headline)
                if let description = device.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text([device.ip, device.mac].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let changed = device.lastStatusChange {
                    LastStatusChangeText(date: changed)
                }
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 44)
            }
            .buttonStyle(.borderless)

            switch device.status {
            case .pending:
                ProgressView()
            case .online:
                if device.canShutdown || device.canSleep {
                    Menu {
                        if device.canShutdown {
                            Button("Tắt máy", systemImage: "power") { onAction(.shutdown) }
                            Button("Khởi động lại", systemImage: "arrow.clockwise") { onAction(.reboot) }
                        }
                        if device.canSleep {
                            Button("Ngủ", systemImage: "moon.zzz") { onAction(.sleep) }
                        }
                    } label: {
                        PowerButtonLabel(isOn: true)
                    }
                } else {
                    PowerButtonLabel(isOn: true)
                }
            case .offline, .unknown:
                Button { onAction(.wake) } label: {
                    PowerButtonLabel(isOn: false)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Sửa", systemImage: "pencil") { onEdit() }
            Divider()
            Button("Bật máy", systemImage: "power") { onAction(.wake) }
            if device.canShutdown {
                Button("Tắt máy", systemImage: "power.circle") { onAction(.shutdown) }
                Button("Khởi động lại", systemImage: "arrow.clockwise") { onAction(.reboot) }
            }
            if device.canSleep {
                Button("Ngủ", systemImage: "moon.zzz") { onAction(.sleep) }
            }
            if let link = device.link, let url = URL(string: link), !link.isEmpty {
                Link(destination: url) { Label("Mở liên kết", systemImage: "safari") }
            }
        }
    }
}

/// "Đổi trạng thái 42 phút trước" — giống "Last status change" trên web, tự cập nhật.
struct LastStatusChangeText: View {
    let date: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            Label {
                Text("Đổi trạng thái \(Self.relative(date, now: context.date)) · \(date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: AppLanguage.current.locale)))")
            } icon: {
                Image(systemName: "clock")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .labelStyle(.titleAndIcon)
        }
    }

    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = AppLanguage.current.locale
        f.unitsStyle = .full
        return f
    }()

    static func relative(_ date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 60 { return tr("vừa xong") }
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

struct PowerButtonLabel: View {
    let isOn: Bool

    var body: some View {
        Image(systemName: "power")
            .font(.title3.bold())
            .foregroundStyle(isOn ? .white : Color.accentColor)
            .frame(width: 44, height: 44)
            .background(Circle().fill(isOn ? Color.green : Color.accentColor.opacity(0.15)))
    }
}

struct StatusDot: View {
    let status: DeviceStatus

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .shadow(color: color.opacity(0.6), radius: status == .online ? 4 : 0)
    }

    private var color: Color {
        switch status {
        case .online: .green
        case .pending: .orange
        case .offline: .red
        case .unknown: .gray
        }
    }
}
