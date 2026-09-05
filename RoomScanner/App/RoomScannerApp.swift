import SwiftUI

/// Point d'entrée commun iOS / macOS. Le contenu réel arrive avec les phases
/// suivantes (bibliothèque, scan, visualiseur, exports).
@main
struct RoomScannerApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
