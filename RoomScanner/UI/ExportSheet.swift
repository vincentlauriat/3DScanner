import SwiftUI

/// Feuille d'export d'une pièce ou d'une maison (`ExportSubject`) : choix du format, génération dans un dossier
/// temporaire, puis partage (`ShareLink`), enregistrement via le sélecteur système
/// ou copie dans `Exports/` du stockage courant (iCloud Drive en phase 7).
struct ExportSheet: View {
    @Environment(RoomStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let subject: ExportSubject
    var initialFormat: ExportFormat? = nil

    init(subject: ExportSubject, initialFormat: ExportFormat? = nil) { self.subject = subject; self.initialFormat = initialFormat }
    init(record: RoomRecord, plan: FloorPlan, packageURL: URL?, initialFormat: ExportFormat? = nil) {
        self.init(subject: ExportSubject(record: record, plan: plan, packageURL: packageURL), initialFormat: initialFormat)
    }

    @State private var selected: ExportFormat = .pdf
    @State private var result: URL?
    @State private var working = false
    @State private var error: String?
    @State private var savingWithPicker = false
    @State private var savedToExports = false

    @State private var meshSource: ExportService.MeshSource = .parametric

    private var formats: [ExportFormat] { ExportService.availableFormats(for: subject) }
    private var hasScanMesh: Bool { subject.usdzMeshURL != nil }

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
                                if group == .threeD, hasScanMesh {
                                    Picker("export.meshSource", selection: $meshSource) {
                                        ForEach(ExportService.MeshSource.allCases) { Text(LocalizedStringKey($0.titleKey)).tag($0) }
                                    }
                                    .onChange(of: meshSource) { _, _ in select(selected) }
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
        .onAppear { select(initialFormat ?? selected) }
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
                        Label(savedToExports ? (store.isCloud ? "export.savedToCloud" : "export.savedToExports")
                                             : (store.isCloud ? "export.saveToCloud" : "export.saveToExports"),
                              systemImage: savedToExports ? "checkmark.circle" : (store.isCloud ? "icloud.and.arrow.up" : "arrow.down.doc"))
                    }.disabled(savedToExports)
                    #if os(macOS)
                    OpenWithMenu(fileURL: result, type: selected.utType).fixedSize()
                    #endif
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
        let subject = self.subject
        var service = ExportService(); service.meshSource = meshSource
        Task.detached(priority: .userInitiated) { [service] in
            let outcome = Result { try service.export(subject, format: format) }
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
            try store.saveExport(url, for: subject)
            savedToExports = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}
