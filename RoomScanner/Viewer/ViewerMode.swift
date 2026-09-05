import Foundation
import Observation

/// Modes du visualiseur : 3D orbite, 2D vue de dessus, AR (iOS).
enum ViewerMode: String, CaseIterable, Identifiable {
    case threeD, twoD, ar
    var id: String { rawValue }

    var titleKey: String {
        switch self { case .threeD: "viewer.mode.3d"; case .twoD: "viewer.mode.2d"; case .ar: "viewer.mode.ar" }
    }

    static var available: [ViewerMode] {
        #if os(iOS)
        return [.threeD, .twoD, .ar]
        #else
        return [.threeD, .twoD]
        #endif
    }
}

/// Échelle de la maquette en AR.
enum ARScale: Double, CaseIterable, Identifiable {
    case oneToTwenty = 0.05
    case oneToFifty = 0.02
    case real = 1
    var id: Double { rawValue }
    var label: String {
        switch self { case .oneToTwenty: "1:20"; case .oneToFifty: "1:50"; case .real: "1:1" }
    }
}

/// État partagé du visualiseur (contrôles ↔ scène).
@Observable
@MainActor
final class ViewerState {
    var mode: ViewerMode = .threeD
    var showDimensions = false
    var showObjects = true
    var arScale: ARScale = .oneToFifty
    /// Incrémenté pour demander un recentrage / une réinitialisation d'ancrage.
    var resetToken = 0
}
