import SwiftUI

@MainActor
final class LogsModel: ObservableObject {
    @Published var logs: [PBLog] = []
    @Published var errorMessage: String?
    @Published var loaded = false
    @Published var level: Int? = nil
    @Published var onlyUpSnap = true
    @Published var search = ""

    private var page = 1
    private var totalPages = 1
    private var isLoading = false
    private let client = UpSnapClient()

    var hasMore: Bool { page < totalPages }

    private var filter: String {
        var parts: [String] = []
        if let level { parts.append("level = \(level)") }
        if onlyUpSnap { parts.append("data.upsnap = true") }
        let q = search.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            let escaped = q.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
            parts.append("(message ~ '\(escaped)' || data ~ '\(escaped)')")
        }
        return parts.joined(separator: " && ")
    }

    func reload() async {
        await fetch(page: 1)
    }

    func loadMore() async {
        guard hasMore else { return }
        await fetch(page: page + 1)
    }

    private func fetch(page: Int) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false; loaded = true }
        do {
            var query = [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "perPage", value: "50"),
                URLQueryItem(name: "sort", value: "-created"),
            ]
            if !filter.isEmpty { query.append(URLQueryItem(name: "filter", value: filter)) }
            let result = try await client.get(PBPage<PBLog>.self, path: "/api/logs", query: query)
            logs = page == 1 ? result.items : logs + result.items
            self.page = result.page
            totalPages = result.totalPages
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct LogsView: View {
    @StateObject private var model = LogsModel()
    @State private var selected: PBLog?

    var body: some View {
        NavigationStack {
            List {
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).font(.footnote)
                }
                ForEach(model.logs) { log in
                    Button { selected = log } label: { LogRow(log: log) }
                        .foregroundStyle(.primary)
                }
                if model.hasMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .task { await model.loadMore() }
                }
            }
            .listStyle(.plain)
            .overlay {
                if model.logs.isEmpty {
                    if model.loaded {
                        ContentUnavailableView("Không có log", systemImage: "list.bullet.rectangle")
                    } else {
                        ProgressView()
                    }
                }
            }
            .navigationTitle("Nhật ký")
            .searchable(text: $model.search, prompt: "Tìm trong log")
            .onSubmit(of: .search) { Task { await model.reload() } }
            .onChange(of: model.search) { _, new in
                if new.isEmpty { Task { await model.reload() } }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Chỉ log UpSnap", isOn: $model.onlyUpSnap)
                        Picker("Mức độ", selection: $model.level) {
                            Text("Tất cả").tag(Int?.none)
                            Text("Debug").tag(Int?.some(-4))
                            Text("Info").tag(Int?.some(0))
                            Text("Warn").tag(Int?.some(4))
                            Text("Error").tag(Int?.some(8))
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .onChange(of: model.level) { Task { await model.reload() } }
            .onChange(of: model.onlyUpSnap) { Task { await model.reload() } }
            .refreshable { await model.reload() }
            .task { await model.reload() }
            .sheet(item: $selected) { LogDetailView(log: $0) }
        }
    }
}

private func levelColor(_ level: Int) -> Color {
    switch level {
    case ..<0: .gray
    case 0..<4: .blue
    case 4..<8: .orange
    default: .red
    }
}

private struct LogRow: View {
    let log: PBLog

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(log.levelName)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(levelColor(log.level).opacity(0.2), in: Capsule())
                    .foregroundStyle(levelColor(log.level))
                Spacer()
                if let date = log.date {
                    Text(date, format: .dateTime.day().month().hour().minute().second())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(log.message).font(.subheadline).lineLimit(2)
            if let device = log.data?.objectEntries.first(where: { $0.0 == "device" })?.1 {
                Text(device.description).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct LogDetailView: View {
    let log: PBLog
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Mức độ", value: log.levelName)
                    LabeledContent("Thời gian", value: log.date?.formatted(date: .abbreviated, time: .standard) ?? log.created)
                    Text(log.message).textSelection(.enabled)
                }
                if let data = log.data, !data.objectEntries.isEmpty {
                    Section("Dữ liệu") {
                        ForEach(data.objectEntries, id: \.0) { key, value in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(key).font(.caption).foregroundStyle(.secondary)
                                Text(value.description)
                                    .font(.system(.footnote, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Chi tiết log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Xong") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
