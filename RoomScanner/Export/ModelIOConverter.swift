import Foundation
import ModelIO

/// Convertit un fichier 3D lisible par Model I/O (USDZ/USD du scan) vers OBJ, STL ou
/// PLY. Model I/O importe l'USDZ et exporte ces trois formats sur iOS et macOS,
/// mais ne sait **pas** écrire d'USDZ (vérifié). À appeler hors du main thread.
enum ModelIOConverter {
    enum ConversionError: LocalizedError {
        case unsupported(String), emptyAsset
        var errorDescription: String? {
            switch self {
            case .unsupported(let ext): "Model I/O ne peut pas écrire « .\(ext) »."
            case .emptyAsset: "Le fichier 3D source ne contient aucun maillage."
            }
        }
    }

    static func canExport(_ format: ExportFormat) -> Bool { MDLAsset.canExportFileExtension(format.fileExtension) }

    static func convert(_ source: URL, to destination: URL) throws {
        let ext = destination.pathExtension
        guard MDLAsset.canExportFileExtension(ext) else { throw ConversionError.unsupported(ext) }
        let asset = MDLAsset(url: source)
        guard asset.count > 0 else { throw ConversionError.emptyAsset }
        try? FileManager.default.removeItem(at: destination)
        try asset.export(to: destination)
    }
}
