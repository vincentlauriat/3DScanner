import Foundation

/// Racine de stockage : conteneur iCloud (phase 7) ou dossier local. Les
/// chemins `Rooms/` et `Exports/` en découlent.
struct StorageLocation: Equatable {
    enum Kind: Equatable { case local, iCloud }

    let kind: Kind
    /// Dossier contenant `Rooms/` et `Exports/` (= `Documents/` du conteneur iCloud).
    let documentsURL: URL

    var roomsURL: URL { documentsURL.appendingPathComponent(FileLayout.roomsFolder, isDirectory: true) }
    var exportsURL: URL { documentsURL.appendingPathComponent(FileLayout.exportsFolder, isDirectory: true) }
    var housesURL: URL { documentsURL.appendingPathComponent(FileLayout.housesFolder, isDirectory: true) }

    func packageURL(for id: UUID) -> URL {
        roomsURL.appendingPathComponent(id.uuidString).appendingPathExtension(FileLayout.packageExtension)
    }

    func housePackageURL(for id: UUID) -> URL {
        housesURL.appendingPathComponent(id.uuidString).appendingPathExtension(FileLayout.housePackageExtension)
    }

    /// Crée `Rooms/` et `Exports/` si besoin.
    func prepare() throws {
        for url in [roomsURL, exportsURL, housesURL] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    /// Dossier Documents de l'app (iOS : visible dans Fichiers ; macOS : conteneur sandbox).
    static func local(fileManager: FileManager = .default) -> StorageLocation {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return StorageLocation(kind: .local, documentsURL: docs)
    }

    /// Racine jetable pour les tests.
    static func temporary() -> StorageLocation {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RoomScanner-\(UUID().uuidString)", isDirectory: true)
        return StorageLocation(kind: .local, documentsURL: url)
    }
}
