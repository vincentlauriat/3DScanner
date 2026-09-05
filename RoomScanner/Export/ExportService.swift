import Foundation

/// Produit le fichier d'export d'une pièce dans un répertoire donné (par défaut
/// un dossier temporaire dédié) et renvoie son URL, prête pour `ShareLink`,
/// `fileExporter`, le glisser-déposer Mac ou la copie dans `Exports/`.
struct ExportService {
    var locale: Locale = .current
    var pageSize = CGSize(width: 842, height: 595)  // A4 paysage, points
    var pngPixelScale: CGFloat = 3

    enum ExportError: LocalizedError {
        case notAvailable(ExportFormat)
        case missingSource(String)
        var errorDescription: String? {
            switch self {
            case .notAvailable(let f): String(localized: "export.error.notAvailable \(String(localized: String.LocalizationValue(f.titleKey)))")
            case .missingSource(let n): String(localized: "export.error.missingSource \(n)")
            }
        }
    }

    /// Formats disponibles à ce stade (les 3D convertis et le ZIP arrivent en phases 6 et 9).
    static var availableFormats: [ExportFormat] { [.pdf, .png, .svg, .dxf, .usdzParametric, .json] }

    static func fileName(for record: RoomRecord, format: ExportFormat) -> String {
        var base = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        base = String(base.unicodeScalars.map { forbidden.contains($0) ? "-" : Character($0) })
        if base.isEmpty { base = "room" }
        return base + format.fileSuffix + "." + format.fileExtension
    }

    /// Répertoire temporaire propre au processus, vidé à chaque appel pour ne pas accumuler.
    static func scratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RoomScannerExports", isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Contenu d'un export **généré** (2D + JSON). Les formats copiés depuis le paquet
    /// (USDZ) passent par `export(_:record:format:packageURL:to:)`.
    func data(for house: House, format: ExportFormat, title: String) throws -> Data {
        var renderer = PlanRenderer()
        renderer.options.locale = locale
        switch format {
        case .pdf: return renderer.pdfData(house, size: pageSize, title: title)
        case .png:
            guard let d = renderer.pngData(house, pageSize: pageSize, pixelScale: pngPixelScale) else { throw ExportError.missingSource("png") }
            return d
        case .svg: return SVGExporter(locale: locale).data(for: house)
        case .dxf: return DXFExporter(locale: locale).data(for: house)
        case .json:
            guard let room = house.allRooms.first else { throw ExportError.missingSource(FileLayout.PackageFile.plan) }
            return try RoomPackage.encoder.encode(room)
        default: throw ExportError.notAvailable(format)
        }
    }

    @discardableResult
    func export(_ house: House, record: RoomRecord, format: ExportFormat, packageURL: URL?, to directory: URL? = nil) throws -> URL {
        let dir = try directory ?? Self.scratchDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(Self.fileName(for: record, format: format))
        try? FileManager.default.removeItem(at: dest)
        switch format {
        case .usdzParametric:
            guard let packageURL else { throw ExportError.missingSource(FileLayout.PackageFile.usdz) }
            let src = packageURL.appendingPathComponent(FileLayout.PackageFile.usdz)
            guard FileManager.default.fileExists(atPath: src.path) else { throw ExportError.missingSource(FileLayout.PackageFile.usdz) }
            try FileManager.default.copyItem(at: src, to: dest)
        case .pdf, .png, .svg, .dxf, .json:
            try data(for: house, format: format, title: record.name).write(to: dest, options: .atomic)
        default:
            throw ExportError.notAvailable(format)
        }
        return dest
    }
}
