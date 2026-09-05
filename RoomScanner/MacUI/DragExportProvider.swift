import AppKit
import UniformTypeIdentifiers

/// Glisser-déposer vers d'autres apps : le fichier est généré à la demande quand
/// la destination le réclame (`registerFileRepresentation`), jamais avant.
enum DragExportProvider {
    /// Fournisseur d'un export généré à la volée (PDF vers Aperçu, DXF vers LibreCAD…).
    static func provider(subject: ExportSubject, format: ExportFormat) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = ExportService.fileName(for: subject, format: format)
        provider.registerFileRepresentation(forTypeIdentifier: format.utType.identifier, fileOptions: [], visibility: .all) { completion in
            do {
                let url = try ExportService().export(subject, format: format)
                completion(url, false, nil)
            } catch {
                completion(nil, false, error)
            }
            return nil
        }
        return provider
    }

    /// Fournisseur du paquet `.roomscan` / `.housescan` lui-même (copie vers le Finder, AirDrop, Mail).
    static func packageProvider(url: URL) -> NSItemProvider {
        let provider = NSItemProvider(contentsOf: url) ?? NSItemProvider()
        provider.suggestedName = url.lastPathComponent
        return provider
    }
}
