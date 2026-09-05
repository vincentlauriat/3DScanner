import Foundation

/// Ce que l'utilisateur scanne : une pièce (v1) ou une maison, pièce après pièce (v2).
enum ScanMode: String, Identifiable, Hashable {
    case room, house
    var id: String { rawValue }
}
