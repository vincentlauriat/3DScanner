import Foundation
import Sparkle

/// Sparkle 2 (macOS) : vérification quotidienne, menu « Rechercher les mises à jour… ».
/// L'updater ne démarre que si `SUPublicEDKey` est présente dans l'Info.plist (ajoutée
/// en phase 10 avec la clé EdDSA du trousseau `RoomScanner`) : sans clé, Sparkle
/// refuserait le flux et afficherait une erreur au lancement.
/// Les propriétés observées sont **stockées** (miroirs de l'état Sparkle) : `@Observable`
/// n'instrumente pas des accesseurs calculés, l'interface ne se rafraîchirait pas.
@Observable
@MainActor
final class UpdaterController {
    private let controller: SPUStandardUpdaterController
    private let delegate = Delegate()
    /// `false` en développement (pas de clé) : l'élément de menu est désactivé.
    let isConfigured: Bool
    private(set) var canCheckForUpdates = false
    private(set) var lastUpdateCheckDate: Date?
    var automaticallyChecksForUpdates: Bool {
        didSet { if isConfigured { controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates } }
    }

    init() {
        isConfigured = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String).map { !$0.isEmpty } ?? false
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: delegate, userDriverDelegate: nil)
        automaticallyChecksForUpdates = true
        if isConfigured { controller.startUpdater() }
        delegate.onCycleFinished = { [weak self] in self?.refresh() }
        refresh()
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
        refresh()
    }

    /// Relit l'état Sparkle dans les miroirs observables.
    func refresh() {
        guard isConfigured else { canCheckForUpdates = false; return }
        canCheckForUpdates = controller.updater.canCheckForUpdates
        lastUpdateCheckDate = controller.updater.lastUpdateCheckDate
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
    }

    /// Relais du cycle de mise à jour Sparkle vers le main thread.
    private final class Delegate: NSObject, SPUUpdaterDelegate {
        var onCycleFinished: (() -> Void)?
        func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
            let cb = onCycleFinished
            Task { @MainActor in cb?() }
        }
    }
}
