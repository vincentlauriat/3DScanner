import XCTest
@testable import RoomScanner

/// iCloud n'est pas disponible dans les tests : on couvre la logique pure
/// (statuts, vainqueur d'un conflit, copies, migration hors ubiquité, chemins).
final class CloudStorageTests: XCTestCase {
    private var tmp: URL!
    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("CloudStorageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func package(named name: String) -> RoomPackage {
        let plan = FloorPlanBuilder().build(from: SyntheticRooms.rectangularRoom().scan, name: name)
        return RoomPackage(record: RoomRecord(plan: plan), plan: plan, scan: nil)
    }

    func testDocumentsURLAndPreferenceDefault() {
        XCTAssertEqual(CloudAvailability.documentsURL(containerURL: URL(fileURLWithPath: "/c")).path, "/c/Documents")
        UserDefaults.standard.removeObject(forKey: CloudAvailability.preferenceKey)
        XCTAssertTrue(CloudAvailability.isEnabledByUser, "iCloud actif par défaut")
        UserDefaults.standard.set(false, forKey: CloudAvailability.preferenceKey)
        XCTAssertFalse(CloudAvailability.isEnabledByUser)
        XCTAssertNil(CloudAvailability.resolveLocation(), "désactivé par l'utilisateur → local")
        UserDefaults.standard.removeObject(forKey: CloudAvailability.preferenceKey)
        XCTAssertEqual(CloudAvailability.containerIdentifier, "iCloud.fr.vincentlauriat.roomscanner")
    }

    func testMigrationIsNoopBetweenLocalRoots() throws {
        let a = StorageLocation(kind: .local, documentsURL: tmp.appendingPathComponent("a")), b = StorageLocation(kind: .iCloud, documentsURL: tmp.appendingPathComponent("b"))
        XCTAssertEqual(try CloudAvailability.migrate(from: b, to: a), 0, "sens interdit")
        XCTAssertEqual(try CloudAvailability.migrate(from: a, to: a), 0)
    }

    func testCloudItemStatusFromAttributes() throws {
        let url = tmp.appendingPathComponent("x.roomscan")
        let s = try XCTUnwrap(CloudItemStatus(attributes: [
            NSMetadataItemURLKey: url,
            NSMetadataUbiquitousItemDownloadingStatusKey: NSMetadataUbiquitousItemDownloadingStatusNotDownloaded,
            NSMetadataUbiquitousItemIsDownloadingKey: true,
            NSMetadataUbiquitousItemPercentDownloadedKey: 42.0,
        ]))
        XCTAssertEqual(s.download, .notDownloaded); XCTAssertFalse(s.isAvailableLocally)
        XCTAssertTrue(s.isDownloading); XCTAssertEqual(s.percentDownloaded, 42)
        let current = try XCTUnwrap(CloudItemStatus(attributes: [NSMetadataItemURLKey: url, NSMetadataUbiquitousItemDownloadingStatusKey: NSMetadataUbiquitousItemDownloadingStatusCurrent]))
        XCTAssertTrue(current.isAvailableLocally); XCTAssertEqual(current.percentDownloaded, 100)
        XCTAssertNil(CloudItemStatus(attributes: [:]))
    }

    func testConflictWinnerIsMostRecentThenCurrent() {
        let t0 = Date(), t1 = t0.addingTimeInterval(10)
        XCTAssertEqual(ConflictResolver.winnerIndex([.init(date: t0, isCurrent: true), .init(date: t1, isCurrent: false)]), 1)
        XCTAssertEqual(ConflictResolver.winnerIndex([.init(date: t1, isCurrent: true), .init(date: t0, isCurrent: false)]), 0)
        XCTAssertEqual(ConflictResolver.winnerIndex([.init(date: t0, isCurrent: false), .init(date: t0, isCurrent: true)]), 1, "égalité → version courante")
        XCTAssertNil(ConflictResolver.winnerIndex([]))
    }

    func testDuplicateAsConflictCopyGetsNewIDAndSuffix() throws {
        let pkg = package(named: "Salon")
        let url = tmp.appendingPathComponent("\(pkg.record.id.uuidString).roomscan")
        try pkg.write(to: url)
        let copy = try ConflictResolver.duplicateAsConflictCopy(packageAt: url, suffix: "(conflit)")
        XCTAssertNotEqual(copy.id, pkg.record.id)
        XCTAssertEqual(copy.name, "Salon (conflit)")
        let copyURL = tmp.appendingPathComponent("\(copy.id.uuidString).roomscan")
        XCTAssertEqual(try RoomPackage.readRecord(from: copyURL), copy)
        XCTAssertEqual(try RoomPackage.readPlan(from: copyURL).id, copy.id)
        XCTAssertEqual(try RoomPackage.readRecord(from: url).name, "Salon", "l'original est intact")
        // Destination explicite (import sandboxé : jamais dans le dossier d'origine).
        let elsewhere = tmp.appendingPathComponent("elsewhere", isDirectory: true)
        let copy2 = try ConflictResolver.duplicateAsConflictCopy(packageAt: url, suffix: "(importé)", into: elsewhere)
        XCTAssertTrue(FileManager.default.fileExists(atPath: elsewhere.appendingPathComponent("\(copy2.id.uuidString).roomscan/meta.json").path))
    }

    func testResolveWithoutConflictsIsNil() throws {
        let pkg = package(named: "Salon")
        let url = tmp.appendingPathComponent("\(pkg.record.id.uuidString).roomscan")
        try pkg.write(to: url)
        XCTAssertEqual(try ConflictResolver.resolve(packageAt: url, suffix: "(conflit)"), [])
    }

    @MainActor
    func testImportPackageAndCollision() throws {
        let store = RoomStore(location: StorageLocation(kind: .local, documentsURL: tmp.appendingPathComponent("store")), allowsCloud: false)
        store.reload()
        let pkg = package(named: "Chambre")
        let incoming = tmp.appendingPathComponent("incoming/\(pkg.record.id.uuidString).roomscan")
        try pkg.write(to: incoming)
        let first = try store.importPackage(from: incoming)
        XCTAssertEqual(first.id, pkg.record.id)
        XCTAssertEqual(store.records.map(\.name), ["Chambre"])
        let second = try store.importPackage(from: incoming)
        XCTAssertNotEqual(second.id, pkg.record.id)
        XCTAssertEqual(Set(store.records.map(\.name)), ["Chambre", "Chambre (importé)"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: incoming.path), "la source n'est pas déplacée")
    }

    @MainActor
    func testSaveExportGoesToRoomSubfolder() throws {
        let store = RoomStore(location: StorageLocation(kind: .local, documentsURL: tmp.appendingPathComponent("store")), allowsCloud: false)
        let pkg = package(named: "Salon / Séjour")
        let file = tmp.appendingPathComponent("plan.pdf"); try Data("pdf".utf8).write(to: file)
        let dest = try store.saveExport(file, for: pkg.record)
        XCTAssertEqual(dest.path, store.location.exportsURL.appendingPathComponent("Salon - Séjour/plan.pdf").path)
        XCTAssertEqual(try Data(contentsOf: dest), Data("pdf".utf8))
        try Data("pdf2".utf8).write(to: file)
        XCTAssertEqual(try Data(contentsOf: try store.saveExport(file, for: pkg.record)), Data("pdf2".utf8), "remplacement")
    }
}
