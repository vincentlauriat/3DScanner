import Foundation

/// Assemble une `House` à partir d'un `StructureInput` : chaque pièce passe par
/// `FloorPlanBuilder` (coordonnées monde partagées ⇒ `transform = .identity`), les
/// niveaux sont déduits de la hauteur des sols, les pièces sont nommées et
/// dédoublonnées comme en v1. Aucune dépendance RoomPlan (v2, D26).
struct HouseBuilder {
    /// Repère monde partagé : pas d'alignement par pièce (la maison sera alignée globalement en v2).
    var planBuilder: FloorPlanBuilder = { var b = FloorPlanBuilder(); b.alignToLongestWall = false; return b }()
    var storyDetector = StoryDetector()
    var naming = RoomNaming()

    func build(from structure: StructureInput, name: String) -> House {
        let heights = Dictionary(uniqueKeysWithValues: structure.rooms.map { ($0.id, StoryDetector.floorHeight(of: $0)) })
        let storyOf = storyDetector.stories(floorHeights: heights)
        var names: [String] = []
        var plans: [FloorPlan] = []
        for scan in structure.rooms {
            let proposed = naming.proposedName(for: scan.sectionLabels.first ?? .unidentified, existingNames: names)
            names.append(proposed)
            var plan = planBuilder.build(from: scan, name: proposed)
            plan.story = storyOf[scan.id] ?? scan.story
            plan.transform = .identity
            plans.append(plan)
        }
        let indices = Set(plans.map(\.story)).sorted()
        let stories = indices.map { i in Story(index: i, rooms: plans.filter { $0.story == i }) }
        return House(id: structure.id, name: name, stories: stories)
    }
}
