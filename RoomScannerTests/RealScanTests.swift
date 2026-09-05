import XCTest
@testable import RoomScanner

/// Scan réel (salle à manger ouverte sur cuisine, iPhone 16 Pro, 2026-09-05) : ce que RoomPlan
/// livre vraiment — 22 murs non chaînables, sol à 44 sommets, repère monde incliné.
final class RealScanTests: XCTestCase {
    static func load(_ name: String) throws -> ScanInput {
        let url = try XCTUnwrap(Bundle(for: RealScanTests.self).url(forResource: name, withExtension: "json"), "fixture \(name).json absente du bundle de tests")
        return try RoomPackage.decoder.decode(ScanInput.self, from: Data(contentsOf: url))
    }

    func testFloorPolygonComesFromRoomPlanCorners() throws {
        let scan = try Self.load("dining-room.scan")
        XCTAssertEqual(scan.walls.count, 22); XCTAssertEqual(scan.floors.first?.polygonCorners.count, 44)
        let plan = FloorPlanBuilder().build(from: scan, name: "Salle à manger")
        XCTAssertGreaterThan(plan.floorPolygon.count, 4, "vrai contour, pas l'englobant")
        XCTAssertLessThan(plan.floorPolygon.count, 44, "sommets colinéaires simplifiés")
        let area = RoomMeasurements(plan: plan).floorArea
        let b = plan.bounds
        XCTAssertLessThan(area, b.width * b.height * 0.95, "la surface du polygone est inférieure à celle de l'englobant")
        XCTAssertGreaterThan(area, 20); XCTAssertLessThan(area, 54, "l'ancienne valeur (englobant) était 54,4 m²")
        // Le contour du sol est contenu dans l'englobant des murs (à 30 cm près).
        let wallsBounds = Rect2D.bounding(plan.walls.flatMap { [$0.start, $0.end] }).insetBy(0.3)
        for p in plan.floorPolygon { XCTAssertTrue(p.x >= wallsBounds.minX && p.x <= wallsBounds.maxX && p.y >= wallsBounds.minY && p.y <= wallsBounds.maxY, "\(p)") }
    }

    func testPlanIsAlignedOnLongestWall() throws {
        let scan = try Self.load("dining-room.scan")
        let plan = FloorPlanBuilder().build(from: scan, name: "Salle à manger")
        let longest = try XCTUnwrap(plan.walls.max { $0.length < $1.length })
        XCTAssertEqual(abs(sin(longest.segment.angle)), 0, accuracy: 1e-6, "mur le plus long horizontal")
        // Sans alignement, ce même mur est incliné.
        var raw = FloorPlanBuilder(); raw.alignToLongestWall = false
        let rawLongest = try XCTUnwrap(raw.build(from: scan, name: "x").walls.max { $0.length < $1.length })
        XCTAssertGreaterThan(abs(sin(rawLongest.segment.angle)), 0.1)
        // Les longueurs et la surface sont invariantes par rotation.
        XCTAssertEqual(longest.length, rawLongest.length, accuracy: 1e-6)
        XCTAssertEqual(RoomMeasurements(plan: plan).floorArea, RoomMeasurements(plan: raw.build(from: scan, name: "x")).floorArea, accuracy: 1e-6)
        // Les ouvertures restent sur leur mur après rotation.
        for o in plan.openings { if let w = plan.wall(withID: o.wallID) { XCTAssertLessThan(w.segment.distance(to: o.center), 0.15) } }
    }

    func testRealScanRendersAndExports() throws {
        let plan = FloorPlanBuilder().build(from: try Self.load("dining-room.scan"), name: "Salle à manger")
        let house = House(room: plan)
        XCTAssertGreaterThan(PlanRenderer().pdfData(house).count, 2000)
        XCTAssertTrue(XMLParser(data: SVGExporter().data(for: house)).parse())
        let mesh = PlanMeshBuilder().build(house)
        XCTAssertFalse(mesh.normals.contains { $0.x.isNaN || $0.y.isNaN || $0.z.isNaN })
        XCTAssertFalse(mesh.isEmpty)
        // Échantillons pour inspection.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("RoomScannerRealScan", isDirectory: true)
        try? FileManager.default.removeItem(at: dir); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try PlanRenderer().pdfData(house).write(to: dir.appendingPathComponent("dining-room.pdf"))
        try XCTUnwrap(PlanRenderer().pngData(house, pageSize: CGSize(width: 842, height: 595), pixelScale: 2)).write(to: dir.appendingPathComponent("dining-room.png"))
    }

    @MainActor
    func testStoreRebuildsStoredPlanFromScan() throws {
        let scan = try Self.load("dining-room.scan")
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("RealScanStore-\(UUID().uuidString)")
        let store = RoomStore(location: StorageLocation(kind: .local, documentsURL: tmp), allowsCloud: false)
        // Ancien plan (englobant, incliné) tel qu'écrit par une version précédente.
        var old = FloorPlanBuilder(); old.alignToLongestWall = false
        var oldPlan = old.build(from: scan, name: "Salle à manger"); oldPlan.floorPolygon = []
        let rec = try store.save(RoomPackage(record: RoomRecord(plan: oldPlan), plan: oldPlan, scan: scan))
        let fresh = try store.plan(for: rec)
        XCTAssertGreaterThan(fresh.floorPolygon.count, 4)
        XCTAssertEqual(try RoomPackage.readPlan(from: store.packageURL(for: rec)), fresh, "plan.json rafraîchi")
        XCTAssertEqual(store.records.first?.areaM2 ?? 0, RoomMeasurements(plan: fresh).floorArea, accuracy: 1e-9)
        XCTAssertNotNil(RoomPackage.thumbnailURL(in: store.packageURL(for: rec)))
        try? FileManager.default.removeItem(at: tmp)
    }
}
