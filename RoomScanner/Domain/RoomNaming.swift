import Foundation

/// Nom proposé pour une pièce d'après son étiquette RoomPlan, dédoublonné
/// (« Chambre », « Chambre 2 », …). Le rendu localisé est injecté pour rester
/// testable indépendamment de la langue du système.
struct RoomNaming {
    var localizedBaseName: (RoomLabel) -> String = RoomNaming.defaultBaseName

    func proposedName(for label: RoomLabel, existingNames: [String]) -> String {
        deduplicated(localizedBaseName(label), existingNames)
    }

    /// Nom d'après **toutes** les sections RoomPlan de la capture : une pièce peut en porter
    /// plusieurs (une salle à manger ouverte sur une cuisine ⇒ « Salle à manger / Cuisine »).
    /// `.unidentified` est écarté dès qu'une autre section existe, les doublons sont supprimés,
    /// et une capture sans section identifiée retombe sur le nom générique dédoublonné.
    func proposedName(for labels: [RoomLabel], existingNames: [String]) -> String {
        var kept: [RoomLabel] = []
        for label in labels where label != .unidentified && !kept.contains(label) { kept.append(label) }
        guard !kept.isEmpty else { return proposedName(for: .unidentified, existingNames: existingNames) }
        return deduplicated(kept.map(localizedBaseName).joined(separator: " / "), existingNames)
    }

    private func deduplicated(_ base: String, _ existingNames: [String]) -> String {
        guard existingNames.contains(base) else { return base }
        var n = 2
        while existingNames.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    static func defaultBaseName(_ label: RoomLabel) -> String {
        String(localized: String.LocalizationValue(label.localizationKey), bundle: .main)
    }
}

extension RoomLabel {
    var localizationKey: String {
        switch self {
        case .livingRoom: "room.label.livingRoom"
        case .bedroom: "room.label.bedroom"
        case .bathroom: "room.label.bathroom"
        case .kitchen: "room.label.kitchen"
        case .diningRoom: "room.label.diningRoom"
        case .unidentified: "room.label.unidentified"
        }
    }
}

/// Libellés localisés des catégories d'objets RoomPlan (`table`, `sofa`, …) ;
/// repli sur la catégorie brute capitalisée si aucune traduction n'existe.
enum ObjectNaming {
    static func localizedName(_ category: String) -> String {
        let key = "object.\(category)"
        let s = String(localized: String.LocalizationValue(key), bundle: .main)
        return s == key ? category.capitalized : s
    }
}
