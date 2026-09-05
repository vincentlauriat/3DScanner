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
        availableFormats(usdzURL: packageURL.flatMap { RoomPackage.usdzURL(in: $0) }, usdzMeshURL: packageURL.flatMap { RoomPackage.usdzMeshURL(in: $0) })
    }

    static func availableFormats(for subject: ExportSubject) -> [ExportFormat] {
        availableFormats(usdzURL: subject.usdzURL, usdzMeshURL: subject.usdzMeshURL)
    }

    static func availableFormats(usdzURL: URL?, usdzMeshURL: URL?) -> [ExportFormat] {
        var formats: [ExportFormat] = [.pdf, .png, .svg, .dxf]
        if usdzURL != nil { formats.append(.usdzParametric) }
        if usdzMeshURL != nil { formats.append(.usdzMesh) }
        formats += [.obj, .stl, .ply, .json, .zip]
        return formats
    }

    /// Le paquet contient-il le maillage brut du scan ?
    static func hasScanMesh(packageURL: URL?) -> Bool { packageURL.flatMap { RoomPackage.usdzMeshURL(in: $0) } != nil }

    /// Nom de fichier assaini (sans séparateurs ni caractères interdits).
    static func fileName(for record: RoomRecord, format: ExportFormat) -> String {
        folderName(for: record) + format.fileSuffix + "." + format.fileExtension
    }

    static func fileName(for subject: ExportSubject, format: ExportFormat) -> String {
        folderName(for: subject) + format.fileSuffix + "." + format.fileExtension
    }

    /// Nom du sous-dossier `Exports/<Pièce>/` (même assainissement). Un nom réduit à des points
    /// (`.`, `..`) ou vide devient `room` : il remonterait sinon dans l'arborescence.
    static func folderName(for record: RoomRecord) -> String { folderName(record.name, fallback: "room") }

    static func folderName(for subject: ExportSubject) -> String {
        folderName(subject.name, fallback: subject.kind == .house ? "house" : "room")
    }

    static func folderName(_ name: String, fallback: String) -> String {
        var base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        base = String(base.unicodeScalars.map { forbidden.contains($0) ? "-" : Character($0) })
        if base.isEmpty || base.allSatisfy({ $0 == "." }) { return fallback }
        return base
    }

    static let scratchRoot = FileManager.default.temporaryDirectory.appendingPathComponent("RoomScannerExports", isDirectory: true)

    /// Sous-dossier temporaire **unique** par export : plusieurs exports peuvent être en cours
    /// (feuille d'export, glisser-déposer) sans s'effacer mutuellement. Les sous-dossiers de
    /// plus d'une heure sont purgés au passage.
    static func scratchDirectory() throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: scratchRoot, withIntermediateDirectories: true)
        let cutoff = Date().addingTimeInterval(-3600)
        for old in (try? fm.contentsOfDirectory(at: scratchRoot, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            if let d = (try? old.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, d < cutoff { try? fm.removeItem(at: old) }
        }
        let url = scratchRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
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
            // Une pièce seule reste un `FloorPlan` (compatibilité v1) ; une maison est encodée entière.
            if house.stories.count == 1, house.stories[0].rooms.count == 1 { return try RoomPackage.encoder.encode(house.stories[0].rooms[0]) }
            return try RoomPackage.encoder.encode(house)
        case .obj: return MeshWriters.obj(PlanMeshBuilder().build(house), name: title)
        case .stl: return MeshWriters.stl(PlanMeshBuilder().build(house), name: title)
        case .ply: return MeshWriters.ply(PlanMeshBuilder().build(house), name: title)
        default: throw ExportError.notAvailable(format)
        }
    }

    /// Dossier temporaire avec tous les exports (sauf le ZIP lui-même) + README.txt, puis compression.
    private func archive(_ subject: ExportSubject, to dest: URL) throws {
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("RoomScannerArchive-\(UUID().uuidString)", isDirectory: true)
        let folder = staging.appendingPathComponent(Self.folderName(for: subject), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        var files: [(name: String, format: ExportFormat)] = []
        for format in Self.availableFormats(for: subject) where format != .zip {
            let url = try export(subject, format: format, to: folder)
            files.append((url.lastPathComponent, format))
        }
        try ArchiveExporter.readme(subject: subject, files: files, locale: locale).write(to: folder.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
        try ArchiveExporter.zip(directory: folder, to: dest)
    }

    private func copy(_ src: URL?, missing: String, to dest: URL) throws {
        guard let src, FileManager.default.fileExists(atPath: src.path) else { throw ExportError.missingSource(missing) }
        try FileManager.default.copyItem(at: src, to: dest)
    }

    /// Export d'une pièce (`RoomRecord` + paquet `.roomscan`), forme v1 conservée.
    @discardableResult
    func export(_ house: House, record: RoomRecord, format: ExportFormat, packageURL: URL?, to directory: URL? = nil) throws -> URL {
        try export(ExportSubject(record: record, house: house, packageURL: packageURL), format: format, to: directory)
    }

    /// Export d'un sujet (pièce ou maison) dans `directory` (sinon un dossier temporaire unique).
    @discardableResult
    func export(_ subject: ExportSubject, format: ExportFormat, to directory: URL? = nil) throws -> URL {
        let dir = try directory ?? Self.scratchDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(Self.fileName(for: subject, format: format))
        try? FileManager.default.removeItem(at: dest)
        switch format {
        case .usdzParametric: try copy(subject.usdzURL, missing: FileLayout.PackageFile.usdz, to: dest)
        case .usdzMesh: try copy(subject.usdzMeshURL, missing: FileLayout.PackageFile.usdzMesh, to: dest)
        case .obj where meshSource == .scan, .stl where meshSource == .scan, .ply where meshSource == .scan:
            guard let src = subject.usdzMeshURL else { throw ExportError.missingSource(FileLayout.PackageFile.usdzMesh) }
            try ModelIOConverter.convert(src, to: dest)
        case .pdf, .png, .svg, .dxf, .json, .obj, .stl, .ply:
            try data(for: subject.house, format: format, title: subject.name).write(to: dest, options: .atomic)
        case .zip:
            try archive(subject, to: dest)
        }
        return dest
    }
}
