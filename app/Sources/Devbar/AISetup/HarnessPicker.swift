import SwiftUI
import DevbarCore

/// Finestra "AI setup" per uno strumento: stato per harness e Installa / Aggiorna.
struct HarnessPicker: View {
    let model: AISetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.tool.isEmpty ? "AI setup" : "AI setup: \(model.tool)").font(.headline)
            content
            // azione lunga in background (fino a 600 s): poi lo stato si ricarica
            if model.confirmation.busy { Text("in corso…").font(.caption).foregroundStyle(.secondary) }
            if let e = model.confirmation.error { Text(e).font(.caption).foregroundStyle(.red) }
        }
        .padding(16)
        .frame(minWidth: 380, minHeight: 200, alignment: .topLeading)
        .confirmationDialog(model.confirmation.title, isPresented: Bindable(model.confirmation).dialogShown,
                            titleVisibility: .visible) {
            Button("Conferma") { Task { await model.confirm() } }
            Button("Annulla", role: .cancel) { model.confirmation.cancel() }
        } message: {
            // Solo testo: le righe del piano non vengono mai eseguite.
            Text(model.confirmation.text)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle: Text("Scegli uno strumento dal pannello.").foregroundStyle(.secondary)
        case .loading: Text("Lettura dello stato…").foregroundStyle(.secondary)
        case .failed(let m): Text(m).foregroundStyle(.red)
        case .ready: ready
        }
    }

    @ViewBuilder private var ready: some View {
        if model.toolMissing {
            Text("\(model.tool) non è installato.").font(.callout)
            if model.canInstallBinary {
                Button("Installa \(model.tool)") { Task { await model.requestBinaryInstall() } }
            }
        } else if model.rows.isEmpty {
            Text("Nessun harness supportato trovato.").foregroundStyle(.secondary)
        } else {
            if model.choosingHarnesses {
                Text("Quali harness vuoi gestire?").font(.callout)
            }
            ForEach(model.rows) { row in
                HStack {
                    Toggle(row.id, isOn: binding(row)).disabled(!row.selectable)
                    Spacer()
                    Text(row.stateLabel).font(.caption).foregroundStyle(.secondary)
                    if let l = row.actionLabel { Text(l).font(.caption2).foregroundStyle(.tint) }
                }
            }
            HStack {
                Spacer()
                Button(installTitle) { Task { await model.requestInstall() } }
                    .disabled(!model.canInstall)
            }
        }
    }

    private var installTitle: String {
        let labels = Set(model.rows.filter { model.chosenIDs.contains($0.id) }.compactMap(\.actionLabel))
        return labels == ["Aggiorna"] ? "Aggiorna" : "Installa"
    }

    private func binding(_ row: HarnessRow) -> Binding<Bool> {
        Binding(get: { model.selected.contains(row.id) },
                set: { on in if on { model.selected.insert(row.id) } else { model.selected.remove(row.id) } })
    }
}
