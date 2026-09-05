import Foundation

/// Résolution du conteneur iCloud Drive et migration local → iCloud (D16, D17).
/// `url(forUbiquityContainerIdentifier:)` peut bloquer : toujours hors du main thread.
enum CloudAvailability {
    static let containerIdentifier = "iCloud.fr.vincentlauriat.roomscanner"
    /// Préférence utilisateur (réglages) ; `true` par défaut.
    static let preferenceKey = "RoomScannerUseICloud"

    static var isEnabledByUser: Bool {
        UserDefaults.standard.object(forKey: preferenceKey) == nil ? true : UserDefaults.standard.bool(forKey: preferenceKey)
    }

    /// Un compte iCloud est-il connecté sur l'appareil ?
    static var isSignedIn: Bool { FileManager.default.ubiquityIdentityToken != nil }

    /// `Documents/` du conteneur (le dossier public « 3D Scanner » de Fichiers / Finder).
    static func documentsURL(containerURL: URL) -> URL {
        containerURL.appendingPathComponent("Documents", isDirectory: true)
    }

    /// Emplacement iCloud, ou `nil` si pas de compte, conteneur absent ou désactivé par l'utilisateur.
    /// À appeler depuis une tâche détachée.
    nonisolated static func resolveLocation() -> StorageLocation? {
        guard isEnabledByUser, isSignedIn,
              let container = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) else { return nil }
        return StorageLocation(kind: .iCloud, documentsURL: documentsURL(containerURL: container))
    }

    /// Déplace dans iCloud les paquets et exports locaux qui n'y sont pas encore
    /// (`setUbiquitous`). Un paquet déjà présent côté iCloud est laissé en place :
    /// la copie locale est conservée, jamais écrasée. Renvoie le nombre d'éléments déplacés.
    @discardableResult
    nonisolated static func migrate(from local: StorageLocation, to cloud: StorageLocation, fileManager fm: FileManager = .default) throws -> Int {
        guard local.kind == .local, cloud.kind == .iCloud, local.documentsURL != cloud.documentsURL else { return 0 }
        try cloud.prepare()
        var moved = 0
        for (src, dst) in [(local.roomsURL, cloud.roomsURL), (local.exportsURL, cloud.exportsURL)] {
            guard fm.fileExists(atPath: src.path) else { continue }
            for item in try fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
                let target = dst.appendingPathComponent(item.lastPathComponent)
                guard !fm.fileExists(atPath: target.path) else { continue }
                try fm.setUbiquitous(true, itemAt: item, destinationURL: target)
                moved += 1
            }
        }
        return moved
    }
}
