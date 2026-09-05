import SwiftUI

/// Écran racine : la bibliothèque, avec le `RoomStore` injecté dans l'environnement.
struct RootView: View {
    @State private var store = RoomStore(location: .local())

    var body: some View {
        RoomListView()
            .environment(store)
    }
}

#Preview {
    RootView()
}
