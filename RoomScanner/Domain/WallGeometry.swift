import Foundation

/// Découpe des murs en boîtes pleines (portions, linteaux, allèges) et panneaux
/// d'ouverture. Pur Swift : partagé par le visualiseur RealityKit
/// (`PlanSceneBuilder`) et l'export de maillage (`PlanMeshBuilder`).
struct WallGeometry {
    /// Hauteur forcée des murs (mode « plan 2D » du visualiseur) ; `nil` = hauteur réelle,
    /// ouvertures découpées.
    var flattenedHeight: Double? = nil

    /// Boîte alignée sur un segment : `segment` le long du mur (m), `bottom`…`top` (m).
    struct Box: Equatable {
        var segment: Segment2D
        var bottom: Double
        var top: Double
        var thickness: Double
        var height: Double { top - bottom }
    }

    /// Découpe un mur en boîtes pleines autour de ses ouvertures : portions
    /// pleines, linteaux au-dessus des portes, allèges sous les fenêtres.
    func wallBoxes(_ wall: Wall, openings: [Opening]) -> [Box] {
        let len = wall.length
        guard len > 0 else { return [] }
        let dir = wall.segment.direction
        let h = flattenedHeight ?? wall.height
        func seg(_ a: Double, _ b: Double) -> Segment2D { Segment2D(start: wall.start + dir * a, end: wall.start + dir * b) }
        var intervals: [(Double, Double, Opening)] = openings.map { o in
            let t = (o.center.x - wall.start.x) * dir.x + (o.center.y - wall.start.y) * dir.y
            return (max(0, t - o.width / 2), min(len, t + o.width / 2), o)
        }.filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
        var boxes: [Box] = []
        var cursor = 0.0
        while !intervals.isEmpty {
            let (a, b, o) = intervals.removeFirst()
            if a > cursor + 0.005 { boxes.append(Box(segment: seg(cursor, a), bottom: 0, top: h, thickness: wall.thickness)) }
            if flattenedHeight == nil {
                let bottom = o.kind == .door ? 0 : o.sillHeight
                let top = min(bottom + o.height, h)
                if bottom > 0.01 { boxes.append(Box(segment: seg(a, b), bottom: 0, top: bottom, thickness: wall.thickness)) }
                if top < h - 0.01 { boxes.append(Box(segment: seg(a, b), bottom: top, top: h, thickness: wall.thickness)) }
            }
            cursor = max(cursor, b)
        }
        if cursor < len - 0.005 { boxes.append(Box(segment: seg(cursor, len), bottom: 0, top: h, thickness: wall.thickness)) }
        return boxes
    }

    /// Panneau de porte (bois) ou vitrage (verre) dans l'ouverture ; `nil` en mode aplati.
    func panelBox(_ o: Opening, wall: Wall?) -> Box? {
        guard flattenedHeight == nil, o.width > 0.05, o.height > 0.05 else { return nil }
        let bottom = o.kind == .door ? 0 : o.sillHeight
        let thickness = (wall?.thickness ?? FloorPlan.defaultWallThickness) * 0.35
        return Box(segment: o.segment, bottom: bottom, top: bottom + o.height, thickness: thickness)
    }

    /// Boîte d'un objet posé au sol (centre, taille, angle).
    static func objectBox(_ o: PlacedObject) -> Box {
        let d = Point2D(x: cos(o.angle), y: sin(o.angle)) * (o.size.width / 2)
        return Box(segment: Segment2D(start: o.center - d, end: o.center + d), bottom: 0, top: o.height, thickness: o.size.depth)
    }
}
