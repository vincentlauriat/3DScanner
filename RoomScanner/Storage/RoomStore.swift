import Foundation
import Observation

/// Bibliothèque des pièces : liste des `RoomRecord`, création, renommage,
/// suppression, import ; racine locale ou iCloud Drive (observation live,
/// téléchargements, conflits — D16/D17).
@Observable
@MainActor
final class RoomStore {
    private(set) var location: StorageLocation
    private(set) var records: [RoomRecord] = []
    private(set) var lastError: AppError?
    /// État iCloud par paquet (vide en stockage local).
    private(set) var cloudStatus: [UUID: CloudItemStatus] = [:]
    /// Nombre de paquets iCloud pas encore téléchargés sur cet appareil.
    private(set) var pendingDownloads = 0
    /// `true` pendant la résolution du conteneur au lancement.
    private(set) var isResolvingCloud = false
    /// Racine forcée (`-RoomScannerStorageRoot`) : pas de bascule iCloud.
    let allowsCloud: Bool

    @ObservationIgnored private var monitor: UbiquityMonitor?
    /// Paquets dont la résolution de conflit a échoué : on ne retente pas à chaque lot du moniteur.
    @ObservationIgnored private var failedConflictResolutions: Set<URL> = []
    @ObservationIgnored private var isResolvingConflicts = false

    init(location: StorageLocation, allowsCloud: Bool = true) {
        self.location = location
        self.allowsCloud = allowsCloud
    }

    var isCloud: Bool { location.kind == .iCloud }

    // MARK: iCloud

    /// Au lancement : résout le conteneur hors main thread, migre le local vers iCloud,
    /// bascule et démarre l'observation. Sans compte ou conteneur, on reste en local.
    func activateCloudIfAvailable() async {
        guard allowsCloud, !isCloud, !isResolvingCloud else { return }
        isResolvingCloud = true
        defer { isResolvingCloud = false }
        let local = location
        let cloud = await Task.detached(priority: .utility) { () -> StorageLocation? in
            guard let cloud = CloudAvailability.resolveLocation() else { return nil }
            try? CloudAvailability.migrate(from: local, to: cloud)
            return cloud
        }.value
        guard let cloud else { return }
        switchLocation(to: cloud)
    }

    /// Réglage « Utiliser iCloud Drive » : bascule immédiate. Désactiver revient au dossier local
    /// (les fichiers iCloud restent dans iCloud Drive, rien n'est déplacé ni supprimé).
    func setCloudEnabled(_ enabled: Bool) async {
        UserDefaults.standard.set(enabled, forKey: CloudAvailability.preferenceKey)
        if enabled { await activateCloudIfAvailable() }
        else if isCloud { switchLocation(to: .local()) }
    }

    /// Change de racine (iCloud ↔ local), recharge, (re)démarre l'observation.
    func switchLocation(to newLocation: StorageLocation) {
        monitor?.stop(); monitor = nil
        cloudStatus = [:]; pendingDownloads = 0
        location = newLocation
        reload()
        if newLocation.kind == .iCloud {
            let m = UbiquityMonitor()
            m.onChange = { [weak self] items in self?.apply(cloudItems: items) }
            m.start()
            monitor = m
        }
    }

    private func apply(cloudItems items: [CloudItemStatus]) {
        var status: [UUID: CloudItemStatus] = [:]
        for item in items {
            if let id = UUID(uuidString: item.url.deletingPathExtension().lastPathComponent) { status[id] = item }
        }
        cloudStatus = status
        pendingDownloads = items.filter { !$0.isAvailableLocally }.count
        reload()
        let conflicts = items.filter { $0.hasUnresolvedConflicts && $0.isAvailableLocally && !failedConflictResolutions.contains($0.url) }.map(\.url)
        if !conflicts.isEmpty { resolveConflicts(at: conflicts) }
    }

    /// Résout les conflits hors du main thread (copies de paquets entiers), une série à la fois.
    private func resolveConflicts(at urls: [URL]) {
        guard !isResolvingConflicts else { return }
        isResolvingConflicts = true
        let suffix = String(localized: "cloud.conflictSuffix")
        Task { [weak self] in
            let failures = await Task.detached(priority: .utility) { () -> [(URL, Error)] in
                var failed: [(URL, Error)] = []
                for url in urls {
                    do { try ConflictResolver.resolve(packageAt: url, suffix: suffix) } catch { failed.append((url, error)) }
                }
                return failed
            }.value
            guard let self else { return }
            self.isResolvingConflicts = false
            for (url, error) in failures {
                self.failedConflictResolutions.insert(url)
                self.lastError = .storageFailed(error.localizedDescription)
            }
            self.reload()
        }
    }

    // MARK: Import / export

    /// Importe un `.roomscan` reçu (AirDrop, Fichiers, double-clic). Si l'identifiant
    /// existe déjà, la pièce importée reçoit un nouvel identifiant et un suffixe.
    @discardableResult
    func importPackage(from url: URL) throws -> RoomRecord {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        try location.prepare()
        var record = try RoomPackage.readRecord(from: url)
        let dest = location.packageURL(for: record.id)
        if FileManager.default.fileExists(atPath: dest.path) {
            // La copie est écrite dans le dossier temporaire de l'app (le dossier d'origine n'est
            // pas accessible en sandbox), puis déplacée dans `Rooms/`.
            let staging = FileManager.default.temporaryDirectory.appendingPathComponent("import-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: staging) }
            let copy = try ConflictResolver.duplicateAsConflictCopy(packageAt: url, suffix: String(localized: "cloud.importedSuffix"), into: staging)
            let tmpCopy = staging.appendingPathComponent(copy.id.uuidString).appendingPathExtension(FileLayout.packageExtension)
            try RoomPackage.coordinatedWrite(at: location.packageURL(for: copy.id), options: .forReplacing) { target in
                try FileManager.default.moveItem(at: tmpCopy, to: target)
            }
            record = copy
        } else {
            try RoomPackage.coordinatedWrite(at: dest, options: .forReplacing) { target in
                try FileManager.default.copyItem(at: url, to: target)
            }
        }
        reload()
        return record
    }

    /// Copie un export dans `Exports/<Pièce>/` de la racine courante (iCloud Drive ou local) ;
    /// visible dans Fichiers / Finder et par toute app tierce.
    @discardableResult
    func saveExport(_ fileURL: URL, for record: RoomRecord) throws -> URL {
        let folder = location.exportsURL.appendingPathComponent(ExportService.folderName(for: record), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = folder.appendingPathComponent(fileURL.lastPathComponent)
        try RoomPackage.coordinatedWrite(at: dest, options: .forReplacing) { target in
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.copyItem(at: fileURL, to: target)
        }
        return dest
    }

    /// Recharge la liste depuis le disque (triée du plus récent au plus ancien).
    func reload() {
        do {
            try location.prepare()
            let fm = FileManager.default
            let urls = try fm.contentsOfDirectory(at: location.roomsURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == FileLayout.packageExtension }
            // Un paquet iCloud pas encore téléchargé n'a pas de `meta.json` lisible : ignoré
            // jusqu'à la notification du moniteur.
            records = urls.compactMap { try? RoomPackage.readRecord(from: $0) }
                .sorted { $0.createdAt > $1.createdAt }
            lastError = nil
        } catch {
            lastError = .storageFailed(error.localizedDescription)
        }
    }

    func packageURL(for record: RoomRecord) -> URL { location.packageURL(for: record.id) }

    /// Nom proposé pour une nouvelle pièce, dédoublonné parmi les existantes.
    func proposedName(for label: RoomLabel) -> String {
        RoomNaming().proposedName(for: label, existingNames: records.map(\.name))
    }

    /// Enregistre un nouveau paquet et l'ajoute à la liste.
    @discardableResult
    func save(_ package: RoomPackage) throws -> RoomRecord {
        try location.prepare()
        try package.write(to: location.packageURL(for: package.record.id))
        records.removeAll { $0.id == package.record.id }
        records.insert(package.record, at: 0)
        records.sort { $0.createdAt > $1.createdAt }
        return package.record
    }

    func plan(for record: RoomRecord) throws -> FloorPlan {
        try RoomPackage.readPlan(from: packageURL(for: record))
    }

    func rename(_ record: RoomRecord, to newName: String) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != record.name else { return }
        var plan = try plan(for: record)
        plan.name = trimmed
        var updated = record
        updated.name = trimmed
        try RoomPackage.update(record: updated, plan: plan, in: packageURL(for: record))
        if let i = records.firstIndex(where: { $0.id == record.id }) { records[i] = updated }
    }

    func delete(_ record: RoomRecord) throws {
        try RoomPackage.delete(at: packageURL(for: record))
        records.removeAll { $0.id == record.id }
    }
}
