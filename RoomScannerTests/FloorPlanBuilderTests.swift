import XCTest
import simd
@testable import RoomScanner

final class FloorPlanBuilderTests: XCTestCase {
    let builder = FloorPlanBuilder()

    func testRectangularRoomWalls() {
        let (scan, _, _) = SyntheticRooms.rectangularRoom()
        let plan = builder.build(from: scan, name: "Salon")
        XCTAssertEqual(plan.walls.count, 4)
        let lengths = plan.walls.map(\.length).sorted()
        XCTAssertEqual(lengths[0], 3, accuracy: 0.001)
        XCTAssertEqual(lengths[1], 3, accuracy: 0.001)
        XCTAssertEqual(lengths[2], 4, accuracy: 0.001)
        XCTAssertEqual(lengths[3], 4, accuracy: 0.001)
        XCTAssertEqual(plan.ceilingHeight.lowerBound, 2.5, accuracy: 0.001)
        XCTAssertEqual(plan.ceilingHeight.upperBound, 2.5, accuracy: 0.001)
        XCTAssertEqual(plan.bounds.width, 4, accuracy: 0.001)
        XCTAssertEqual(plan.bounds.height, 3, accuracy: 0.001)
        XCTAssertEqual(plan.label, .livingRoom)
        XCTAssertEqual(plan.name, "Salon")
        XCTAssertEqual(plan.transform, .identity)
    }

    func testRectangularRoomFloorPolygonAndArea() {
        let (scan, _, _) = SyntheticRooms.rectangularRoom()
        let plan = builder.build(from: scan, name: "Salon")
        XCTAssertEqual(plan.floorPolygon.count, 4)
        XCTAssertEqual(Polygon2D.area(plan.floorPolygon), 12, accuracy: 0.001)
        XCTAssertGreaterThan(Polygon2D.signedArea(plan.floorPolygon), 0, "contour normalisé en sens trigonométrique")
    }

    func testOpeningsAttachToParentWall() {
        let (scan, south, north) = SyntheticRooms.rectangularRoom()
        let plan = builder.build(from: scan, name: "Salon")
        let door = plan.openings.first { $0.kind == .door }!
        let window = plan.openings.first { $0.kind == .window }!
        XCTAssertEqual(door.wallID, south.id)
        XCTAssertEqual(window.wallID, north.id)
        XCTAssertEqual(door.width, 0.9, accuracy: 0.001)
        XCTAssertEqual(door.sillHeight, 0, accuracy: 0.001)
        XCTAssertEqual(door.center.x, 1, accuracy: 0.001, "porte aux 3/4 du mur sud (x de −2 à 2)")
        XCTAssertEqual(door.center.y, -1.5, accuracy: 0.001)
        XCTAssertEqual(window.width, 1.2, accuracy: 0.001)
        XCTAssertEqual(window.height, 1.0, accuracy: 0.001)
        XCTAssertEqual(window.sillHeight, 1.0, accuracy: 0.001, "allège = bas de la fenêtre − sol")
        // La trace au sol de la porte reste sur le mur sud.
        XCTAssertEqual(door.segment.start.y, -1.5, accuracy: 0.001)
        XCTAssertEqual(door.segment.length, 0.9, accuracy: 0.001)
    }

    func testOpeningsWithoutParentFallBackToNearestWall() {
        let (scan, south, north) = SyntheticRooms.rectangularRoom(withParentIDs: false)
        let plan = builder.build(from: scan, name: "Salon")
        XCTAssertEqual(plan.openings.first { $0.kind == .door }?.wallID, south.id)
        XCTAssertEqual(plan.openings.first { $0.kind == .window }?.wallID, north.id)
    }

    func testObjects() {
        let (scan, _, _) = SyntheticRooms.rectangularRoom()
        let plan = builder.build(from: scan, name: "Salon")
        XCTAssertEqual(plan.objects.count, 1)
        let table = plan.objects[0]
        XCTAssertEqual(table.category, "table")
        XCTAssertEqual(table.center.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(table.center.y, -0.2, accuracy: 0.001)
        XCTAssertEqual(table.size.width, 1.2, accuracy: 0.001)
        XCTAssertEqual(table.size.depth, 0.8, accuracy: 0.001)
        XCTAssertEqual(table.height, 0.75, accuracy: 0.001)
    }

    func testLShapedRoom() {
        let plan = builder.build(from: SyntheticRooms.lShapedRoom(), name: "Chambre")
        XCTAssertEqual(plan.walls.count, 6)
        XCTAssertEqual(plan.floorPolygon.count, 6)
        XCTAssertEqual(Polygon2D.area(plan.floorPolygon), 24, accuracy: 0.001)
        XCTAssertEqual(plan.story, 1)
        XCTAssertEqual(plan.label, .bedroom)
    }

    func testFloorFallsBackToBoundingBoxWhenWallsDoNotClose() {
        // Trois murs seulement : le contour ne se referme pas → englobant.
        var walls = SyntheticRooms.walls(closing: SyntheticRooms.rectangleCorners)
        walls.removeLast()
        let plan = builder.build(from: ScanInput(surfaces: walls), name: "Partiel")
        XCTAssertEqual(plan.floorPolygon.count, 4)
        XCTAssertEqual(Polygon2D.area(plan.floorPolygon), 12, accuracy: 0.001)
    }

    func testEmptyScan() {
        let plan = builder.build(from: ScanInput(surfaces: []), name: "Vide")
        XCTAssertTrue(plan.walls.isEmpty)
        XCTAssertTrue(plan.floorPolygon.isEmpty)
        XCTAssertTrue(plan.bounds.isEmpty)
        XCTAssertEqual(plan.ceilingHeight, 0...0)
    }

    func testFloorPlanCodableRoundTrip() throws {
        let (scan, _, _) = SyntheticRooms.rectangularRoom()
        let plan = builder.build(from: scan, name: "Salon")
        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(FloorPlan.self, from: data)
        XCTAssertEqual(decoded, plan)
    }

    func testScanInputCodableRoundTripKeepsMatrices() throws {
        let (scan, _, _) = SyntheticRooms.rectangularRoom()
        let data = try JSONEncoder().encode(scan)
        let decoded = try JSONDecoder().decode(ScanInput.self, from: data)
        XCTAssertEqual(decoded, scan)
        XCTAssertEqual(decoded.walls[0].transform.translation, scan.walls[0].transform.translation)
    }

    func testHouseWrapsSingleRoom() {
        let plan = builder.build(from: SyntheticRooms.lShapedRoom(), name: "Chambre")
        let house = House(room: plan)
        XCTAssertEqual(house.allRooms, [plan])
        XCTAssertEqual(house.stories.first?.index, 1)
        XCTAssertEqual(house.name, "Chambre")
    }
}
