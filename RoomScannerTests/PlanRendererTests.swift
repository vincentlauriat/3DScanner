import XCTest
import CoreGraphics
@testable import RoomScanner

final class PlanRendererTests: XCTestCase {
    private func house() -> House {
        House(room: FloorPlanBuilder().build(from: SyntheticRooms.rectangularRoom().scan, name: "Salon"))
    }

    func testStandardScaleFitsA4Landscape() {
        // Pièce 4 × 3 m + marges de cotes (5,1 × 4,1 m). À 1:25 (113 pt/m) il faut 578 × 465 pt.
        let b = Rect2D(minX: -2, minY: -1.5, maxX: 2, maxY: 1.5)
        XCTAssertEqual(PlanRenderer.standardScale(fitting: b, into: CGSize(width: 750, height: 500)), 25)
        XCTAssertEqual(PlanRenderer.standardScale(fitting: b, into: CGSize(width: 750, height: 400)), 50, "trop bas pour 1:25 → 1:50")
        // Grande maison 30 × 20 m (31,1 × 21,1 m) : 1:100 demande 881 × 598 pt.
        XCTAssertEqual(PlanRenderer.standardScale(fitting: Rect2D(minX: 0, minY: 0, maxX: 30, maxY: 20), into: CGSize(width: 900, height: 620)), 100)
        XCTAssertEqual(PlanRenderer.standardScale(fitting: Rect2D(minX: 0, minY: 0, maxX: 30, maxY: 20), into: CGSize(width: 750, height: 400)), 200)
        // Minuscule zone → l'échelle la plus petite disponible
        XCTAssertEqual(PlanRenderer.standardScale(fitting: b, into: CGSize(width: 10, height: 10)), 500)
    }

    func testPNGHasExpectedSizeAndInk() throws {
        let png = try XCTUnwrap(PlanRenderer().pngData(house(), pixels: CGSize(width: 800, height: 600)))
        let src = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        XCTAssertEqual(img.width, 800); XCTAssertEqual(img.height, 600)
        XCTAssertGreaterThan(darkPixelRatio(img), 0.003, "les murs doivent laisser de l'encre")
        XCTAssertLessThan(darkPixelRatio(img), 0.5, "mais la page reste majoritairement blanche")
    }

    func testPDFIsValidAndVectorial() throws {
        let pdf = PlanRenderer().pdfData(house(), title: "Salon")
        XCTAssertTrue(String(decoding: pdf.prefix(5), as: UTF8.self).hasPrefix("%PDF-"))
        let doc = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: pdf as CFData)!))
        XCTAssertEqual(doc.numberOfPages, 1)
        let box = doc.page(at: 1)!.getBoxRect(.mediaBox)
        XCTAssertEqual(box.width, 842, accuracy: 0.5); XCTAssertEqual(box.height, 595, accuracy: 0.5)
        XCTAssertGreaterThan(pdf.count, 2000)
    }

    func testFillModeWithoutTitleBlockUsesMoreOfTheCanvas() throws {
        var page = PlanRenderer(); page.options.mode = .page(titleBlock: false)
        var fill = PlanRenderer(); fill.options.mode = .fill
        let size = CGSize(width: 600, height: 400)
        let a = try XCTUnwrap(page.image(house(), pixels: size)), b = try XCTUnwrap(fill.image(house(), pixels: size))
        XCTAssertGreaterThan(inkBounds(b).width, inkBounds(a).width, "en mode remplissage le plan occupe plus de largeur")
    }

    func testPagePNGKeepsPointScale() throws {
        let png = try XCTUnwrap(PlanRenderer().pngData(house(), pageSize: CGSize(width: 842, height: 595), pixelScale: 3))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(png as CFData, nil)!, 0, nil))
        XCTAssertEqual(img.width, 2526); XCTAssertEqual(img.height, 1785)
    }

    func testInteriorSideOnLShape() {
        let plan = FloorPlanBuilder().build(from: SyntheticRooms.lShapedRoom(), name: "L")
        let side = PlanRenderer.InteriorSide(polygon: plan.floorPolygon, fallback: plan.bounds.center)
        // Mur rentrant (3,3)→(3,5) : l'intérieur est à gauche (x < 3), le centroïde de l'englobant est à droite.
        let inner = plan.walls.first { abs($0.start.x - 3) < 0.01 && abs($0.end.x - 3) < 0.01 }!
        let inward = side.inward(of: inner.segment)
        XCTAssertTrue(Polygon2D.contains(plan.floorPolygon, inner.segment.midpoint + inward * 0.05))
        XCTAssertLessThan(inward.x, 0)
    }

    func testPointInPolygon() {
        let sq = [Point2D(x: 0, y: 0), Point2D(x: 4, y: 0), Point2D(x: 4, y: 3), Point2D(x: 0, y: 3)]
        XCTAssertTrue(Polygon2D.contains(sq, Point2D(x: 1, y: 1)))
        XCTAssertFalse(Polygon2D.contains(sq, Point2D(x: 5, y: 1)))
        XCTAssertFalse(Polygon2D.contains(SyntheticRooms.lShapeCorners, Point2D(x: 5, y: 4)), "l'encoche du L est dehors")
    }

    func testThumbnail() throws {
        let plan = FloorPlanBuilder().build(from: SyntheticRooms.lShapedRoom(), name: "Chambre")
        let png = try XCTUnwrap(PlanRenderer.thumbnailPNG(for: plan))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(png as CFData, nil)!, 0, nil))
        XCTAssertEqual(img.width, 600); XCTAssertEqual(img.height, 400)
    }

    func testWallPiecesAreCutAroundOpenings() {
        let plan = FloorPlanBuilder().build(from: SyntheticRooms.rectangularRoom().scan, name: "Salon")
        let renderer = PlanRenderer()
        let door = plan.openings.first { $0.kind == .door }!
        let south = plan.wall(withID: door.wallID)!
        let pieces = renderer.wallPieces(south, openings: [door])
        XCTAssertEqual(pieces.count, 2)
        XCTAssertEqual(pieces.reduce(0) { $0 + $1.length }, south.length - door.width, accuracy: 0.001)
        XCTAssertEqual(renderer.wallPieces(south, openings: []).count, 1)
    }

    func testEmptyHouseStillRenders() throws {
        let empty = House(room: FloorPlanBuilder().build(from: ScanInput(surfaces: []), name: "Vide"))
        XCTAssertNotNil(PlanRenderer().pngData(empty, pixels: CGSize(width: 200, height: 100)))
        XCTAssertTrue(String(decoding: PlanRenderer().pdfData(empty).prefix(4), as: UTF8.self) == "%PDF")
    }

    /// Écrit des rendus dans `<tmp>/RoomScannerPlanSamples` pour inspection visuelle.
    func testWriteSamplesForInspection() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("RoomScannerPlanSamples", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var fr = PlanRenderer(); fr.options.locale = Locale(identifier: "fr_FR")
        try fr.pdfData(house(), title: "Salon").write(to: dir.appendingPathComponent("salon.pdf"))
        try XCTUnwrap(fr.pngData(house(), pageSize: CGSize(width: 842, height: 595), pixelScale: 2)).write(to: dir.appendingPathComponent("salon.png"))
        let l = House(room: FloorPlanBuilder().build(from: SyntheticRooms.lShapedRoom(), name: "Chambre"))
        try XCTUnwrap(fr.pngData(l, pageSize: CGSize(width: 842, height: 595), pixelScale: 2)).write(to: dir.appendingPathComponent("chambre-L.png"))
        try XCTUnwrap(PlanRenderer.thumbnailPNG(for: house().allRooms[0])).write(to: dir.appendingPathComponent("thumb.png"))
    }

    // MARK: helpers

    private func pixels(_ img: CGImage) -> (data: [UInt8], bpr: Int)? {
        guard let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        let ptr = ctx.data!.assumingMemoryBound(to: UInt8.self)
        return (Array(UnsafeBufferPointer(start: ptr, count: ctx.bytesPerRow * img.height)), ctx.bytesPerRow)
    }

    private func darkPixelRatio(_ img: CGImage) -> Double {
        guard let (d, bpr) = pixels(img) else { return 0 }
        var dark = 0
        for y in 0..<img.height { for x in 0..<img.width {
            let i = y * bpr + x * 4
            if Int(d[i]) + Int(d[i + 1]) + Int(d[i + 2]) < 3 * 110 { dark += 1 }
        } }
        return Double(dark) / Double(img.width * img.height)
    }

    private func inkBounds(_ img: CGImage) -> CGRect {
        guard let (d, bpr) = pixels(img) else { return .zero }
        var minX = img.width, maxX = 0, minY = img.height, maxY = 0
        for y in 0..<img.height { for x in 0..<img.width {
            let i = y * bpr + x * 4
            if Int(d[i]) + Int(d[i + 1]) + Int(d[i + 2]) < 3 * 110 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
        } }
        return maxX < minX ? .zero : CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
