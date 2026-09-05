#if canImport(RoomPlan)
import SwiftUI

/// Écran de scan plein écran : guidage Apple, Annuler / Terminer, traitement,
/// puis enregistrement dans le `RoomStore` et retour à la liste.
/// Mode maison : « Pièce suivante » enchaîne les pièces dans le même repère, « Terminer la maison »
/// fusionne et enregistre un `.housescan`.
struct ScanView: View {
    @Environment(RoomStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var coordinator: ScanCoordinator
    @State private var saveError: AppError?
    let mode: ScanMode
    /// Élément créé (pièce ou maison), transmis à l'appelant pour l'ouvrir.
    var onSaved: (LibraryItem) -> Void

    init(mode: ScanMode = .room, onSaved: @escaping (LibraryItem) -> Void = { _ in }) {
        self.mode = mode
        self.onSaved = onSaved
        _coordinator = State(initialValue: ScanCoordinator(mode: mode))
    }

    var body: some View {
        ZStack {
            switch coordinator.state {
            case .failed(.cameraDenied):
                CameraDeniedView(onClose: { dismiss() })
            case .failed(.unsupportedDevice):
                UnsupportedDeviceView(onClose: { dismiss() })
            default:
                RoomCaptureViewRepresentable(coordinator: coordinator)
                    .ignoresSafeArea()
                overlay
            }
        }
        .onAppear { coordinator.start() }
        .onChange(of: coordinator.state) { _, state in handle(state) }
        .alert(item: $saveError) { error in
            Alert(title: Text("scan.error.title"), message: Text(error.localizedDescription),
                  dismissButton: .default(Text("common.ok")) { dismiss() })
        }
    }

    @ViewBuilder private var overlay: some View {
        VStack {
            HStack {
                Button(role: .cancel) { coordinator.cancel(); dismiss() } label: { Text("common.cancel") }
                    .buttonStyle(.bordered)
                Spacer()
                if mode == .house {
                    Text("scan.house.room \(coordinator.capturedRooms.count + 1)")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                    Spacer()
                }
                Button { coordinator.finish() } label: { Text(mode == .house ? "scan.finishRoom" : "scan.finish") }
                    .buttonStyle(.borderedProminent)
                    .disabled(coordinator.state != .scanning)
            }
            .padding()
            Spacer()
        }
        switch coordinator.state {
        case .processing, .merging:
            VStack(spacing: 12) {
                ProgressView()
                Text(coordinator.state == .merging ? "scan.merging" : "scan.processing")
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        case .roomCaptured(let count):
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
                Text("scan.house.captured \(count)").font(.headline)
                Text("scan.house.hint").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button { coordinator.nextRoom() } label: { Label("scan.nextRoom", systemImage: "arrow.right.circle") }
                    .buttonStyle(.borderedProminent)
                Button { coordinator.finishHouse() } label: { Label("scan.finishHouse", systemImage: "house.fill") }
                    .buttonStyle(.bordered)
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        default:
            EmptyView()
        }
    }

    private func handle(_ state: ScanCoordinator.State) {
        switch state {
        case .finished(let result):
            do {
                let name = store.proposedName(for: result.scan.sectionLabels.first ?? .unidentified)
                let plan = FloorPlanBuilder().build(from: result.scan, name: name)
                let package = RoomPackage(record: RoomRecord(plan: plan), plan: plan, scan: result.scan,
                                          capturedRoomData: result.capturedRoomData, usdzData: result.usdzData, usdzMeshData: result.usdzMeshData,
                                          thumbnailPNG: PlanRenderer.thumbnailPNG(for: plan))
                let record = try store.save(package)
                onSaved(.room(record))
                dismiss()
            } catch {
                saveError = .storageFailed(error.localizedDescription)
            }
        case .finishedHouse(let result):
            do {
                let extras = result.rooms.mapValues { HousePackage.RoomExtras(capturedRoomData: $0.capturedRoomData, usdzData: $0.usdzData, usdzMeshData: $0.usdzMeshData) }
                let package = HousePackage.assemble(structure: result.structure, name: store.proposedHouseName(),
                                                    capturedStructureData: result.capturedStructureData, usdzData: result.usdzData, roomExtras: extras)
                let record = try store.saveHouse(package)
                onSaved(.house(record))
                dismiss()
            } catch {
                saveError = .storageFailed(error.localizedDescription)
            }
        case .failed(let error) where error != .scanCancelled && error != .cameraDenied && error != .unsupportedDevice:
            saveError = error
        default:
            break
        }
    }
}

extension AppError: Identifiable {
    var id: String { localizedDescription }
}
#endif
