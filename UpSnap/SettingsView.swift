import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: SessionModel
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system

    @State private var priv: PrivateSettings?
    @State private var pub: PublicSettings?
    @State private var original: (PrivateSettings?, PublicSettings?) = (nil, nil)
    @State private var saving = false
    @State private var message: (String, Bool)?
    @State private var confirmLogout = false

    private let client = UpSnapClient()

    private var changed: Bool { priv != original.0 || pub != original.1 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tài khoản") {
                    LabeledContent("Máy chủ", value: session.serverURL?.absoluteString ?? "-")
                    LabeledContent("Tài khoản", value: session.identity ?? "-")
                    LabeledContent("Vai trò", value: session.isSuperuser ? tr("Quản trị viên") : tr("Người dùng"))
                    if let url = session.serverURL {
                        Link(destination: url) { Label("Mở giao diện web", systemImage: "safari") }
                    }
                }

                Section("Giao diện") {
                    Picker("Giao diện", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    Picker("Ngôn ngữ", selection: Binding(
                        get: { language },
                        set: { newValue in
                            AppLanguage.current = newValue // lưu cho cả widget
                            language = newValue
                            reloadAllDeviceWidgets()
                        }
                    )) {
                        ForEach(AppLanguage.allCases) { Text(verbatim: $0.title).tag($0) }
                    }
                } footer: {
                    Text("Bàn phím và một số nút hệ thống sẽ đổi ngôn ngữ sau khi mở lại app.")
                }

                if session.isSuperuser {
                    serverSettings
                }

                Section("Thêm vào Control Center") {
                    Label("Vuốt xuống từ góc phải trên để mở Control Center", systemImage: "1.circle")
                    Label("Nhấn giữ vùng trống › \"Thêm điều khiển\"", systemImage: "2.circle")
                    Label("Tìm \"UpSnap\", chọn \"Bật máy tính\" hoặc \"Công tắc máy tính\"", systemImage: "3.circle")
                    Label("Chạm vào nút vừa thêm để chọn máy", systemImage: "4.circle")
                }
                .font(.subheadline)

                Section {
                    Button("Đăng xuất", role: .destructive) { confirmLogout = true }
                } footer: {
                    HStack(spacing: 4) {
                        Text("UpSnap cho iOS \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") bởi")
                        Link("huy", destination: AppConfig.repoURL)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Cài đặt")
            .toolbar {
                if session.isSuperuser {
                    ToolbarItem(placement: .confirmationAction) {
                        if saving { ProgressView() } else {
                            Button("Lưu", action: save).disabled(!changed)
                        }
                    }
                }
            }
            .confirmationDialog("Đăng xuất khỏi UpSnap?", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("Đăng xuất", role: .destructive) { session.logout() }
            }
            .task { if session.isSuperuser { await load() } }
            .refreshable { if session.isSuperuser { await load() } }
        }
    }

    @ViewBuilder
    private var serverSettings: some View {
        if let message {
            Section {
                Label(message.0, systemImage: message.1 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(message.1 ? .green : .red)
                    .font(.footnote)
            }
        }

        Section {
            if priv != nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Chu kỳ ping (cron)").font(.caption).foregroundStyle(.secondary)
                    TextField("@every 3s", text: optional(\.interval))
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Toggle("Lazy ping", isOn: Binding(
                    get: { priv?.lazyPing ?? false },
                    set: { priv?.lazyPing = $0 }
                ))
                if priv?.trackIpInterval != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Chu kỳ theo dõi IP (cron)").font(.caption).foregroundStyle(.secondary)
                        TextField("@every 1h", text: optional(\.trackIpInterval))
                            .font(.system(.body, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        } header: {
            Text("Máy chủ UpSnap")
        } footer: {
            Text("Lazy ping: chỉ ping thiết bị khi có người đang mở UpSnap.")
        }

        if pub != nil {
            Section("Giao diện web") {
                TextField("Tiêu đề website", text: Binding(
                    get: { pub?.websiteTitle ?? "" },
                    set: { pub?.websiteTitle = $0 }
                ))
            }
        }
    }

    private func optional(_ kp: WritableKeyPath<PrivateSettings, String?>) -> Binding<String> {
        Binding(get: { priv?[keyPath: kp] ?? "" }, set: { priv?[keyPath: kp] = $0 })
    }

    private func load() async {
        do {
            async let a = client.get(PBList<PrivateSettings>.self, path: "/api/collections/settings_private/records")
            async let b = client.get(PBList<PublicSettings>.self, path: "/api/collections/settings_public/records")
            let (p, q) = try await (a.items.first, b.items.first)
            priv = p; pub = q
            original = (p, q)
        } catch {
            message = (error.localizedDescription, false)
        }
    }

    private func save() {
        saving = true
        Task {
            do {
                if let priv, priv != original.0 {
                    try await client.send("PATCH", path: "/api/collections/settings_private/records/\(priv.id)", body: priv)
                }
                if let pub, pub != original.1 {
                    try await client.send("PATCH", path: "/api/collections/settings_public/records/\(pub.id)", body: pub)
                }
                original = (priv, pub)
                message = (tr("Đã lưu cài đặt"), true)
            } catch {
                message = (error.localizedDescription, false)
            }
            saving = false
        }
    }
}
