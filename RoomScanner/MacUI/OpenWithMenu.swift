import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// « Ouvrir avec… » : les applications du Mac capables d'ouvrir le fichier exporté
/// (`NSWorkspace.urlsForApplications(toOpen:)`), avec leur icône.
struct OpenWithMenu: View {
    let fileURL: URL
    let type: UTType
    @State private var apps: [URL] = []

    var body: some View {
        Menu {
            if apps.isEmpty {
                Text("mac.openWith.none")
            } else {
                ForEach(apps, id: \.self) { app in
                    Button {
                        NSWorkspace.shared.open([fileURL], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                    } label: {
                        Label { Text(appName(app)) } icon: { Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)) }
                    }
                }
            }
            Divider()
            Button("mac.revealInFinder") { NSWorkspace.shared.activateFileViewerSelecting([fileURL]) }
        } label: {
            Label("mac.openWith", systemImage: "arrow.up.forward.app")
        }
        .task(id: type) { apps = Self.applications(for: type) }
    }

    static func applications(for type: UTType) -> [URL] {
        NSWorkspace.shared.urlsForApplications(toOpen: type)
            .sorted { $0.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveCompare($1.deletingPathExtension().lastPathComponent) == .orderedAscending }
    }

    private func appName(_ url: URL) -> String {
        FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
