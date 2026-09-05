import XCTest
@testable import RoomScanner

final class MeshWritersTests: XCTestCase {
    private var mesh: TriangleMesh { PlanMeshBuilder().build(House(room: FloorPlanBuilder().build(from: SyntheticRooms.rectangularRoom().scan, name: "Salon"))) }

    func testOBJ() {
        let m = mesh
        let s = String(decoding: MeshWriters.obj(m, name: "Salon test"), as: UTF8.self)
        let lines = s.split(separator: "\n")
        XCTAssertEqual(lines.filter { $0.hasPrefix("v ") }.count, m.positions.count)
        XCTAssertEqual(lines.filter { $0.hasPrefix("vn ") }.count, m.normals.count)
        XCTAssertEqual(lines.filter { $0.hasPrefix("f ") }.count, m.triangles.count)
        XCTAssertEqual(lines.filter { $0.hasPrefix("g ") }.map { String($0.dropFirst(2)) }, ["walls", "doors", "windows", "floor", "objects"])
        XCTAssertTrue(s.contains("o Salon_test"))
        // Indices 1-based dans les bornes.
        let maxIndex = lines.filter { $0.hasPrefix("f ") }.flatMap { $0.split(separator: " ").dropFirst().compactMap { Int($0.split(separator: "/")[0]) } }.max()
        XCTAssertEqual(maxIndex, m.positions.count)
        XCTAssertFalse(lines.contains { ($0.hasPrefix("v ") || $0.hasPrefix("vn ")) && $0.contains(",") }, "décimales avec virgule")
    }

    func testSTLBinaryLayout() {
        let m = mesh
        let d = MeshWriters.stl(m, name: "Salon")
        XCTAssertEqual(d.count, 84 + 50 * m.triangles.count)
        let count = d.subdata(in: 80..<84).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        XCTAssertEqual(Int(UInt32(littleEndian: count)), m.triangles.count)
        XCTAssertTrue(String(decoding: d.prefix(10), as: UTF8.self).hasPrefix("3D Scanner"))
    }

    func testPLYHeader() {
        let m = mesh
        let s = String(decoding: MeshWriters.ply(m, name: "Salon"), as: UTF8.self)
        XCTAssertTrue(s.hasPrefix("ply\nformat ascii 1.0\n"))
        XCTAssertTrue(s.contains("element vertex \(m.positions.count)\n"))
        XCTAssertTrue(s.contains("element face \(m.triangles.count)\n"))
        let body = s.components(separatedBy: "end_header\n")[1].split(separator: "\n")
        XCTAssertEqual(body.count, m.positions.count + m.triangles.count)
        XCTAssertTrue(body.suffix(m.triangles.count).allSatisfy { $0.hasPrefix("3 ") })
    }
}
