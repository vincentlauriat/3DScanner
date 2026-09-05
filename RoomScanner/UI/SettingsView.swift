import SwiftUI

/// Réglages : iCloud Drive, dossier « 3D Scanner », mises à jour (Mac), à propos.
struct SettingsView: View {
    @Environment(RoomStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CloudAvailability.preferenceKey) private var useICloud = true
    #if os(macOS)
    @Environment(UpdaterController.self) private var updater
    @State private var autoCheck = true
    #endif

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(v) (\(b))"
    }

    var body: some View {
        #if os(iOS)
        NavigationStack {
            form
                .navigationTitle("settings.title")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("common.close") { dismiss() } } }
        }
        #else
        form.frame(width: 480).frame(minHeight: 380)
        #endif
    }

    private var form: some View {
        Form {
            Section {
                Toggle("settings.icloud.toggle", isOn: $useICloud)
                    .disabled(!store.allowsCloud)
                    .onChange(of: useICloud) { _, on in Task { await store.setCloudEnabled(on) } }
                LabeledContent("settings.icloud.status") {
                    Label(store.isCloud ? "cloud.title.icloud" : "cloud.title.local", systemImage: store.isCloud ? "checkmark.icloud" : "internaldrive")
                        .foregroundStyle(.secondary)
                }
                if !CloudAvailability.isSignedIn { Text("cloud.status.localNoAccount").font(.footnote).foregroundStyle(.secondary) }
                Button { openLibraryFolder() } label: { Label("settings.openFolder", systemImage: "folder") }
            } header: { Text("settings.icloud.header") } footer: { Text("settings.icloud.footer") }

            #if os(macOS)
            Section("settings.updates.header") {
                Toggle("settings.updates.auto", isOn: $autoCheck)
                    .disabled(!updater.isConfigured)
                    .onChange(of: autoCheck) { _, on in if updater.isConfigured { updater.automaticallyChecksForUpdates = on } }
                LabeledContent("settings.updates.last") {
                    Text(updater.lastUpdateCheckDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? String(localized: "settings.updates.never")).foregroundStyle(.secondary)
                }
                Button("mac.menu.checkForUpdates") { updater.checkForUpdates() }.disabled(!updater.canCheckForUpdates)
                if !updater.isConfigured { Text("settings.updates.devBuild").font(.footnote).foregroundStyle(.secondary) }
            }
            .onAppear { if updater.isConfigured { autoCheck = updater.automaticallyChecksForUpdates } }
            #endif

            Section("settings.about.header") {
                LabeledContent("settings.about.version", value: version)
                Link(destination: URL(string: "https://vincentlauriat.github.io/3DScanner/")!) { Label("settings.about.website", systemImage: "globe") }
                Link(destination: URL(string: "https://github.com/vincentlauriat/3DScanner")!) { Label("settings.about.source", systemImage: "chevron.left.forwardslash.chevron.right") }
            }
        }
        .formStyle(.grouped)
    }

    private func openLibraryFolder() {
        try? store.location.prepare()
        #if os(macOS)
        NSWorkspace.shared.open(store.location.documentsURL)
        #else
        // Fichiers ouvre le dossier via le schéma shareddocuments://.
        var comps = URLComponents(url: store.location.documentsURL, resolvingAgainstBaseURL: false)
        comps?.scheme = "shareddocuments"
        if let url = comps?.url { UIApplication.shared.open(url) }
        #endif
    }
}
