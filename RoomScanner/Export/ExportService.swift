import Foundation

/// Produit le fichier d'export d'une pièce dans un répertoire donné (par défaut
/// un dossier temporaire dédié) et renvoie son URL, prête pour `ShareLink`,
/// `fileExporter`, le glisser-déposer Mac ou la copie dans `Exports/`.
/// 2D et JSON sont générés ; USDZ copiés du paquet ; OBJ/STL/PLY construits depuis
/// le plan (`PlanMeshBuilder`) ou convertis du maillage du scan (`ModelIOConverter`).
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

    /// Source des maillages OBJ / STL / PLY.
    enum MeshSource: String, CaseIterable, Identifiable {
        /// Maillage paramétrique construit depuis le plan (`PlanMeshBuilder`) : propre, léger, identique iOS/Mac.
        case parametric
        /// Maillage brut du scan (`room-mesh.usdz`) converti par Model I/O : fidèle, lourd, iPhone seulement à la capture.
        case scan
        var id: String { rawValue }
        var titleKey: String { "export.meshSource.\(rawValue)" }
    }
    var meshSource: MeshSource = .parametric

    /// Formats proposés pour un paquet donné : les USDZ n'apparaissent que si le fichier existe
    /// (le maillage brut n'est produit que par un scan iPhone) ; le ZIP arrive en phase 9.
    static func availableFormats(packageURL: URL?) -> [ExportFormat] {
        var formats: [ExportFormat] = [.pdf, .png, .svg, .dxf]
        if let packageURL, RoomPackage.usdzURL(in: packageURL) != nil { formats.append(.usdzParametric) }
        if let packageURL, RoomPackage.usdzMeshURL(in: packageURL) != nil { formats.append(.usdzMesh) }
        formats += [.obj, .stl, .ply, .json, .zip]
        return formats
    }

    /// Le paquet contient-il le maillage brut du scan ?
    static func hasScanMesh(packageURL: URL?) -> Bool { packageURL.flatMap { RoomPackage.usdzMeshURL(in: $0) } != nil }

    /// Nom de fichier assaini (sans séparateurs ni caractères interdits).
    static func fileName(for record: RoomRecord, format: ExportFormat) -> String {
        folderName(for: record) + format.fileSuffix + "." + format.fileExtension
    }

    /// Nom du sous-dossier `Exports/<Pièce>/` (même assainissement).
    static func folderName(for record: RoomRecord) -> String {
        var base = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        base = String(base.unicodeScalars.map { forbidden.contains($0) ? "-" : Character($0) })
        return base.isEmpty ? "room" : base
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
        case .obj: return MeshWriters.obj(PlanMeshBuilder().build(house), name: title)
        case .stl: return MeshWriters.stl(PlanMeshBuilder().build(house), name: title)
        case .ply: return MeshWriters.ply(PlanMeshBuilder().build(house), name: title)
        default: throw ExportError.notAvailable(format)
        }
    }

    /// Dossier temporaire avec tous les exports (sauf le ZIP lui-même) + README.txt, puis compression.
    private func archive(_ house: House, record: RoomRecord, packageURL: URL?, to dest: URL) throws {
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("RoomScannerArchive-\(UUID().uuidString)", isDirectory: true)
        let folder = staging.appendingPathComponent(Self.folderName(for: record), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        var files: [(name: String, format: ExportFormat)] = []
        for format in Self.availableFormats(packageURL: packageURL) where format != .zip {
            let url = try export(house, record: record, format: format, packageURL: packageURL, to: folder)
            files.append((url.lastPathComponent, format))
        }
        if let plan = house.allRooms.first {
            try ArchiveExporter.readme(record: record, plan: plan, files: files, locale: locale).write(to: folder.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
        }
        try ArchiveExporter.zip(directory: folder, to: dest)
    }

    private func copyFromPackage(_ file: String, packageURL: URL?, to dest: URL) throws {
        guard let packageURL else { throw ExportError.missingSource(file) }
        let src = packageURL.appendingPathComponent(file)
        guard FileManager.default.fileExists(atPath: src.path) else { throw ExportError.missingSource(file) }
        try FileManager.default.copyItem(at: src, to: dest)
    }

    @discardableResult
    func export(_ house: House, record: RoomRecord, format: ExportFormat, packageURL: URL?, to directory: URL? = nil) throws -> URL {
        let dir = try directory ?? Self.scratchDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(Self.fileName(for: record, format: format))
        try? FileManager.default.removeItem(at: dest)
        switch format {
        case .usdzParametric: try copyFromPackage(FileLayout.PackageFile.usdz, packageURL: packageURL, to: dest)
        case .usdzMesh: try copyFromPackage(FileLayout.PackageFile.usdzMesh, packageURL: packageURL, to: dest)
        case .obj where meshSource == .scan, .stl where meshSource == .scan, .ply where meshSource == .scan:
            guard let packageURL, let src = RoomPackage.usdzMeshURL(in: packageURL) else { throw ExportError.missingSource(FileLayout.PackageFile.usdzMesh) }
            try ModelIOConverter.convert(src, to: dest)
        case .pdf, .png, .svg, .dxf, .json, .obj, .stl, .ply:
            try data(for: house, format: format, title: record.name).write(to: dest, options: .atomic)
        case .zip:
            try archive(house, record: record, packageURL: packageURL, to: dest)
        }
        return dest
    }
}
