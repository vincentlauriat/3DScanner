import Foundation

/// Ce que l'on exporte : une pièce (`.roomscan`) ou une maison (`.housescan`). Tout l'aval
/// (`ExportService`, feuille d'export, glisser-déposer, README) ne connaît que ce type.
struct ExportSubject: Equatable {
    enum Kind: Equatable { case room, house }
    var kind: Kind
    var id: UUID
    var name: String
    var createdAt: Date
    var house: House
    /// Modèle USDZ paramétrique du paquet, s'il existe.
    var usdzURL: URL?
    /// Maillage brut du scan (pièces iPhone seulement).
    var usdzMeshURL: URL?

    init(record: RoomRecord, house: House, packageURL: URL?) {
        kind = .room; id = record.id; name = record.name; createdAt = record.createdAt; self.house = house
        usdzURL = packageURL.flatMap { RoomPackage.usdzURL(in: $0) }
        usdzMeshURL = packageURL.flatMap { RoomPackage.usdzMeshURL(in: $0) }
    }

    init(record: RoomRecord, plan: FloorPlan, packageURL: URL?) {
        self.init(record: record, house: House(room: plan), packageURL: packageURL)
    }

    init(record: HouseRecord, house: House, packageURL: URL?) {
        kind = .house; id = record.id; name = record.name; createdAt = record.createdAt; self.house = house
        usdzURL = packageURL.flatMap { HousePackage.usdzURL(in: $0) }
        usdzMeshURL = nil
    }
}
