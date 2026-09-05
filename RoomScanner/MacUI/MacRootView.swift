import SwiftUI
import AppKit

/// Fenêtre Mac : barre latérale des pièces (recherche, badge iCloud, glisser du paquet)
/// et détail à onglets ; exécute les actions des menus (export, impression, Finder, import).
struct MacRootView: View {
    @Environment(RoomStore.self) private var store
    @State private var appState = MacAppState()
    @State private var pendingDeletion: RoomRecord?
    @State private var search = ""
    @State private var exportSheet: ExportRequest?
    @State private var errorMessage: String?

    struct ExportRequest: Identifiable { let id = UUID(); let record: RoomRecord; let plan: FloorPlan; let format: ExportFormat? }

    private var filtered: [RoomRecord] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? store.records : store.records.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $appState.selected) {
                ForEach(filtered) { record in
                    RoomRow(record: record)
                        .tag(record)
                        .onDrag { DragExportProvider.packageProvider(url: store.packageURL(for: record)) }
                        .contextMenu {
                            Button("mac.menu.export") { appState.request(.export(nil)) }
                            Button("mac.menu.revealInFinder") { NSWorkspace.shared.activateFileViewerSelecting([store.packageURL(for: record)]) }
                            Divider()
                            Button("common.delete", role: .destructive) { pendingDeletion = record }
                        }
                }
            }
            .searchable(text: $search, placement: .sidebar, prompt: Text("mac.search"))
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .toolbar { ToolbarItem(placement: .automatic) { CloudStatusBadge() } }
            .overlay { if store.records.isEmpty { Text("list.empty.title").foregroundStyle(.secondary).font(.callout) } }
        } detail: {
            if let record = appState.selected, store.records.contains(record) {
                RoomDetailView(record: record)
                    .id(record.id)
            } else {
                MacEmptyStateView { importPackage() }
            }
        }
        .focusedSceneValue(\.macAppState, appState)
        .confirmationDialog("list.delete.confirm \(pendingDeletion?.name ?? "")", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }), titleVisibility: .visible) {
            Button("common.delete", role: .destructive) {
                if let r = pendingDeletion { try? store.delete(r); if appState.selected?.id == r.id { appState.selected = nil } }
                pendingDeletion = nil
            }
        } message: { Text("list.delete.message") }
        .navigationTitle(Text("app.name"))
        .task { await store.activateCloudIfAvailable(); autoSelect() }
        .onChange(of: store.records) { _, _ in
            if let s = appState.selected, !store.records.contains(where: { $0.id == s.id }) { appState.selected = nil }
            else if let s = appState.selected, let fresh = store.records.first(where: { $0.id == s.id }), fresh != s { appState.selected = fresh }
        }
        .onChange(of: appState.pendingAction) { _, action in
            guard let action else { return }
            appState.pendingAction = nil
            perform(action)
        }
        .onOpenURL { url in
            guard url.pathExtension == FileLayout.packageExtension else { return }
            do { appState.selected = try store.importPackage(from: url) } catch { errorMessage = error.localizedDescription }
        }
        .sheet(item: $exportSheet) { req in
            ExportSheet(record: req.record, plan: req.plan, initialFormat: req.format).environment(store)
        }
        .alert("mac.actionFailed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("common.ok") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .frame(minWidth: 900, minHeight: 600)
    }

    private func autoSelect() {
        store.reload()
        if UserDefaults.standard.bool(forKey: "RoomScannerAutoOpenFirst"), appState.selected == nil { appState.selected = store.records.first }
    }

    private func perform(_ action: MacAppState.Action) {
        switch action {
        case .export(let format):
            guard let record = appState.selected, let plan = try? store.plan(for: record) else { return }
            exportSheet = ExportRequest(record: record, plan: plan, format: format)
        case .print:
            guard let record = appState.selected, let plan = try? store.plan(for: record) else { return }
            PrintController.printPlan(House(room: plan), title: record.name, window: NSApp.keyWindow)
        case .revealInFinder:
            guard let record = appState.selected else { return }
            NSWorkspace.shared.activateFileViewerSelecting([store.packageURL(for: record)])
        case .openLibraryFolder:
            try? store.location.prepare()
            NSWorkspace.shared.open(store.location.documentsURL)
        case .importPackage:
            importPackage()
        }
    }

    private func importPackage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.roomScan]
        panel.allowsMultipleSelection = true
        panel.message = String(localized: "mac.import.message")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            do { appState.selected = try store.importPackage(from: url) } catch { errorMessage = error.localizedDescription }
        }
    }
}
