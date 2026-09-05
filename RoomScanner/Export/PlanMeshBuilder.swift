import Foundation
import simd

/// Maillage triangulé indexé, normales par face (rendu à facettes), groupes nommés.
/// Repère : mètres, **y vers le haut**, z = −y_plan (même convention que RealityKit
/// et que l'USDZ de RoomPlan).
struct TriangleMesh: Equatable {
    struct Group: Equatable { var name: String; var triangles: Range<Int> }
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var triangles: [SIMD3<UInt32>] = []
    var groups: [Group] = []

    var isEmpty: Bool { triangles.isEmpty }

    var bounds: (min: SIMD3<Float>, max: SIMD3<Float>)? {
        guard let f = positions.first else { return nil }
        return positions.dropFirst().reduce((f, f)) { (simd_min($0.0, $1), simd_max($0.1, $1)) }
    }

    /// Ajoute un quadrilatère plan (4 sommets dans l'ordre, normale extérieure = sens trigonométrique vu de dehors).
    mutating func addQuad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>) {
        let cross = simd_cross(b - a, c - a)
        guard simd_length(cross) > 1e-9 else { return }   // face plate : pas de normale possible
        let n = simd_normalize(cross)
        let base = UInt32(positions.count)
        positions += [a, b, c, d]; normals += [n, n, n, n]
        triangles += [SIMD3(base, base + 1, base + 2), SIMD3(base, base + 2, base + 3)]
    }

    /// Ajoute un triangle avec sa normale.
    mutating func addTriangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) {
        let cross = simd_cross(b - a, c - a)
        guard simd_length(cross) > 1e-9 else { return }
        let n = simd_normalize(cross)
        let base = UInt32(positions.count)
        positions += [a, b, c]; normals += [n, n, n]
        triangles.append(SIMD3(base, base + 1, base + 2))
    }

    mutating func group(_ name: String, _ body: (inout TriangleMesh) -> Void) {
        let start = triangles.count
        body(&self)
        if triangles.count > start { groups.append(Group(name: name, triangles: start..<triangles.count)) }
    }
}

/// Construit le maillage paramétrique d'une maison : murs découpés (linteaux,
/// allèges), panneaux de portes et vitrages, dalle de sol polygonale, objets en
/// boîtes. Résultat déterministe, identique iOS / macOS, indépendant de RoomPlan.
struct PlanMeshBuilder {
    var floorThickness: Double = 0.05
    var includeObjects = true
    var includePanels = true

    func build(_ house: House) -> TriangleMesh {
        var mesh = TriangleMesh()
        let geometry = WallGeometry()
        for room in house.allRooms {
            let t = room.transform
            let prefix = house.allRooms.count > 1 ? "\(room.name)/" : ""
            mesh.group(prefix + "walls") { m in
                for wall in room.walls {
                    let ops = room.openings.filter { $0.wallID == wall.id }
                    for box in geometry.wallBoxes(wall, openings: ops) { Self.addBox(box, transform: t, to: &m) }
                }
            }
            if includePanels {
                for kind in [Opening.Kind.door, .window] {
                    mesh.group(prefix + (kind == .door ? "doors" : "windows")) { m in
                        for o in room.openings where o.kind == kind {
                            if let box = geometry.panelBox(o, wall: room.wall(withID: o.wallID)) { Self.addBox(box, transform: t, to: &m) }
                        }
                    }
                }
            }
            mesh.group(prefix + "floor") { m in Self.addFloor(room, transform: t, thickness: floorThickness, to: &m) }
            if includeObjects {
                mesh.group(prefix + "objects") { m in
                    for o in room.objects { Self.addBox(WallGeometry.objectBox(o), transform: t, to: &m) }
                }
            }
        }
        return mesh
    }

    // MARK: primitives

    static func point(_ p: Point2D, y: Double) -> SIMD3<Float> { SIMD3(Float(p.x), Float(y), Float(-p.y)) }

    /// Boîte posée sur un segment : les 6 faces avec normales extérieures.
    static func addBox(_ box: WallGeometry.Box, transform t: Transform2D, to mesh: inout TriangleMesh) {
        guard box.segment.length > 0, box.height > 0, box.thickness > 0 else { return }
        let seg = Segment2D(start: t.apply(box.segment.start), end: t.apply(box.segment.end))
        let n = seg.leftNormal * (box.thickness / 2)
        // Coins au sol dans le plan : a→b le long du segment, côté +n puis −n.
        let p0 = seg.start + n, p1 = seg.end + n, p2 = seg.end - n, p3 = seg.start - n
        let (lo, hi) = (box.bottom, box.top)
        let a0 = point(p0, y: lo), a1 = point(p1, y: lo), a2 = point(p2, y: lo), a3 = point(p3, y: lo)
        let b0 = point(p0, y: hi), b1 = point(p1, y: hi), b2 = point(p2, y: hi), b3 = point(p3, y: hi)
        // Le passage plan (x, y) → 3D (x, −z) inverse la chiralité : les quads sont
        // énumérés dans le sens qui donne des normales extérieures (vérifié par test).
        mesh.addQuad(b3, b2, b1, b0)       // dessus (+y)
        mesh.addQuad(a0, a1, a2, a3)       // dessous (−y)
        mesh.addQuad(a0, b0, b1, a1)       // face +n (z négatif)
        mesh.addQuad(a2, b2, b3, a3)       // face −n
        mesh.addQuad(a1, b1, b2, a2)       // bout `end`
        mesh.addQuad(a3, b3, b0, a0)       // bout `start`
    }

    /// Dalle : polygone du sol (ou rectangle englobant) triangulé dessus/dessous + flancs.
    static func addFloor(_ room: FloorPlan, transform t: Transform2D, thickness: Double, to mesh: inout TriangleMesh) {
        let b = room.bounds
        guard !b.isEmpty else { return }
        let rectangle = [Point2D(x: b.minX, y: b.minY), Point2D(x: b.maxX, y: b.minY), Point2D(x: b.maxX, y: b.maxY), Point2D(x: b.minX, y: b.maxY)]
        var poly = room.floorPolygon.count >= 3 ? room.floorPolygon : rectangle
        // Orientation trigonométrique pour que les normales pointent dehors.
        if Polygon2D.signedArea(poly) < 0 { poly.reverse() }
        var pts = poly.map(t.apply)
        var (tris, complete) = Polygon2D.triangulation(pts)
        if !complete {
            // Contour dégénéré : une dalle partielle avec tous ses flancs serait non fermée (rejetée à
            // l'impression 3D). Repli sur le rectangle englobant, toujours triangulable.
            pts = rectangle.map(t.apply)
            (tris, _) = Polygon2D.triangulation(pts)
        }
        for tri in tris {
            let (a, b, c) = (pts[tri.0], pts[tri.1], pts[tri.2])
            mesh.addTriangle(point(a, y: 0), point(b, y: 0), point(c, y: 0))                                    // dessus : normale +y
            mesh.addTriangle(point(a, y: -thickness), point(c, y: -thickness), point(b, y: -thickness))          // dessous : −y
        }
        for i in pts.indices {
            let p = pts[i], q = pts[(i + 1) % pts.count]
            mesh.addQuad(point(q, y: -thickness), point(q, y: 0), point(p, y: 0), point(p, y: -thickness))   // flanc, normale vers l’extérieur
        }
    }
}
