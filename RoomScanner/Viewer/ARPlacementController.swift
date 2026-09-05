#if os(iOS)
import Foundation
import RealityKit
import Observation

/// Mode AR (iOS) : suivi spatial, ancrage de la maquette sur un plan horizontal,
/// échelle 1:20 / 1:50 / 1:1, réinitialisation.
@Observable
@MainActor
final class ARPlacementController {
    private var session: SpatialTrackingSession?
    private(set) var anchor: AnchorEntity?

    func start(root: Entity, scale: ARScale) {
        let session = SpatialTrackingSession()
        let config = SpatialTrackingSession.Configuration(tracking: [.plane])
        Task { _ = await session.run(config) }
        self.session = session
        attach(root, scale: scale)
    }

    func stop() {
        guard let session else { return }
        self.session = nil
        Task { await session.stop() }
    }

    /// Détache la scène de l'ancre AR (retour aux modes 3D / 2D).
    func detach(_ root: Entity) {
        guard let anchor else { return }
        root.removeFromParent()
        anchor.removeFromParent()
        self.anchor = nil
        root.scale = .one
        root.position = .zero
    }

    func reset(root: Entity, scale: ARScale) {
        detach(root)
        attach(root, scale: scale)
    }

    func apply(scale: ARScale, to root: Entity) {
        guard anchor != nil else { return }
        root.scale = SIMD3(repeating: Float(scale.rawValue))
    }

    private func attach(_ root: Entity, scale: ARScale) {
        // Table pour la maquette, sol pour la superposition 1:1.
        let classification: AnchoringComponent.Target.Classification = scale == .real ? .floor : .any
        let anchor = AnchorEntity(.plane(.horizontal, classification: classification, minimumBounds: SIMD2(0.3, 0.3)))
        let parent = root.parent
        root.removeFromParent()
        root.scale = SIMD3(repeating: Float(scale.rawValue))
        root.position = .zero
        anchor.addChild(root)
        parent?.addChild(anchor)
        self.anchor = anchor
    }
}
#endif
