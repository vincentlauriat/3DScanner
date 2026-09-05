#if canImport(RoomPlan)
import SwiftUI

/// Écran de scan plein écran : guidage Apple, Annuler / Terminer, traitement,
/// puis enregistrement dans le `RoomStore` et retour à la liste.
struct ScanView: View {
    @Environment(RoomStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var coordinator = ScanCoordinator()
    @State private var saveError: AppError?
    /// Identifiant de la pièce créée, transmis à l'appelant pour l'ouvrir.
    var onSaved: (RoomRecord) -> Void = { _ in }

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
                Button { coordinator.finish() } label: { Text("scan.finish") }
                    .buttonStyle(.borderedProminent)
                    .disabled(coordinator.state != .scanning)
            }
            .padding()
            Spacer()
        }
        if coordinator.state == .processing {
            VStack(spacing: 12) {
                ProgressView()
                Text("scan.processing")
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func handle(_ state: ScanCoordinator.State) {
        switch state {
        case .finished(let result):
            do {
                let name = store.proposedName(for: result.scan.sectionLabels.first ?? .unidentified)
                let plan = FloorPlanBuilder().build(from: result.scan, name: name)
                let package = RoomPackage(record: RoomRecord(plan: plan), plan: plan, scan: result.scan,
                                          capturedRoomData: result.capturedRoomData, usdzData: result.usdzData)
                let record = try store.save(package)
                onSaved(record)
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
