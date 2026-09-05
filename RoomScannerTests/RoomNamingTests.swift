import XCTest
@testable import RoomScanner

final class RoomNamingTests: XCTestCase {
    let naming = RoomNaming(localizedBaseName: { label in
        switch label { case .bedroom: "Chambre"; case .livingRoom: "Salon"; default: "Pièce" }
    })

    func testFirstNameIsBase() {
        XCTAssertEqual(naming.proposedName(for: .bedroom, existingNames: []), "Chambre")
    }

    func testDuplicatesGetNumbered() {
        XCTAssertEqual(naming.proposedName(for: .bedroom, existingNames: ["Chambre"]), "Chambre 2")
        XCTAssertEqual(naming.proposedName(for: .bedroom, existingNames: ["Chambre", "Chambre 2", "Salon"]), "Chambre 3")
        XCTAssertEqual(naming.proposedName(for: .bedroom, existingNames: ["Chambre", "Chambre 3"]), "Chambre 2", "réutilise le premier numéro libre")
    }

    func testUnidentified() {
        XCTAssertEqual(naming.proposedName(for: .unidentified, existingNames: ["Pièce"]), "Pièce 2")
    }

    // MARK: - Noms composés (une capture peut porter plusieurs sections)

    func testCompositeNameJoinsEverySection() {
        XCTAssertEqual(naming.proposedName(for: [.livingRoom, .bedroom], existingNames: []), "Salon / Chambre")
    }

    func testUnidentifiedIsDroppedWhenAnotherSectionExists() {
        XCTAssertEqual(naming.proposedName(for: [.unidentified, .bedroom], existingNames: []), "Chambre")
        XCTAssertEqual(naming.proposedName(for: [.bedroom, .unidentified], existingNames: []), "Chambre")
    }

    func testRepeatedSectionsAreDeduplicated() {
        XCTAssertEqual(naming.proposedName(for: [.bedroom, .bedroom], existingNames: []), "Chambre")
    }

    func testOnlyUnidentifiedFallsBackOnTheGenericName() {
        XCTAssertEqual(naming.proposedName(for: [], existingNames: []), "Pièce")
        XCTAssertEqual(naming.proposedName(for: [.unidentified], existingNames: ["Pièce"]), "Pièce 2")
    }

    func testCompositeNamesAreNumberedLikeSimpleOnes() {
        XCTAssertEqual(naming.proposedName(for: [.livingRoom, .bedroom], existingNames: ["Salon / Chambre"]), "Salon / Chambre 2")
    }

    func testEveryLabelHasALocalizationKey() {
        for label in RoomLabel.allCases {
            XCTAssertTrue(label.localizationKey.hasPrefix("room.label."))
        }
    }
}
