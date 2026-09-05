import Foundation

/// Conflits iCloud sur un paquet `.roomscan` (édition simultanée iPhone / Mac) :
/// **la version la plus récente gagne**, l'autre est conservée comme pièce
/// « (conflit) » avec un nouvel identifiant — un scan n'est jamais perdu (D17).
enum ConflictResolver {
    struct Version { var date: Date; var isCurrent: Bool }

    /// Index de la version gagnante (la plus récente ; à égalité, la version courante).
    static func winnerIndex(_ versions: [Version]) -> Int? {
        guard !versions.isEmpty else { return nil }
        return versions.indices.max { a, b in
            let (va, vb) = (versions[a], versions[b])
            if va.date != vb.date { return va.date < vb.date }
            return !va.isCurrent && vb.isCurrent
        }
    }

    /// Copie un paquet sous un nouvel identifiant, nom suffixé, dans le même dossier `Rooms/`.
    @discardableResult
    static func duplicateAsConflictCopy(packageAt url: URL, suffix: String, fileManager fm: FileManager = .default) throws -> RoomRecord {
        let record = try RoomPackage.readRecord(from: url)
        let plan = try RoomPackage.readPlan(from: url)
        var copyRecord = record; var copyPlan = plan
        let newID = UUID()
        copyRecord.id = newID; copyPlan.id = newID
        copyRecord.name = "\(record.name) \(suffix)"; copyPlan.name = copyRecord.name
        let dest = url.deletingLastPathComponent().appendingPathComponent(newID.uuidString).appendingPathExtension(FileLayout.packageExtension)
        try fm.copyItem(at: url, to: dest)
        try RoomPackage.update(record: copyRecord, plan: copyPlan, in: dest)
        return copyRecord
    }

    /// Résout les versions en conflit d'un paquet. Renvoie la copie « conflit » créée, s'il y en a une.
    @discardableResult
    static func resolve(packageAt url: URL, suffix: String) throws -> RoomRecord? {
        guard let others = NSFileVersion.unresolvedConflictVersionsOfItem(at: url), !others.isEmpty else { return nil }
        let current = NSFileVersion.currentVersionOfItem(at: url)
        var versions = [Version(date: current?.modificationDate ?? .distantPast, isCurrent: true)]
        versions += others.map { Version(date: $0.modificationDate ?? .distantPast, isCurrent: false) }
        var copy: RoomRecord?
        if let w = winnerIndex(versions), w > 0 {
            // Une version distante plus récente gagne : on garde l'actuelle en copie, puis on la remplace.
            copy = try duplicateAsConflictCopy(packageAt: url, suffix: suffix)
            try others[w - 1].replaceItem(at: url)
        } else {
            // La version courante gagne : la plus récente des autres est conservée en copie.
            if let newest = others.max(by: { ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast) }) {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("conflict-\(UUID().uuidString).roomscan")
                try newest.replaceItem(at: tmp)
                var rec = try RoomPackage.readRecord(from: tmp); var plan = try RoomPackage.readPlan(from: tmp)
                let newID = UUID(); rec.id = newID; plan.id = newID; rec.name = "\(rec.name) \(suffix)"; plan.name = rec.name
                let dest = url.deletingLastPathComponent().appendingPathComponent(newID.uuidString).appendingPathExtension(FileLayout.packageExtension)
                try FileManager.default.moveItem(at: tmp, to: dest)
                try RoomPackage.update(record: rec, plan: plan, in: dest)
                copy = rec
            }
        }
        for v in others { v.isResolved = true }
        try NSFileVersion.removeOtherVersionsOfItem(at: url)
        return copy
    }
}
