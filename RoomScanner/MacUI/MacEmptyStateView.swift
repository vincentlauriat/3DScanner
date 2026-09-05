import SwiftUI

/// Détail vide sur Mac : la capture se fait sur iPhone, les pièces arrivent par iCloud Drive
/// ou par import d'un `.roomscan`.
struct MacEmptyStateView: View {
    @Environment(RoomStore.self) private var store
    var onImport: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("mac.empty.title", systemImage: "iphone.gen3.radiowaves.left.and.right")
        } description: {
            Text(store.isCloud ? "mac.empty.description.icloud" : "mac.empty.description.local")
        } actions: {
            Button("mac.menu.import", action: onImport)
        }
    }
}
