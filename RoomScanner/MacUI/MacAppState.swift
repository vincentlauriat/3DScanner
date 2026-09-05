import SwiftUI

/// État partagé de la fenêtre Mac : pièce sélectionnée et actions demandées par
/// les menus (`MacMenuCommands`), exécutées par `MacRootView`.
@Observable
@MainActor
final class MacAppState {
    enum Action: Equatable { case export(ExportFormat?), print, revealInFinder, importPackage, openLibraryFolder }
    var selected: RoomRecord?
    var pendingAction: Action?
    var hasSelection: Bool { selected != nil }
    func request(_ action: Action) { pendingAction = action }
}

struct MacAppStateKey: FocusedValueKey { typealias Value = MacAppState }
extension FocusedValues {
    var macAppState: MacAppState? {
        get { self[MacAppStateKey.self] }
        set { self[MacAppStateKey.self] = newValue }
    }
}
