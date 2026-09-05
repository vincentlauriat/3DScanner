import SwiftUI

/// Écran racine : la bibliothèque, avec le `RoomStore` injecté dans l'environnement.
struct RootView: View {
    @State private var store = RoomStore(location: RootView.initialLocation(), allowsCloud: !RootView.hasForcedRoot)
    @State private var importError: String?

    static var hasForcedRoot: Bool { UserDefaults.standard.string(forKey: "RoomScannerStorageRoot") != nil }

    /// `-RoomScannerStorageRoot <dossier>` au lancement force une racine locale
    /// (démonstrations, captures d'écran, tests) ; sinon le stockage normal.
    static func initialLocation() -> StorageLocation {
        if let path = UserDefaults.standard.string(forKey: "RoomScannerStorageRoot") {
            return StorageLocation(kind: .local, documentsURL: URL(fileURLWithPath: path, isDirectory: true))
        }
        return .local()
    }

    var body: some View {
        RoomListView()
            .environment(store)
            .task { await store.activateCloudIfAvailable() }
            .onOpenURL { url in
                guard [FileLayout.packageExtension, FileLayout.housePackageExtension].contains(url.pathExtension) else { return }
                do { try store.importAny(from: url) } catch { importError = error.localizedDescription }
            }
            .alert("cloud.importFailed", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("common.ok") { importError = nil }
            } message: { Text(importError ?? "") }
    }
}

#Preview {
    RootView()
}
