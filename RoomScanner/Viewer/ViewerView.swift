import SwiftUI
import RealityKit

/// Visualiseur `RealityView` commun iOS / macOS (D13).
/// - 3D : caméra virtuelle + contrôles orbite du framework.
/// - 2D : murs aplatis, caméra au zénith verrouillée, glisser / pincer.
/// - AR (iOS) : caméra `.spatialTracking`, maquette ancrée sur un plan horizontal.
struct ViewerView: View {
    let house: House
    @Bindable var state: ViewerState

    /// Racine de la scène, reconstruite quand les options changent.
    @State private var sceneRoot = Entity()
    @State private var camera = PerspectiveCamera()
    @State private var twoDPan: CGSize = .zero
    @State private var twoDZoom: CGFloat = 1
    #if os(iOS)
    @State private var ar = ARPlacementController()
    #endif

    var body: some View {
        RealityView { content in
            rebuildScene()
            content.add(sceneRoot)
            content.add(camera)
            frameCamera()
            #if os(iOS)
            content.camera = .virtual
            #else
            content.camera = .virtual
            #endif
        } update: { content in
            #if os(iOS)
            content.camera = state.mode == .ar ? .spatialTracking : .virtual
            #endif
        }
        .realityViewCameraControls(state.mode == .threeD ? .orbit : .none)
        .gesture(state.mode == .twoD ? twoDGestures : nil)
        .onChange(of: state.mode) { _, _ in modeChanged() }
        .onChange(of: state.showDimensions) { _, _ in rebuildScene() }
        .onChange(of: state.showObjects) { _, _ in rebuildScene() }
        .onChange(of: house) { _, _ in rebuildScene(); resetView() }
        .onChange(of: state.resetToken) { _, _ in resetView() }
        #if os(iOS)
        .onChange(of: state.arScale) { _, _ in ar.apply(scale: state.arScale, to: sceneRoot) }
        #endif
        .background(Color(white: 0.12))
    }

    // MARK: - Scène

    private func rebuildScene() {
        var builder = PlanSceneBuilder()
        builder.options.showDimensions = state.showDimensions
        builder.options.showObjects = state.showObjects
        builder.options.flattenWalls = state.mode == .twoD
        let fresh = builder.makeScene(for: house)
        // Remplace les enfants en gardant la même entité racine (déjà ajoutée au contenu).
        for child in sceneRoot.children.map({ $0 }) { child.removeFromParent() }
        for child in fresh.children.map({ $0 }) { sceneRoot.addChild(child) }
        // Recentre la maison sur l'origine : les contrôles orbite de RealityView pivotent
        // autour de l'origine du monde, et l'ancre AR pose la maquette par son centre.
        let b = house.bounds
        sceneRoot.position = b.isEmpty ? .zero : SIMD3(Float(-b.center.x), 0, Float(b.center.y))
        #if os(iOS)
        if state.mode == .ar { ar.apply(scale: state.arScale, to: sceneRoot) } else { ar.detach(sceneRoot) }
        #endif
    }

    private func modeChanged() {
        #if os(iOS)
        if state.mode == .ar {
            rebuildScene()
            ar.start(root: sceneRoot, scale: state.arScale)
            return
        } else {
            ar.stop()
        }
        #endif
        rebuildScene()
        frameCamera()
    }

    private func resetView() {
        twoDPan = .zero; twoDZoom = 1
        #if os(iOS)
        if state.mode == .ar { ar.reset(root: sceneRoot, scale: state.arScale); return }
        #endif
        frameCamera()
    }

    /// Cadre la maison (centrée sur l'origine) : vue 3/4 en 3D, zénith en 2D.
    private func frameCamera() {
        let b = house.bounds
        let radius = Float(max(b.width, b.height, 2))
        let target = SIMD3<Float>(0, 0.5, 0)
        switch state.mode {
        case .twoD:
            let height = radius * 1.15 / CGFloat(twoDZoom).float
            let pan = SIMD3<Float>(Float(-twoDPan.width) * 0.002 * height, 0, Float(-twoDPan.height) * 0.002 * height)
            camera.look(at: target + pan, from: target + pan + SIMD3(0, height, 0.0001), relativeTo: nil)
        default:
            camera.look(at: target, from: target + SIMD3(radius * 0.9, radius * 0.8, radius * 1.1), relativeTo: nil)
        }
    }

    // MARK: - Gestes 2D

    private var twoDGestures: some Gesture {
        DragGesture()
            .onChanged { v in twoDPan = v.translation; frameCamera() }
            .onEnded { _ in }
            .simultaneously(with: MagnifyGesture()
                .onChanged { v in twoDZoom = min(max(v.magnification, 0.4), 6); frameCamera() })
    }
}

private extension CGFloat { var float: Float { Float(self) } }
