import SwiftUI

/// Point d'entrée : bibliothèque en pile sur iPhone, fenêtre à barre latérale et
/// menus Fichier sur Mac (`MacUI/`).
@main
struct RoomScannerApp: App {
    #if os(macOS)
    @State private var store = RoomStore(location: RootView.initialLocation(), allowsCloud: !RootView.hasForcedRoot)
    @State private var updater = UpdaterController()
    #endif

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            MacRootView()
                .environment(store)
                .environment(updater)
        }
        .commands { MacMenuCommands(updater: updater) }
        Settings {
            SettingsView()
                .environment(store)
                .environment(updater)
        }
        #else
        WindowGroup {
            RootView()
        }
        #endif
    }
}
