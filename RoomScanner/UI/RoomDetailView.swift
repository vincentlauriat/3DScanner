import SwiftUI

/// Détail d'une pièce. Phase 2 : mesures en texte ; plan 2D, visualiseur et
/// exports arrivent en phases 3 à 6.
struct RoomDetailView: View {
    @Environment(RoomStore.self) private var store
    let record: RoomRecord
    @State private var plan: FloorPlan?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let plan {
                MeasuresView(plan: plan)
            } else if let loadError {
                ContentUnavailableView(loadError, systemImage: "exclamationmark.triangle")
            } else {
                ProgressView()
            }
        }
        .navigationTitle(record.name)
        .task(id: record.id) {
            do { plan = try store.plan(for: record) } catch { loadError = error.localizedDescription }
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
                    ForEach(m.openings) { o in
                        row(openingName(o.kind), openingText(o), o.confidence)
                    }
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

    private func row(_ title: LocalizedStringKey, _ value: String, _ confidence: Confidence? = nil) -> some View {
        row(Text(title), value, confidence)
    }
    private func row(_ title: String, _ value: String, _ confidence: Confidence? = nil) -> some View {
        row(Text(title), value, confidence)
    }
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

/// Libellés localisés des catégories d'objets RoomPlan (`table`, `sofa`, …).
enum ObjectNaming {
    static func localizedName(_ category: String) -> String {
        let key = "object.\(category)"
        let s = String(localized: String.LocalizationValue(key), bundle: .main)
        return s == key ? category.capitalized : s
    }
}
