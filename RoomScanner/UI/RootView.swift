import SwiftUI

/// Écran racine : la bibliothèque, avec le `RoomStore` injecté dans l'environnement.
struct RootView: View {
    @State private var store = RoomStore(location: RootView.initialLocation())

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
    }
}

#Preview {
    RootView()
}
