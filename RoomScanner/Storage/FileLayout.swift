import Foundation

/// Noms de fichiers et de dossiers du stockage — un seul endroit pour les changer.
enum FileLayout {
    static let roomsFolder = "Rooms"
    static let exportsFolder = "Exports"
    static let packageExtension = "roomscan"

    /// Fichiers d'un paquet `.roomscan`.
    enum PackageFile {
        static let capturedRoom = "room.json"   // CapturedRoom Apple (iOS seulement)
        static let scan = "scan.json"           // ScanInput neutre
        static let plan = "plan.json"           // FloorPlan
        static let meta = "meta.json"           // RoomRecord
        static let usdz = "room.usdz"
        static let usdzMesh = "room-mesh.usdz" // maillage brut du scan (iOS, optionnel)
        static let thumbnail = "thumbnail.png"
    }
}
