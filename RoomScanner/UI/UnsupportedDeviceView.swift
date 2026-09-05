import SwiftUI

/// Appareil sans LiDAR / RoomPlan indisponible.
struct UnsupportedDeviceView: View {
    var onClose: (() -> Void)? = nil
    var body: some View {
        ContentUnavailableView {
            Label("unsupported.title", systemImage: "iphone.slash")
        } description: {
            Text("unsupported.message")
        } actions: {
            if let onClose { Button("common.close", action: onClose) }
        }
    }
}
