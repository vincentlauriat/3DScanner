import XCTest
import ModelIO
@testable import RoomScanner

final class ModelIOConverterTests: XCTestCase {
    private var tmp: URL!
    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ModelIOConverterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    /// Model I/O ne sait pas écrire d'USDZ : on part d'un `.usdc` (même famille USD que le contenu d'un USDZ).
    private func makeUSD() throws -> URL {
        let mesh = MDLMesh(boxWithExtent: [4, 2.5, 0.1], segments: [1, 1, 1], inwardNormals: false, geometryType: .triangles, allocator: MDLMeshBufferDataAllocator())
        let asset = MDLAsset(); asset.add(mesh)
        let url = tmp.appendingPathComponent("box.usdc")
        try asset.export(to: url)
        return url
    }

    func testCapabilities() {
        XCTAssertTrue(MDLAsset.canImportFileExtension("usdz"))
        for f in [ExportFormat.obj, .stl, .ply] { XCTAssertTrue(ModelIOConverter.canExport(f), f.rawValue) }
        XCTAssertFalse(MDLAsset.canExportFileExtension("usdz"), "si Model I/O apprend à écrire l'USDZ, `.usdzMesh` peut être régénéré côté Mac")
    }

    func testConvertsUSDToOBJSTLPLY() throws {
        let src = try makeUSD()
        for ext in ["obj", "stl", "ply"] {
            let dest = tmp.appendingPathComponent("out.\(ext)")
            try ModelIOConverter.convert(src, to: dest)
            let data = try Data(contentsOf: dest)
            XCTAssertGreaterThan(data.count, 100, ext)
            if ext == "obj" { XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\nv ")) }
        }
    }

    func testRejectsUnsupportedExtension() throws {
        let src = try makeUSD()
        XCTAssertThrowsError(try ModelIOConverter.convert(src, to: tmp.appendingPathComponent("out.usdz")))
    }
}
