import SwiftUI
import AppKit

/// Fenêtre Mac : barre latérale (maisons puis pièces, recherche, badge iCloud, glisser du
/// paquet) et détail à onglets ; exécute les actions des menus (export, impression, Finder, import).
struct MacRootView: View {
    @Environment(RoomStore.self) private var store
    @State private var appState = MacAppState()
    @State private var pendingDeletion: LibraryItem?
    @State private var search = ""
    @State private var exportSheet: ExportRequest?
    @State private var errorMessage: String?

    struct ExportRequest: Identifiable { let id = UUID(); let subject: ExportSubject; let format: ExportFormat? }

    private func matches(_ name: String) -> Bool {
        let q = search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || name.localizedCaseInsensitiveContains(q)
    }
    private var filteredRooms: [RoomRecord] { store.records.filter { matches($0.name) } }
    private var filteredHouses: [HouseRecord] { store.houseRecords.filter { matches($0.name) } }
    private var isEmpty: Bool { store.records.isEmpty && store.houseRecords.isEmpty }

    var body: some View {
        NavigationSplitView {
            List(selection: $appState.selected) {
                if !filteredHouses.isEmpty {
                    Section("library.houses") {
                        ForEach(filteredHouses) { record in
                            HouseRow(record: record).tag(LibraryItem.house(record))
                                .modifier(RowActions(item: .house(record), url: store.packageURL(for: record), appState: appState, pendingDeletion: $pendingDeletion))
                        }
                    }
                }
                Section(filteredHouses.isEmpty ? "" : "library.rooms") {
                    ForEach(filteredRooms) { record in
                        RoomRow(record: record).tag(LibraryItem.room(record))
                            .modifier(RowActions(item: .room(record), url: store.packageURL(for: record), appState: appState, pendingDeletion: $pendingDeletion))
                    }
                }
            }
            .searchable(text: $search, placement: .sidebar, prompt: Text("mac.search"))
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .toolbar { ToolbarItem(placement: .automatic) { CloudStatusBadge() } }
            .overlay { if isEmpty { Text("list.empty.title").foregroundStyle(.secondary).font(.callout) } }
        } detail: {
            switch appState.selected {
            case .room(let record) where store.records.contains(record):
                RoomDetailView(record: record).id(record.id)
            case .house(let record) where store.houseRecords.contains(record):
                HouseDetailView(record: record).id(record.id)
            default:
                MacEmptyStateView { importPackage() }
            }
        }
        .focusedSceneValue(\.macAppState, appState)
        .confirmationDialog("list.delete.confirm \(pendingDeletion?.name ?? "")", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }), titleVisibility: .visible) {
            Button("common.delete", role: .destructive) {
                if let item = pendingDeletion { try? store.delete(item); if appState.selected?.id == item.id { appState.selected = nil } }
                pendingDeletion = nil
            }
        } message: { Text("list.delete.message") }
        .navigationTitle(Text("app.name"))
        .task { await store.activateCloudIfAvailable(); autoSelect() }
        .onChange(of: store.records) { _, _ in refreshSelection() }
        .onChange(of: store.houseRecords) { _, _ in refreshSelection() }
        .onChange(of: appState.selected, initial: true) { _, item in
            appState.availableFormats = item.map { availableFormats(for: $0) } ?? []
        }
        .onChange(of: appState.pendingAction) { _, action in
            guard let action else { return }
            appState.pendingAction = nil
            perform(action)
        }
        .onOpenURL { url in
            guard [FileLayout.packageExtension, FileLayout.housePackageExtension].contains(url.pathExtension) else { return }
            do { appState.selected = try store.importAny(from: url) } catch { errorMessage = error.localizedDescription }
        }
        .sheet(item: $exportSheet) { req in
            ExportSheet(subject: req.subject, initialFormat: req.format).environment(store)
        }
        .alert("mac.actionFailed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("common.ok") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .frame(minWidth: 900, minHeight: 600)
    }

    /// Menu contextuel et glisser du paquet, communs aux deux types de lignes.
    private struct RowActions: ViewModifier {
        let item: LibraryItem
        let url: URL
        let appState: MacAppState
        @Binding var pendingDeletion: LibraryItem?
        func body(content: Content) -> some View {
            content
                .onDrag { DragExportProvider.packageProvider(url: url) }
                .contextMenu {
                    Button("mac.menu.export") { appState.selected = item; appState.request(.export(nil)) }
                    Button("mac.menu.revealInFinder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    Divider()
                    Button("common.delete", role: .destructive) { pendingDeletion = item }
                }
        }
    }

    /// Garde la sélection en phase avec les listes (suppression, renommage, recalcul).
    private func refreshSelection() {
        switch appState.selected {
        case .room(let r):
            if let fresh = store.records.first(where: { $0.id == r.id }) { if fresh != r { appState.selected = .room(fresh) } } else { appState.selected = nil }
        case .house(let h):
            if let fresh = store.houseRecords.first(where: { $0.id == h.id }) { if fresh != h { appState.selected = .house(fresh) } } else { appState.selected = nil }
        case nil: break
        }
    }

    private func availableFormats(for item: LibraryItem) -> [ExportFormat] {
        switch item {
        case .room(let r): ExportService.availableFormats(packageURL: store.packageURL(for: r))
        case .house(let h): ExportService.availableFormats(usdzURL: HousePackage.usdzURL(in: store.packageURL(for: h)), usdzMeshURL: nil)
        }
    }

    /// Sujet d'export de l'élément sélectionné (plan/maison rechargés depuis le paquet).
    private func subject(for item: LibraryItem) -> ExportSubject? {
        switch item {
        case .room(let r): (try? store.plan(for: r)).map { ExportSubject(record: r, plan: $0, packageURL: store.packageURL(for: r)) }
        case .house(let h): (try? store.house(for: h)).map { ExportSubject(record: h, house: $0, packageURL: store.packageURL(for: h)) }
        }
    }

    private func autoSelect() {
        store.reload()
        if UserDefaults.standard.bool(forKey: "RoomScannerAutoOpenFirst"), appState.selected == nil {
            appState.selected = store.houseRecords.first.map { .house($0) } ?? store.records.first.map { .room($0) }
        }
    }

    private func perform(_ action: MacAppState.Action) {
        switch action {
        case .export(let format):
            guard let item = appState.selected, let subject = subject(for: item) else { return }
            exportSheet = ExportRequest(subject: subject, format: format)
        case .print:
            guard let item = appState.selected, let subject = subject(for: item) else { return }
            PrintController.printPlan(subject.house, title: subject.name, window: NSApp.keyWindow)
        case .revealInFinder:
            guard let item = appState.selected else { return }
            NSWorkspace.shared.activateFileViewerSelecting([store.packageURL(for: item)])
        case .openLibraryFolder:
            try? store.location.prepare()
            NSWorkspace.shared.open(store.location.documentsURL)
        case .importPackage:
            importPackage()
        }
    }

    private func importPackage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.roomScan, .houseScan]
        panel.allowsMultipleSelection = true
        panel.message = String(localized: "mac.import.message")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            do { appState.selected = try store.importAny(from: url) } catch { errorMessage = error.localizedDescription }
        }
    }
}
