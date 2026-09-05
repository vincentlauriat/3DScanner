#if canImport(RoomPlan)
import Foundation
import Observation
import ARKit
import RoomPlan
import AVFoundation

/// Pilote une session RoomPlan : possède l'`ARSession` (injectable, réutilisée
/// entre pièces en v2), la `RoomCaptureView`, et reçoit le résultat.
@Observable
@MainActor
final class ScanCoordinator {
    enum State: Equatable {
        case idle, scanning, processing
        case finished(ScanResult)
        case failed(AppError)
    }

    /// Résultat prêt à être enregistré.
    struct ScanResult: Equatable {
        let scan: ScanInput
        let capturedRoomData: Data
        let usdzData: Data?
        static func == (a: ScanResult, b: ScanResult) -> Bool { a.scan.id == b.scan.id }
    }

    private(set) var state: State = .idle
    let arSession: ARSession
    let captureView: RoomCaptureView
    /// `RoomCaptureViewDelegate` exige `NSCoding` : on le porte par un objet dédié.
    private let delegateProxy = CaptureViewDelegateProxy()

    static var isSupported: Bool { RoomCaptureSession.isSupported }

    init(arSession: ARSession = ARSession()) {
        self.arSession = arSession
        self.captureView = RoomCaptureView(frame: .zero, arSession: arSession)
        delegateProxy.onResult = { [weak self] room, error in
            Task { @MainActor in self?.receive(room: room, error: error) }
        }
        captureView.delegate = delegateProxy
    }

    /// Démarre le scan (demande l'accès caméra si nécessaire).
    func start() {
        guard Self.isSupported else { state = .failed(.unsupportedDevice); return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            state = .failed(.cameraDenied)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in granted ? self.run() : (self.state = .failed(.cameraDenied)) }
            }
        default:
            run()
        }
    }

    private func run() {
        var config = RoomCaptureSession.Configuration()
        config.isCoachingEnabled = true
        state = .scanning
        captureView.captureSession.run(configuration: config)
    }

    /// L'utilisateur termine : RoomPlan post-traite puis appelle `didPresent`.
    func finish() {
        guard state == .scanning else { return }
        state = .processing
        captureView.captureSession.stop()
    }

    func cancel() {
        captureView.captureSession.stop()
        state = .failed(.scanCancelled)
    }

    // MARK: Résultat RoomPlan

    private func receive(room: CapturedRoom?, error: (any Error)?) {
        if let error {
            state = .failed(.scanFailed(Self.describe(error)))
            return
        }
        guard let room else { state = .failed(.scanFailed("no result")); return }
        do {
            let data = try CapturedRoomAdapter.encode(room)
            let usdz = try? CapturedRoomAdapter.usdzData(for: room)
            let scan = CapturedRoomAdapter.scanInput(from: room)
            state = .finished(ScanResult(scan: scan, capturedRoomData: data, usdzData: usdz))
        } catch {
            state = .failed(.scanFailed(error.localizedDescription))
        }
    }

    /// Message humain pour les erreurs RoomPlan les plus fréquentes.
    static func describe(_ error: any Error) -> String {
        let text = String(describing: error)
        let known: [(String, String)] = [
            ("exceedSceneSizeLimit", "error.roomplan.tooLarge"),
            ("lowTexture", "error.roomplan.lowTexture"),
            ("deviceTooHot", "error.roomplan.tooHot"),
            ("worldTrackingFailure", "error.roomplan.trackingLost"),
            ("insufficientInput", "error.roomplan.insufficient"),
            ("deviceNotSupported", "error.unsupportedDevice"),
        ]
        if let (_, key) = known.first(where: { text.contains($0.0) }) {
            return String(localized: String.LocalizationValue(key), bundle: .main)
        }
        return error.localizedDescription
    }
}

/// Delegate de `RoomCaptureView`. Le protocole exige `NSCoding` (la vue est
/// archivable) : on l'implémente à vide, l'objet n'est jamais archivé.
final class CaptureViewDelegateProxy: NSObject, RoomCaptureViewDelegate {
    var onResult: ((CapturedRoom?, (any Error)?) -> Void)?

    override init() { super.init() }
    required init?(coder: NSCoder) { nil }
    func encode(with coder: NSCoder) {}

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: (any Error)?) -> Bool { true }

    func captureView(didPresent processedResult: CapturedRoom, error: (any Error)?) {
        onResult?(processedResult, error)
    }
}
#endif
