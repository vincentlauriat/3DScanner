import XCTest
@testable import RoomScanner

final class HouseBuilderTests: XCTestCase {
    func testStoryDetectorClustersByFloorHeight() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let stories = StoryDetector().stories(floorHeights: [a: 0, b: 0.02, c: 2.7, d: -2.6])
        XCTAssertEqual(stories[d], 0, "le plus bas est le niveau 0")
        XCTAssertEqual(stories[a], 1); XCTAssertEqual(stories[b], 1, "0.02 m d'écart → même niveau")
        XCTAssertEqual(stories[c], 2)
        XCTAssertEqual(StoryDetector().stories(floorHeights: [:]), [:])
        XCTAssertEqual(StoryDetector(tolerance: 3).stories(floorHeights: [a: 0, c: 2.7]), [a: 0, c: 0])
    }

    func testFloorHeightFallsBackToWallBottoms() {
        var scan = SyntheticRooms.rectangularRoom(origin: .zero, width: 4, depth: 3, floorY: 2.7)
        XCTAssertEqual(StoryDetector.floorHeight(of: scan), 2.7, accuracy: 1e-5)
        scan.surfaces.removeAll { $0.category == .floor }
        XCTAssertEqual(StoryDetector.floorHeight(of: scan), 2.7, accuracy: 1e-5, "bas des murs")
    }

    func testTwoRoomApartmentIsOneStoryInSharedFrame() {
        let house = HouseBuilder().build(from: SyntheticRooms.twoRoomApartment(), name: "Appartement")
        XCTAssertEqual(house.stories.count, 1)
        XCTAssertEqual(house.allRooms.map(\.name), ["Salon", "Cuisine"])
        XCTAssertTrue(house.allRooms.allSatisfy { $0.transform == .identity }, "repère monde partagé")
        let b = house.bounds
        XCTAssertEqual(b.minX, 0, accuracy: 0.01); XCTAssertEqual(b.maxX, 7, accuracy: 0.01)
        XCTAssertEqual(b.minY, 0, accuracy: 0.01); XCTAssertEqual(b.maxY, 3, accuracy: 0.01)
        let m = HouseMeasurements(house: house)
        XCTAssertEqual(m.roomCount, 2); XCTAssertEqual(m.storyCount, 1)
        XCTAssertEqual(m.floorArea, 12 + 9, accuracy: 0.05)
        // Le mur mitoyen (x = 4) est présent dans chaque pièce : deux murs colinéaires superposés.
        let shared = house.allRooms.flatMap(\.walls).filter { abs($0.start.x - 4) < 0.01 && abs($0.end.x - 4) < 0.01 }
        XCTAssertEqual(shared.count, 2)
    }

    func testTwoStoryHouseGroupsRoomsByLevel() {
        let house = HouseBuilder().build(from: SyntheticRooms.twoStoryHouse(), name: "Maison")
        XCTAssertEqual(house.stories.map(\.index), [0, 1])
        XCTAssertEqual(house.stories[0].rooms.map(\.name), ["Salon", "Cuisine"])
        XCTAssertEqual(house.stories[1].rooms.map(\.name), ["Chambre"])
        XCTAssertEqual(house.stories[1].rooms[0].story, 1)
        XCTAssertEqual(HouseMeasurements(house: house).storyCount, 2)
        XCTAssertEqual(StoryNaming.localizationKey(for: 0), "story.ground")
        XCTAssertEqual(StoryNaming.localizationKey(for: 2), "story.upper %lld")
    }

    func testDuplicateLabelsAreNumbered() {
        let s = StructureInput(rooms: [
            SyntheticRooms.rectangularRoom(origin: .zero, width: 3, depth: 3, label: .bedroom),
            SyntheticRooms.rectangularRoom(origin: Point2D(x: 3, y: 0), width: 3, depth: 3, label: .bedroom),
        ])
        XCTAssertEqual(HouseBuilder().build(from: s, name: "M").allRooms.map(\.name), ["Chambre", "Chambre 2"])
    }

    func testHouseRendersAndExportsAcrossRooms() throws {
        let house = HouseBuilder().build(from: SyntheticRooms.twoRoomApartment(), name: "Appartement")
        XCTAssertGreaterThan(PlanRenderer().pdfData(house).count, 1000)
        let svg = SVGExporter().svg(for: house)
        XCTAssertEqual(svg.components(separatedBy: "<polygon ").count - 1, 2, "un sol par pièce")
        let mesh = PlanMeshBuilder().build(house)
        XCTAssertEqual(mesh.groups.map(\.name), ["Salon/walls", "Salon/doors", "Salon/floor", "Cuisine/walls", "Cuisine/doors", "Cuisine/floor"])
        let dxf = try DXFExporterTestsSupport.pairs(DXFExporter().dxf(for: house))
        XCTAssertEqual(dxf.filter { $0 == (0, "ARC") }.count, 2, "une porte par pièce")
    }
}

enum DXFExporterTestsSupport {
    static func pairs(_ dxf: String) throws -> [(Int, String)] {
        let lines = dxf.split(separator: "\n", omittingEmptySubsequences: false).dropLast()
        var out: [(Int, String)] = []
        for i in stride(from: 0, to: lines.count - 1, by: 2) {
            guard let code = Int(lines[i].trimmingCharacters(in: .whitespaces)) else { throw NSError(domain: "dxf", code: 1) }
            out.append((code, String(lines[i + 1])))
        }
        return out
    }
}
