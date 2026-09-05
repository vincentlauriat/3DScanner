import Foundation
import RealityKit
import simd
import CoreGraphics

#if canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
typealias PlatformColor = NSColor
#endif

/// Construit la scène RealityKit **paramétrique** d'une maison (D13) :
/// murs = boîtes découpées autour des ouvertures, panneaux de portes/fenêtres,
/// sol texturé avec le plan 2D, objets, cotes 3D optionnelles.
/// Repère : plan (x, y) → RealityKit (x, hauteur, −y), Y vers le haut, mètres.
@MainActor
struct PlanSceneBuilder {
    struct Options {
        var showObjects = true
        var showDimensions = false
        var showFloorTexture = true
        /// Murs aplatis (mode 2D) : hauteur graphique quand `flattenWalls` est vrai.
        var flattenWalls = false
        var flattenedHeight: Float = 0.02
        var floorTexturePixelsPerMeter = 120.0
        var locale: Locale = .current
    }

    enum Names {
        static let root = "house"
        static let roomPrefix = "room:"
        static let walls = "walls"
        static let floor = "floor"
        static let objects = "objects"
        static let dimensions = "dimensions"
        static let panels = "panels"
    }

    var options = Options()

    // MARK: - Scène

    /// Racine contenant une entité par pièce, chacune placée par `FloorPlan.transform`.
    func makeScene(for house: House) -> Entity {
        let root = Entity()
        root.name = Names.root
        for room in house.allRooms {
            let e = makeRoom(room)
            e.name = Names.roomPrefix + room.id.uuidString
            e.position = SIMD3(Float(room.transform.translation.x), 0, Float(-room.transform.translation.y))
            e.orientation = simd_quatf(angle: Float(room.transform.rotation), axis: SIMD3(0, 1, 0))
            root.addChild(e)
        }
        return root
    }

    func makeRoom(_ room: FloorPlan) -> Entity {
        let roomEntity = Entity()
        let walls = Entity(); walls.name = Names.walls
        let panels = Entity(); panels.name = Names.panels
        for wall in room.walls {
            let openings = room.openings.filter { $0.wallID == wall.id }
            for box in wallBoxes(wall, openings: openings) {
                walls.addChild(makeBox(box, material: wallMaterial))
            }
        }
        for o in room.openings { if let panel = panelBox(o, wall: room.wall(withID: o.wallID)) {
            panels.addChild(makeBox(panel, material: o.kind == .window ? glassMaterial : doorMaterial))
        } }
        roomEntity.addChild(walls)
        roomEntity.addChild(panels)
        if let floor = makeFloor(room) { roomEntity.addChild(floor) }
        if options.showObjects {
            let objects = Entity(); objects.name = Names.objects
            for o in room.objects { objects.addChild(makeObject(o)) }
            roomEntity.addChild(objects)
        }
        if options.showDimensions {
            let dims = Entity(); dims.name = Names.dimensions
            for wall in room.walls { dims.addChild(makeDimensionLabel(wall)) }
            roomEntity.addChild(dims)
        }
        return roomEntity
    }

    // MARK: - Géométrie des murs

    /// Boîte alignée sur un segment : `from`…`to` le long du mur (m), `bottom`…`top` (m).
    struct WallBox: Equatable {
        var segment: Segment2D
        var bottom: Double
        var top: Double
        var thickness: Double
        var height: Double { top - bottom }
    }

    /// Découpe un mur en boîtes pleines autour de ses ouvertures : portions
    /// pleines, linteaux au-dessus des portes, allèges sous les fenêtres.
    func wallBoxes(_ wall: Wall, openings: [Opening]) -> [WallBox] {
        let len = wall.length
        guard len > 0 else { return [] }
        let dir = wall.segment.direction
        let h = options.flattenWalls ? Double(options.flattenedHeight) : wall.height
        func seg(_ a: Double, _ b: Double) -> Segment2D { Segment2D(start: wall.start + dir * a, end: wall.start + dir * b) }
        var intervals: [(Double, Double, Opening)] = openings.map { o in
            let t = (o.center.x - wall.start.x) * dir.x + (o.center.y - wall.start.y) * dir.y
            return (max(0, t - o.width / 2), min(len, t + o.width / 2), o)
        }.filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
        var boxes: [WallBox] = []
        var cursor = 0.0
        while !intervals.isEmpty {
            let (a, b, o) = intervals.removeFirst()
            if a > cursor + 0.005 { boxes.append(WallBox(segment: seg(cursor, a), bottom: 0, top: h, thickness: wall.thickness)) }
            if !options.flattenWalls {
                let bottom = o.kind == .door ? 0 : o.sillHeight
                let top = min(bottom + o.height, h)
                if bottom > 0.01 { boxes.append(WallBox(segment: seg(a, b), bottom: 0, top: bottom, thickness: wall.thickness)) }
                if top < h - 0.01 { boxes.append(WallBox(segment: seg(a, b), bottom: top, top: h, thickness: wall.thickness)) }
            }
            cursor = max(cursor, b)
        }
        if cursor < len - 0.005 { boxes.append(WallBox(segment: seg(cursor, len), bottom: 0, top: h, thickness: wall.thickness)) }
        return boxes
    }

    /// Panneau de porte (bois) ou vitrage (verre) dans l'ouverture.
    func panelBox(_ o: Opening, wall: Wall?) -> WallBox? {
        guard !options.flattenWalls, o.width > 0.05, o.height > 0.05 else { return nil }
        let bottom = o.kind == .door ? 0 : o.sillHeight
        let thickness = (wall?.thickness ?? FloorPlan.defaultWallThickness) * 0.35
        return WallBox(segment: o.segment, bottom: bottom, top: bottom + o.height, thickness: thickness)
    }

    private func makeBox(_ box: WallBox, material: RealityKit.Material) -> ModelEntity {
        let mesh = MeshResource.generateBox(width: Float(box.segment.length), height: Float(box.height), depth: Float(box.thickness))
        let e = ModelEntity(mesh: mesh, materials: [material])
        let mid = box.segment.midpoint
        e.position = SIMD3(Float(mid.x), Float(box.bottom + box.height / 2), Float(-mid.y))
        // L'axe X local suit le segment ; l'angle du plan est mesuré dans le repère (x, y_plan) = (x, −z).
        e.orientation = simd_quatf(angle: Float(box.segment.angle), axis: SIMD3(0, 1, 0))
        return e
    }

    // MARK: - Sol, objets, cotes

    private func makeFloor(_ room: FloorPlan) -> ModelEntity? {
        let b = room.bounds
        guard !b.isEmpty else { return nil }
        let mesh = (try? Self.floorMesh(polygon: room.floorPolygon, bounds: b))
            ?? MeshResource.generatePlane(width: Float(b.width), depth: Float(b.height))
        var material: RealityKit.Material = UnlitMaterial(color: PlatformColor(white: 0.95, alpha: 1))
        if options.showFloorTexture {
            var r = PlanRenderer(); r.options.locale = options.locale; r.options.showObjects = false
            if let img = r.floorTextureImage(House(room: untransformed(room)), bounds: b, pixelsPerMeter: options.floorTexturePixelsPerMeter),
               let tex = try? TextureResource.generate(from: img, options: .init(semantic: .color)) {
                var m = UnlitMaterial(); m.color = .init(texture: .init(tex)); material = m
            }
        }
        let e = ModelEntity(mesh: mesh, materials: [material])
        e.name = Names.floor
        // Le maillage polygonal est déjà en coordonnées pièce ; le plan de repli est centré.
        e.position = room.floorPolygon.count >= 3 ? SIMD3(0, 0.001, 0) : SIMD3(Float(b.center.x), 0.001, Float(-b.center.y))
        return e
    }

    /// Maillage du sol suivant le contour de la pièce (triangulation par oreilles),
    /// UV normalisées sur `bounds` pour caler la texture rendue par `floorTextureImage`
    /// (u = x croissant, v = 0 en haut de l'image = y_plan max).
    static func floorMesh(polygon: [Point2D], bounds: Rect2D) throws -> MeshResource {
        guard polygon.count >= 3 else { throw NSError(domain: "PlanSceneBuilder", code: 1) }
        let tris = Polygon2D.triangulate(polygon)
        guard !tris.isEmpty else { throw NSError(domain: "PlanSceneBuilder", code: 2) }
        var desc = MeshDescriptor(name: "floor")
        desc.positions = MeshBuffers.Positions(polygon.map { SIMD3(Float($0.x), 0, Float(-$0.y)) })
        desc.normals = MeshBuffers.Normals(polygon.map { _ in SIMD3<Float>(0, 1, 0) })
        desc.textureCoordinates = MeshBuffers.TextureCoordinates(polygon.map {
            SIMD2(Float(($0.x - bounds.minX) / bounds.width), Float(($0.y - bounds.minY) / bounds.height))
        })
        // Face visible du dessus : ordre trigonométrique vu depuis +Y.
        var indices: [UInt32] = []
        for (a, b, c) in tris {
            let pa = polygon[a], pb = polygon[b], pc = polygon[c]
            let ccw = (pb.x - pa.x) * (pc.y - pa.y) - (pb.y - pa.y) * (pc.x - pa.x) >= 0
            indices += ccw ? [UInt32(a), UInt32(b), UInt32(c)] : [UInt32(a), UInt32(c), UInt32(b)]
        }
        desc.primitives = .triangles(indices)
        return try MeshResource.generate(from: [desc])
    }

    /// La pièce est dessinée dans son propre repère (l'entité porte le placement maison).
    private func untransformed(_ room: FloorPlan) -> FloorPlan { var r = room; r.transform = .identity; return r }

    private func makeObject(_ o: PlacedObject) -> Entity {
        let mesh = MeshResource.generateBox(width: Float(o.size.width), height: Float(o.height), depth: Float(o.size.depth), cornerRadius: 0.01)
        let e = ModelEntity(mesh: mesh, materials: [objectMaterial])
        e.name = "object:\(o.category)"
        e.position = SIMD3(Float(o.center.x), Float(o.height / 2), Float(-o.center.y))
        e.orientation = simd_quatf(angle: Float(o.angle), axis: SIMD3(0, 1, 0))
        let label = makeLabel(ObjectNaming.localizedName(o.category), size: 0.12)
        label.position = SIMD3(0, Float(o.height / 2) + 0.12, 0)
        e.addChild(label)
        return e
    }

    private func makeDimensionLabel(_ wall: Wall) -> Entity {
        let text = MeasurementFormat.centimeters(wall.length, locale: options.locale)
        let label = makeLabel(text, size: 0.16, color: PlatformColor(red: 0.07, green: 0.42, blue: 0.86, alpha: 1))
        let mid = wall.segment.midpoint
        label.position = SIMD3(Float(mid.x), Float((options.flattenWalls ? 0.02 : wall.height) + 0.15), Float(-mid.y))
        return label
    }

    /// Texte 3D centré, extrudé très finement.
    func makeLabel(_ text: String, size: Float, color: PlatformColor = PlatformColor(white: 0.25, alpha: 1)) -> ModelEntity {
        let mesh = MeshResource.generateText(text, extrusionDepth: 0.002, font: .systemFont(ofSize: CGFloat(size)),
                                             containerFrame: .zero, alignment: .center, lineBreakMode: .byClipping)
        let e = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: color)])
        // generateText ancre le texte en bas à gauche : on le recentre.
        let bounds = mesh.bounds
        e.position = SIMD3(-bounds.center.x, 0, 0)
        let holder = ModelEntity()
        holder.addChild(e)
        holder.components.set(BillboardComponent())
        return holder
    }

    // MARK: - Matériaux

    private var wallMaterial: RealityKit.Material { SimpleMaterial(color: PlatformColor(white: 0.93, alpha: 1), roughness: 0.8, isMetallic: false) }
    private var doorMaterial: RealityKit.Material { SimpleMaterial(color: PlatformColor(red: 0.62, green: 0.45, blue: 0.30, alpha: 1), roughness: 0.6, isMetallic: false) }
    private var glassMaterial: RealityKit.Material { SimpleMaterial(color: PlatformColor(red: 0.45, green: 0.72, blue: 1.0, alpha: 0.35), roughness: 0.1, isMetallic: false) }
    private var objectMaterial: RealityKit.Material { SimpleMaterial(color: PlatformColor(white: 0.55, alpha: 0.55), roughness: 0.7, isMetallic: false) }
}
