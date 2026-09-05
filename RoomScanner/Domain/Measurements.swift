import Foundation

/// Mesures dérivées d'un `FloorPlan`. Toutes les valeurs en mètres / m².
struct RoomMeasurements: Equatable {
    struct WallMeasure: Equatable, Identifiable { let id: UUID; let length: Double; let height: Double; let confidence: Confidence }
    struct OpeningMeasure: Equatable, Identifiable {
        let id: UUID; let kind: Opening.Kind; let width: Double; let height: Double; let sillHeight: Double; let confidence: Confidence
    }
    struct ObjectMeasure: Equatable, Identifiable {
        let id: UUID; let category: String; let width: Double; let depth: Double; let height: Double; let confidence: Confidence
    }

    let floorArea: Double
    let perimeter: Double
    let ceilingHeight: ClosedRange<Double>
    let walls: [WallMeasure]
    let openings: [OpeningMeasure]
    let objects: [ObjectMeasure]

    init(plan: FloorPlan) {
        floorArea = Polygon2D.area(plan.floorPolygon)
        perimeter = plan.walls.reduce(0) { $0 + $1.length }
        ceilingHeight = plan.ceilingHeight
        walls = plan.walls.map { WallMeasure(id: $0.id, length: $0.length, height: $0.height, confidence: $0.confidence) }
        openings = plan.openings.map {
            OpeningMeasure(id: $0.id, kind: $0.kind, width: $0.width, height: $0.height, sillHeight: $0.sillHeight, confidence: $0.confidence)
        }
        objects = plan.objects.map {
            ObjectMeasure(id: $0.id, category: $0.category, width: $0.size.width, depth: $0.size.depth, height: $0.height, confidence: $0.confidence)
        }
    }

    var doors: [OpeningMeasure] { openings.filter { $0.kind == .door } }
    var windows: [OpeningMeasure] { openings.filter { $0.kind == .window } }
}

/// Mesures d'une maison : somme des pièces.
struct HouseMeasurements: Equatable {
    let floorArea: Double
    let roomCount: Int
    let storyCount: Int

    init(house: House) {
        let rooms = house.allRooms
        floorArea = rooms.reduce(0) { $0 + RoomMeasurements(plan: $1).floorArea }
        roomCount = rooms.count
        storyCount = house.stories.count
    }
}

/// Formatage des mesures pour l'affichage et les exports 2D : centimètres
/// entiers pour les longueurs, m² à une décimale, locale du système.
enum MeasurementFormat {
    static func centimeters(_ meters: Double, locale: Locale = .current) -> String {
        let cm = (meters * 100).rounded()
        let f = NumberFormatter(); f.locale = locale; f.maximumFractionDigits = 0
        return (f.string(from: cm as NSNumber) ?? "\(Int(cm))") + " cm"
    }

    static func meters(_ meters: Double, locale: Locale = .current) -> String {
        let f = NumberFormatter(); f.locale = locale; f.minimumFractionDigits = 2; f.maximumFractionDigits = 2
        return (f.string(from: meters as NSNumber) ?? String(format: "%.2f", meters)) + " m"
    }

    static func squareMeters(_ m2: Double, locale: Locale = .current) -> String {
        let f = NumberFormatter(); f.locale = locale; f.minimumFractionDigits = 1; f.maximumFractionDigits = 1
        return (f.string(from: m2 as NSNumber) ?? String(format: "%.1f", m2)) + " m²"
    }
}
