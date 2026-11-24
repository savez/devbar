import SwiftUI
import AppKit
import DevbarCore

struct FooterBar: View {
    let store: StatusStore
    let actions: PanelActions
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let s = PanelModel.footerStatus(engineBusy: store.engineBusy, refreshError: store.refreshError,
                                               isRefreshing: store.isRefreshing) ?? actions.lastError {
                Text(s).font(Typo.note).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(spacing: 14) {
                Button("Impostazioni") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                Spacer()
                Button("Ricontrolla") { Task { await store.refresh(force: true) } }
                    .disabled(store.isRefreshing)
                    .help("Rilancia tutti i controlli ignorando la cache")
                Button("Esci") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.link)
            .font(.system(size: 12))
        }
        .padding(.top, 8)
    }
}
