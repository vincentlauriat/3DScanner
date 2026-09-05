import Foundation
import simd

/// Convertit un `ScanInput` (RoomPlan) en `FloorPlan` : projection au sol,
/// rattachement des ouvertures, contour du sol, hauteurs.
struct FloorPlanBuilder {
    /// Tolérance de raccordement des murs (m) pour reconstituer le contour.
    var chainTolerance = 0.25
    var wallThickness = FloorPlan.defaultWallThickness
    /// Tourne le plan pour que le mur le plus long soit horizontal (RoomPlan livre un repère
    /// monde arbitraire : la pièce arrive inclinée). Désactivé par `HouseBuilder` (repère partagé).
    var alignToLongestWall = true

    func build(from scan: ScanInput, name: String) -> FloorPlan {
        let floorY = floorLevel(of: scan)
        var walls = scan.walls.map { makeWall($0) }
        var openings = scan.openings.map { makeOpening($0, walls: walls, floorY: floorY) }
        var objects = scan.objects.map { makeObject($0) }
        var polygon = floorPolygon(walls: walls, scan: scan)
        if alignToLongestWall, let longest = walls.max(by: { $0.length < $1.length }) {
            // Rotation la plus petite (±90° max) qui rend ce mur horizontal.
            var theta = longest.segment.angle
            while theta > .pi / 2 { theta -= .pi }; while theta <= -.pi / 2 { theta += .pi }
            if abs(theta) > 1e-6 {
                let r = Transform2D(translation: .zero, rotation: -theta)
                walls = walls.map { var w = $0; w.segment = Segment2D(start: r.apply($0.start), end: r.apply($0.end)); return w }
                openings = openings.map { var o = $0; o.center = r.apply($0.center); o.angle -= theta; return o }
                objects = objects.map { var o = $0; o.center = r.apply($0.center); o.angle -= theta; return o }
                polygon = polygon.map(r.apply)
            }
        }
        let heights = walls.map(\.height)
        let ceiling: ClosedRange<Double> = heights.isEmpty ? 0...0 : heights.min()!...heights.max()!
        return FloorPlan(
            id: scan.id,
            name: name,
            label: scan.sectionLabels.first ?? .unidentified,
            story: scan.story,
            transform: .identity,
            walls: walls,
            openings: openings,
            objects: objects,
            floorPolygon: polygon,
            ceilingHeight: ceiling)
    }

    // MARK: - Éléments

    private func makeWall(_ s: ScanSurface) -> Wall {
        let center = Point2D(projecting: s.transform.translation)
        let dir = planarDirection(of: s.transform)
        let half = Double(s.dimensions.x) / 2
        return Wall(id: s.id,
                    segment: Segment2D(start: center - dir * half, end: center + dir * half),
                    height: Double(s.dimensions.y),
                    thickness: wallThickness,
                    confidence: s.confidence)
    }

    private func makeOpening(_ s: ScanSurface, walls: [Wall], floorY: Double) -> Opening {
        let center = Point2D(projecting: s.transform.translation)
        let kind: Opening.Kind = switch s.category { case .door: .door; case .window: .window; default: .opening }
        // RoomPlan fournit le mur parent ; sinon on prend le mur le plus proche.
        let wallID = s.parentID.flatMap { pid in walls.first { $0.id == pid }?.id }
            ?? walls.min { $0.segment.distance(to: center) < $1.segment.distance(to: center) }?.id
        let bottom = Double(s.transform.translation.y) - Double(s.dimensions.y) / 2
        let sill = kind == .door ? 0 : max(0, bottom - floorY)
        return Opening(id: s.id, kind: kind, wallID: wallID, center: center,
                       width: Double(s.dimensions.x), height: Double(s.dimensions.y),
                       sillHeight: sill, angle: planarDirection(of: s.transform).angle, confidence: s.confidence)
    }

    private func makeObject(_ o: ScanObject) -> PlacedObject {
        PlacedObject(id: o.id, category: o.category,
                     center: Point2D(projecting: o.transform.translation),
                     size: Size2D(width: Double(o.dimensions.x), depth: Double(o.dimensions.z)),
                     height: Double(o.dimensions.y),
                     angle: planarDirection(of: o.transform).angle,
                     confidence: o.confidence)
    }

    // MARK: - Sol

    /// Contour du sol : le polygone de la surface `floor` de RoomPlan (`polygonCorners`, coordonnées
    /// locales de la surface → monde → plan, simplifié) ; sinon le chaînage des murs ; sinon l'englobant.
    private func floorPolygon(walls: [Wall], scan: ScanInput) -> [Point2D] {
        if let floor = scan.floors.first, floor.polygonCorners.count >= 3 {
            let world = floor.polygonCorners.map { c -> Point2D in
                let p = floor.transform * SIMD4<Float>(c.x, c.y, c.z, 1)
                return Point2D(projecting: SIMD3(p.x, p.y, p.z))
            }
            let poly = Polygon2D.simplified(world, tolerance: 0.01)
            if poly.count >= 3, Polygon2D.area(poly) > 0.5 {
                return Polygon2D.signedArea(poly) < 0 ? poly.reversed() : poly
            }
        }
        if let chained = Polygon2D.chain(walls.map(\.segment), tolerance: chainTolerance) {
            return Polygon2D.signedArea(chained) < 0 ? chained.reversed() : chained
        }
        let b = Rect2D.bounding(walls.flatMap { [$0.start, $0.end] })
        guard !b.isEmpty else { return [] }
        return [Point2D(x: b.minX, y: b.minY), Point2D(x: b.maxX, y: b.minY),
                Point2D(x: b.maxX, y: b.maxY), Point2D(x: b.minX, y: b.maxY)]
    }

    /// Altitude du sol : surface `floor` si présente, sinon bas des murs.
    private func floorLevel(of scan: ScanInput) -> Double {
        if let f = scan.floors.first { return Double(f.transform.translation.y) }
        let bottoms = scan.walls.map { Double($0.transform.translation.y) - Double($0.dimensions.y) / 2 }
        return bottoms.min() ?? 0
    }

    // MARK: - Helpers

    /// Direction « largeur » d'une surface projetée au sol (axe X local → plan).
    private func planarDirection(of t: simd_float4x4) -> Point2D {
        let a = t.xAxis
        let d = Point2D(x: Double(a.x), y: -Double(a.z)).normalized
        return d.length > 0 ? d : Point2D(x: 1, y: 0)
    }
}

private extension Point2D {
    var angle: Double { atan2(y, x) }
}
