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
        readme(subject: ExportSubject(record: record, house: House(room: plan), packageURL: nil), files: files, locale: locale)
    }

    /// README.txt d'un sujet : une pièce donne ses mesures détaillées, une maison ses niveaux et pièces.
    static func readme(subject: ExportSubject, files: [(name: String, format: ExportFormat)], locale: Locale = .current) -> String {
        let df = DateFormatter(); df.locale = locale; df.dateStyle = .long; df.timeStyle = .short
        let scanned = String(localized: "readme.scannedOn \(df.string(from: subject.createdAt))")
        var body: [String] = [scanned]
        if subject.kind == .room, let plan = subject.house.allRooms.first {
            let m = RoomMeasurements(plan: plan)
            let r = m.ceilingHeight
            let ceiling = abs(r.upperBound - r.lowerBound) < 0.02 ? MeasurementFormat.meters(r.lowerBound, locale: locale)
                : "\(MeasurementFormat.meters(r.lowerBound, locale: locale)) – \(MeasurementFormat.meters(r.upperBound, locale: locale))"
            body.append(String(localized: "readme.area \(MeasurementFormat.squareMeters(m.floorArea, locale: locale)) \(MeasurementFormat.meters(m.perimeter, locale: locale)) \(ceiling)"))
            body.append(String(localized: "readme.counts \(plan.walls.count) \(m.doors.count) \(m.windows.count) \(plan.objects.count)"))
        } else {
            let hm = HouseMeasurements(house: subject.house)
            body.append(String(localized: "readme.house \(hm.roomCount) \(hm.storyCount) \(MeasurementFormat.squareMeters(hm.floorArea, locale: locale))"))
            for story in subject.house.stories {
                let names = story.rooms.map { "\($0.name) (\(MeasurementFormat.squareMeters(RoomMeasurements(plan: $0).floorArea, locale: locale)))" }.joined(separator: ", ")
                body.append("  \(StoryNaming.localizedName(for: story.index)) : \(names)")
            }
        }
        var s = "3D Scanner — \(subject.name)\n" + String(repeating: "=", count: 13 + subject.name.count) + "\n\n"
        s += body.joined(separator: "\n") + "\n\n" + String(localized: "readme.files") + "\n"
        for f in files {
            s += "  \(f.name)\n      \(String(localized: String.LocalizationValue(f.format.descriptionKey)))\n"
        }
        s += "\n\(String(localized: "readme.units"))\n\(String(localized: "readme.footer"))\n"
        return s
    }
}
