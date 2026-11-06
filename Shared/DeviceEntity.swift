import AppIntents
import Foundation

/// Một máy tính trong UpSnap, dùng cho Shortcuts / Siri / Control Center.
struct DeviceEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Máy tính"
    static let defaultQuery = DeviceQuery()

    var id: String
    var name: String
    var ip: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: ip.map { LocalizedStringResource(stringLiteral: $0) }
        )
    }

    init(id: String, name: String, ip: String? = nil) {
        self.id = id
        self.name = name
        self.ip = ip
    }

    init(_ device: Device) {
        self.init(id: device.id, name: device.name, ip: device.ip)
    }
}

struct DeviceQuery: EntityQuery {
    func entities(for identifiers: [DeviceEntity.ID]) async throws -> [DeviceEntity] {
        let all = await loadDevices()
        return identifiers.map { id in
            all.first { $0.id == id } ?? DeviceEntity(id: id, name: tr("Máy tính"))
        }
    }

    func suggestedEntities() async throws -> [DeviceEntity] {
        await loadDevices()
    }

    private func loadDevices() async -> [DeviceEntity] {
        if let devices = try? await UpSnapClient().devices() {
            return devices.map(DeviceEntity.init)
        }
        return DeviceCache.load().map(DeviceEntity.init)
    }
}
