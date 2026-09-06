import SwiftUI
import ImageIO

/// Détail d'une maison (v2) : sélecteur de niveau, onglets Plan 2D / Visualiseur / Mesures,
/// export (⌘E), titre renommable. Le sélecteur de niveau s'applique aux trois onglets
/// (« Tous les niveaux » superpose les étages en 3D).
struct HouseDetailView: View {
    @Environment(RoomStore.self) private var store
    let record: HouseRecord
    @State private var house: House?
    @State private var loadError: String?
    @State private var tab: Tab = .plan
    @State private var storyIndex: Int?
    @State private var renaming = false
    @State private var exporting = false
    @State private var newName = ""
    @State private var viewerState = ViewerState()

    enum Tab: Hashable { case plan, viewer, measures }

    private var currentRecord: HouseRecord { store.houseRecords.first { $0.id == record.id } ?? record }

    var body: some View {
        Group {
            if let house {
                content(house)
            } else if let loadError {
                ContentUnavailableView(loadError, systemImage: "exclamationmark.triangle")
            } else {
                ProgressView()
            }
        }
        .navigationTitle(currentRecord.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { exporting = true } label: { Label("detail.export", systemImage: "square.and.arrow.up") }
                    .disabled(house == nil)
                    #if os(iOS)
                    .keyboardShortcut("e", modifiers: .command)
                    #endif
            }
            ToolbarItem(placement: .primaryAction) {
                Button { newName = currentRecord.name; renaming = true } label: { Label("detail.rename", systemImage: "pencil") }
            }
        }
        .sheet(isPresented: $exporting) {
            if let house { ExportSheet(subject: ExportSubject(record: currentRecord, house: house, packageURL: store.packageURL(for: currentRecord))).environment(store) }
        }
        .alert("detail.rename", isPresented: $renaming) {
            TextField("detail.rename.placeholder", text: $newName)
            Button("common.ok") { rename() }
            Button("common.cancel", role: .cancel) {}
        }
        .task(id: record.id) { load() }
    }

    /// Maison réduite au niveau sélectionné (plan 2D, mesures) ; `nil` = tous les niveaux.
    private func shown(_ house: House) -> House {
        guard let storyIndex, let story = house.stories.first(where: { $0.index == storyIndex }) else { return house }
        return House(id: house.id, name: house.name, stories: [story])
    }

    @ViewBuilder private func content(_ house: House) -> some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $tab) {
                    Text("detail.tab.plan").tag(Tab.plan)
                    Text("detail.tab.viewer").tag(Tab.viewer)
                    Text("detail.tab.measures").tag(Tab.measures)
                }
                .pickerStyle(.segmented)
                if house.stories.count > 1 {
                    Picker("house.story", selection: $storyIndex) {
                        Text("house.story.all").tag(Int?.none)
                        ForEach(house.stories, id: \.index) { story in
                            Text(StoryNaming.localizedName(for: story.index)).tag(Int?.some(story.index))
                        }
                    }
                    .fixedSize()
                    .accessibilityIdentifier("house.storyPicker")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            switch tab {
            case .plan:
                #if os(macOS)
                Plan2DView(house: shown(house))
                    .onDrag { DragExportProvider.provider(subject: ExportSubject(record: currentRecord, house: shown(house), packageURL: store.packageURL(for: currentRecord)), format: .pdf) }
                    .help("mac.dragHint")
                #else
                Plan2DView(house: shown(house))
                #endif
            case .viewer:
                VStack(spacing: 0) {
                    ViewerView(house: shown(house), state: viewerState)
                    ViewerControls(state: viewerState, usdzURL: HousePackage.usdzURL(in: store.packageURL(for: currentRecord)))
                }
            case .measures: HouseMeasuresView(house: shown(house))
            }
        }
    }

    private func load() {
        do {
            let h = try store.house(for: currentRecord)
            house = h
            if let storyIndex, !h.stories.contains(where: { $0.index == storyIndex }) { self.storyIndex = nil }
        } catch { loadError = error.localizedDescription }
    }

    private func rename() {
        do { try store.rename(currentRecord, to: newName); load() } catch { loadError = error.localizedDescription }
    }
}

/// Mesures d'une maison : totaux puis une section par niveau et par pièce.
struct HouseMeasuresView: View {
    let house: House

    var body: some View {
        let hm = HouseMeasurements(house: house)
        List {
            // La surface de la maison est l'union des pièces d'un même niveau : elle est plus
            // petite que la somme des pièces listées plus bas (les mitoyennes se recouvrent).
            // Le libellé et la note l'expliquent pour que les deux chiffres se lisent ensemble.
            Section("measures.summary") {
                row(Text("house.area"), MeasurementFormat.squareMeters(hm.floorArea))
                row(Text("house.rooms"), "\(hm.roomCount)")
                row(Text("house.stories"), "\(hm.storyCount)")
                Text("house.area.footnote").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(house.stories, id: \.index) { story in
                Section(StoryNaming.localizedName(for: story.index)) {
                    ForEach(story.rooms) { room in
                        let m = RoomMeasurements(plan: room)
                        row(Text(room.name), "\(MeasurementFormat.squareMeters(m.floorArea)) · \(MeasurementFormat.meters(m.perimeter))")
                    }
                }
            }
        }
    }

    private func row(_ title: Text, _ value: String) -> some View {
        HStack { title; Spacer(); Text(value).foregroundStyle(.secondary).monospacedDigit() }
    }
}

/// Ligne de bibliothèque d'une maison : vignette du premier niveau, pièces, niveaux, surface.
struct HouseRow: View {
    @Environment(RoomStore.self) private var store
    let record: HouseRecord
    @State private var thumbnail: CGImage?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "house").font(.title2).foregroundStyle(.tint)
                }
            }
            .frame(width: 72, height: 48)
            .background(Color(white: 0.96))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .task(id: record.id) { thumbnail = await loadThumbnail() }
            VStack(alignment: .leading, spacing: 2) {
                Text(record.name).font(.headline)
                Text("house.row \(record.roomCount) \(record.storyCount) \(MeasurementFormat.squareMeters(record.areaM2))")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func loadThumbnail() async -> CGImage? {
        let url = store.packageURL(for: record)
        if let f = HousePackage.thumbnailURL(in: url), let src = CGImageSourceCreateWithURL(f as CFURL, nil),
           let img = CGImageSourceCreateImageAtIndex(src, 0, nil) { return img }
        guard let house = try? store.house(for: record), let png = PlanRenderer.thumbnailPNG(for: house) else { return nil }
        try? HousePackage.writeThumbnail(png, in: url)
        guard let src = CGImageSourceCreateWithData(png as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
