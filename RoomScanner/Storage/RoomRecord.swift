import Foundation

/// Métadonnées d'une pièce (`meta.json` du paquet) : ce que la liste affiche
/// sans ouvrir le plan.
struct RoomRecord: Codable, Equatable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var createdAt: Date
    var label: RoomLabel
    var areaM2: Double
    var storyIndex: Int
    var schemaVersion: Int

    init(id: UUID, name: String, createdAt: Date = Date(), label: RoomLabel, areaM2: Double, storyIndex: Int, schemaVersion: Int = FloorPlan.schemaVersion) {
        self.id = id; self.name = name; self.label = label
        // Millisecondes : ce que l'ISO 8601 avec fractions conserve exactement.
        self.createdAt = Date(timeIntervalSince1970: (createdAt.timeIntervalSince1970 * 1000).rounded() / 1000)
        self.areaM2 = areaM2; self.storyIndex = storyIndex; self.schemaVersion = schemaVersion
    }

    init(plan: FloorPlan, createdAt: Date = Date()) {
        self.init(id: plan.id, name: plan.name, createdAt: createdAt, label: plan.label,
                  areaM2: RoomMeasurements(plan: plan).floorArea, storyIndex: plan.story)
    }
}
