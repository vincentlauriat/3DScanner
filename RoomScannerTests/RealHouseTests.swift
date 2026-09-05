import XCTest
@testable import RoomScanner

/// Première maison réelle (3 pièces de plain-pied, iPhone 16 Pro, 2026-09-05) : ce que
/// `StructureBuilder` livre vraiment, et les deux défauts qu'elle a révélés — des pièces qui
/// se recouvrent (la somme de leurs surfaces surestime la maison) et une capture portant
/// deux sections RoomPlan à la fois (salle à manger ouverte sur cuisine).
final class RealHouseTests: XCTestCase {
    /// Noms indépendants de la langue du système : on teste la composition, pas la traduction.
    private var builder: HouseBuilder {
        var b = HouseBuilder()
        b.naming = RoomNaming(localizedBaseName: { $0.rawValue })
        return b
    }

    private func loadStructure() throws -> StructureInput {
        let url = try XCTUnwrap(Bundle(for: RealHouseTests.self).url(forResource: "house.structure", withExtension: "json"),
                                "fixture house.structure.json absente du bundle de tests")
        return try RoomPackage.decoder.decode(StructureInput.self, from: Data(contentsOf: url))
    }

    func testStructureCarriesApplesMergedSurfaces() throws {
        let structure = try loadStructure()
        XCTAssertEqual(structure.rooms.count, 3)
        // D26 : `StructureBuilder` reconstruit les murs (52 par pièce → 48 fusionnés) et
        // fusionne les 3 sols en un seul. Aucun mur n'est partagé entre deux pièces : le mur
        // mitoyen n'est pas un doublon repérable par identité, on ne dédoublonne donc jamais nous-mêmes.
        XCTAssertEqual(structure.mergedWalls.count, 48)
        XCTAssertEqual(structure.mergedFloors.count, 1)
        XCTAssertEqual(structure.rooms.reduce(0) { $0 + $1.walls.count }, 52)
        let wallIDs = structure.rooms.flatMap { $0.walls.map(\.id) }
        XCTAssertEqual(Set(wallIDs).count, wallIDs.count, "aucun identifiant de mur partagé entre deux pièces")
    }

    func testRoomCarryingTwoSectionsGetsACompositeName() throws {
        let structure = try loadStructure()
        XCTAssertEqual(structure.rooms[0].sectionLabels, [.diningRoom, .kitchen])
        let house = builder.build(from: structure, name: "Maison")
        XCTAssertEqual(house.allRooms.map(\.name), ["diningRoom / kitchen", "unidentified", "unidentified 2"])
    }

    func testHouseAreaIsTheUnionOfTheRoomsNotTheirSum() throws {
        let house = builder.build(from: try loadStructure(), name: "Maison")
        XCTAssertEqual(house.stories.count, 1)
        let rooms = house.allRooms
        XCTAssertEqual(rooms.count, 3)

        // Valeurs de référence : intégration sur grille de 1 cm des trois polygones de sol
        // (sonde validée à 0,0 % contre l'aire du lacet de chaque pièce prise isolément).
        let sum = rooms.reduce(0) { $0 + RoomMeasurements(plan: $1).floorArea }
        XCTAssertEqual(sum, 78.40, accuracy: 0.05, "somme des pièces — l'ancienne valeur annoncée")

        let area = HouseMeasurements(house: house).floorArea
        XCTAssertEqual(area, 76.26, accuracy: 0.05, "union réelle des pièces")
        XCTAssertLessThan(area, sum, "les pièces se recouvrent : l'union est plus petite que la somme")
        XCTAssertEqual(sum - area, 2.14, accuracy: 0.05, "recouvrement mesuré entre la salle à manger et la pièce voisine")
    }

    /// Deux niveaux se superposent en plan : leurs surfaces s'additionnent, elles ne s'unissent pas.
    func testStoriesAreAddedNotUnioned() throws {
        let house = builder.build(from: try loadStructure(), name: "Maison")
        let ground = house.stories[0]
        var upstairs = ground
        upstairs.index = 1
        let twoStorey = House(id: house.id, name: house.name, stories: [ground, upstairs])
        XCTAssertEqual(HouseMeasurements(house: twoStorey).floorArea,
                       2 * HouseMeasurements(house: house).floorArea, accuracy: 1e-6)
    }
}
