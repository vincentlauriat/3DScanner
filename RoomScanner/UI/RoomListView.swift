import SwiftUI
import ImageIO

/// Bibliothèque des pièces. Phase 2 : liste + scan (iOS) + suppression ;
/// vignettes et détails riches arrivent en phases 3 et 9.
struct RoomListView: View {
    @Environment(RoomStore.self) private var store
    @State private var showScanner = false
    @State private var selection: RoomRecord?
    @State private var path: [RoomRecord] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.records.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(store.records) { record in
                            NavigationLink(value: record) { RoomRow(record: record) }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle(Text("app.name"))
            .navigationDestination(for: RoomRecord.self) { record in
                RoomDetailView(record: record)
            }
            .toolbar {
                #if os(iOS)
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
        .onAppear {
            store.reload()
            // `-RoomScannerAutoOpenFirst YES` : ouvre la première pièce (captures d'écran, essais).
            if UserDefaults.standard.bool(forKey: "RoomScannerAutoOpenFirst"), let first = store.records.first { path = [first] }
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

    private func delete(at offsets: IndexSet) {
        for record in offsets.map({ store.records[$0] }) {
            try? store.delete(record)
        }
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
