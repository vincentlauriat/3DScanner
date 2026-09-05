import XCTest
@testable import RoomScanner

final class DXFExporterTests: XCTestCase {
    private var house: House { House(room: FloorPlanBuilder().build(from: SyntheticRooms.rectangularRoom().scan, name: "Salon")) }

    /// Paires (code, valeur) du fichier ; échoue si le nombre de lignes est impair.
    private func pairs(_ dxf: String) throws -> [(Int, String)] {
        let lines = dxf.split(separator: "\n", omittingEmptySubsequences: false).dropLast()
        XCTAssertEqual(lines.count % 2, 0, "nombre de lignes impair")
        var out: [(Int, String)] = []
        for i in stride(from: 0, to: lines.count - 1, by: 2) {
            let code = try XCTUnwrap(Int(lines[i].trimmingCharacters(in: .whitespaces)), "code invalide : \(lines[i])")
            out.append((code, String(lines[i + 1])))
        }
        return out
    }

    func testStructureR12() throws {
        let dxf = DXFExporter().dxf(for: house)
        let p = try pairs(dxf)
        XCTAssertEqual(p.last?.1, "EOF")
        let sections = zip(p, p.dropFirst()).filter { $0.0 == (0, "SECTION") }.map { $0.1.1 }
        XCTAssertEqual(sections, ["HEADER", "TABLES", "ENTITIES"])
        XCTAssertTrue(dxf.contains("9\n$ACADVER\n1\nAC1009"))
        XCTAssertTrue(dxf.contains("9\n$INSUNITS\n70\n6"))
        XCTAssertEqual(p.filter { $0 == (0, "SECTION") }.count, p.filter { $0 == (0, "ENDSEC") }.count)
        XCTAssertEqual(p.filter { $0 == (0, "POLYLINE") }.count, p.filter { $0 == (0, "SEQEND") }.count)
    }

    func testEntityLayersAreDeclared() throws {
        let p = try pairs(DXFExporter().dxf(for: house))
        let declared = Set(zip(p, p.dropFirst()).filter { $0.0 == (0, "LAYER") }.map { $0.1.1 })
        XCTAssertEqual(declared, Set(DXFExporter.Layer.allCases.map(\.rawValue)))
        let used = Set(p.filter { $0.0 == 8 }.map(\.1))
        XCTAssertTrue(used.isSubset(of: declared), "\(used.subtracting(declared))")
        XCTAssertTrue(used.isSuperset(of: ["WALLS", "DOORS", "WINDOWS", "OBJECTS", "DIMENSIONS", "FLOOR", "TEXT"]))
    }

    func testEntitiesAndUnits() throws {
        let p = try pairs(DXFExporter(locale: Locale(identifier: "en_US")).dxf(for: house))
        XCTAssertEqual(p.filter { $0 == (0, "ARC") }.count, 1)
        XCTAssertEqual(p.filter { $0 == (0, "TEXT") }.count, 5, "4 cotes + 1 objet")
        XCTAssertTrue(p.contains { $0.0 == 1 && $0.1 == "400 cm" })
        // Extents en mètres : pièce 4 × 3 m centrée à l’origine + marge de cote 0.55.
        let extmaxIndex = try XCTUnwrap(p.firstIndex { $0 == (9, "$EXTMAX") })
        XCTAssertEqual(try XCTUnwrap(Double(p[extmaxIndex + 1].1)), 2.55, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(Double(p[extmaxIndex + 2].1)), 2.05, accuracy: 0.001)
        XCTAssertFalse(p.contains { $0.1.contains(",") && [10, 20, 11, 21, 40, 50, 51].contains($0.0) }, "décimales avec virgule")
    }

    func testCodePageAndAccentsAreCP1252() throws {
        var plan = FloorPlanBuilder().build(from: SyntheticRooms.rectangularRoom().scan, name: "Salon")
        plan.objects[0].category = "television"   // « Télévision » en français
        let exporter = DXFExporter(locale: Locale(identifier: "fr_FR"))
        let text = exporter.dxf(for: House(room: plan))
        XCTAssertTrue(text.contains("9\n$DWGCODEPAGE\n3\nANSI_1252\n"))
        let data = exporter.data(for: House(room: plan))
        XCTAssertTrue(data.contains(0xE9), "« é » doit être l'octet CP1252 0xE9, pas la séquence UTF-8 C3 A9")
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Ã©"))
        XCTAssertEqual(try XCTUnwrap(String(data: data, encoding: .windowsCP1252)), text)
    }

    func testPolylineHasR12DummyPoint() throws {
        let p = try pairs(DXFExporter().dxf(for: house))
        let starts = p.indices.filter { p[$0] == (0, "POLYLINE") }
        XCTAssertFalse(starts.isEmpty)
        for i in starts {
            XCTAssertEqual(p[i + 1].0, 8)
            XCTAssertEqual(Array(p[(i + 2)...(i + 4)].map(\.0)), [10, 20, 30], "point factice 10/20/30 avant 66/70")
            XCTAssertEqual(p[i + 5].0, 66)
        }
    }
}
