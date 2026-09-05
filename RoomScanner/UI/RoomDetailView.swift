import SwiftUI

/// Détail d'une pièce : onglets Plan 2D / Visualiseur / Mesures, export (⌘E),
/// titre renommable.
struct RoomDetailView: View {
    @Environment(RoomStore.self) private var store
    let record: RoomRecord
    @State private var plan: FloorPlan?
    @State private var loadError: String?
    /// `-RoomScannerInitialTab viewer|measures` et `-RoomScannerInitialViewerMode 2d|ar` au lancement (captures, essais).
    @State private var tab: Tab = {
        switch UserDefaults.standard.string(forKey: "RoomScannerInitialTab") { case "viewer": .viewer; case "measures": .measures; default: .plan }
    }()
    @State private var renaming = false
    @State private var exporting = false
    @State private var newName = ""
    @State private var viewerState: ViewerState = {
        let s = ViewerState()
        switch UserDefaults.standard.string(forKey: "RoomScannerInitialViewerMode") { case "2d": s.mode = .twoD; case "ar": s.mode = .ar; default: break }
        s.showDimensions = UserDefaults.standard.bool(forKey: "RoomScannerInitialDimensions")
        return s
    }()

    enum Tab: Hashable { case plan, viewer, measures }

    private var currentRecord: RoomRecord { store.records.first { $0.id == record.id } ?? record }

    var body: some View {
        Group {
            if let plan {
                content(plan)
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
                    .disabled(plan == nil)
                    #if os(iOS)
                    .keyboardShortcut("e", modifiers: .command)
                    #endif
            }
            ToolbarItem(placement: .primaryAction) {
                Button { newName = currentRecord.name; renaming = true } label: { Label("detail.rename", systemImage: "pencil") }
            }
        }
        .sheet(isPresented: $exporting) {
            if let plan { ExportSheet(record: currentRecord, plan: plan).environment(store) }
        }
        .alert("detail.rename", isPresented: $renaming) {
            TextField("detail.rename.placeholder", text: $newName)
            Button("common.ok") { rename() }
            Button("common.cancel", role: .cancel) {}
        }
        .task(id: record.id) { load() }
    }

    @ViewBuilder private func content(_ plan: FloorPlan) -> some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("detail.tab.plan").tag(Tab.plan)
                Text("detail.tab.viewer").tag(Tab.viewer)
                Text("detail.tab.measures").tag(Tab.measures)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            switch tab {
            case .plan:
                #if os(macOS)
                Plan2DView(house: House(room: plan))
                    .onDrag { DragExportProvider.provider(house: House(room: plan), record: currentRecord, format: .pdf, packageURL: store.packageURL(for: currentRecord)) }
                    .help("mac.dragHint")
                #else
                Plan2DView(house: House(room: plan))
                #endif
            case .viewer:
                VStack(spacing: 0) {
                    ViewerView(house: House(room: plan), state: viewerState)
                    ViewerControls(state: viewerState, usdzURL: RoomPackage.usdzURL(in: store.packageURL(for: currentRecord)))
                }
            case .measures: MeasuresView(plan: plan)
            }
        }
    }

    private func load() {
        do { plan = try store.plan(for: currentRecord) } catch { loadError = error.localizedDescription }
    }

    private func rename() {
        do {
            try store.rename(currentRecord, to: newName)
            load()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

/// Liste structurée des mesures (surface, périmètre, hauteur, murs, ouvertures, objets).
struct MeasuresView: View {
    let plan: FloorPlan
    private var m: RoomMeasurements { RoomMeasurements(plan: plan) }

    var body: some View {
        List {
            Section("measures.summary") {
                row("measures.area", MeasurementFormat.squareMeters(m.floorArea))
                row("measures.perimeter", MeasurementFormat.meters(m.perimeter))
                row("measures.ceiling", ceilingText)
            }
            Section("measures.walls") {
                ForEach(Array(m.walls.enumerated()), id: \.element.id) { i, w in
                    row(String(localized: "measures.wall \(i + 1)"),
                        "\(MeasurementFormat.centimeters(w.length)) × \(MeasurementFormat.centimeters(w.height))", w.confidence)
                }
            }
            if !m.openings.isEmpty {
                Section("measures.openings") {
                    ForEach(m.openings) { o in row(openingName(o.kind), openingText(o), o.confidence) }
                }
            }
            if !m.objects.isEmpty {
                Section("measures.objects") {
                    ForEach(m.objects) { o in
                        row(ObjectNaming.localizedName(o.category),
                            "\(MeasurementFormat.centimeters(o.width)) × \(MeasurementFormat.centimeters(o.depth)) × \(MeasurementFormat.centimeters(o.height))", o.confidence)
                    }
                }
            }
        }
    }

    private var ceilingText: String {
        let r = m.ceilingHeight
        return abs(r.upperBound - r.lowerBound) < 0.02
            ? MeasurementFormat.meters(r.lowerBound)
            : "\(MeasurementFormat.meters(r.lowerBound)) – \(MeasurementFormat.meters(r.upperBound))"
    }

    private func openingName(_ kind: Opening.Kind) -> String {
        switch kind {
        case .door: String(localized: "opening.door")
        case .window: String(localized: "opening.window")
        case .opening: String(localized: "opening.opening")
        }
    }

    private func openingText(_ o: RoomMeasurements.OpeningMeasure) -> String {
        var t = "\(MeasurementFormat.centimeters(o.width)) × \(MeasurementFormat.centimeters(o.height))"
        if o.kind == .window { t += " · " + String(localized: "measures.sill \(MeasurementFormat.centimeters(o.sillHeight))") }
        return t
    }

    private func row(_ title: LocalizedStringKey, _ value: String, _ confidence: Confidence? = nil) -> some View { row(Text(title), value, confidence) }
    private func row(_ title: String, _ value: String, _ confidence: Confidence? = nil) -> some View { row(Text(title), value, confidence) }
    private func row(_ title: Text, _ value: String, _ confidence: Confidence?) -> some View {
        HStack {
            title
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
            if let confidence, confidence != .high {
                Image(systemName: confidence == .medium ? "questionmark.circle" : "exclamationmark.circle")
                    .foregroundStyle(confidence == .medium ? .orange : .red)
                    .accessibilityLabel(Text(confidence == .medium ? "confidence.medium" : "confidence.low"))
            }
        }
    }
}
