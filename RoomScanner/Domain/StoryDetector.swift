import Foundation

/// Regroupe des pièces en niveaux d'après la hauteur de leur sol (D27) : les hauteurs
/// à moins de `tolerance` l'une de l'autre forment un même niveau ; le plus bas est 0.
/// Les niveaux restent éditables ensuite — ceci n'est qu'une proposition.
struct StoryDetector {
    var tolerance: Double = 0.5

    /// Index de niveau par identifiant de pièce.
    func stories(floorHeights: [UUID: Double]) -> [UUID: Int] {
        let sorted = floorHeights.sorted { $0.value < $1.value }
        var result: [UUID: Int] = [:]
        var currentIndex = -1
        var clusterStart = -Double.infinity
        for (id, h) in sorted {
            if h - clusterStart > tolerance { currentIndex += 1; clusterStart = h }
            result[id] = currentIndex
        }
        return result
    }

    /// Hauteur du sol d'un scan (m, repère RoomPlan) : premier sol connu, sinon bas des murs.
    static func floorHeight(of scan: ScanInput) -> Double {
        if let f = scan.floors.first { return Double(f.transform.translation.y) }
        let bottoms = scan.walls.map { Double($0.transform.translation.y) - Double($0.dimensions.y) / 2 }
        return bottoms.min() ?? 0
    }
}

/// Noms de niveaux (« Rez-de-chaussée », « Étage 1 »…), clés localisées.
enum StoryNaming {
    static func localizationKey(for index: Int) -> String { index == 0 ? "story.ground" : "story.upper %lld" }
    static func localizedName(for index: Int) -> String {
        index == 0 ? String(localized: "story.ground") : String(localized: "story.upper \(index)")
    }
}
