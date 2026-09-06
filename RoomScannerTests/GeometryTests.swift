import XCTest
@testable import RoomScanner

final class GeometryTests: XCTestCase {
    let square = [Point2D(x: 0, y: 0), Point2D(x: 4, y: 0), Point2D(x: 4, y: 3), Point2D(x: 0, y: 3)]

    func testShoelaceArea() {
        XCTAssertEqual(Polygon2D.area(square), 12, accuracy: 1e-9)
        XCTAssertEqual(Polygon2D.signedArea(square), 12, accuracy: 1e-9, "sens trigonométrique ⇒ positif")
        XCTAssertEqual(Polygon2D.signedArea(square.reversed()), -12, accuracy: 1e-9)
        XCTAssertEqual(Polygon2D.area([Point2D(x: 0, y: 0), Point2D(x: 1, y: 1)]), 0)
    }

    func testPerimeter() {
        XCTAssertEqual(Polygon2D.perimeter(square), 14, accuracy: 1e-9)
    }

    func testChainReordersAndReversesSegments() {
        let segs = [Segment2D(start: square[2], end: square[3]),   // désordonné
                    Segment2D(start: square[1], end: square[0]),   // inversé
                    Segment2D(start: square[3], end: square[0]),
                    Segment2D(start: square[1], end: square[2])]
        let contour = Polygon2D.chain(segs, tolerance: 0.01)
        XCTAssertEqual(contour?.count, 4)
        XCTAssertEqual(Polygon2D.area(contour ?? []), 12, accuracy: 1e-9)
    }

    func testChainFailsOnGap() {
        var segs = square.indices.map { Segment2D(start: square[$0], end: square[($0 + 1) % 4]) }
        segs[2].end = Point2D(x: 0.5, y: 3)   // le contour ne se referme plus
        XCTAssertNil(Polygon2D.chain(segs, tolerance: 0.1))
    }

    func testChainToleratesSmallGaps() {
        var segs = square.indices.map { Segment2D(start: square[$0], end: square[($0 + 1) % 4]) }
        segs[0].end = Point2D(x: 3.9, y: 0.05)   // 11 cm d'écart, typique d'un scan
        XCTAssertNotNil(Polygon2D.chain(segs, tolerance: 0.25))
    }

    func testSegmentDistance() {
        let s = Segment2D(start: Point2D(x: 0, y: 0), end: Point2D(x: 4, y: 0))
        XCTAssertEqual(s.distance(to: Point2D(x: 2, y: 1)), 1, accuracy: 1e-9)
        XCTAssertEqual(s.distance(to: Point2D(x: 6, y: 0)), 2, accuracy: 1e-9, "au-delà de l'extrémité")
    }

    func testTriangulationCoversArea() {
        for poly in [square, SyntheticRooms.lShapeCorners, SyntheticRooms.lShapeCorners.reversed()] {
            let tris = Polygon2D.triangulate(poly)
            XCTAssertEqual(tris.count, poly.count - 2)
            let area = tris.reduce(0.0) { $0 + Polygon2D.area([poly[$1.0], poly[$1.1], poly[$1.2]]) }
            XCTAssertEqual(area, Polygon2D.area(poly), accuracy: 1e-9, "les triangles recouvrent exactement le polygone")
        }
        XCTAssertTrue(Polygon2D.triangulate([Point2D(x: 0, y: 0), Point2D(x: 1, y: 0)]).isEmpty)
    }

    func testProjectionFlipsZ() {
        let p = Point2D(projecting: SIMD3<Float>(1, 5, 2))
        XCTAssertEqual(p, Point2D(x: 1, y: -2))
    }

    func testTriangulationSkipsFlatLastTripletAndReportsDegenerateContours() {
        // Rectangle avec un sommet aligné sur un côté : le dernier triplet peut être plat.
        let pts = [Point2D(x: 0, y: 0), Point2D(x: 2, y: 0), Point2D(x: 4, y: 0), Point2D(x: 4, y: 3), Point2D(x: 0, y: 3)]
        let (tris, complete) = Polygon2D.triangulation(pts)
        XCTAssertTrue(complete)
        for t in tris {
            let a = pts[t.0], b = pts[t.1], c = pts[t.2]
            XCTAssertGreaterThan(abs(Polygon2D.signedArea([a, b, c])), 1e-9, "aucun triangle plat")
        }
        XCTAssertEqual(tris.reduce(0.0) { $0 + abs(Polygon2D.signedArea([pts[$1.0], pts[$1.1], pts[$1.2]])) }, 12, accuracy: 1e-9)
        // Contour dégénéré (tous alignés) : incomplet, sans triangle.
        let flat = [Point2D(x: 0, y: 0), Point2D(x: 1, y: 0), Point2D(x: 2, y: 0), Point2D(x: 3, y: 0)]
        let r = Polygon2D.triangulation(flat)
        XCTAssertFalse(r.complete); XCTAssertTrue(r.triangles.isEmpty)
    }

    // MARK: - Union et intersection de polygones (surface d'une maison)

    private func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [Point2D] {
        [Point2D(x: x0, y: y0), Point2D(x: x1, y: y0), Point2D(x: x1, y: y1), Point2D(x: x0, y: y1)]
    }

    func testUnionOfDisjointPolygonsIsTheSum() {
        let a = rect(0, 0, 1, 1), b = rect(2, 0, 3, 1)
        XCTAssertEqual(Polygon2D.unionArea([a, b]), 2, accuracy: 1e-9)
        XCTAssertEqual(Polygon2D.intersectionArea([a, b]), 0, accuracy: 1e-9)
    }

    func testUnionOfIdenticalPolygonsIsOneOfThem() {
        let a = rect(0, 0, 2, 3)
        XCTAssertEqual(Polygon2D.unionArea([a, a, a]), 6, accuracy: 1e-9)
        XCTAssertEqual(Polygon2D.intersectionArea([a, a]), 6, accuracy: 1e-9)
    }

    func testUnionSubtractsThePairwiseOverlap() {
        // [0,1]² et [0.5,1.5]×[0,1] : recouvrement de 0,5.
        let a = rect(0, 0, 1, 1), b = rect(0.5, 0, 1.5, 1)
        XCTAssertEqual(Polygon2D.intersectionArea([a, b]), 0.5, accuracy: 1e-9)
        XCTAssertEqual(Polygon2D.unionArea([a, b]), 1.5, accuracy: 1e-9)
    }

    /// Cas qui distingue l'inclusion–exclusion complète d'une simple soustraction des
    /// recouvrements deux à deux : trois carrés partageant une même zone. Somme 3,
    /// recouvrements deux à deux 0,5 + 0,5 + 0,25, zone triple 0,25 ⇒ union = 2.
    /// Une implémentation qui s'arrêterait aux paires répondrait 1,75.
    func testUnionHandlesARegionSharedByThreePolygons() {
        let a = rect(0, 0, 1, 1), b = rect(0.5, 0, 1.5, 1), c = rect(0, 0.5, 1, 1.5)
        XCTAssertEqual(Polygon2D.intersectionArea([a, b, c]), 0.25, accuracy: 1e-9)
        XCTAssertEqual(Polygon2D.unionArea([a, b, c]), 2, accuracy: 1e-9)
    }

    func testUnionOfConcavePolygons() {
        // L renversé : [0,2]×[0,1] ∪ [0,1]×[0,2] décrit d'un seul tenant (aire 3),
        // uni avec le carré manquant [1,2]×[1,2] ⇒ le carré plein 2×2.
        let l = [Point2D(x: 0, y: 0), Point2D(x: 2, y: 0), Point2D(x: 2, y: 1),
                 Point2D(x: 1, y: 1), Point2D(x: 1, y: 2), Point2D(x: 0, y: 2)]
        XCTAssertEqual(Polygon2D.area(l), 3, accuracy: 1e-9)
        XCTAssertEqual(Polygon2D.unionArea([l, rect(1, 1, 2, 2)]), 4, accuracy: 1e-9)
    }

    func testUnionIgnoresDegeneratePolygons() {
        let a = rect(0, 0, 1, 1)
        XCTAssertEqual(Polygon2D.unionArea([a, [], [Point2D(x: 5, y: 5), Point2D(x: 6, y: 6)]]), 1, accuracy: 1e-9)
        XCTAssertEqual(Polygon2D.unionArea([]), 0)
    }

    func testClipByConvexKeepsTheCommonPart() {
        let clipped = Polygon2D.clip(rect(0, 0, 2, 2), byConvex: rect(1, 1, 3, 3))
        XCTAssertEqual(Polygon2D.area(clipped), 1, accuracy: 1e-9)
    }
}
