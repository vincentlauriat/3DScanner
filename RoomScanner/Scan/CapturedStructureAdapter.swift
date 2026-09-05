#if canImport(RoomPlan)
import Foundation
import RoomPlan

/// Convertit une `CapturedStructure` RoomPlan (fusion de plusieurs `CapturedRoom` par
/// `StructureBuilder`) en `StructureInput` neutre pour `HouseBuilder`. Comme `CapturedRoomAdapter`,
/// c'est l'un des deux seuls endroits qui lisent les types RoomPlan.
enum CapturedStructureAdapter {
    static func structureInput(from structure: CapturedStructure) -> StructureInput {
        StructureInput(id: structure.identifier,
                       rooms: structure.rooms.map(CapturedRoomAdapter.scanInput(from:)),
                       mergedWalls: structure.walls.map { CapturedRoomAdapter.surface($0, .wall) },
                       mergedFloors: structure.floors.map { CapturedRoomAdapter.surface($0, .floor) })
    }

    /// Encodage Apple brut (`structure-apple.json`) — source de vérité v2.
    static func encode(_ structure: CapturedStructure) throws -> Data {
        try RoomPackage.encoder.encode(structure)
    }

    /// USDZ de la structure entière produit par RoomPlan.
    static func usdzData(for structure: CapturedStructure, options: CapturedStructure.USDExportOptions = .parametric) throws -> Data {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(structure.identifier.uuidString)-\(UUID().uuidString).usdz")
        defer { try? FileManager.default.removeItem(at: url) }
        try structure.export(to: url, exportOptions: options)
        return try Data(contentsOf: url)
    }
}
#endif
