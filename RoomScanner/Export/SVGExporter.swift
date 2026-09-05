import Foundation

/// Plan 2D en SVG : unités **millimètres** (1 unité = 1 mm), calques en `<g id>`.
/// Repère SVG y vers le bas : y_svg = (maxY − y_plan). Lisible dans Illustrator,
/// Figma, Inkscape et les navigateurs.
struct SVGExporter {
    var locale: Locale = .current
    var margin = 0.6  // m autour du plan (cotes)

    func svg(for house: House) -> String {
        let rooms = house.allRooms
        let b = house.bounds.insetBy(margin)
        guard !b.isEmpty else { return emptyDocument() }
        let W = mm(b.width), H = mm(b.height)
        let renderer = PlanRenderer()
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(W)mm" height="\(H)mm" viewBox="0 0 \(W) \(H)" font-family="sans-serif">
        <title>\(esc(house.name))</title>
        <desc>3D Scanner — millimetres</desc>

        """
        func X(_ p: Point2D, _ t: Transform2D) -> String { let q = t.apply(p); return mm(q.x - b.minX) }
        func Y(_ p: Point2D, _ t: Transform2D) -> String { let q = t.apply(p); return mm(b.maxY - q.y) }
        func line(_ s: Segment2D, _ t: Transform2D, _ attrs: String) -> String {
            "  <line x1=\"\(X(s.start, t))\" y1=\"\(Y(s.start, t))\" x2=\"\(X(s.end, t))\" y2=\"\(Y(s.end, t))\" \(attrs)/>\n"
        }
        func poly(_ pts: [Point2D], _ t: Transform2D, _ attrs: String) -> String {
            "  <polygon points=\"" + pts.map { "\(X($0, t)),\(Y($0, t))" }.joined(separator: " ") + "\" \(attrs)/>\n"
        }

        var floors = "", walls = "", doors = "", windows = "", openings = "", objects = "", dims = "", texts = ""
        for room in rooms {
            let t = room.transform
            let side = PlanRenderer.InteriorSide(polygon: room.floorPolygon, fallback: room.bounds.center)
            if room.floorPolygon.count >= 3 { floors += poly(room.floorPolygon, t, "fill=\"#eef2fa\" stroke=\"none\"") }
            for wall in room.walls {
                let ops = room.openings.filter { $0.wallID == wall.id }
                for piece in renderer.wallPieces(wall, openings: ops) {
                    walls += line(piece, t, "stroke=\"#1a1a1a\" stroke-width=\"\(mm(wall.thickness))\" stroke-linecap=\"square\"")
                }
                // Cote
                let seg = wall.segment
                guard seg.length >= PlanRenderer.minimumDimensionedLength else { continue }
                let outward = side.inward(of: seg) * -1
                let a = seg.start + outward * PlanRenderer.dimensionOffset, c = seg.end + outward * PlanRenderer.dimensionOffset
                dims += line(Segment2D(start: a, end: c), t, "stroke=\"#126bdb\" stroke-width=\"12\" marker-start=\"url(#arrow)\" marker-end=\"url(#arrow)\"")
                dims += line(Segment2D(start: seg.start + outward * 0.05, end: a + outward * 0.06), t, "stroke=\"#126bdb\" stroke-width=\"8\"")
                dims += line(Segment2D(start: seg.end + outward * 0.05, end: c + outward * 0.06), t, "stroke=\"#126bdb\" stroke-width=\"8\"")
                let label = MeasurementFormat.centimeters(wall.length, locale: locale)
                let pos = seg.midpoint + outward * (PlanRenderer.dimensionOffset + 0.16)
                let q = t.apply(pos)
                var angle = -(seg.angle + t.rotation) * 180 / .pi
                while angle > 90 { angle -= 180 }; while angle <= -90 { angle += 180 }
                texts += "  <text x=\"\(mm(q.x - b.minX))\" y=\"\(mm(b.maxY - q.y))\" font-size=\"120\" fill=\"#126bdb\" text-anchor=\"middle\" dominant-baseline=\"middle\" transform=\"rotate(\(fmt(angle)) \(mm(q.x - b.minX)) \(mm(b.maxY - q.y)))\">\(esc(label))</text>\n"
            }
            for o in room.openings {
                let seg = o.segment
                switch o.kind {
                case .door:
                    let inward = side.inward(of: seg)
                    let leaf = Segment2D(start: seg.start, end: seg.start + inward * o.width)
                    doors += line(leaf, t, "stroke=\"#1a1a1a\" stroke-width=\"15\"")
                    // Arc de débattement : de l'extrémité de l'ouverture au bout du battant, autour de la charnière.
                    let r = mm(o.width)
                    let sweep = arcSweep(hinge: seg.start, from: seg.end, to: leaf.end, flipY: true)
                    doors += "  <path d=\"M \(X(seg.end, t)) \(Y(seg.end, t)) A \(r) \(r) 0 0 \(sweep) \(X(leaf.end, t)) \(Y(leaf.end, t))\" fill=\"none\" stroke=\"#1a1a1a\" stroke-width=\"10\" stroke-dasharray=\"50 40\"/>\n"
                case .window:
                    let n = seg.leftNormal * (FloorPlan.defaultWallThickness * 0.3)
                    windows += line(Segment2D(start: seg.start + n, end: seg.end + n), t, "stroke=\"#338cf2\" stroke-width=\"15\"")
                    windows += line(Segment2D(start: seg.start - n, end: seg.end - n), t, "stroke=\"#338cf2\" stroke-width=\"15\"")
                case .opening:
                    openings += line(seg, t, "stroke=\"#1a1a1a\" stroke-width=\"12\" stroke-dasharray=\"80 60\"")
                }
            }
            for o in room.objects {
                let c = cos(o.angle), s = sin(o.angle), hw = o.size.width / 2, hd = o.size.depth / 2
                let corners = [(-hw, -hd), (hw, -hd), (hw, hd), (-hw, hd)].map { (x, y) in Point2D(x: o.center.x + x * c - y * s, y: o.center.y + x * s + y * c) }
                objects += poly(corners, t, "fill=\"#cccccc\" fill-opacity=\"0.5\" stroke=\"#737373\" stroke-width=\"12\"")
                let q = t.apply(o.center)
                objects += "  <text x=\"\(mm(q.x - b.minX))\" y=\"\(mm(b.maxY - q.y))\" font-size=\"110\" fill=\"#737373\" text-anchor=\"middle\" dominant-baseline=\"middle\">\(esc(ObjectNaming.localizedName(o.category)))</text>\n"
            }
        }
        out += """
        <defs>
          <marker id="arrow" viewBox="0 0 10 10" refX="1" refY="5" markerWidth="8" markerHeight="8" orient="auto-start-reverse">
            <path d="M 0 0 L 10 5 L 0 10 z" fill="#126bdb"/>
          </marker>
        </defs>
        <g id="floors">\n\(floors)</g>
        <g id="objects">\n\(objects)</g>
        <g id="walls">\n\(walls)</g>
        <g id="doors">\n\(doors)</g>
        <g id="windows">\n\(windows)</g>
        <g id="openings">\n\(openings)</g>
        <g id="dimensions">\n\(dims)</g>
        <g id="text">\n\(texts)</g>
        </svg>

        """
        return out
    }

    func data(for house: House) -> Data { Data(svg(for: house).utf8) }

    // MARK: helpers

    private func emptyDocument() -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100mm\" height=\"100mm\" viewBox=\"0 0 100 100\"/>\n"
    }
    private func mm(_ m: Double) -> String { fmt(m * 1000) }
    private func fmt(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), r)
    }
    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    /// Sens de balayage SVG (0/1) d'un arc de `from` à `to` autour de `hinge`.
    private func arcSweep(hinge: Point2D, from: Point2D, to: Point2D, flipY: Bool) -> Int {
        let a1 = atan2(from.y - hinge.y, from.x - hinge.x), a2 = atan2(to.y - hinge.y, to.x - hinge.x)
        var d = a2 - a1
        while d > .pi { d -= 2 * .pi }; while d < -.pi { d += 2 * .pi }
        // En SVG (y vers le bas) un angle croissant dans le repère plan devient un balayage horaire (flag 0 = anti-horaire).
        let ccwInPlan = d > 0
        return (ccwInPlan != flipY) ? 1 : 0
    }
}
