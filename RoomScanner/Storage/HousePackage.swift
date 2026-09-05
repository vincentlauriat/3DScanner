import Foundation
import UniformTypeIdentifiers

/// Paquet `.housescan` (v2, D25) : `meta.json` (`HouseRecord`), `house.json` (`House`),
/// `structure.json` (`StructureInput` neutre), `structure-apple.json` (`CapturedStructure`,
/// opaque ici), `rooms/<uuid>.roomscan` (paquets v1 inchangés), `house.usdz`, `thumbnail.png`.
/// Écrit en une opération coordonnée, comme `RoomPackage`.
struct HousePackage {
    var record: HouseRecord
    var house: House
    var structure: StructureInput?
    var capturedStructureData: Data?
    var rooms: [RoomPackage]
    var usdzData: Data?
    var thumbnailPNG: Data?

    typealias F = FileLayout.HousePackageFile

    /// Captures brutes d'une pièce (Apple `room.json`, USDZ paramétrique, maillage), à imbriquer.
    struct RoomExtras { var capturedRoomData: Data?; var usdzData: Data?; var usdzMeshData: Data? }

    /// Assemble un paquet complet depuis une structure neutre : la maison est construite par
    /// `HouseBuilder`, chaque pièce reçoit son `.roomscan` (plan, scan, captures brutes, vignette).
    static func assemble(structure: StructureInput, name: String, capturedStructureData: Data?, usdzData: Data?,
                         roomExtras: [UUID: RoomExtras] = [:], createdAt: Date = Date()) -> HousePackage {
        let house = HouseBuilder().build(from: structure, name: name)
        let rooms = house.allRooms.map { plan -> RoomPackage in
            let extras = roomExtras[plan.id]
            return RoomPackage(record: RoomRecord(plan: plan, createdAt: createdAt), plan: plan,
                               scan: structure.rooms.first { $0.id == plan.id },
                               capturedRoomData: extras?.capturedRoomData, usdzData: extras?.usdzData, usdzMeshData: extras?.usdzMeshData,
                               thumbnailPNG: PlanRenderer.thumbnailPNG(for: plan))
        }
        return HousePackage(record: HouseRecord(house: house, createdAt: createdAt), house: house, structure: structure,
                            capturedStructureData: capturedStructureData, rooms: rooms, usdzData: usdzData,
                            thumbnailPNG: PlanRenderer.thumbnailPNG(for: house))
    }

    func write(to packageURL: URL, fileManager fm: FileManager = .default) throws {
        let staging = fm.temporaryDirectory.appendingPathComponent("housescan-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging.appendingPathComponent(F.rooms, isDirectory: true), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        try RoomPackage.encoder.encode(record).write(to: staging.appendingPathComponent(F.meta))
        try RoomPackage.encoder.encode(house).write(to: staging.appendingPathComponent(F.house))
        if let structure { try RoomPackage.encoder.encode(structure).write(to: staging.appendingPathComponent(F.structure)) }
        if let capturedStructureData { try capturedStructureData.write(to: staging.appendingPathComponent(F.capturedStructure)) }
        if let usdzData { try usdzData.write(to: staging.appendingPathComponent(F.usdz)) }
        if let thumbnailPNG { try thumbnailPNG.write(to: staging.appendingPathComponent(F.thumbnail)) }
        for room in rooms {
            try room.write(to: staging.appendingPathComponent(F.rooms).appendingPathComponent(room.record.id.uuidString).appendingPathExtension(FileLayout.packageExtension))
        }
        try fm.createDirectory(at: packageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try RoomPackage.coordinatedWrite(at: packageURL, options: .forReplacing) { url in
            if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
            try fm.moveItem(at: staging, to: url)
        }
    }

    // MARK: Lecture

    static func readRecord(from url: URL) throws -> HouseRecord {
        try RoomPackage.coordinatedRead(at: url) { u in try RoomPackage.decoder.decode(HouseRecord.self, from: Data(contentsOf: u.appendingPathComponent(F.meta))) }
    }

    static func readHouse(from url: URL) throws -> House {
        try RoomPackage.coordinatedRead(at: url) { u in try RoomPackage.decoder.decode(House.self, from: Data(contentsOf: u.appendingPathComponent(F.house))) }
    }

    static func readStructure(from url: URL) throws -> StructureInput? {
        try RoomPackage.coordinatedRead(at: url) { u in
            let f = u.appendingPathComponent(F.structure)
            guard FileManager.default.fileExists(atPath: f.path) else { return nil }
            return try RoomPackage.decoder.decode(StructureInput.self, from: Data(contentsOf: f))
        }
    }

    /// URLs des paquets de pièces imbriqués.
    static func roomPackageURLs(in url: URL) -> [URL] {
        let dir = url.appendingPathComponent(F.rooms, isDirectory: true)
        return ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == FileLayout.packageExtension }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func usdzURL(in url: URL) -> URL? {
        let f = url.appendingPathComponent(F.usdz); return FileManager.default.fileExists(atPath: f.path) ? f : nil
    }
    static func thumbnailURL(in url: URL) -> URL? {
        let f = url.appendingPathComponent(F.thumbnail); return FileManager.default.fileExists(atPath: f.path) ? f : nil
    }

    /// Réécrit `meta.json` et `house.json` (renommage, recalcul) sans toucher au reste.
    static func update(record: HouseRecord, house: House, in url: URL) throws {
        try RoomPackage.coordinatedWrite(at: url, options: .forMerging) { u in
            try RoomPackage.encoder.encode(record).write(to: u.appendingPathComponent(F.meta), options: .atomic)
            try RoomPackage.encoder.encode(house).write(to: u.appendingPathComponent(F.house), options: .atomic)
        }
    }

    static func writeThumbnail(_ png: Data, in url: URL) throws {
        try RoomPackage.coordinatedWrite(at: url, options: .forMerging) { u in try png.write(to: u.appendingPathComponent(F.thumbnail), options: .atomic) }
    }

    static func delete(at url: URL) throws {
        try RoomPackage.coordinatedWrite(at: url, options: .forDeleting) { u in try FileManager.default.removeItem(at: u) }
    }
}

extension UTType {
    /// `fr.vincentlauriat.roomscanner.house`, déclaré dans les Info.plist des deux cibles.
    static let houseScan = UTType(exportedAs: "fr.vincentlauriat.roomscanner.house", conformingTo: .package)
}
