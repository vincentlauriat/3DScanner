import Foundation
import Observation

/// Bibliothèque des pièces : liste des `RoomRecord`, création, renommage,
/// suppression. Racine locale en phase 2 ; iCloud + observation live en phase 7.
@Observable
@MainActor
final class RoomStore {
    private(set) var location: StorageLocation
    private(set) var records: [RoomRecord] = []
    private(set) var lastError: AppError?

    init(location: StorageLocation) {
        self.location = location
    }

    /// Recharge la liste depuis le disque (triée du plus récent au plus ancien).
    func reload() {
        do {
            try location.prepare()
            let fm = FileManager.default
            let urls = try fm.contentsOfDirectory(at: location.roomsURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == FileLayout.packageExtension }
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
