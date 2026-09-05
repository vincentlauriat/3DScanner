import SwiftUI

/// Menus macOS : Fichier › Importer… (⌘O), Exporter… (⌘E) avec sous-menu par format,
/// Imprimer… (⌘P), Révéler dans le Finder (⇧⌘R), Ouvrir le dossier 3D Scanner.
struct MacMenuCommands: Commands {
    @FocusedValue(\.macAppState) private var state
    let updater: UpdaterController

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("mac.menu.checkForUpdates") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
        CommandGroup(replacing: .newItem) {
            Button("mac.menu.import") { state?.request(.importPackage) }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(state == nil)
        }
        CommandGroup(replacing: .importExport) {
            Button("mac.menu.export") { state?.request(.export(nil)) }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(state?.hasSelection != true)
            Menu("mac.menu.exportAs") {
                ForEach(ExportFormat.Group.allCases) { group in
                    Section(LocalizedStringKey(group.titleKey)) {
                        ForEach((state?.availableFormats ?? []).filter { $0.group == group }) { format in
                            Button(LocalizedStringKey(format.titleKey)) { state?.request(.export(format)) }
                        }
                    }
                }
            }
            .disabled(state?.hasSelection != true)
            Divider()
            Button("mac.menu.revealInFinder") { state?.request(.revealInFinder) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(state?.hasSelection != true)
            Button("mac.menu.openLibraryFolder") { state?.request(.openLibraryFolder) }
                .disabled(state == nil)
        }
        CommandGroup(replacing: .printItem) {
            Button("mac.menu.print") { state?.request(.print) }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(state?.hasSelection != true)
        }
    }
}
