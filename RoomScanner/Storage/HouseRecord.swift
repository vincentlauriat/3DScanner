import Foundation

/// Métadonnées d'une maison (`meta.json` du paquet `.housescan`) : ce que la
/// bibliothèque affiche sans ouvrir le modèle.
struct HouseRecord: Codable, Equatable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var createdAt: Date
    var roomCount: Int
    var storyCount: Int
    var areaM2: Double
    var schemaVersion: Int

    init(id: UUID, name: String, createdAt: Date = Date(), roomCount: Int, storyCount: Int, areaM2: Double, schemaVersion: Int = FloorPlan.schemaVersion) {
        self.id = id; self.name = name
        self.createdAt = Date(timeIntervalSince1970: (createdAt.timeIntervalSince1970 * 1000).rounded() / 1000)
        self.roomCount = roomCount; self.storyCount = storyCount; self.areaM2 = areaM2; self.schemaVersion = schemaVersion
    }

    init(house: House, createdAt: Date = Date()) {
        let m = HouseMeasurements(house: house)
        self.init(id: house.id, name: house.name, createdAt: createdAt, roomCount: m.roomCount, storyCount: m.storyCount, areaM2: m.floorArea)
    }
}
