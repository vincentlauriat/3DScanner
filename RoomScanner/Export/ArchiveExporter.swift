import Foundation

/// ZIP « tout » : chaque export disponible + `README.txt`, sans dépendance —
/// `NSFileCoordinator` avec `.forUploading` produit une archive ZIP d'un dossier
/// sur iOS comme sur macOS.
enum ArchiveExporter {
    enum ArchiveError: LocalizedError {
        case coordination(Error), noArchive
        var errorDescription: String? {
            switch self {
            case .coordination(let e): e.localizedDescription
            case .noArchive: "Archive ZIP non produite."
            }
        }
    }

    /// Compresse `directory` dans `destination` (écrasée).
    static func zip(directory: URL, to destination: URL) throws {
        var coordinationError: NSError?
        var copyError: Error?
        var produced = false
        NSFileCoordinator().coordinate(readingItemAt: directory, options: .forUploading, error: &coordinationError) { zipURL in
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: zipURL, to: destination)
                produced = true
            } catch { copyError = error }
        }
        if let coordinationError { throw ArchiveError.coordination(coordinationError) }
        if let copyError { throw ArchiveError.coordination(copyError) }
        guard produced else { throw ArchiveError.noArchive }
    }

    /// README.txt de l'archive : pièce, mesures, liste des fichiers et leur usage.
    static func readme(record: RoomRecord, plan: FloorPlan, files: [(name: String, format: ExportFormat)], locale: Locale = .current) -> String {
        let m = RoomMeasurements(plan: plan)
        let df = DateFormatter(); df.locale = locale; df.dateStyle = .long; df.timeStyle = .short
        let scanned = String(localized: "readme.scannedOn \(df.string(from: record.createdAt))")
        let r = m.ceilingHeight
        let ceiling = abs(r.upperBound - r.lowerBound) < 0.02 ? MeasurementFormat.meters(r.lowerBound, locale: locale)
            : "\(MeasurementFormat.meters(r.lowerBound, locale: locale)) – \(MeasurementFormat.meters(r.upperBound, locale: locale))"
        let area = String(localized: "readme.area \(MeasurementFormat.squareMeters(m.floorArea, locale: locale)) \(MeasurementFormat.meters(m.perimeter, locale: locale)) \(ceiling)")
        let counts = String(localized: "readme.counts \(plan.walls.count) \(m.doors.count) \(m.windows.count) \(plan.objects.count)")
        var s = "3D Scanner — \(record.name)\n" + String(repeating: "=", count: 13 + record.name.count) + "\n\n"
        s += scanned + "\n" + area + "\n" + counts + "\n\n" + String(localized: "readme.files") + "\n"
        for f in files {
            s += "  \(f.name)\n      \(String(localized: String.LocalizationValue(f.format.descriptionKey)))\n"
        }
        s += "\n\(String(localized: "readme.units"))\n\(String(localized: "readme.footer"))\n"
        return s
    }
}
