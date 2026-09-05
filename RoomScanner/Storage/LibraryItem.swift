import Foundation

/// Élément de la bibliothèque : une pièce ou une maison (sélection Mac, navigation iOS).
enum LibraryItem: Hashable, Identifiable {
    case room(RoomRecord)
    case house(HouseRecord)

    var id: UUID {
        switch self { case .room(let r): r.id; case .house(let h): h.id }
    }
    var name: String {
        switch self { case .room(let r): r.name; case .house(let h): h.name }
    }
}
