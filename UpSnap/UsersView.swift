import SwiftUI

@MainActor
final class UsersModel: ObservableObject {
    @Published var users: [PBUser] = []
    @Published var permissions: [PBPermission] = []
    @Published var devices: [Device] = []
    @Published var errorMessage: String?
    @Published var loaded = false

    private let client = UpSnapClient()
    private let all = [URLQueryItem(name: "perPage", value: "500")]

    func load() async {
        do {
            async let u = client.get(PBList<PBUser>.self, path: "/api/collections/users/records",
                                     query: all + [URLQueryItem(name: "sort", value: "username")])
            async let p = client.get(PBList<PBPermission>.self, path: "/api/collections/permissions/records", query: all)
            async let d = client.devices()
            (users, permissions, devices) = try await (u.items, p.items, d)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        loaded = true
    }

    func permission(for user: PBUser) -> PBPermission {
        permissions.first { $0.user == user.id } ?? PBPermission(user: user.id)
    }

    func createUser(username: String, password: String) async throws {
        try await client.send("POST", path: "/api/collections/users/records",
                              body: NewUser(username: username, password: password, passwordConfirm: password))
        await load()
    }

    func delete(_ user: PBUser) async {
        do {
            if let pid = permission(for: user).id {
                try await client.delete(path: "/api/collections/permissions/records/\(pid)")
            }
            try await client.delete(path: "/api/collections/users/records/\(user.id)")
        } catch {
            errorMessage = error.localizedDescription
        }
        await load()
    }

    func save(_ permission: PBPermission) async throws {
        if let id = permission.id {
            try await client.send("PATCH", path: "/api/collections/permissions/records/\(id)", body: permission)
        } else {
            try await client.send("POST", path: "/api/collections/permissions/records", body: permission)
        }
        await load()
    }
}

struct UsersView: View {
    @StateObject private var model = UsersModel()
    @State private var showAdd = false
    @State private var userToDelete: PBUser?

    var body: some View {
        NavigationStack {
            List {
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).font(.footnote)
                }
                Section {
                    ForEach(model.users) { user in
                        NavigationLink {
                            UserPermissionView(user: user, model: model)
                        } label: {
                            UserRow(user: user, permission: model.permission(for: user), deviceCount: model.devices.count)
                        }
                        .swipeActions {
                            Button("Xoá", systemImage: "trash", role: .destructive) { userToDelete = user }
                        }
                    }
                } footer: {
                    if !model.users.isEmpty {
                        Text("Chạm vào người dùng để phân quyền từng thiết bị. Vuốt trái để xoá.")
                    }
                }
            }
            .overlay {
                if model.users.isEmpty {
                    if model.loaded {
                        ContentUnavailableView("Chưa có người dùng", systemImage: "person.2",
                                               description: Text("Nhấn + để tạo người dùng mới."))
                    } else {
                        ProgressView()
                    }
                }
            }
            .navigationTitle("Người dùng")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Thêm", systemImage: "plus") { showAdd = true }
                }
            }
            .refreshable { await model.load() }
            .task { await model.load() }
            .sheet(isPresented: $showAdd) { AddUserView(model: model) }
            .confirmationDialog(
                "Xoá người dùng \(userToDelete?.displayName ?? "")?",
                isPresented: Binding(get: { userToDelete != nil }, set: { if !$0 { userToDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Xoá", role: .destructive) {
                    if let user = userToDelete { Task { await model.delete(user) } }
                }
            }
        }
    }
}

private struct UserRow: View {
    let user: PBUser
    let permission: PBPermission
    let deviceCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName).font(.headline)
                (Text("Xem \(permission.read.count)/\(deviceCount) · Bật/tắt \(permission.power.count)/\(deviceCount)")
                 + (permission.create ? Text(" · Được tạo máy") : Text(verbatim: "")))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct UserPermissionView: View {
    let user: PBUser
    @ObservedObject var model: UsersModel

    @Environment(\.dismiss) private var dismiss
    @State private var permission: PBPermission
    @State private var original: PBPermission
    @State private var saving = false
    @State private var errorMessage: String?

    init(user: PBUser, model: UsersModel) {
        self.user = user
        self.model = model
        let p = model.permission(for: user)
        _permission = State(initialValue: p)
        _original = State(initialValue: p)
    }

    var body: some View {
        Form {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.footnote)
            }

            Section {
                Toggle("Được tạo thiết bị mới", isOn: $permission.create)
            }

            ForEach(model.devices) { device in
                Section {
                    Toggle("Xem", isOn: membership(\.read, device.id))
                    Toggle("Sửa", isOn: membership(\.update, device.id))
                    Toggle("Xoá", isOn: membership(\.delete, device.id))
                    Toggle("Bật / Tắt", isOn: membership(\.power, device.id))
                } header: {
                    HStack {
                        Text(device.name)
                        Spacer()
                        Button("Chọn hết") {
                            for kp in [\PBPermission.read, \.update, \.delete, \.power] {
                                membership(kp, device.id).wrappedValue = true
                            }
                        }
                        .font(.caption)
                        .textCase(nil)
                    }
                }
            }
        }
        .disabled(saving)
        .navigationTitle(user.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if saving {
                    ProgressView()
                } else {
                    Button("Lưu", action: save).disabled(permission == original)
                }
            }
        }
    }

    private func membership(_ keyPath: WritableKeyPath<PBPermission, [String]>, _ id: String) -> Binding<Bool> {
        Binding(
            get: { permission[keyPath: keyPath].contains(id) },
            set: { on in
                permission[keyPath: keyPath].removeAll { $0 == id }
                if on { permission[keyPath: keyPath].append(id) }
            }
        )
    }

    private func save() {
        saving = true
        Task {
            do {
                try await model.save(permission)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            saving = false
        }
    }
}

private struct AddUserView: View {
    @ObservedObject var model: UsersModel
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tên đăng nhập", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Mật khẩu (tối thiểu 8 ký tự)", text: $password)
                } footer: {
                    Text("Sau khi tạo, chạm vào người dùng để cấp quyền cho từng thiết bị.")
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).font(.footnote)
                }
            }
            .disabled(saving)
            .navigationTitle("Người dùng mới")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tạo") {
                        saving = true
                        Task {
                            do {
                                try await model.createUser(username: username, password: password)
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                            saving = false
                        }
                    }
                    .disabled(username.isEmpty || password.count < 8)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
