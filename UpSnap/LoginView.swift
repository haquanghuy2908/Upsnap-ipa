import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: SessionModel

    @AppStorage("lastServer") private var server = ""
    @State private var identity = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        !server.isEmpty && !identity.isEmpty && !password.isEmpty && !isLoading
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "power.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.tint)
                        Text("UpSnap")
                            .font(.largeTitle.bold())
                        Text("Bật máy tính từ xa qua máy chủ UpSnap của bạn")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

                Section {
                    TextField("http://192.168.1.10:8090", text: $server)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Địa chỉ máy chủ")
                } footer: {
                    Text("Địa chỉ bạn dùng để mở UpSnap trên trình duyệt (IP NAS + port, hoặc tên miền).")
                }

                Section("Tài khoản") {
                    TextField("Email hoặc username", text: $identity)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Mật khẩu", text: $password)
                        .textContentType(.password)
                        .onSubmit(submit)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if isLoading { ProgressView() } else { Text("Đăng nhập").bold() }
                            Spacer()
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
            .onAppear {
                if identity.isEmpty { identity = session.identity ?? "" }
            }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await session.login(server: server, identity: identity, password: password)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
