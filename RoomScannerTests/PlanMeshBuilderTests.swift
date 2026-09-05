import XCTest
import simd
@testable import RoomScanner

final class PlanMeshBuilderTests: XCTestCase {
    private let plan = FloorPlanBuilder().build(from: SyntheticRooms.rectangularRoom().scan, name: "Salon")

    func testGroupsAndCounts() {
        let mesh = PlanMeshBuilder().build(House(room: plan))
        XCTAssertEqual(mesh.groups.map(\.name), ["walls", "doors", "windows", "floor", "objects"])
        // Murs : sud (2 portions + linteau), est, nord (2 portions + allège + linteau), ouest = 9 boîtes × 12 triangles.
        let boxes = plan.walls.reduce(0) { acc, wall in acc + WallGeometry().wallBoxes(wall, openings: plan.openings.filter { $0.wallID == wall.id }).count }
        XCTAssertEqual(boxes, 9)
        XCTAssertEqual(mesh.groups[0].triangles.count, boxes * 12)
        XCTAssertEqual(mesh.groups[1].triangles.count, 12, "un panneau de porte")
        XCTAssertEqual(mesh.groups[2].triangles.count, 12, "un vitrage")
        XCTAssertEqual(mesh.groups[3].triangles.count, 2 * 2 + 4 * 2, "dalle rectangulaire : dessus, dessous, 4 flancs")
        XCTAssertEqual(mesh.groups[4].triangles.count, 12, "une table")
        XCTAssertEqual(mesh.positions.count, mesh.normals.count)
        XCTAssertTrue(mesh.triangles.allSatisfy { Int($0.max()) < mesh.positions.count })
        XCTAssertTrue(mesh.normals.allSatisfy { abs(simd_length($0) - 1) < 1e-4 })
    }

    func testBoundsMatchRoom() throws {
        let mesh = PlanMeshBuilder().build(House(room: plan))
        let b = try XCTUnwrap(mesh.bounds)
        // 4 × 3 m centrés à l'origine, murs de 10 cm centrés sur le segment ; dalle 5 cm sous le sol ; plafond 2.5 m.
        XCTAssertEqual(b.min.x, -2.05, accuracy: 0.001); XCTAssertEqual(b.max.x, 2.05, accuracy: 0.001)
        XCTAssertEqual(b.min.z, -1.55, accuracy: 0.001); XCTAssertEqual(b.max.z, 1.55, accuracy: 0.001)
        XCTAssertEqual(b.min.y, -0.05, accuracy: 0.001); XCTAssertEqual(b.max.y, 2.5, accuracy: 0.001)
    }

    func testOutwardNormals() {
        // Pour une boîte convexe, chaque normale de face pointe à l'opposé du centre de la boîte.
        var mesh = TriangleMesh()
        let box = WallGeometry.Box(segment: Segment2D(start: Point2D(x: 0, y: 0), end: Point2D(x: 2, y: 0)), bottom: 0, top: 1, thickness: 0.2)
        PlanMeshBuilder.addBox(box, transform: .identity, to: &mesh)
        let center = SIMD3<Float>(1, 0.5, 0)
        for t in mesh.triangles {
            let c = (mesh.positions[Int(t.x)] + mesh.positions[Int(t.y)] + mesh.positions[Int(t.z)]) / 3
            XCTAssertGreaterThan(simd_dot(mesh.normals[Int(t.x)], c - center), 0)
        }
        XCTAssertEqual(mesh.triangles.count, 12)
    }

    func testLShapedFloorUsesPolygon() {
        let l = FloorPlanBuilder().build(from: SyntheticRooms.lShapedRoom(), name: "L")
        var mesh = TriangleMesh()
        PlanMeshBuilder.addFloor(l, transform: .identity, thickness: 0.05, to: &mesh)
        XCTAssertEqual(l.floorPolygon.count, 6)
        XCTAssertEqual(mesh.triangles.count, 4 * 2 + 6 * 2, "6 sommets → 4 triangles dessus + dessous, 6 flancs")
    }

    func testFloorNormalsPointOutward() {
        let mesh = PlanMeshBuilder().build(House(room: plan))
        let floor = mesh.groups.first { $0.name == "floor" }!
        let centroid = SIMD3<Float>(0, -0.025, 0)
        for i in floor.triangles {
            let t = mesh.triangles[i]
            let c = (mesh.positions[Int(t.x)] + mesh.positions[Int(t.y)] + mesh.positions[Int(t.z)]) / 3
            let n = mesh.normals[Int(t.x)]
            if abs(c.y) < 1e-5 { XCTAssertGreaterThan(n.y, 0.99, "dessus") }
            else if abs(c.y + 0.05) < 1e-5 { XCTAssertLessThan(n.y, -0.99, "dessous") }
            else { XCTAssertGreaterThan(simd_dot(n, c - centroid), 0, "flanc") }
        }
    }

    func testEmptyHouse() {
        XCTAssertTrue(PlanMeshBuilder().build(House(name: "Vide", stories: [])).isEmpty)
    }

    func testNoNaNNormalsWithAlignedFloorVertices() {
        var p = plan
        p.floorPolygon = [Point2D(x: -2, y: -1.5), Point2D(x: 0, y: -1.5), Point2D(x: 2, y: -1.5), Point2D(x: 2, y: 1.5), Point2D(x: -2, y: 1.5)]
        let mesh = PlanMeshBuilder().build(House(room: p))
        XCTAssertFalse(mesh.normals.contains { $0.x.isNaN || $0.y.isNaN || $0.z.isNaN })
        XCTAssertFalse(mesh.positions.contains { $0.x.isNaN || $0.y.isNaN || $0.z.isNaN })
        let obj = String(decoding: MeshWriters.obj(mesh, name: "x"), as: UTF8.self)
        XCTAssertFalse(obj.lowercased().contains("nan"))
    }

    func testDegenerateFloorFallsBackToClosedRectangle() {
        var p = plan
        p.floorPolygon = [Point2D(x: 0, y: 0), Point2D(x: 1, y: 0), Point2D(x: 2, y: 0)]   // contour plat
        var mesh = TriangleMesh()
        PlanMeshBuilder.addFloor(p, transform: .identity, thickness: 0.05, to: &mesh)
        XCTAssertEqual(mesh.triangles.count, 2 * 2 + 4 * 2, "dalle rectangulaire fermée de repli")
    }
}
