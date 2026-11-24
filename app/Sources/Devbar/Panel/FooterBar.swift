import SwiftUI
import AppKit
import DevbarCore

struct FooterBar: View {
    let store: StatusStore
    let actions: PanelActions
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let s = PanelModel.footerStatus(engineBusy: store.engineBusy, refreshError: store.refreshError,
                                               isRefreshing: store.isRefreshing) ?? actions.lastError {
                Text(s).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack {
                Button("⚙ Impostazioni") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                Spacer()
                Button("Aggiorna") { Task { await store.refresh(force: true) } }
                    .disabled(store.isRefreshing)
                Button("Esci") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.link)
        }
    }
}
