import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

/// Dessine un plan 2D coté en **Core Graphics pur** — identique sur iOS et macOS.
/// Sert au PDF, au PNG, à la vignette, à la texture du sol du visualiseur et à
/// l'impression. Unités d'entrée : mètres (repère plan, Y vers le haut) ; le
/// contexte CG a aussi l'origine en bas à gauche, donc aucun retournement.
struct PlanRenderer {
    enum Mode: Equatable {
        /// Feuille à l'échelle standard (1:n), avec ou sans cartouche.
        case page(titleBlock: Bool)
        /// Remplit la zone (texture du sol, vignette) : pas d'échelle normalisée, pas de cartouche.
        case fill
    }

    struct Options {
        var mode: Mode = .page(titleBlock: true)
        var locale: Locale = .current
        var showDimensions = true
        var showObjects = true
        var showFloor = true
        /// Fond transparent (texture) ou blanc (feuille).
        var transparentBackground = false
        /// Palette « plan d'architecte ».
        var wallColor = CGColor(gray: 0.10, alpha: 1)
        var floorColor = CGColor(red: 0.93, green: 0.95, blue: 0.98, alpha: 1)
        var dimensionColor = CGColor(red: 0.07, green: 0.42, blue: 0.86, alpha: 1)
        var objectFill = CGColor(gray: 0.80, alpha: 0.5)
        var objectStroke = CGColor(gray: 0.45, alpha: 1)
        var textColor = CGColor(gray: 0.15, alpha: 1)
        var windowColor = CGColor(red: 0.20, green: 0.55, blue: 0.95, alpha: 1)
    }

    /// Dénominateurs d'échelle usuels en architecture.
    static let standardScales: [Double] = [10, 20, 25, 50, 75, 100, 200, 500]
    /// Points PostScript par mètre à l'échelle 1:1.
    static let pointsPerMeter = 72.0 / 0.0254

    /// Marge autour du plan (m) réservée aux cotes.
    static let dimensionMargin = 0.55
    static let dimensionOffset = 0.30
    /// Les murs plus courts (retours, piliers) ne sont pas cotés : leurs libellés se chevauchaient sur les vrais scans.
    static let minimumDimensionedLength = 0.5

    var options = Options()

    // MARK: - Sorties

    /// PDF vectoriel d'une page `size` (points). A4 paysage par défaut.
    func pdfData(_ house: House, size: CGSize = CGSize(width: 842, height: 595), title: String? = nil) -> Data {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: size)
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        var info: [CFString: Any] = [kCGPDFContextCreator: "3D Scanner"]
        if let title { info[kCGPDFContextTitle] = title }
        let ctx = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary)!
        ctx.beginPDFPage(nil)
        draw(house, in: ctx, size: size)
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }

    /// Image bitmap RGBA (`makeImage`) de `pixels` pixels.
    func image(_ house: House, pixels: CGSize) -> CGImage? {
        let w = Int(pixels.width.rounded()), h = Int(pixels.height.rounded())
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        draw(house, in: ctx, size: pixels)
        return ctx.makeImage()
    }

    /// Image d'une *page* (points) rendue à `pixelScale` × : le calcul d'échelle
    /// se fait en points, donc « Échelle 1:n » reste exact quel que soit le facteur.
    func image(_ house: House, pageSize: CGSize, pixelScale: CGFloat) -> CGImage? {
        let w = Int((pageSize.width * pixelScale).rounded()), h = Int((pageSize.height * pixelScale).rounded())
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: pixelScale, y: pixelScale)
        draw(house, in: ctx, size: pageSize)
        return ctx.makeImage()
    }

    func pngData(_ house: House, pageSize: CGSize, pixelScale: CGFloat) -> Data? {
        image(house, pageSize: pageSize, pixelScale: pixelScale).flatMap(Self.encodePNG)
    }

    /// PNG de `pixels` pixels.
    func pngData(_ house: House, pixels: CGSize) -> Data? {
        image(house, pixels: pixels).flatMap(Self.encodePNG)
    }

    static func encodePNG(_ img: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    // MARK: - Échelle

    /// Plus grande échelle standard (plus petit `n`) telle que le plan et ses
    /// cotes tiennent dans `area` (points).
    static func standardScale(fitting bounds: Rect2D, into area: CGSize) -> Double {
        let w = bounds.width + 2 * dimensionMargin, h = bounds.height + 2 * dimensionMargin
        for n in standardScales {
            let ppm = pointsPerMeter / n
            if w * ppm <= Double(area.width), h * ppm <= Double(area.height) { return n }
        }
        return standardScales.last!
    }

    // MARK: - Dessin

    /// Dessine la maison dans `ctx`, dimensionné `size` (points ou pixels).
    func draw(_ house: House, in ctx: CGContext, size: CGSize) {
        let rooms = house.allRooms
        if !options.transparentBackground {
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        // Zone de dessin : réserve le cartouche en bas si demandé.
        let titleHeight: CGFloat = options.mode == .page(titleBlock: true) ? min(size.height * 0.16, 96) : 0
        let inset: CGFloat = options.mode == .fill ? size.width * 0.02 : min(size.width, size.height) * 0.05
        let area = CGRect(x: inset, y: titleHeight + inset, width: size.width - 2 * inset, height: size.height - titleHeight - 2 * inset)

        var bounds = Rect2D.empty
        for r in rooms { bounds = r.bounds.isEmpty ? bounds : merge(bounds, transformed(r.bounds, r.transform)) }
        guard !bounds.isEmpty else {
            if titleHeight > 0 { drawTitleBlock(house, rooms: rooms, scaleDenominator: nil, in: ctx, size: size, height: titleHeight) }
            return
        }

        let margin = options.showDimensions ? Self.dimensionMargin : 0.15
        let ppm: Double
        var scaleDenominator: Double? = nil
        switch options.mode {
        case .page:
            let n = Self.standardScale(fitting: bounds.insetBy(margin - Self.dimensionMargin), into: area.size)
            ppm = Self.pointsPerMeter / n; scaleDenominator = n
        case .fill:
            ppm = min(Double(area.width) / (bounds.width + 2 * margin), Double(area.height) / (bounds.height + 2 * margin))
        }
        // Centre le plan dans la zone.
        let planW = (bounds.width + 2 * margin) * ppm, planH = (bounds.height + 2 * margin) * ppm
        let origin = CGPoint(x: area.midX - planW / 2 + margin * ppm - bounds.minX * ppm,
                             y: area.midY - planH / 2 + margin * ppm - bounds.minY * ppm)
        let mapper = Mapper(origin: origin, ppm: ppm)

        for room in rooms { drawRoom(room, mapper: mapper, in: ctx) }
        if titleHeight > 0 { drawTitleBlock(house, rooms: rooms, scaleDenominator: scaleDenominator, in: ctx, size: size, height: titleHeight) }
    }

    /// Texture du sol pour le visualiseur : les pièces sont dessinées de sorte que
    /// `bounds` (m, repère maison) couvre exactement l'image — pas de marge, pas de
    /// cartouche. `pixelsPerMeter` fixe la résolution.
    func floorTextureImage(_ house: House, bounds: Rect2D, pixelsPerMeter: Double) -> CGImage? {
        let w = Int((bounds.width * pixelsPerMeter).rounded()), h = Int((bounds.height * pixelsPerMeter).rounded())
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let mapper = Mapper(origin: CGPoint(x: -bounds.minX * pixelsPerMeter, y: -bounds.minY * pixelsPerMeter), ppm: pixelsPerMeter)
        for room in house.allRooms { drawRoom(room, mapper: mapper, in: ctx) }
        return ctx.makeImage()
    }

    /// Conversion plan (m) → contexte (pt/px), avec le placement de la pièce dans la maison.
    struct Mapper {
        var origin: CGPoint
        var ppm: Double
        var transform: Transform2D = .identity
        func point(_ p: Point2D) -> CGPoint {
            let q = transform.apply(p)
            return CGPoint(x: origin.x + q.x * ppm, y: origin.y + q.y * ppm)
        }
        func length(_ m: Double) -> CGFloat { CGFloat(m * ppm) }
    }

    private func drawRoom(_ room: FloorPlan, mapper base: Mapper, in ctx: CGContext) {
        var mapper = base; mapper.transform = room.transform
        let side = InteriorSide(polygon: room.floorPolygon, fallback: room.bounds.center)

        // Sol
        if options.showFloor, room.floorPolygon.count >= 3 {
            ctx.setFillColor(options.floorColor)
            path(room.floorPolygon, mapper: mapper, in: ctx); ctx.fillPath()
        }
        // Objets
        if options.showObjects {
            for o in room.objects { drawObject(o, mapper: mapper, in: ctx) }
        }
        // Murs avec percements
        let thickness = max(mapper.length(FloorPlan.defaultWallThickness), 1.5)
        ctx.setStrokeColor(options.wallColor); ctx.setLineWidth(thickness); ctx.setLineCap(.square)
        for wall in room.walls {
            let openings = room.openings.filter { $0.wallID == wall.id }
            for piece in wallPieces(wall, openings: openings) {
                ctx.move(to: mapper.point(piece.start)); ctx.addLine(to: mapper.point(piece.end))
            }
        }
        ctx.strokePath()
        // Portes / fenêtres / ouvertures
        for o in room.openings { drawOpening(o, side: side, mapper: mapper, in: ctx) }
        // Cotes
        if options.showDimensions {
            for wall in room.walls { drawDimension(wall, side: side, mapper: mapper, in: ctx) }
        }
    }

    /// Découpe la trace du mur autour des ouvertures qui lui sont rattachées.
    func wallPieces(_ wall: Wall, openings: [Opening]) -> [Segment2D] {
        let len = wall.length
        guard len > 0 else { return [] }
        let dir = wall.segment.direction
        // Intervalles [t0, t1] (m le long du mur) occupés par les ouvertures.
        var gaps: [(Double, Double)] = openings.map { o in
            let t = ((o.center.x - wall.start.x) * dir.x + (o.center.y - wall.start.y) * dir.y)
            return (max(0, t - o.width / 2), min(len, t + o.width / 2))
        }.filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
        var pieces: [Segment2D] = []
        var cursor = 0.0
        while !gaps.isEmpty {
            let g = gaps.removeFirst()
            if g.0 > cursor + 0.005 { pieces.append(Segment2D(start: wall.start + dir * cursor, end: wall.start + dir * g.0)) }
            cursor = max(cursor, g.1)
        }
        if cursor < len - 0.005 { pieces.append(Segment2D(start: wall.start + dir * cursor, end: wall.end)) }
        return pieces
    }

    private func drawOpening(_ o: Opening, side: InteriorSide, mapper: Mapper, in ctx: CGContext) {
        let seg = o.segment
        let a = mapper.point(seg.start), b = mapper.point(seg.end)
        let n = seg.leftNormal
        let inward = side.inward(of: seg)
        let thin = max(mapper.length(0.02), 0.8)
        switch o.kind {
        case .door:
            // Battant ouvert à 90° vers l'intérieur + arc de débattement depuis la charnière (start).
            ctx.setStrokeColor(options.wallColor); ctx.setLineWidth(thin); ctx.setLineDash(phase: 0, lengths: [])
            let hinge = seg.start
            let leafEnd = hinge + inward * o.width
            ctx.move(to: mapper.point(hinge)); ctx.addLine(to: mapper.point(leafEnd)); ctx.strokePath()
            ctx.setLineWidth(thin * 0.8)
            ctx.setLineDash(phase: 0, lengths: [mapper.length(0.05), mapper.length(0.04)])
            let startAngle = atan2(seg.end.y - hinge.y, seg.end.x - hinge.x)
            let endAngle = atan2(leafEnd.y - hinge.y, leafEnd.x - hinge.x)
            let clockwise = normalizedDelta(from: startAngle, to: endAngle) < 0
            ctx.addArc(center: mapper.point(hinge), radius: mapper.length(o.width), startAngle: startAngle, endAngle: endAngle, clockwise: clockwise)
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
        case .window:
            // Deux traits fins (vitrage) dans l'épaisseur du mur.
            ctx.setStrokeColor(options.windowColor); ctx.setLineWidth(thin); ctx.setLineDash(phase: 0, lengths: [])
            let off = n * (FloorPlan.defaultWallThickness * 0.3)
            for d in [off, off * -1] {
                ctx.move(to: mapper.point(seg.start + d)); ctx.addLine(to: mapper.point(seg.end + d))
            }
            ctx.strokePath()
        case .opening:
            ctx.setStrokeColor(options.wallColor); ctx.setLineWidth(thin)
            ctx.setLineDash(phase: 0, lengths: [mapper.length(0.08), mapper.length(0.06)])
            ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
        }
    }

    private func drawObject(_ o: PlacedObject, mapper: Mapper, in ctx: CGContext) {
        let c = cos(o.angle), s = sin(o.angle)
        let hw = o.size.width / 2, hd = o.size.depth / 2
        let corners = [(-hw, -hd), (hw, -hd), (hw, hd), (-hw, hd)].map { (x, y) in
            Point2D(x: o.center.x + x * c - y * s, y: o.center.y + x * s + y * c)
        }
        ctx.setFillColor(options.objectFill); ctx.setStrokeColor(options.objectStroke)
        ctx.setLineWidth(max(mapper.length(0.015), 0.6)); ctx.setLineDash(phase: 0, lengths: [])
        path(corners, mapper: mapper, in: ctx); ctx.drawPath(using: .fillStroke)
        let fontSize = max(min(mapper.length(0.22), 11), 4)
        if mapper.length(o.size.width) > fontSize * 2 {
            drawText(ObjectNaming.localizedName(o.category), at: mapper.point(o.center), angle: readable(o.angle),
                     fontSize: fontSize, color: options.objectStroke, in: ctx)
        }
    }

    private func drawDimension(_ wall: Wall, side: InteriorSide, mapper: Mapper, in ctx: CGContext) {
        let seg = wall.segment
        guard seg.length >= PlanRenderer.minimumDimensionedLength else { return }
        // Ligne de cote à l'extérieur du mur.
        let n = seg.leftNormal
        let outward = side.inward(of: seg) * -1
        let off = outward * Self.dimensionOffset
        let a = seg.start + off, b = seg.end + off
        ctx.setStrokeColor(options.dimensionColor); ctx.setLineWidth(max(mapper.length(0.012), 0.6)); ctx.setLineDash(phase: 0, lengths: [])
        ctx.move(to: mapper.point(a)); ctx.addLine(to: mapper.point(b))
        // Traits de rappel et extrémités
        let tick = outward * 0.06
        for (p, q) in [(seg.start + outward * 0.05, a + tick), (seg.end + outward * 0.05, b + tick)] {
            ctx.move(to: mapper.point(p)); ctx.addLine(to: mapper.point(q))
        }
        ctx.strokePath()
        // Flèches (petits triangles pleins)
        let d = seg.direction
        let arrowLen = 0.09, arrowHalf = 0.03
        for (tip, back) in [(a, a + d * arrowLen), (b, b - d * arrowLen)] {
            let left = back + n * arrowHalf, right = back - n * arrowHalf
            ctx.setFillColor(options.dimensionColor)
            path([tip, left, right], mapper: mapper, in: ctx); ctx.fillPath()
        }
        let label = MeasurementFormat.centimeters(wall.length, locale: options.locale)
        let fontSize = max(min(mapper.length(0.24), 12), 4)
        let textPos = seg.midpoint + off + outward * (0.12 + Double(fontSize) / mapper.ppm * 0.4)
        drawText(label, at: mapper.point(textPos), angle: readable(seg.angle), fontSize: fontSize, color: options.dimensionColor, in: ctx)
    }

    private func drawTitleBlock(_ house: House, rooms: [FloorPlan], scaleDenominator: Double?, in ctx: CGContext, size: CGSize, height: CGFloat) {
        let inset = min(size.width, size.height) * 0.05
        let rect = CGRect(x: inset, y: inset * 0.6, width: size.width - 2 * inset, height: height - inset * 0.2)
        ctx.setStrokeColor(CGColor(gray: 0.6, alpha: 1)); ctx.setLineWidth(0.8); ctx.setLineDash(phase: 0, lengths: [])
        ctx.stroke(rect)
        let loc = options.locale
        let area = rooms.reduce(0) { $0 + Polygon2D.area($1.floorPolygon) }
        let perimeter = rooms.reduce(0) { $0 + $1.walls.reduce(0) { $0 + $1.length } }
        let ceil = rooms.first?.ceilingHeight ?? 0...0
        let ceilText = abs(ceil.upperBound - ceil.lowerBound) < 0.02 ? MeasurementFormat.meters(ceil.lowerBound, locale: loc)
            : "\(MeasurementFormat.meters(ceil.lowerBound, locale: loc)) – \(MeasurementFormat.meters(ceil.upperBound, locale: loc))"
        let date = house.allRooms.isEmpty ? Date() : Date()
        let df = DateFormatter(); df.locale = loc; df.dateStyle = .medium; df.timeStyle = .none
        let big = min(rect.height * 0.30, 16), small = min(rect.height * 0.18, 9.5)
        let x = rect.minX + 10
        drawText(house.name, at: CGPoint(x: x, y: rect.maxY - big * 1.1), angle: 0, fontSize: big, weight: .bold, color: options.textColor, align: .left, in: ctx)
        let line1 = [String(localized: "plan.area", locale: loc) + " " + MeasurementFormat.squareMeters(area, locale: loc),
                     String(localized: "plan.perimeter", locale: loc) + " " + MeasurementFormat.meters(perimeter, locale: loc),
                     String(localized: "plan.ceiling", locale: loc) + " " + ceilText].joined(separator: "   ·   ")
        drawText(line1, at: CGPoint(x: x, y: rect.maxY - big * 1.1 - small * 1.6), angle: 0, fontSize: small, color: options.textColor, align: .left, in: ctx)
        var line2 = [df.string(from: date), "3D Scanner", String(localized: "plan.disclaimer", locale: loc)]
        if let n = scaleDenominator { line2.insert(String(localized: "plan.scale", locale: loc) + " 1:\(Int(n))", at: 0) }
        drawText(line2.joined(separator: "   ·   "), at: CGPoint(x: x, y: rect.minY + small * 0.8), angle: 0, fontSize: small, color: CGColor(gray: 0.4, alpha: 1), align: .left, in: ctx)
    }

    // MARK: - Texte (Core Text)

    enum Align { case left, center }
    enum Weight { case regular, bold }

    func drawText(_ text: String, at p: CGPoint, angle: CGFloat, fontSize: CGFloat, weight: Weight = .regular,
                  color: CGColor, align: Align = .center, in ctx: CGContext) {
        let font = CTFontCreateUIFontForLanguage(weight == .bold ? .emphasizedSystem : .system, fontSize, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        ctx.saveGState()
        ctx.translateBy(x: p.x, y: p.y)
        ctx.rotate(by: angle)
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: align == .center ? -width / 2 : 0, y: -fontSize * 0.35)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    /// Détermine de quel côté d'un segment se trouve l'intérieur de la pièce :
    /// test point-dans-polygone à 5 cm du milieu (robuste sur les pièces en L),
    /// repli sur la position du centre de l'englobant.
    struct InteriorSide {
        let polygon: [Point2D]
        let fallback: Point2D
        func inward(of seg: Segment2D) -> Point2D {
            let n = seg.leftNormal
            if polygon.count >= 3 {
                let probe = seg.midpoint + n * 0.05
                if Polygon2D.contains(polygon, probe) { return n }
                if Polygon2D.contains(polygon, seg.midpoint - n * 0.05) { return n * -1 }
            }
            let toInterior = fallback - seg.midpoint
            return (n.x * toInterior.x + n.y * toInterior.y) >= 0 ? n : n * -1
        }
    }

    // MARK: - Helpers

    private func path(_ pts: [Point2D], mapper: Mapper, in ctx: CGContext) {
        guard let first = pts.first else { return }
        ctx.move(to: mapper.point(first))
        for p in pts.dropFirst() { ctx.addLine(to: mapper.point(p)) }
        ctx.closePath()
    }

    /// Angle ramené dans ]−π/2, π/2] pour qu'un texte ne soit jamais tête en bas.
    private func readable(_ angle: Double) -> CGFloat {
        var a = angle
        while a > .pi / 2 { a -= .pi }
        while a <= -.pi / 2 { a += .pi }
        return CGFloat(a)
    }

    private func normalizedDelta(from a: Double, to b: Double) -> Double {
        var d = b - a
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return d
    }

    private func transformed(_ r: Rect2D, _ t: Transform2D) -> Rect2D {
        Rect2D.bounding([Point2D(x: r.minX, y: r.minY), Point2D(x: r.maxX, y: r.minY),
                         Point2D(x: r.maxX, y: r.maxY), Point2D(x: r.minX, y: r.maxY)].map(t.apply))
    }

    private func merge(_ a: Rect2D, _ b: Rect2D) -> Rect2D {
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return Rect2D(minX: min(a.minX, b.minX), minY: min(a.minY, b.minY), maxX: max(a.maxX, b.maxX), maxY: max(a.maxY, b.maxY))
    }
}

extension PlanRenderer {
    /// Vignette de bibliothèque (600 × 400 px, sans cartouche).
    static func thumbnailPNG(for plan: FloorPlan) -> Data? {
        var r = PlanRenderer(); r.options.mode = .fill; r.options.showObjects = true
        return r.pngData(House(room: plan), pixels: CGSize(width: 600, height: 400))
    }
}
