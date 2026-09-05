import SwiftUI
import ImageIO

/// Bibliothèque : maisons (v2) puis pièces, scan (iOS), suppression, réglages.
struct RoomListView: View {
    @Environment(RoomStore.self) private var store
    @State private var showScanner = false
    @State private var showSettings = false
    @State private var pendingDeletion: [LibraryItem] = []
    @State private var selection: RoomRecord?
    @State private var path: [LibraryItem] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.records.isEmpty && store.houseRecords.isEmpty {
                    emptyState
                } else {
                    List {
                        if !store.houseRecords.isEmpty {
                            Section("library.houses") {
                                ForEach(store.houseRecords) { record in
                                    NavigationLink(value: LibraryItem.house(record)) { HouseRow(record: record) }
                                }
                                .onDelete { pendingDeletion = $0.map { .house(store.houseRecords[$0]) } }
                            }
                        }
                        Section(store.houseRecords.isEmpty ? "" : "library.rooms") {
                            ForEach(store.records) { record in
                                NavigationLink(value: LibraryItem.room(record)) { RoomRow(record: record) }
                            }
                            .onDelete { pendingDeletion = $0.map { .room(store.records[$0]) } }
                        }
                    }
                }
            }
            .navigationTitle(Text("app.name"))
            .navigationDestination(for: LibraryItem.self) { item in
                switch item {
                case .room(let record): RoomDetailView(record: record)
                case .house(let record): HouseDetailView(record: record)
                }
            }
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .cancellationAction) { CloudStatusBadge() }
                ToolbarItem(placement: .cancellationAction) {
                    Button { showSettings = true } label: { Label("settings.title", systemImage: "gearshape") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showScanner = true } label: { Label("list.scan", systemImage: "camera.viewfinder") }
                        .disabled(!scanSupported)
                }
                #endif
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $showScanner) {
                ScanView(onSaved: { selection = $0 }).environment(store)
            }
            #endif
        }
        .sheet(isPresented: $showSettings) { SettingsView().environment(store) }
        .confirmationDialog("list.delete.confirm \(pendingDeletion.first?.name ?? "")", isPresented: Binding(get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion = [] } }), titleVisibility: .visible) {
            Button("common.delete", role: .destructive) { confirmDeletion() }
        } message: { Text("list.delete.message") }
        .onAppear {
            store.reload()
            // `-RoomScannerAutoOpenFirst YES` : ouvre la première pièce (captures d'écran, essais).
            if UserDefaults.standard.bool(forKey: "RoomScannerAutoOpenFirst") {
                if let first = store.houseRecords.first { path = [.house(first)] } else if let first = store.records.first { path = [.room(first)] }
            }
        }
    }

    private var scanSupported: Bool {
        #if canImport(RoomPlan)
        return ScanCoordinator.isSupported
        #else
        return false
        #endif
    }

    @ViewBuilder private var emptyState: some View {
        #if os(iOS)
        if scanSupported {
            ContentUnavailableView {
                Label("list.empty.title", systemImage: "cube.transparent")
            } description: {
                Text("list.empty.message")
            } actions: {
                Button { showScanner = true } label: { Label("list.scan", systemImage: "camera.viewfinder") }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            UnsupportedDeviceView()
        }
        #else
        ContentUnavailableView {
            Label("list.empty.title", systemImage: "cube.transparent")
        } description: {
            Text("list.empty.mac")
        }
        #endif
    }

    private func confirmDeletion() {
        for item in pendingDeletion { try? store.delete(item) }
        pendingDeletion = []
    }
}

struct RoomRow: View {
    @Environment(RoomStore.self) private var store
    let record: RoomRecord
    @State private var thumbnail: CGImage?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "square.split.bottomrightquarter").font(.title2).foregroundStyle(.tint)
                }
            }
            .frame(width: 72, height: 48)
            .background(Color(white: 0.96))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .task(id: record.id) { thumbnail = await loadThumbnail() }
            VStack(alignment: .leading, spacing: 2) {
                Text(record.name).font(.headline)
                Text("\(MeasurementFormat.squareMeters(record.areaM2)) · \(record.createdAt, format: .dateTime.day().month().year())")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    /// Vignette du paquet ; si absente (ancien paquet), rendue à la volée et mémorisée.
    private func loadThumbnail() async -> CGImage? {
        let url = store.packageURL(for: record)
        if let f = RoomPackage.thumbnailURL(in: url), let src = CGImageSourceCreateWithURL(f as CFURL, nil),
           let img = CGImageSourceCreateImageAtIndex(src, 0, nil) { return img }
        guard let plan = try? store.plan(for: record) else { return nil }
        var r = PlanRenderer(); r.options.mode = .fill
        let img = r.image(House(room: plan), pixels: CGSize(width: 600, height: 400))
        if let png = PlanRenderer.thumbnailPNG(for: plan) { try? RoomPackage.writeThumbnail(png, in: url) }
        return img
    }
}
