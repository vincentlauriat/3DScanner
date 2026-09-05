import XCTest
@testable import RoomScanner

final class ExportServiceTests: XCTestCase {
    private var tmp: URL!
    private var record: RoomRecord!
    private var house: House!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ExportServiceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let plan = FloorPlanBuilder().build(from: SyntheticRooms.rectangularRoom().scan, name: "Salon")
        record = RoomRecord(id: plan.id, name: "Salon / Séjour: test", label: .livingRoom, areaM2: 12, storyIndex: 0)
        house = House(room: plan)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    func testFileNameIsSanitized() {
        XCTAssertEqual(ExportService.fileName(for: record, format: .pdf), "Salon - Séjour- test.pdf")
        XCTAssertEqual(ExportService.fileName(for: record, format: .usdzMesh), "Salon - Séjour- test-mesh.usdz")
        for bad in ["..", ".", "...", "", "  "] {
            var r = record!; r.name = bad
            XCTAssertEqual(ExportService.folderName(for: r), "room", "« \(bad) » ne doit pas remonter dans l'arborescence")
        }
    }

    func testScratchDirectoriesAreUniqueAndPurgedByAge() throws {
        let a = try ExportService.scratchDirectory(), b = try ExportService.scratchDirectory()
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path), "un second export n'efface pas le premier")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-7200)], ofItemAtPath: a.path)
        _ = try ExportService.scratchDirectory()
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path), "purgé après une heure")
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path))
    }

    func testGeneratedFormatsAreWritten() throws {
        let service = ExportService(locale: Locale(identifier: "fr_FR"))
        for format in [ExportFormat.pdf, .png, .svg, .dxf, .json, .obj, .stl, .ply] {
            let url = try service.export(house, record: record, format: format, packageURL: nil, to: tmp)
            let data = try Data(contentsOf: url)
            XCTAssertGreaterThan(data.count, 200, format.rawValue)
            switch format {
            case .pdf: XCTAssertEqual(String(decoding: data.prefix(5), as: UTF8.self), "%PDF-")
            case .png: XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
            case .svg: XCTAssertTrue(String(decoding: data.prefix(40), as: UTF8.self).contains("<?xml"))
            case .dxf: XCTAssertTrue(String(decoding: data, as: UTF8.self).hasSuffix("0\nEOF\n"))
            case .json:
                let plan = try RoomPackage.decoder.decode(FloorPlan.self, from: data)
                XCTAssertEqual(plan, house.allRooms[0])
            case .obj: XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\ng walls\n"))
            case .stl: XCTAssertEqual((data.count - 84) % 50, 0)
            case .ply: XCTAssertTrue(String(decoding: data.prefix(4), as: UTF8.self) == "ply\n")
            default: break
            }
        }
    }

    func testUSDZIsCopiedFromPackage() throws {
        let pkg = tmp.appendingPathComponent("x.roomscan", isDirectory: true)
        try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
        try Data("usdz".utf8).write(to: pkg.appendingPathComponent(FileLayout.PackageFile.usdz))
        let url = try ExportService().export(house, record: record, format: .usdzParametric, packageURL: pkg, to: tmp)
        XCTAssertEqual(try Data(contentsOf: url), Data("usdz".utf8))
        XCTAssertThrowsError(try ExportService().export(house, record: record, format: .usdzParametric, packageURL: nil, to: tmp))
    }

    func testUnavailableFormatsThrow() {
        XCTAssertThrowsError(try ExportService().export(house, record: record, format: .usdzMesh, packageURL: nil, to: tmp), "pas de maillage de scan")
        var scan = ExportService(); scan.meshSource = .scan
        XCTAssertThrowsError(try scan.export(house, record: record, format: .obj, packageURL: nil, to: tmp), "source scan sans room-mesh.usdz")
    }

    func testAvailableFormatsDependOnPackage() throws {
        XCTAssertEqual(ExportService.availableFormats(packageURL: nil), [.pdf, .png, .svg, .dxf, .obj, .stl, .ply, .json, .zip])
        let pkg = tmp.appendingPathComponent("y.roomscan", isDirectory: true)
        try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
        try Data("u".utf8).write(to: pkg.appendingPathComponent(FileLayout.PackageFile.usdz))
        try Data("m".utf8).write(to: pkg.appendingPathComponent(FileLayout.PackageFile.usdzMesh))
        XCTAssertEqual(ExportService.availableFormats(packageURL: pkg), [.pdf, .png, .svg, .dxf, .usdzParametric, .usdzMesh, .obj, .stl, .ply, .json, .zip])
        XCTAssertTrue(ExportService.hasScanMesh(packageURL: pkg))
        let url = try ExportService().export(house, record: record, format: .usdzMesh, packageURL: pkg, to: tmp)
        XCTAssertEqual(try Data(contentsOf: url), Data("m".utf8))
        XCTAssertTrue(url.lastPathComponent.hasSuffix("-mesh.usdz"))
    }
    /// Écrit tous les exports générés dans `<tmp>/RoomScannerExportSamples` pour inspection
    /// (Aperçu, Inkscape, LibreCAD…) ; le chemin est imprimé dans le journal.
    func testWriteSamplesForInspection() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("RoomScannerExportSamples", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        let service = ExportService(locale: Locale(identifier: "fr_FR"))
        let lPlan = FloorPlanBuilder().build(from: SyntheticRooms.lShapedRoom(), name: "Chambre en L")
        let lRecord = RoomRecord(id: lPlan.id, name: "Chambre en L", label: .bedroom, areaM2: 24, storyIndex: 0)
        for (h, r) in [(house!, record!), (House(room: lPlan), lRecord)] {
            for format in [ExportFormat.pdf, .png, .svg, .dxf, .json, .obj, .stl, .ply] {
                try service.export(h, record: r, format: format, packageURL: nil, to: dir)
            }
        }
        print("Export samples: \(dir.path)")
    }
}
