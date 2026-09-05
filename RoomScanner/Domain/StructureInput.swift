import Foundation

/// Instantané neutre d'une **maison** scannée pièce par pièce dans un même repère
/// monde (session AR conservée) : les scans de chaque pièce plus, optionnellement,
/// les surfaces fusionnées fournies par la structure Apple (`CapturedStructure`),
/// converties par l'adaptateur iOS. Le Domain ne connaît jamais RoomPlan (v2, D26).
struct StructureInput: Codable, Equatable, Identifiable {
    var id: UUID
    /// Une entrée par pièce, coordonnées monde partagées.
    var rooms: [ScanInput]
    /// Murs / sols fusionnés par Apple (dédoublonnés) ; vides si la structure n'est pas disponible.
    var mergedWalls: [ScanSurface]
    var mergedFloors: [ScanSurface]

    init(id: UUID = UUID(), rooms: [ScanInput], mergedWalls: [ScanSurface] = [], mergedFloors: [ScanSurface] = []) {
        self.id = id; self.rooms = rooms; self.mergedWalls = mergedWalls; self.mergedFloors = mergedFloors
    }
}
