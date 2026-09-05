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

    /// Copie un paquet sous un nouvel identifiant, nom suffixé, dans `directory` (par défaut le
    /// dossier du paquet). Renvoie la fiche de la copie ; son URL est `directory/<id>.roomscan`.
    @discardableResult
    static func duplicateAsConflictCopy(packageAt url: URL, suffix: String, into directory: URL? = nil, fileManager fm: FileManager = .default) throws -> RoomRecord {
        let record = try RoomPackage.readRecord(from: url)
        let plan = try RoomPackage.readPlan(from: url)
        var copyRecord = record; var copyPlan = plan
        let newID = UUID()
        copyRecord.id = newID; copyPlan.id = newID
        copyRecord.name = "\(record.name) \(suffix)"; copyPlan.name = copyRecord.name
        let dir = directory ?? url.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(newID.uuidString).appendingPathExtension(FileLayout.packageExtension)
        // Lecture de la source et écriture de la cible coordonnées : iCloud peut être en train
        // de matérialiser la source, et la cible doit apparaître complète d'un coup.
        var coordError: NSError?; var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], writingItemAt: dest, options: .forReplacing, error: &coordError) { src, dst in
            do { try fm.copyItem(at: src, to: dst) } catch { copyError = error }
        }
        if let coordError { throw coordError }
        if let copyError { throw copyError }
        try RoomPackage.update(record: copyRecord, plan: copyPlan, in: dest)
        return copyRecord
    }

    /// Résout les versions en conflit d'un paquet : la gagnante devient la version courante,
    /// **chaque** version perdante est conservée comme pièce « (conflit) » (trois appareils
    /// peuvent produire plusieurs versions). Renvoie les copies créées.
    @discardableResult
    static func resolve(packageAt url: URL, suffix: String) throws -> [RoomRecord] {
        guard let others = NSFileVersion.unresolvedConflictVersionsOfItem(at: url), !others.isEmpty else { return [] }
        let current = NSFileVersion.currentVersionOfItem(at: url)
        var versions = [Version(date: current?.modificationDate ?? .distantPast, isCurrent: true)]
        versions += others.map { Version(date: $0.modificationDate ?? .distantPast, isCurrent: false) }
        let winner = winnerIndex(versions) ?? 0
        var copies: [RoomRecord] = []
        // 1. Les versions distantes perdantes → copies « (conflit) ».
        for (i, v) in others.enumerated() where i + 1 != winner {
            copies.append(try keepAsConflictCopy(version: v, of: url, suffix: suffix))
        }
        // 2. Si une version distante gagne : l'actuelle devient une copie, puis est remplacée.
        if winner > 0 {
            copies.append(try duplicateAsConflictCopy(packageAt: url, suffix: suffix))
            let winning = others[winner - 1]
            try RoomPackage.coordinatedWrite(at: url, options: .forReplacing) { target in _ = try winning.replaceItem(at: target) }
        }
        for v in others { v.isResolved = true }
        try NSFileVersion.removeOtherVersionsOfItem(at: url)
        return copies
    }

    /// Matérialise une `NSFileVersion` en pièce « (conflit) » à côté du paquet.
    private static func keepAsConflictCopy(version: NSFileVersion, of url: URL, suffix: String) throws -> RoomRecord {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("conflict-\(UUID().uuidString).roomscan")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try version.replaceItem(at: tmp)
        return try duplicateAsConflictCopy(packageAt: tmp, suffix: suffix, into: url.deletingLastPathComponent())
    }
}
