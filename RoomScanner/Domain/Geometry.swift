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
