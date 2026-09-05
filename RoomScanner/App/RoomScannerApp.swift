import SwiftUI

/// Point d'entrée : bibliothèque en pile sur iPhone, fenêtre à barre latérale et
/// menus Fichier sur Mac (`MacUI/`).
@main
struct RoomScannerApp: App {
    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            MacRootView()
        }
        .commands { MacMenuCommands() }
        #else
        WindowGroup {
            RootView()
        }
        #endif
    }
}
