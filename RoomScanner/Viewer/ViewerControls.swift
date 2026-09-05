import SwiftUI

/// Barre de contrôle du visualiseur : mode, cotes, objets, échelle AR, recentrer, Aperçu rapide.
struct ViewerControls: View {
    @Bindable var state: ViewerState
    var usdzURL: URL?
    @State private var showQuickLook = false

    var body: some View {
        HStack(spacing: 12) {
            Picker("viewer.mode", selection: $state.mode) {
                ForEach(ViewerMode.available) { mode in Text(LocalizedStringKey(mode.titleKey)).tag(mode) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)
            if state.mode == .ar {
                Picker("viewer.arScale", selection: $state.arScale) {
                    ForEach(ARScale.allCases) { s in Text(s.label).tag(s) }
                }
                .pickerStyle(.menu)
            }
            Spacer(minLength: 0)
            Toggle(isOn: $state.showDimensions) { Image(systemName: "ruler") }
                .toggleStyle(.button).help(Text("viewer.dimensions"))
            Toggle(isOn: $state.showObjects) { Image(systemName: "chair.lounge") }
                .toggleStyle(.button).help(Text("viewer.objects"))
            Button { state.resetToken += 1 } label: { Image(systemName: "scope") }
                .help(Text("viewer.recenter"))
            if let usdzURL {
                Button { showQuickLook = true } label: { Image(systemName: "arkit") }
                    .help(Text("viewer.quicklook"))
                    .quickLookPreview(usdzURL, isPresented: $showQuickLook)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

private extension View {
    /// Aperçu rapide (QuickLook) d'un fichier — iOS : `quickLookPreview` natif ; macOS : QLPreviewPanel via `NSWorkspace`.
    @ViewBuilder
    func quickLookPreview(_ url: URL, isPresented: Binding<Bool>) -> some View {
        #if os(iOS)
        self.quickLookPreview(isPresented.wrappedValue ? url : nil, onDismiss: { isPresented.wrappedValue = false })
        #else
        self.onChange(of: isPresented.wrappedValue) { _, shown in
            if shown { NSWorkspace.shared.open(url); isPresented.wrappedValue = false }
        }
        #endif
    }

    #if os(iOS)
    func quickLookPreview(_ url: URL?, onDismiss: @escaping () -> Void) -> some View {
        modifier(QuickLookModifier(url: url, onDismiss: onDismiss))
    }
    #endif
}

#if os(iOS)
import QuickLook

private struct QuickLookModifier: ViewModifier {
    let url: URL?
    let onDismiss: () -> Void
    @State private var item: URL?
    func body(content: Content) -> some View {
        content
            .onChange(of: url) { _, new in item = new }
            .quickLookPreview($item)
            .onChange(of: item) { _, new in if new == nil { onDismiss() } }
    }
}
#endif
