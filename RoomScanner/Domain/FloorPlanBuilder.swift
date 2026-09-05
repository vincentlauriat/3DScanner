import Foundation
import simd

/// Convertit un `ScanInput` (RoomPlan) en `FloorPlan` : projection au sol,
/// rattachement des ouvertures, contour du sol, hauteurs.
struct FloorPlanBuilder {
    /// Tolérance de raccordement des murs (m) pour reconstituer le contour.
    var chainTolerance = 0.25
    var wallThickness = FloorPlan.defaultWallThickness

    func build(from scan: ScanInput, name: String) -> FloorPlan {
        let floorY = floorLevel(of: scan)
        let walls = scan.walls.map { makeWall($0) }
        let openings = scan.openings.map { makeOpening($0, walls: walls, floorY: floorY) }
        let objects = scan.objects.map { makeObject($0) }
        let polygon = floorPolygon(walls: walls, scan: scan)
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

    /// Contour du sol : d'abord en chaînant les murs (robuste, indépendant des
    /// conventions de `polygonCorners`), sinon l'englobant des murs.
    private func floorPolygon(walls: [Wall], scan: ScanInput) -> [Point2D] {
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
