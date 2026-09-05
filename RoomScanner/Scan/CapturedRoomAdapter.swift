#if canImport(RoomPlan)
import Foundation
import RoomPlan

/// Seul endroit du projet qui lit les types RoomPlan : convertit un
/// `CapturedRoom` en `ScanInput` neutre pour le Domain.
enum CapturedRoomAdapter {
    static func scanInput(from room: CapturedRoom) -> ScanInput {
        let surfaces = room.walls.map { surface($0, .wall) }
            + room.doors.map { surface($0, .door) }
            + room.windows.map { surface($0, .window) }
            + room.openings.map { surface($0, .opening) }
            + room.floors.map { surface($0, .floor) }
        let objects = room.objects.map {
            ScanObject(id: $0.identifier, category: String(describing: $0.category),
                       dimensions: $0.dimensions, transform: $0.transform, confidence: confidence($0.confidence))
        }
        let labels = room.sections.compactMap { RoomLabel(rawValue: String(describing: $0.label)) }
        return ScanInput(id: room.identifier, story: room.story, sectionLabels: labels, surfaces: surfaces, objects: objects)
    }

    static func surface(_ s: CapturedRoom.Surface, _ category: ScanSurface.Category) -> ScanSurface {
        ScanSurface(id: s.identifier, category: category, dimensions: s.dimensions, transform: s.transform,
                    confidence: confidence(s.confidence), parentID: s.parentIdentifier, polygonCorners: s.polygonCorners)
    }

    private static func confidence(_ c: CapturedRoom.Confidence) -> Confidence {
        switch c { case .high: .high; case .medium: .medium; case .low: .low; @unknown default: .medium }
    }

    /// Encodage Apple brut (`room.json`) — source de vérité pour la fusion v2.
    static func encode(_ room: CapturedRoom) throws -> Data {
        try RoomPackage.encoder.encode(room)
    }

    /// USDZ produit par RoomPlan : `.parametric` (murs/ouvertures/objets en volumes) ou `.mesh` (maillage brut).
    static func usdzData(for room: CapturedRoom, options: CapturedRoom.USDExportOptions = .parametric) throws -> Data {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(room.identifier.uuidString)-\(UUID().uuidString).usdz")
        defer { try? FileManager.default.removeItem(at: url) }
        try room.export(to: url, exportOptions: options)
        return try Data(contentsOf: url)
    }
}
#endif
