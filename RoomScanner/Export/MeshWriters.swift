import Foundation
import simd

/// Écrivains de maillage sans dépendance : OBJ (texte, groupes), STL (binaire),
/// PLY (ASCII). Mètres, y vers le haut.
enum MeshWriters {
    private static let posix = Locale(identifier: "en_US_POSIX")
    private static func f(_ v: Float) -> String { String(format: "%.4f", locale: posix, v == 0 ? 0 : v) }

    /// Wavefront OBJ : `v`, `vn`, `g <groupe>`, faces `f v//vn`. Indices 1-based.
    static func obj(_ mesh: TriangleMesh, name: String) -> Data {
        var s = "# 3D Scanner — \(name)\n# units: meters / y up\no \(name.replacingOccurrences(of: " ", with: "_"))\n"
        for p in mesh.positions { s += "v \(f(p.x)) \(f(p.y)) \(f(p.z))\n" }
        for n in mesh.normals { s += "vn \(f(n.x)) \(f(n.y)) \(f(n.z))\n" }
        var groups = mesh.groups
        if groups.isEmpty, !mesh.triangles.isEmpty { groups = [.init(name: "mesh", triangles: 0..<mesh.triangles.count)] }
        for g in groups {
            s += "g \(g.name.replacingOccurrences(of: " ", with: "_"))\n"
            for i in g.triangles {
                let t = mesh.triangles[i]
                s += "f \(t.x + 1)//\(t.x + 1) \(t.y + 1)//\(t.y + 1) \(t.z + 1)//\(t.z + 1)\n"
            }
        }
        return Data(s.utf8)
    }

    /// STL binaire : en-tête 80 octets, nombre de triangles UInt32, 50 octets par triangle (normale, 3 sommets, attribut).
    static func stl(_ mesh: TriangleMesh, name: String) -> Data {
        var d = Data()
        var header = Array("3D Scanner \(name)".utf8.prefix(80)); header += [UInt8](repeating: 0, count: 80 - header.count)
        d.append(contentsOf: header)
        d.append(le(UInt32(mesh.triangles.count)))
        for t in mesh.triangles {
            let a = mesh.positions[Int(t.x)], b = mesh.positions[Int(t.y)], c = mesh.positions[Int(t.z)]
            let n = simd_normalize(simd_cross(b - a, c - a))
            for v in [n, a, b, c] { d.append(le(v.x.bitPattern)); d.append(le(v.y.bitPattern)); d.append(le(v.z.bitPattern)) }
            d.append(le(UInt16(0)))
        }
        return d
    }

    /// PLY ASCII : `vertex` (x y z nx ny nz), `face` (liste d'indices).
    static func ply(_ mesh: TriangleMesh, name: String) -> Data {
        var s = """
        ply
        format ascii 1.0
        comment 3D Scanner — \(name) — meters, y up
        element vertex \(mesh.positions.count)
        property float x
        property float y
        property float z
        property float nx
        property float ny
        property float nz
        element face \(mesh.triangles.count)
        property list uchar int vertex_indices
        end_header

        """
        for (p, n) in zip(mesh.positions, mesh.normals) { s += "\(f(p.x)) \(f(p.y)) \(f(p.z)) \(f(n.x)) \(f(n.y)) \(f(n.z))\n" }
        for t in mesh.triangles { s += "3 \(t.x) \(t.y) \(t.z)\n" }
        return Data(s.utf8)
    }

    private static func le<T: FixedWidthInteger>(_ v: T) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
}
