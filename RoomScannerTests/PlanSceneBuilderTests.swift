import XCTest
import RealityKit
@testable import RoomScanner

@MainActor
final class PlanSceneBuilderTests: XCTestCase {
    private func plan() -> FloorPlan { FloorPlanBuilder().build(from: SyntheticRooms.rectangularRoom().scan, name: "Salon") }

    func testWallBoxesCutAroundOpenings() {
        let p = plan(); let b = PlanSceneBuilder()
        let door = p.openings.first { $0.kind == .door }!, window = p.openings.first { $0.kind == .window }!
        let south = p.wall(withID: door.wallID)!, north = p.wall(withID: window.wallID)!
        // Porte : 2 portions pleines + 1 linteau (2,0 → 2,5 m)
        let s = b.wallBoxes(south, openings: [door])
        XCTAssertEqual(s.count, 3)
        let lintel = s.first { $0.bottom > 0.1 }!
        XCTAssertEqual(lintel.bottom, 2.0, accuracy: 0.001); XCTAssertEqual(lintel.top, 2.5, accuracy: 0.001)
        XCTAssertEqual(lintel.segment.length, 0.9, accuracy: 0.001)
        // Fenêtre : 2 portions pleines + allège (0 → 1,0) + linteau (2,0 → 2,5)
        let n = b.wallBoxes(north, openings: [window])
        XCTAssertEqual(n.count, 4)
        XCTAssertTrue(n.contains { abs($0.top - 1.0) < 0.001 && $0.bottom == 0 })
        XCTAssertTrue(n.contains { abs($0.bottom - 2.0) < 0.001 && abs($0.top - 2.5) < 0.001 })
        // Mur plein : une seule boîte pleine hauteur
        let east = p.walls.first { $0.id != south.id && $0.id != north.id }!
        XCTAssertEqual(b.wallBoxes(east, openings: []), [PlanSceneBuilder.WallBox(segment: east.segment, bottom: 0, top: 2.5, thickness: 0.10)])
    }

    func testFlattenedWallsIgnoreOpenings() {
        var b = PlanSceneBuilder(); b.options.flattenWalls = true
        let p = plan(); let door = p.openings.first { $0.kind == .door }!
        let boxes = b.wallBoxes(p.wall(withID: door.wallID)!, openings: [door])
        XCTAssertEqual(boxes.count, 2)
        XCTAssertTrue(boxes.allSatisfy { abs($0.top - 0.02) < 0.0001 })
    }

    func testSceneHierarchy() {
        let house = House(room: plan())
        let root = PlanSceneBuilder().makeScene(for: house)
        XCTAssertEqual(root.name, "house")
        XCTAssertEqual(root.children.count, 1)
        let room = root.children[0]
        XCTAssertTrue(room.name.hasPrefix("room:"))
        let walls = room.children.first { $0.name == "walls" }!
        XCTAssertEqual(walls.children.count, 1 + 1 + 3 + 4, "est + ouest pleins, sud avec porte, nord avec fenêtre")
        XCTAssertNotNil(room.children.first { $0.name == "floor" })
        XCTAssertEqual(room.children.first { $0.name == "panels" }?.children.count, 2)
        XCTAssertEqual(room.children.first { $0.name == "objects" }?.children.count, 1)
        XCTAssertNil(room.children.first { $0.name == "dimensions" }, "cotes désactivées par défaut")
    }

    func testWallPlacementInRealityKitSpace() {
        let p = plan()
        let root = PlanSceneBuilder().makeScene(for: House(room: p))
        let walls = root.children[0].children.first { $0.name == "walls" }!
        // Mur est : x = 2, centre en z = 0 (y_plan = 0 → z = 0), hauteur 2,5 → centre y = 1,25
        let east = walls.children.first { abs($0.position.x - 2) < 0.01 }!
        XCTAssertEqual(east.position.y, 1.25, accuracy: 0.001)
        XCTAssertEqual(east.position.z, 0, accuracy: 0.001)
        // Mur nord (y_plan = 1,5) → z = −1,5
        XCTAssertTrue(walls.children.contains { abs($0.position.z + 1.5) < 0.01 })
    }

    func testDimensionsAndMultiRoomPlacement() {
        var b = PlanSceneBuilder(); b.options.showDimensions = true
        var a = plan(); var c = plan()
        c.id = UUID(); c.transform = Transform2D(translation: Point2D(x: 10, y: 0), rotation: .pi / 2)
        let root = b.makeScene(for: House(name: "Maison", stories: [Story(index: 0, rooms: [a, c])]))
        XCTAssertEqual(root.children.count, 2)
        XCTAssertEqual(root.children[1].position.x, 10, accuracy: 0.001)
        XCTAssertEqual(root.children[0].children.first { $0.name == "dimensions" }?.children.count, 4)
        a.name = "x"  // évite l'avertissement de variable non mutée
    }

    func testFloorMeshFollowsPolygon() throws {
        let p = FloorPlanBuilder().build(from: SyntheticRooms.lShapedRoom(), name: "L")
        let mesh = try PlanSceneBuilder.floorMesh(polygon: p.floorPolygon, bounds: p.bounds)
        let b = mesh.bounds
        XCTAssertEqual(b.extents.x, 6, accuracy: 0.001); XCTAssertEqual(b.extents.z, 5, accuracy: 0.001)
        XCTAssertEqual(b.extents.y, 0, accuracy: 0.001)
    }

    func testFloorTextureCoversBounds() throws {
        let p = plan()
        let img = try XCTUnwrap(PlanRenderer().floorTextureImage(House(room: p), bounds: p.bounds, pixelsPerMeter: 100))
        XCTAssertEqual(img.width, 400); XCTAssertEqual(img.height, 300)
    }

    func testZenithLabelsLieFlatWithoutBillboard() throws {
        let plan = FloorPlanBuilder().build(from: SyntheticRooms.rectangularRoom().scan, name: "Salon")
        var b = PlanSceneBuilder(); b.options.showDimensions = true; b.options.flattenWalls = true
        let root = b.makeScene(for: House(room: plan))
        let dims = try XCTUnwrap(root.children[0].children.first { $0.name == "dimensions" })
        XCTAssertEqual(dims.children.count, 4)
        for label in dims.children {
            XCTAssertNil(label.components[BillboardComponent.self], "à plat, pas de billboard en vue zénithale")
            // Face du texte vers le haut : la normale locale +z devient +y.
            let up = label.orientation.act(SIMD3<Float>(0, 0, 1))
            XCTAssertEqual(up.y, 1, accuracy: 1e-4)
            XCTAssertLessThan(label.position.y, 0.1, "posé sur le sol aplati")
        }
        // Le libellé du mur sud (y = −1.5 → z = +1.5) est décalé vers l'extérieur (z > 1.5).
        XCTAssertTrue(dims.children.contains { $0.position.z > 1.6 && abs($0.position.x) < 0.01 })
        // Texte lisible : la direction de lecture (+x local) ne pointe jamais vers −x.
        for label in dims.children { XCTAssertGreaterThanOrEqual(label.orientation.act(SIMD3<Float>(1, 0, 0)).x, -1e-4) }

        var b3 = PlanSceneBuilder(); b3.options.showDimensions = true
        let root3 = b3.makeScene(for: House(room: plan))
        let dims3 = try XCTUnwrap(root3.children[0].children.first { $0.name == "dimensions" })
        XCTAssertTrue(dims3.children.allSatisfy { $0.components[BillboardComponent.self] != nil }, "billboard en 3D")
    }
}
