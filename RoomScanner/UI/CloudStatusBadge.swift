import SwiftUI

/// Pastille d'état iCloud Drive dans la bibliothèque : local / iCloud / téléchargements
/// en cours, avec explication au toucher ou au clic.
struct CloudStatusBadge: View {
    @Environment(RoomStore.self) private var store
    @State private var showing = false

    private var symbol: String {
        if store.isResolvingCloud { return "icloud" }
        guard store.isCloud else { return "internaldrive" }
        return store.pendingDownloads > 0 ? "icloud.and.arrow.down" : "checkmark.icloud"
    }
    private var explanationKey: LocalizedStringKey {
        if store.isResolvingCloud { return "cloud.status.resolving" }
        guard store.isCloud else { return store.allowsCloud ? (CloudAvailability.isSignedIn ? "cloud.status.localNoContainer" : "cloud.status.localNoAccount") : "cloud.status.localForced" }
        return store.pendingDownloads > 0 ? "cloud.status.downloading \(store.pendingDownloads)" : "cloud.status.synced"
    }

    var body: some View {
        Button { showing.toggle() } label: {
            Label { Text("cloud.status") } icon: {
                Image(systemName: symbol)
                    .symbolEffect(.pulse, isActive: store.isResolvingCloud || store.pendingDownloads > 0)
            }
            .labelStyle(.iconOnly)
        }
        .accessibilityLabel(Text(explanationKey))
        .popover(isPresented: $showing) {
            VStack(alignment: .leading, spacing: 8) {
                Label(store.isCloud ? "cloud.title.icloud" : "cloud.title.local", systemImage: symbol).font(.headline)
                Text(explanationKey).font(.callout).foregroundStyle(.secondary)
                Text(verbatim: store.location.documentsURL.path).font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(3)
            }
            .padding()
            .frame(minWidth: 260, maxWidth: 340)
            .presentationCompactAdaptation(.popover)
        }
    }
}
