import SwiftUI

extension DeviceDetail {
    /// Khi PATCH không gửi `id`.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(description, forKey: .description)
        try c.encode(ip, forKey: .ip)
        try c.encode(mac, forKey: .mac)
        try c.encode(netmask, forKey: .netmask)
        try c.encode(link, forKey: .link)
        try c.encode(pingCmd, forKey: .pingCmd)
        try c.encode(wakeCmd, forKey: .wakeCmd)
        try c.encode(shutdownCmd, forKey: .shutdownCmd)
        try c.encode(wakeCron, forKey: .wakeCron)
        try c.encode(wakeCronEnabled, forKey: .wakeCronEnabled)
        try c.encode(shutdownCron, forKey: .shutdownCron)
        try c.encode(shutdownCronEnabled, forKey: .shutdownCronEnabled)
        try c.encode(wakeConfirm, forKey: .wakeConfirm)
        try c.encode(shutdownConfirm, forKey: .shutdownConfirm)
        try c.encode(wakeTimeout, forKey: .wakeTimeout)
        try c.encode(shutdownTimeout, forKey: .shutdownTimeout)
    }
}

/// Sửa thiết bị — tương ứng nút bút chì trên card của web.
struct DeviceEditView: View {
    let deviceID: String
    let deviceName: String
    var onChange: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var detail = DeviceDetail()
    @State private var original = DeviceDetail()
    @State private var loaded = false
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var confirmDelete = false

    private let client = UpSnapClient()
    private var path: String { "/api/collections/devices/records/\(deviceID)" }

    var body: some View {
        Form {
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            Section("Thông tin chung") {
                field("Tên", text: $detail.name)
                field("Mô tả", text: $detail.description)
                field("Địa chỉ IP", text: $detail.ip, keyboard: .numbersAndPunctuation)
                field("Địa chỉ MAC", text: $detail.mac)
                field("Netmask", text: $detail.netmask, keyboard: .numbersAndPunctuation)
                field("Liên kết", text: $detail.link, keyboard: .URL)
            }

            Section {
                Toggle("Hẹn giờ bật máy", isOn: $detail.wakeCronEnabled)
                if detail.wakeCronEnabled {
                    field("Cron bật máy", text: $detail.wakeCron, placeholder: "0 8 * * 1-5", mono: true)
                }
                Toggle("Hẹn giờ tắt máy", isOn: $detail.shutdownCronEnabled)
                if detail.shutdownCronEnabled {
                    field("Cron tắt máy", text: $detail.shutdownCron, placeholder: "0 23 * * *", mono: true)
                }
            } header: {
                Text("Lịch hẹn giờ")
            } footer: {
                Text("Cú pháp cron: phút giờ ngày tháng thứ. Ví dụ \"0 8 * * 1-5\" = 8:00 thứ 2–6.")
            }

            Section {
                field("Lệnh tắt máy", text: $detail.shutdownCmd, placeholder: "net rpc shutdown -I 192.168.1.10 -U user%pass", mono: true)
                field("Lệnh bật máy (tuỳ chọn)", text: $detail.wakeCmd, placeholder: "Mặc định dùng Wake-on-LAN", mono: true)
                field("Lệnh ping (tuỳ chọn)", text: $detail.pingCmd, placeholder: "Mặc định dùng ping", mono: true)
            } header: {
                Text("Lệnh tuỳ chỉnh")
            } footer: {
                Text("Lệnh chạy trên máy chủ UpSnap (NAS). Cần lệnh tắt máy để dùng Tắt máy / Khởi động lại.")
            }

            Section("Chờ & xác nhận") {
                Toggle("Hỏi lại trước khi bật", isOn: $detail.wakeConfirm)
                Toggle("Hỏi lại trước khi tắt", isOn: $detail.shutdownConfirm)
                number("Thời gian chờ bật (giây)", value: $detail.wakeTimeout)
                number("Thời gian chờ tắt (giây)", value: $detail.shutdownTimeout)
            }

            Section {
                if let url = CredentialStore.shared.serverURL?.appendingPathComponent("device/\(deviceID)") {
                    Link(destination: url) {
                        Label("Cài đặt nâng cao trên web", systemImage: "safari")
                    }
                }
            } footer: {
                Text("Ports, nhóm, Sleep-on-LAN, mật khẩu WoL… chỉnh trên giao diện web.")
            }

            Section {
                Button("Xoá thiết bị", role: .destructive) { confirmDelete = true }
            }
        }
        .disabled(!loaded || saving)
        .overlay { if !loaded && errorMessage == nil { ProgressView() } }
        .navigationTitle(detail.name.isEmpty ? deviceName : detail.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if saving {
                    ProgressView()
                } else {
                    Button("Lưu", action: save)
                        .disabled(!loaded || detail == original || detail.name.isEmpty)
                }
            }
        }
        .confirmationDialog("Xoá \(detail.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Xoá", role: .destructive, action: deleteDevice)
        } message: {
            Text("Thao tác này không thể hoàn tác.")
        }
        .task { await load() }
    }

    // MARK: - Fields

    private func field(
        _ title: LocalizedStringKey,
        text: Binding<String>,
        placeholder: LocalizedStringKey? = nil,
        keyboard: UIKeyboardType = .default,
        mono: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(placeholder ?? title, text: text, axis: mono ? .vertical : .horizontal)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(mono ? .system(.body, design: .monospaced) : .body)
        }
    }

    private func number(_ title: LocalizedStringKey, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
        }
    }

    // MARK: - Actions

    private func load() async {
        do {
            let d = try await client.get(DeviceDetail.self, path: path)
            detail = d
            original = d
            loaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        saving = true
        errorMessage = nil
        Task {
            do {
                try await client.send("PATCH", path: path, body: detail)
                original = detail
                onChange()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            saving = false
        }
    }

    private func deleteDevice() {
        saving = true
        Task {
            do {
                try await client.delete(path: path)
                onChange()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            saving = false
        }
    }
}
