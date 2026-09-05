import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// `.roomscan` — un scan complet vu comme un seul fichier (déclaré dans les Info.plist).
    static let roomScan = UTType(exportedAs: "fr.vincentlauriat.roomscanner.room", conformingTo: .package)
}

/// Contenu d'un paquet `.roomscan` et lecture/écriture coordonnée.
///
/// Écriture : le paquet est d'abord assemblé dans un dossier temporaire puis
/// déplacé en une seule opération coordonnée, pour qu'iCloud le voie complet.
struct RoomPackage {
    var record: RoomRecord
    var plan: FloorPlan
    var scan: ScanInput?
    /// `CapturedRoom` Apple encodé — opaque ici (lisible sur iOS seulement).
    var capturedRoomData: Data?
    var usdzData: Data?
    /// Maillage brut du scan (`CapturedRoom.export(.mesh)`), optionnel.
    var usdzMeshData: Data?
    var thumbnailPNG: Data?

    /// Dates ISO 8601 *avec* fractions de seconde : lisibles dans `meta.json`
    /// et stables à l'aller-retour (la stratégie `.iso8601` standard tronque).
    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer(); try c.encode(dateFormatter.string(from: date))
        }
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            guard let date = dateFormatter.date(from: s) ?? ISO8601DateFormatter().date(from: s) else {
                throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "date invalide: \(s)"))
            }
            return date
        }
        return d
    }()

    // MARK: Écriture

    func write(to packageURL: URL, fileManager: FileManager = .default) throws {
        let staging = fileManager.temporaryDirectory
            .appendingPathComponent("roomscan-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        try Self.encoder.encode(record).write(to: staging.appendingPathComponent(FileLayout.PackageFile.meta))
        try Self.encoder.encode(plan).write(to: staging.appendingPathComponent(FileLayout.PackageFile.plan))
        if let scan { try Self.encoder.encode(scan).write(to: staging.appendingPathComponent(FileLayout.PackageFile.scan)) }
        if let capturedRoomData { try capturedRoomData.write(to: staging.appendingPathComponent(FileLayout.PackageFile.capturedRoom)) }
        if let usdzData { try usdzData.write(to: staging.appendingPathComponent(FileLayout.PackageFile.usdz)) }
        if let usdzMeshData { try usdzMeshData.write(to: staging.appendingPathComponent(FileLayout.PackageFile.usdzMesh)) }
        if let thumbnailPNG { try thumbnailPNG.write(to: staging.appendingPathComponent(FileLayout.PackageFile.thumbnail)) }

        try fileManager.createDirectory(at: packageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.coordinatedWrite(at: packageURL, options: .forReplacing) { url in
            if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
            try fileManager.moveItem(at: staging, to: url)
        }
    }

    // MARK: Lecture

    static func readRecord(from packageURL: URL) throws -> RoomRecord {
        try coordinatedRead(at: packageURL) { url in
            try decoder.decode(RoomRecord.self, from: Data(contentsOf: url.appendingPathComponent(FileLayout.PackageFile.meta)))
        }
    }

    static func readPlan(from packageURL: URL) throws -> FloorPlan {
        try coordinatedRead(at: packageURL) { url in
            try decoder.decode(FloorPlan.self, from: Data(contentsOf: url.appendingPathComponent(FileLayout.PackageFile.plan)))
        }
    }

    static func readScan(from packageURL: URL) throws -> ScanInput? {
        try coordinatedRead(at: packageURL) { url in
            let f = url.appendingPathComponent(FileLayout.PackageFile.scan)
            guard FileManager.default.fileExists(atPath: f.path) else { return nil }
            return try decoder.decode(ScanInput.self, from: Data(contentsOf: f))
        }
    }

    static func usdzURL(in packageURL: URL) -> URL? {
        let f = packageURL.appendingPathComponent(FileLayout.PackageFile.usdz)
        return FileManager.default.fileExists(atPath: f.path) ? f : nil
    }

    static func usdzMeshURL(in packageURL: URL) -> URL? {
        let f = packageURL.appendingPathComponent(FileLayout.PackageFile.usdzMesh)
        return FileManager.default.fileExists(atPath: f.path) ? f : nil
    }

    static func thumbnailURL(in packageURL: URL) -> URL? {
        let f = packageURL.appendingPathComponent(FileLayout.PackageFile.thumbnail)
        return FileManager.default.fileExists(atPath: f.path) ? f : nil
    }

    /// Réécrit `meta.json` et `plan.json` (renommage, recalcul) sans toucher au reste.
    static func update(record: RoomRecord, plan: FloorPlan, in packageURL: URL) throws {
        try coordinatedWrite(at: packageURL, options: .forMerging) { url in
            try encoder.encode(record).write(to: url.appendingPathComponent(FileLayout.PackageFile.meta), options: .atomic)
            try encoder.encode(plan).write(to: url.appendingPathComponent(FileLayout.PackageFile.plan), options: .atomic)
        }
    }

    static func writeThumbnail(_ png: Data, in packageURL: URL) throws {
        try coordinatedWrite(at: packageURL, options: .forMerging) { url in
            try png.write(to: url.appendingPathComponent(FileLayout.PackageFile.thumbnail), options: .atomic)
        }
    }

    static func delete(at packageURL: URL) throws {
        try coordinatedWrite(at: packageURL, options: .forDeleting) { url in
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: Coordination

    static func coordinatedRead<T>(at url: URL, _ body: (URL) throws -> T) throws -> T {
        var coordError: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { u in
            result = Result { try body(u) }
        }
        if let coordError { throw coordError }
        guard let result else { throw AppError.storageFailed("NSFileCoordinator n'a pas exécuté la lecture de \(url.lastPathComponent)") }
        return try result.get()
    }

    static func coordinatedWrite(at url: URL, options: NSFileCoordinator.WritingOptions, _ body: (URL) throws -> Void) throws {
        var coordError: NSError?
        var bodyError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: options, error: &coordError) { u in
            do { try body(u) } catch { bodyError = error }
        }
        if let coordError { throw coordError }
        if let bodyError { throw bodyError }
    }
}
