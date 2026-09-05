import SwiftUI

/// Bibliothèque des pièces. Phase 2 : liste + scan (iOS) + suppression ;
/// vignettes et détails riches arrivent en phases 3 et 9.
struct RoomListView: View {
    @Environment(RoomStore.self) private var store
    @State private var showScanner = false
    @State private var selection: RoomRecord?

    var body: some View {
        NavigationStack {
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
        .onAppear { store.reload() }
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
    let record: RoomRecord
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.split.bottomrightquarter")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.name).font(.headline)
                Text("\(MeasurementFormat.squareMeters(record.areaM2)) · \(record.createdAt, format: .dateTime.day().month().year())")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
