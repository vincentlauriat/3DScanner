import Foundation
import Sparkle

/// Sparkle 2 (macOS) : vérification quotidienne, menu « Rechercher les mises à jour… ».
/// L'updater ne démarre que si `SUPublicEDKey` est présente dans l'Info.plist (ajoutée
/// en phase 10 avec la clé EdDSA du trousseau `RoomScanner`) : sans clé, Sparkle
/// refuserait le flux et afficherait une erreur au lancement.
@Observable
@MainActor
final class UpdaterController {
    private let controller: SPUStandardUpdaterController
    /// `false` en développement (pas de clé) : l'élément de menu est désactivé.
    let isConfigured: Bool

    init() {
        isConfigured = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String).map { !$0.isEmpty } ?? false
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        if isConfigured { controller.startUpdater() }
    }

    var canCheckForUpdates: Bool { isConfigured && controller.updater.canCheckForUpdates }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var lastUpdateCheckDate: Date? { controller.updater.lastUpdateCheckDate }

    func checkForUpdates() { controller.checkForUpdates(nil) }
}
