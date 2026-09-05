import Foundation
import simd

/// Point du plan 2D, en mètres. Repère : X vers la droite, Y vers le haut de la
/// feuille. Un point RoomPlan (x, y, z) se projette en (x, −z) : vue de dessus.
struct Point2D: Codable, Equatable, Hashable {
    var x: Double
    var y: Double

    static let zero = Point2D(x: 0, y: 0)

    init(x: Double, y: Double) { self.x = x; self.y = y }

    /// Projection au sol d'une position RoomPlan (Y vers le haut, sol = plan XZ).
    init(projecting v: SIMD3<Float>) { self.init(x: Double(v.x), y: -Double(v.z)) }

    func distance(to other: Point2D) -> Double { (self - other).length }
    var length: Double { (x * x + y * y).squareRoot() }
    var normalized: Point2D { let l = length; return l > 0 ? Point2D(x: x / l, y: y / l) : .zero }

    static func + (a: Point2D, b: Point2D) -> Point2D { Point2D(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: Point2D, b: Point2D) -> Point2D { Point2D(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: Point2D, k: Double) -> Point2D { Point2D(x: a.x * k, y: a.y * k) }

    func isClose(to other: Point2D, tolerance: Double) -> Bool { distance(to: other) <= tolerance }
}

struct Size2D: Codable, Equatable, Hashable {
    var width: Double
    var depth: Double
}

/// Segment 2D orienté (start → end).
struct Segment2D: Codable, Equatable, Hashable {
    var start: Point2D
    var end: Point2D

    var length: Double { start.distance(to: end) }
    var midpoint: Point2D { (start + end) * 0.5 }
    var direction: Point2D { (end - start).normalized }
    /// Angle du segment par rapport à l'axe X, en radians, dans ]−π, π].
    var angle: Double { atan2(end.y - start.y, end.x - start.x) }
    /// Normale unitaire à gauche du sens de parcours.
    var leftNormal: Point2D { let d = direction; return Point2D(x: -d.y, y: d.x) }

    /// Distance du point au segment (et non à la droite portante).
    func distance(to p: Point2D) -> Double {
        let ab = end - start
        let ab2 = ab.x * ab.x + ab.y * ab.y
        guard ab2 > 0 else { return start.distance(to: p) }
        let t = max(0, min(1, ((p.x - start.x) * ab.x + (p.y - start.y) * ab.y) / ab2))
        return p.distance(to: start + ab * t)
    }
}

/// Rectangle englobant axis-aligned, en mètres.
struct Rect2D: Codable, Equatable, Hashable {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double

    static let empty = Rect2D(minX: .infinity, minY: .infinity, maxX: -.infinity, maxY: -.infinity)

    var isEmpty: Bool { minX > maxX || minY > maxY }
    var width: Double { isEmpty ? 0 : maxX - minX }
    var height: Double { isEmpty ? 0 : maxY - minY }
    var center: Point2D { Point2D(x: (minX + maxX) / 2, y: (minY + maxY) / 2) }

    func union(_ p: Point2D) -> Rect2D {
        Rect2D(minX: min(minX, p.x), minY: min(minY, p.y), maxX: max(maxX, p.x), maxY: max(maxY, p.y))
    }

    func insetBy(_ d: Double) -> Rect2D {
        Rect2D(minX: minX - d, minY: minY - d, maxX: maxX + d, maxY: maxY + d)
    }

    static func bounding(_ points: [Point2D]) -> Rect2D {
        points.reduce(.empty) { $0.union($1) }
    }
}

enum Polygon2D {
    /// Aire signée (formule du lacet) ; positive si le contour est parcouru
    /// dans le sens trigonométrique. Retourne 0 pour moins de 3 points.
    static func signedArea(_ pts: [Point2D]) -> Double {
        guard pts.count >= 3 else { return 0 }
        var s = 0.0
        for i in pts.indices {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            s += a.x * b.y - b.x * a.y
        }
        return s / 2
    }

    static func area(_ pts: [Point2D]) -> Double { abs(signedArea(pts)) }

    /// Test point-dans-polygone (parité des croisements).
    static func contains(_ pts: [Point2D], _ p: Point2D) -> Bool {
        guard pts.count >= 3 else { return false }
        var inside = false
        var j = pts.count - 1
        for i in pts.indices {
            let a = pts[i], b = pts[j]
            if (a.y > p.y) != (b.y > p.y) {
                let x = (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x
                if p.x < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    /// Triangulation d'un polygone simple (convexe ou concave, sans trou) par
    /// découpage d'oreilles. Retourne des triplets d'indices dans `pts`.
    /// Supprime les sommets quasi colinéaires (distance à la corde < `tolerance`) et les doublons.
    /// RoomPlan livre des contours de sol à 40+ points dont la plupart sont alignés.
    static func simplified(_ pts: [Point2D], tolerance: Double = 0.01) -> [Point2D] {
        guard pts.count > 3 else { return pts }
        var out = pts
        var changed = true
        while changed && out.count > 3 {
            changed = false
            for i in out.indices {
                let a = out[(i + out.count - 1) % out.count], b = out[i], c = out[(i + 1) % out.count]
                let seg = Segment2D(start: a, end: c)
                if a.distance(to: b) < tolerance || seg.distance(to: b) < tolerance { out.remove(at: i); changed = true; break }
            }
        }
        return out
    }

    static func triangulate(_ pts: [Point2D]) -> [(Int, Int, Int)] { triangulation(pts).triangles }

    /// Comme `triangulate`, en signalant si tout le polygone a pu être découpé (`complete`).
    /// `false` = contour dégénéré (auto-intersection, sommets dupliqués) : le résultat est partiel.
    static func triangulation(_ pts: [Point2D]) -> (triangles: [(Int, Int, Int)], complete: Bool) {
        guard pts.count >= 3 else { return ([], false) }
        // Travaille toujours dans le sens trigonométrique.
        let ccw = signedArea(pts) >= 0
        var idx = Array(pts.indices)
        if !ccw { idx.reverse() }
        var tris: [(Int, Int, Int)] = []
        var guardCount = 0
        while idx.count > 3 && guardCount < 10_000 {
            guardCount += 1
            var earFound = false
            for i in idx.indices {
                let ia = idx[(i + idx.count - 1) % idx.count], ib = idx[i], ic = idx[(i + 1) % idx.count]
                let a = pts[ia], b = pts[ib], c = pts[ic]
                // Sommet convexe ?
                if cross(b - a, c - b) <= 1e-12 { continue }
                // Aucun autre sommet dans le triangle ?
                var contains = false
                for j in idx where j != ia && j != ib && j != ic {
                    if pointInTriangle(pts[j], a, b, c) { contains = true; break }
                }
                if contains { continue }
                tris.append((ia, ib, ic))
                idx.remove(at: i)
                earFound = true
                break
            }
            if !earFound { break }   // polygone dégénéré : on s'arrête proprement
        }
        var complete = idx.count == 3
        if idx.count == 3 {
            // Dernier triplet : ignoré s'il est plat (sommets alignés), sinon il produirait une normale NaN.
            let a = pts[idx[0]], b = pts[idx[1]], c = pts[idx[2]]
            if abs(cross(b - a, c - a)) > 1e-12 { tris.append((idx[0], idx[1], idx[2])) }
            else if tris.isEmpty { complete = false }
        }
        return (tris, complete)
    }

    /// Découpe `subject` par un polygone **convexe** parcouru dans le sens trigonométrique
    /// (Sutherland–Hodgman). La convexité du découpeur est la condition de validité de
    /// l'algorithme : on ne découpe donc jamais que par des triangles issus de `triangulate`,
    /// jamais par un contour de pièce (concave, et piégeux sur les arêtes colinéaires).
    static func clip(_ subject: [Point2D], byConvex clipper: [Point2D]) -> [Point2D] {
        guard subject.count >= 3, clipper.count >= 3 else { return [] }
        var out = subject
        for i in clipper.indices {
            if out.isEmpty { return [] }
            let a = clipper[i], b = clipper[(i + 1) % clipper.count]
            let input = out
            out.removeAll(keepingCapacity: true)
            var prev = input[input.count - 1]
            var prevInside = cross(b - a, prev - a) >= -1e-12
            for point in input {
                let inside = cross(b - a, point - a) >= -1e-12
                if inside != prevInside, let x = lineIntersection(prev, point, a, b) { out.append(x) }
                if inside { out.append(point) }
                prev = point; prevInside = inside
            }
        }
        return out
    }

    /// Aire de l'intersection de plusieurs polygones simples (0 si elle est vide).
    static func intersectionArea(_ polygons: [[Point2D]]) -> Double {
        intersectionPieces(polygons).reduce(0) { $0 + area($1) }
    }

    /// Aire de l'**union** de plusieurs polygones simples, par inclusion–exclusion avec
    /// élagage dès qu'une intersection est vide. Les pièces d'une maison se recouvrent
    /// légèrement (épaisseur des murs, contours de scan imprécis) : sommer leurs aires
    /// surestime la surface — mesuré à +2,14 m² sur la première maison réelle.
    static func unionArea(_ polygons: [[Point2D]]) -> Double {
        let polys = polygons.filter { $0.count >= 3 }
        guard !polys.isEmpty else { return 0 }
        var total = 0.0
        func walk(from start: Int, pieces: [[Point2D]], sign: Double) {
            total += sign * pieces.reduce(0) { $0 + area($1) }
            guard start < polys.count else { return }
            for j in start..<polys.count {
                let next = clipPieces(pieces, by: polys[j])
                if !next.isEmpty { walk(from: j + 1, pieces: next, sign: -sign) }
            }
        }
        for i in polys.indices { walk(from: i + 1, pieces: convexPieces(of: polys[i]), sign: 1) }
        return total
    }

    private static func intersectionPieces(_ polygons: [[Point2D]]) -> [[Point2D]] {
        let polys = polygons.filter { $0.count >= 3 }
        guard let first = polys.first else { return [] }
        var pieces = convexPieces(of: first)
        for poly in polys.dropFirst() {
            if pieces.isEmpty { return [] }
            pieces = clipPieces(pieces, by: poly)
        }
        return pieces
    }

    /// Chaque morceau convexe est redécoupé par chaque triangle du polygone.
    private static func clipPieces(_ pieces: [[Point2D]], by polygon: [Point2D]) -> [[Point2D]] {
        let tris = convexPieces(of: polygon)
        guard !tris.isEmpty else { return [] }
        var out: [[Point2D]] = []
        for piece in pieces {
            for t in tris {
                let c = clip(piece, byConvex: t)
                if c.count >= 3, area(c) > 1e-12 { out.append(c) }
            }
        }
        return out
    }

    private static func convexPieces(of polygon: [Point2D]) -> [[Point2D]] {
        triangulate(polygon).map { [polygon[$0.0], polygon[$0.1], polygon[$0.2]] }
    }

    /// Intersection du segment `p1p2` avec la **droite** `ab` (les deux sont sécants par
    /// construction : `p1` et `p2` sont de part et d'autre de `ab`).
    private static func lineIntersection(_ p1: Point2D, _ p2: Point2D, _ a: Point2D, _ b: Point2D) -> Point2D? {
        let d1 = p2 - p1, d2 = b - a
        let den = cross(d1, d2)
        guard abs(den) > 1e-15 else { return nil }
        let t = cross(a - p1, d2) / den
        return Point2D(x: p1.x + d1.x * t, y: p1.y + d1.y * t)
    }

    private static func cross(_ u: Point2D, _ v: Point2D) -> Double { u.x * v.y - u.y * v.x }

    private static func pointInTriangle(_ p: Point2D, _ a: Point2D, _ b: Point2D, _ c: Point2D) -> Bool {
        let d1 = cross(b - a, p - a), d2 = cross(c - b, p - b), d3 = cross(a - c, p - c)
        let hasNeg = d1 < -1e-12 || d2 < -1e-12 || d3 < -1e-12
        let hasPos = d1 > 1e-12 || d2 > 1e-12 || d3 > 1e-12
        return !(hasNeg && hasPos)
    }

    static func perimeter(_ pts: [Point2D]) -> Double {
        guard pts.count >= 2 else { return 0 }
        return pts.indices.reduce(0.0) { $0 + pts[$1].distance(to: pts[($1 + 1) % pts.count]) }
    }

    /// Chaîne des segments (murs) en un contour fermé : chaque extrémité est
    /// raccordée à l'extrémité la plus proche d'un segment non encore utilisé,
    /// dans la limite de `tolerance`. Retourne nil si la chaîne ne se referme
    /// pas (mur manquant, scan partiel).
    static func chain(_ segments: [Segment2D], tolerance: Double) -> [Point2D]? {
        guard segments.count >= 3 else { return nil }
        var remaining = segments
        var current = remaining.removeFirst()
        var contour = [current.start, current.end]
        while !remaining.isEmpty {
            let tail = contour[contour.count - 1]
            var bestIndex: Int? = nil
            var bestDistance = tolerance
            var bestReversed = false
            for (i, seg) in remaining.enumerated() {
                let dStart = seg.start.distance(to: tail)
                let dEnd = seg.end.distance(to: tail)
                if dStart <= bestDistance { bestDistance = dStart; bestIndex = i; bestReversed = false }
                if dEnd <= bestDistance { bestDistance = dEnd; bestIndex = i; bestReversed = true }
            }
            guard let idx = bestIndex else { return nil }
            current = remaining.remove(at: idx)
            let next = bestReversed ? current.start : current.end
            contour.append(next)
        }
        // Fermeture : le dernier point doit rejoindre le premier.
        guard contour.first!.isClose(to: contour.last!, tolerance: tolerance) else { return nil }
        contour.removeLast()
        return contour
    }
}

extension simd_float4x4 {
    /// Translation (colonne 3).
    var translation: SIMD3<Float> { SIMD3(columns.3.x, columns.3.y, columns.3.z) }
    /// Axe X local (colonne 0), c'est-à-dire la direction « largeur » d'une surface RoomPlan.
    var xAxis: SIMD3<Float> { SIMD3(columns.0.x, columns.0.y, columns.0.z) }
    /// Axe Y local (colonne 1).
    var yAxis: SIMD3<Float> { SIMD3(columns.1.x, columns.1.y, columns.1.z) }
    /// Axe Z local (colonne 2).
    var zAxis: SIMD3<Float> { SIMD3(columns.2.x, columns.2.y, columns.2.z) }
}
