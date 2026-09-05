#if canImport(RoomPlan)
import SwiftUI
import RoomPlan

/// Héberge la `RoomCaptureView` UIKit du coordinateur dans SwiftUI.
struct RoomCaptureViewRepresentable: UIViewRepresentable {
    let coordinator: ScanCoordinator

    func makeUIView(context: Context) -> RoomCaptureView { coordinator.captureView }
    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}
#endif
