import SwiftUI

/// Écran racine provisoire (phase 0) : confirme que les deux cibles compilent
/// et que la localisation fr/en est en place.
struct RootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("app.name", bundle: .main)
                .font(.largeTitle.bold())
            Text("root.placeholder", bundle: .main)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(minWidth: 320, minHeight: 240)
    }
}

#Preview {
    RootView()
}
