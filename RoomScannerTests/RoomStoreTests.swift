import XCTest
@testable import RoomScanner

@MainActor
final class RoomStoreTests: XCTestCase {
    var location: StorageLocation!
    var store: RoomStore!

    override func setUp() async throws {
        location = .temporary()
        store = RoomStore(location: location)
        store.reload()
    }
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: location.documentsURL)
    }

    private func package(named name: String, label: RoomLabel = .livingRoom, at date: Date = Date()) -> RoomPackage {
        var scan = SyntheticRooms.rectangularRoom().scan
        scan.id = UUID(); scan.sectionLabels = [label]
        let plan = FloorPlanBuilder().build(from: scan, name: name)
        return RoomPackage(record: RoomRecord(plan: plan, createdAt: date), plan: plan, scan: scan)
    }

    func testEmptyStoreCreatesFolders() {
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertNil(store.lastError)
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.roomsURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.exportsURL.path))
    }

    func testSaveListsNewestFirstAndSurvivesReload() throws {
        try store.save(package(named: "Ancienne", at: Date(timeIntervalSinceNow: -3600)))
        try store.save(package(named: "Récente"))
        XCTAssertEqual(store.records.map(\.name), ["Récente", "Ancienne"])
        let fresh = RoomStore(location: location)
        fresh.reload()
        XCTAssertEqual(fresh.records.map(\.name), ["Récente", "Ancienne"])
        XCTAssertEqual(fresh.records[0].areaM2, 12, accuracy: 0.001)
    }

    func testProposedNameDedupes() throws {
        XCTAssertEqual(store.proposedName(for: .bedroom), RoomNaming.defaultBaseName(.bedroom))
        try store.save(package(named: RoomNaming.defaultBaseName(.bedroom), label: .bedroom))
        XCTAssertEqual(store.proposedName(for: .bedroom), RoomNaming.defaultBaseName(.bedroom) + " 2")
    }

    func testRenameUpdatesRecordAndPlan() throws {
        let record = try store.save(package(named: "Salon"))
        try store.rename(record, to: "  Séjour ")
        XCTAssertEqual(store.records[0].name, "Séjour")
        XCTAssertEqual(try store.plan(for: store.records[0]).name, "Séjour")
        try store.rename(store.records[0], to: "   ")
        XCTAssertEqual(store.records[0].name, "Séjour", "un nom vide est ignoré")
    }

    func testDeleteRemovesPackage() throws {
        let record = try store.save(package(named: "Salon"))
        let url = store.packageURL(for: record)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        try store.delete(record)
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testReloadIgnoresForeignFiles() throws {
        try store.save(package(named: "Salon"))
        try Data().write(to: location.roomsURL.appendingPathComponent("notes.txt"))
        try FileManager.default.createDirectory(at: location.roomsURL.appendingPathComponent("broken.roomscan"), withIntermediateDirectories: true)
        store.reload()
        XCTAssertEqual(store.records.count, 1)
    }
}
