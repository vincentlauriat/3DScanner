import XCTest
@testable import RoomScanner

final class ArchiveExporterTests: XCTestCase {
    private var tmp: URL!
    private let plan = FloorPlanBuilder().build(from: SyntheticRooms.rectangularRoom().scan, name: "Salon")

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiveExporterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    func testZipOfDirectoryHasPKSignature() throws {
        let dir = tmp.appendingPathComponent("Salon", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: dir.appendingPathComponent("a.txt"))
        let zip = tmp.appendingPathComponent("Salon.zip")
        try ArchiveExporter.zip(directory: dir, to: zip)
        let data = try Data(contentsOf: zip)
        XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4B, 0x03, 0x04])
        #if os(macOS)
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); p.arguments = ["-l", zip.path]
        let pipe = Pipe(); p.standardOutput = pipe; try p.run(); p.waitUntilExit()
        let listing = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertTrue(listing.contains("Salon/a.txt"), listing)
        #endif
    }

    func testReadmeMentionsFilesAndMeasurements() {
        let record = RoomRecord(plan: plan)
        let readme = ArchiveExporter.readme(record: record, plan: plan, files: [("Salon.pdf", .pdf), ("Salon.dxf", .dxf)], locale: Locale(identifier: "fr_FR"))
        XCTAssertTrue(readme.hasPrefix("3D Scanner — Salon\n"))
        XCTAssertTrue(readme.contains("Salon.pdf")); XCTAssertTrue(readme.contains("Salon.dxf"))
        XCTAssertTrue(readme.contains("12") && readme.contains("m²"), "surface 12 m²")
        XCTAssertTrue(readme.contains("4") && readme.contains("1"), "4 murs, 1 porte, 1 fenêtre")
        XCTAssertTrue(readme.contains("https://vincentlauriat.github.io/3DScanner/"))
    }

    func testExportServiceZipContainsEverything() throws {
        let record = RoomRecord(plan: plan)
        let url = try ExportService().export(House(room: plan), record: record, format: .zip, packageURL: nil, to: tmp)
        let data = try Data(contentsOf: url)
        XCTAssertEqual(Array(data.prefix(2)), [0x50, 0x4B])
        XCTAssertGreaterThan(data.count, 20_000, "PDF + PNG + SVG + DXF + OBJ + STL + PLY + JSON + README")
        #if os(macOS)
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); p.arguments = ["-Z1", url.path]
        let pipe = Pipe(); p.standardOutput = pipe; try p.run(); p.waitUntilExit()
        let names = Set(String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n").map(String.init))
        for f in ["Salon/Salon.pdf", "Salon/Salon.png", "Salon/Salon.svg", "Salon/Salon.dxf", "Salon/Salon.obj", "Salon/Salon.stl", "Salon/Salon.ply", "Salon/Salon.json", "Salon/README.txt"] {
            XCTAssertTrue(names.contains(f), "\(f) absent de \(names)")
        }
        XCTAssertFalse(names.contains { $0.hasSuffix(".zip") })
        #endif
    }
}
