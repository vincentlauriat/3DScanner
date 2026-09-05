import SwiftUI

/// Accès caméra refusé : explication + lien vers Réglages.
struct CameraDeniedView: View {
    var onClose: (() -> Void)? = nil
    var body: some View {
        ContentUnavailableView {
            Label("camera.denied.title", systemImage: "camera.fill.badge.ellipsis")
        } description: {
            Text("camera.denied.message")
        } actions: {
            #if os(iOS)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("camera.denied.openSettings", destination: url)
            }
            #endif
            if let onClose { Button("common.close", action: onClose) }
        }
    }
}
