import XCTest
@testable import RoomScanner

/// Écrit un stockage de démonstration `<tmp>/RoomScannerDemo` (deux pièces) utilisé
/// pour lancer l'app avec `-RoomScannerStorageRoot` (captures d'écran, essais manuels).
@MainActor
final class DemoDataTests: XCTestCase {
    static let demoRoot = FileManager.default.temporaryDirectory.appendingPathComponent("RoomScannerDemo", isDirectory: true)

    func testWriteDemoStorage() throws {
        let location = StorageLocation(kind: .local, documentsURL: Self.demoRoot)
        try? FileManager.default.removeItem(at: Self.demoRoot)
        let store = RoomStore(location: location); store.reload()
        let salonScan = SyntheticRooms.rectangularRoom().scan
        let salon = FloorPlanBuilder().build(from: salonScan, name: "Salon")
        try store.save(RoomPackage(record: RoomRecord(plan: salon, createdAt: Date(timeIntervalSinceNow: -86400)), plan: salon, scan: salonScan,
                                   thumbnailPNG: PlanRenderer.thumbnailPNG(for: salon)))
        let chambreScan = SyntheticRooms.lShapedRoom()
        let chambre = FloorPlanBuilder().build(from: chambreScan, name: "Chambre")
        try store.save(RoomPackage(record: RoomRecord(plan: chambre), plan: chambre, scan: chambreScan,
                                   thumbnailPNG: PlanRenderer.thumbnailPNG(for: chambre)))
        XCTAssertEqual(RoomStore(location: location).records.count, 0, "la liste se charge à reload()")
        let fresh = RoomStore(location: location); fresh.reload()
        XCTAssertEqual(fresh.records.map(\.name), ["Chambre", "Salon"])
    }
}
