import SwiftUI

/// Feuille d'export d'une pièce : choix du format, génération dans un dossier
/// temporaire, puis partage (`ShareLink`), enregistrement via le sélecteur système
/// ou copie dans `Exports/` du stockage courant (iCloud Drive en phase 7).
struct ExportSheet: View {
    @Environment(RoomStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let record: RoomRecord
    let plan: FloorPlan

    @State private var selected: ExportFormat = .pdf
    @State private var result: URL?
    @State private var working = false
    @State private var error: String?
    @State private var savingWithPicker = false
    @State private var savedToExports = false

    private var formats: [ExportFormat] { ExportService.availableFormats }
    private var house: House { House(room: plan) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    ForEach(ExportFormat.Group.allCases) { group in
                        let items = formats.filter { $0.group == group }
                        if !items.isEmpty {
                            Section(LocalizedStringKey(group.titleKey)) {
                                ForEach(items) { format in
                                    Button { select(format) } label: { row(format) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                Divider()
                footer
            }
            .navigationTitle("export.title")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("common.close") { dismiss() } } }
            .fileExporter(isPresented: $savingWithPicker, items: result.map { [$0] } ?? [], contentTypes: [selected.utType]) { outcome in
                if case .failure(let e) = outcome { error = e.localizedDescription }
            }
        }
        .onAppear { select(selected) }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }

    /// Pied fixe : fichier produit + actions. Reste visible pendant que la liste défile.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if working {
                    ProgressView().controlSize(.small)
                    Text("export.generating").foregroundStyle(.secondary)
                } else if let result {
                    Image(systemName: "doc").foregroundStyle(.secondary)
                    Text(result.lastPathComponent).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
            }
            .font(.callout)
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            HStack {
                if let result, !working {
                    ShareLink(item: result) { Label("export.share", systemImage: "square.and.arrow.up") }
                    Button { savingWithPicker = true } label: { Label("export.saveAs", systemImage: "folder") }
                    Button { saveToExports(result) } label: {
                        Label(savedToExports ? "export.savedToExports" : "export.saveToExports", systemImage: savedToExports ? "checkmark.circle" : "arrow.down.doc")
                    }.disabled(savedToExports)
                }
                Spacer()
            }
            .controlSize(.regular)
        }
        .padding()
        #if os(macOS)
        .background(.bar)
        #endif
    }

    private func row(_ format: ExportFormat) -> some View {
        HStack {
            Image(systemName: format.systemImage).frame(width: 24).foregroundStyle(.tint)
            VStack(alignment: .leading) {
                Text(LocalizedStringKey(format.titleKey))
                Text(LocalizedStringKey(format.descriptionKey)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if format == selected { Image(systemName: "checkmark").foregroundStyle(.tint) }
        }
        .contentShape(Rectangle())
    }

    private func select(_ format: ExportFormat) {
        selected = format
        result = nil; error = nil; savedToExports = false; working = true
        let house = self.house, record = self.record, packageURL = store.packageURL(for: record)
        Task.detached(priority: .userInitiated) {
            let outcome = Result { try ExportService().export(house, record: record, format: format, packageURL: packageURL) }
            await MainActor.run {
                guard selected == format else { return }
                working = false
                switch outcome {
                case .success(let url): result = url
                case .failure(let e): error = e.localizedDescription
                }
            }
        }
    }

    private func saveToExports(_ url: URL) {
        do {
            let dir = store.location.exportsURL
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: url, to: dest)
            savedToExports = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}
