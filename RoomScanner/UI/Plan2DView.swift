import SwiftUI

/// Plan 2D interactif : rendu par `PlanRenderer` en bitmap haute résolution,
/// zoom au pincement / molette, déplacement au doigt, double-tap pour recentrer.
struct Plan2DView: View {
    let house: House
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Color(white: 0.97)
                if let image = render(size: size) {
                    Image(decorative: image, scale: displayScale * 2)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size.width, height: size.height)
                        .scaleEffect(scale)
                        .offset(offset)
                }
            }
            .contentShape(Rectangle())
            .gesture(drag.simultaneously(with: magnify))
            .onTapGesture(count: 2) { withAnimation(.snappy) { scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero } }
            .clipped()
        }
        .accessibilityLabel(Text("plan.accessibility"))
    }

    private func render(size: CGSize) -> CGImage? {
        guard size.width > 10, size.height > 10 else { return nil }
        var r = PlanRenderer()
        // À l'écran : le plan remplit la zone (pas d'échelle papier) et les textes sont en points,
        // rendus à 2× la densité d'écran pour rester nets une fois zoomés.
        r.options.mode = .fill
        return r.image(house, pageSize: size, pixelScale: displayScale * 2)
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { v in offset = CGSize(width: lastOffset.width + v.translation.width, height: lastOffset.height + v.translation.height) }
            .onEnded { _ in lastOffset = offset }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { v in scale = min(max(lastScale * v.magnification, 0.5), 8) }
            .onEnded { _ in lastScale = scale }
    }
}
