import XCTest
@testable import RoomScanner

final class SVGExporterTests: XCTestCase {
    private var house: House { House(room: FloorPlanBuilder().build(from: SyntheticRooms.rectangularRoom().scan, name: "Salon")) }

    func testIsWellFormedXML() {
        let data = SVGExporter(locale: Locale(identifier: "fr_FR")).data(for: house)
        let parser = XMLParser(data: data)
        XCTAssertTrue(parser.parse(), "XML invalide : \(parser.parserError?.localizedDescription ?? "")")
    }

    func testMillimetreViewBoxMatchesBounds() throws {
        let svg = SVGExporter().svg(for: house)
        // 4 m × 3 m + 2 × 0.6 m de marge → 5200 × 4200 mm.
        XCTAssertTrue(svg.contains("width=\"5200mm\" height=\"4200mm\""), svg.prefix(300).description)
        XCTAssertTrue(svg.contains("viewBox=\"0 0 5200 4200\""))
    }

    func testLayersAndEntities() {
        let svg = SVGExporter(locale: Locale(identifier: "en_US")).svg(for: house)
        for id in ["floors", "walls", "doors", "windows", "openings", "objects", "dimensions", "text"] {
            XCTAssertTrue(svg.contains("<g id=\"\(id)\">"), id)
        }
        XCTAssertEqual(svg.components(separatedBy: "stroke-dasharray=\"50 40\"").count - 1, 1, "un arc de porte")
        XCTAssertEqual(svg.components(separatedBy: "<polygon ").count - 1, 2, "sol + table")
        XCTAssertTrue(svg.contains("400 cm") || svg.contains("400 cm"), "cote du grand mur")
        XCTAssertTrue(svg.contains("Table"))
    }

    func testEmptyHouseProducesValidDocument() {
        let empty = House(name: "Vide", stories: [])
        XCTAssertTrue(XMLParser(data: SVGExporter().data(for: empty)).parse())
    }
}
