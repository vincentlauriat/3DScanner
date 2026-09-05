import Foundation

/// Niveau de confiance RoomPlan, neutre.
enum Confidence: String, Codable, Comparable {
    case low, medium, high
    private var rank: Int { switch self { case .low: 0; case .medium: 1; case .high: 2 } }
    static func < (a: Confidence, b: Confidence) -> Bool { a.rank < b.rank }
}

/// Étiquette de pièce RoomPlan (`CapturedRoom.Section.Label`), neutre.
enum RoomLabel: String, Codable, CaseIterable {
    case livingRoom, bedroom, bathroom, kitchen, diningRoom, unidentified
}

/// Placement planaire d'une pièce dans le repère de la maison (D14).
/// Identité en v1 ; renseigné par la fusion multi-pièces en v2.
struct Transform2D: Codable, Equatable {
    var translation: Point2D
    /// Rotation autour de la verticale, radians.
    var rotation: Double

    static let identity = Transform2D(translation: .zero, rotation: 0)

    func apply(_ p: Point2D) -> Point2D {
        let c = cos(rotation), s = sin(rotation)
        return Point2D(x: c * p.x - s * p.y + translation.x, y: s * p.x + c * p.y + translation.y)
    }
}

/// Mur : trace au sol (segment) + hauteur. L'épaisseur n'est pas mesurée par
/// RoomPlan : valeur graphique constante (`FloorPlan.defaultWallThickness`).
struct Wall: Codable, Equatable, Identifiable {
    var id: UUID
    var segment: Segment2D
    var height: Double
    var thickness: Double
    var confidence: Confidence

    var start: Point2D { segment.start }
    var end: Point2D { segment.end }
    var length: Double { segment.length }
}

/// Porte, fenêtre ou ouverture, rattachée à un mur quand RoomPlan le fournit.
struct Opening: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case door, window, opening }
    var id: UUID
    var kind: Kind
    var wallID: UUID?
    var center: Point2D
    var width: Double
    var height: Double
    /// Hauteur d'allège (bas de l'ouverture au-dessus du sol) ; 0 pour une porte.
    var sillHeight: Double
    /// Orientation dans le plan, radians (axe « largeur »).
    var angle: Double
    var confidence: Confidence

    /// Trace au sol de l'ouverture.
    var segment: Segment2D {
        let d = Point2D(x: cos(angle), y: sin(angle)) * (width / 2)
        return Segment2D(start: center - d, end: center + d)
    }
}

/// Meuble / équipement détecté, représenté par une boîte 2D orientée.
struct PlacedObject: Codable, Equatable, Identifiable {
    var id: UUID
    var category: String
    var center: Point2D
    var size: Size2D
    var height: Double
    var angle: Double
    var confidence: Confidence
}

/// Modèle pivot d'une pièce (D3). Mètres, `Double`, pur Swift. Sérialisé dans
/// `plan.json` pour être lu sans RoomPlan (Mac) ; recalculable depuis `room.json`.
struct FloorPlan: Codable, Equatable, Identifiable {
    static let schemaVersion = 1
    static let defaultWallThickness = 0.10

    var id: UUID
    var name: String
    var label: RoomLabel
    var story: Int
    var transform: Transform2D
    var walls: [Wall]
    var openings: [Opening]
    var objects: [PlacedObject]
    /// Contour du sol, sens trigonométrique, vide si non déterminable.
    var floorPolygon: [Point2D]
    var ceilingHeight: ClosedRange<Double>

    /// Englobant de tout ce qui se dessine (murs, ouvertures, objets, sol).
    var bounds: Rect2D {
        var pts = walls.flatMap { [$0.start, $0.end] } + floorPolygon
        pts += openings.flatMap { [$0.segment.start, $0.segment.end] }
        for o in objects {
            let c = cos(o.angle), s = sin(o.angle), hw = o.size.width / 2, hd = o.size.depth / 2
            pts += [(-hw, -hd), (hw, -hd), (hw, hd), (-hw, hd)].map { (x, y) in Point2D(x: o.center.x + x * c - y * s, y: o.center.y + x * s + y * c) }
        }
        return Rect2D.bounding(pts)
    }

    func wall(withID id: UUID?) -> Wall? {
        guard let id else { return nil }
        return walls.first { $0.id == id }
    }
}

/// Agrégat maison (D14) : N pièces réparties par niveau. En v1 : une pièce.
struct House: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var stories: [Story]

    init(id: UUID = UUID(), name: String, stories: [Story]) { self.id = id; self.name = name; self.stories = stories }

    /// Maison d'une seule pièce.
    init(room: FloorPlan) {
        self.init(name: room.name, stories: [Story(index: room.story, rooms: [room])])
    }

    var allRooms: [FloorPlan] { stories.flatMap(\.rooms) }

    /// Englobant de toutes les pièces dans le repère maison (placements appliqués).
    var bounds: Rect2D {
        var pts: [Point2D] = []
        for r in allRooms where !r.bounds.isEmpty {
            let b = r.bounds
            pts += [Point2D(x: b.minX, y: b.minY), Point2D(x: b.maxX, y: b.minY), Point2D(x: b.maxX, y: b.maxY), Point2D(x: b.minX, y: b.maxY)].map(r.transform.apply)
        }
        return Rect2D.bounding(pts)
    }
}

struct Story: Codable, Equatable {
    var index: Int
    var rooms: [FloorPlan]
}
