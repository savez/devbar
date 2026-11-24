import SwiftUI
import AppKit
import DevbarCore

struct AISetupSection: View {
    let model: PanelModel
    let actions: PanelActions
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: "AI setup")
            // Harness installati ma non gestiti: segnalati, mai toccati. Il clic apre le impostazioni.
            ForEach(model.unmanagedHarnesses, id: \.self) { id in
                HStack {
                    Text("Trovato \(id): gestirlo?").font(.caption)
                    Spacer()
                    Button("Gestisci") {
                        NSApp.activate(ignoringOtherApps: true)
                        openSettings()
                    }.controlSize(.small)
                }
            }
            HStack {
                ForEach(model.aiTools, id: \.self) { t in
                    Button(t) {
                        NSApp.activate(ignoringOtherApps: true)
                        openWindow(id: WindowID.aiSetup)
                        Task { await actions.aiSetup.begin(displayTool: t) }
                    }.controlSize(.small)
                }
            }
            Button("Init progetto") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: WindowID.initProject)
                Task { await actions.projectInit.loadRepos() }
            }.controlSize(.small)
        }
    }
}

enum WindowID {
    static let aiSetup = "ai-setup"
    static let initProject = "init-project"
}
