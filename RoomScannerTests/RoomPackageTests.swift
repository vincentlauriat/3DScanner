import XCTest
import UniformTypeIdentifiers
@testable import RoomScanner

final class RoomPackageTests: XCTestCase {
    var location: StorageLocation!

    override func setUpWithError() throws {
        location = .temporary()
        try location.prepare()
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: location.documentsURL)
    }

    private func makePackage() -> RoomPackage {
        let scan = SyntheticRooms.rectangularRoom().scan
        let plan = FloorPlanBuilder().build(from: scan, name: "Salon")
        return RoomPackage(record: RoomRecord(plan: plan), plan: plan, scan: scan,
                           capturedRoomData: Data("{\"apple\":true}".utf8), usdzData: Data([0x50, 0x4B]), thumbnailPNG: nil)
    }

    func testUTType() {
        XCTAssertEqual(UTType.roomScan.identifier, "fr.vincentlauriat.roomscanner.room")
        XCTAssertTrue(UTType.roomScan.conforms(to: .package))
    }

    func testWriteThenReadRoundTrip() throws {
        let pkg = makePackage()
        let url = location.packageURL(for: pkg.record.id)
        try pkg.write(to: url)

        XCTAssertEqual(url.pathExtension, "roomscan")
        let contents = try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
        XCTAssertEqual(contents, ["meta.json", "plan.json", "room.json", "room.usdz", "scan.json"])

        XCTAssertEqual(try RoomPackage.readRecord(from: url), pkg.record)
        XCTAssertEqual(try RoomPackage.readPlan(from: url), pkg.plan)
        XCTAssertEqual(try RoomPackage.readScan(from: url), pkg.scan)
        XCTAssertNotNil(RoomPackage.usdzURL(in: url))
        XCTAssertNil(RoomPackage.thumbnailURL(in: url))
    }

    func testRewriteReplacesPackage() throws {
        var pkg = makePackage()
        let url = location.packageURL(for: pkg.record.id)
        try pkg.write(to: url)
        pkg.record.name = "Séjour"; pkg.plan.name = "Séjour"; pkg.usdzData = nil
        try pkg.write(to: url)
        XCTAssertEqual(try RoomPackage.readRecord(from: url).name, "Séjour")
        XCTAssertNil(RoomPackage.usdzURL(in: url), "l'ancien USDZ ne survit pas au remplacement")
    }

    func testUpdateMetaAndPlanOnly() throws {
        var pkg = makePackage()
        let url = location.packageURL(for: pkg.record.id)
        try pkg.write(to: url)
        pkg.record.name = "Renommée"; pkg.plan.name = "Renommée"
        try RoomPackage.update(record: pkg.record, plan: pkg.plan, in: url)
        XCTAssertEqual(try RoomPackage.readRecord(from: url).name, "Renommée")
        XCTAssertNotNil(RoomPackage.usdzURL(in: url), "les autres fichiers sont conservés")
    }

    func testThumbnailWriteAndDelete() throws {
        let pkg = makePackage()
        let url = location.packageURL(for: pkg.record.id)
        try pkg.write(to: url)
        try RoomPackage.writeThumbnail(Data([0x89, 0x50]), in: url)
        XCTAssertNotNil(RoomPackage.thumbnailURL(in: url))
        try RoomPackage.delete(at: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testMetaUsesISO8601Dates() throws {
        let pkg = makePackage()
        let url = location.packageURL(for: pkg.record.id)
        try pkg.write(to: url)
        let meta = try String(contentsOf: url.appendingPathComponent("meta.json"), encoding: .utf8)
        XCTAssertTrue(meta.contains("\"createdAt\":\"20"), meta)
        XCTAssertTrue(meta.contains("\"schemaVersion\":\(FloorPlan.schemaVersion)"))
    }
}
