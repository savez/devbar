import SwiftUI
import DevbarCore

struct PanelView: View {
    let store: StatusStore
    let actions: PanelActions

    var body: some View {
        let model = PanelModel(all: AllChecks(rows: store.results, raw: store.raw), detect: actions.detect)
        VStack(alignment: .leading, spacing: 10) {
            if store.results.isEmpty {
                Text(store.isRefreshing ? "Controllo in corso…" : "Nessun dato")
                    .foregroundStyle(.secondary)
            } else {
                BrewSection(model: model, actions: actions)
                VulnsSection(model: model, actions: actions)
                if model.colimaState != .hidden { ColimaSection(model: model, actions: actions) }
                if model.showsTokenSection { TokensSection(model: model, actions: actions) }
                if model.showsAISetup { AISetupSection(model: model, actions: actions) }
            }
            Divider()
            FooterBar(store: store, actions: actions)
        }
        .padding(12)
        .frame(width: 380)
        .task {
            await actions.loadDetect()
            await store.panelOpened()
        }
        .confirmationDialog(actions.pending?.title ?? "Conferma",
                            isPresented: Bindable(actions).dialogShown, titleVisibility: .visible) {
            Button("Conferma") { Task { await actions.confirmPending() } }
            Button("Annulla", role: .cancel) { actions.cancelPending() }
        } message: {
            // Solo testo: le righe del piano non vengono mai eseguite.
            Text(actions.plan?.text ?? "")
        }
    }
}

/// Intestazione di sezione.
struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
    }
}

/// Riga "Init <strumento>" per una sezione non configurata.
struct InitButton: View {
    let title: String
    let action: () -> Void
    var body: some View { Button(title, action: action).controlSize(.small) }
}
