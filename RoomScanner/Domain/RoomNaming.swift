import Foundation

/// Nom proposé pour une pièce d'après son étiquette RoomPlan, dédoublonné
/// (« Chambre », « Chambre 2 », …). Le rendu localisé est injecté pour rester
/// testable indépendamment de la langue du système.
struct RoomNaming {
    var localizedBaseName: (RoomLabel) -> String = RoomNaming.defaultBaseName

    func proposedName(for label: RoomLabel, existingNames: [String]) -> String {
        let base = localizedBaseName(label)
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
