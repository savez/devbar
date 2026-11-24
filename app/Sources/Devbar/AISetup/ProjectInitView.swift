import SwiftUI
import DevbarCore

/// Finestra "Init progetto": repo trovati, "Scegli cartella…", stato e Applica.
struct ProjectInitView: View {
    let model: ProjectInitModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Init progetto").font(.headline)
            HStack {
                Menu(model.selected.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Scegli un repo") {
                    ForEach(model.repos, id: \.path) { r in
                        Button(r.name) { Task { await model.select(r.path) } }
                    }
                }
                Button("Scegli cartella…") {
                    if let p = FolderPicker.choose(multiple: false, prompt: "Scegli").first {
                        Task { await model.select(p) }
                    }
                }
            }
            if let s = model.selected { Text(s).font(.caption).foregroundStyle(.secondary) }
            if model.loading { Text("Controllo…").foregroundStyle(.secondary) }
            if let e = model.error { Text(e).foregroundStyle(.red) }
            ForEach(model.rows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Image(systemName: row.ok ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(row.ok ? .green : .orange)
                        Text(row.tool).bold()
                        Text(row.detail).font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(row.willWrite, id: \.self) { w in
                        Text(w).font(.caption.monospaced()).foregroundStyle(.secondary).padding(.leading, 22)
                    }
                }
            }
            // azione lunga in background (fino a 600 s): poi lo stato si ricarica
            if model.confirmation.busy { Text("in corso…").font(.caption).foregroundStyle(.secondary) }
            if let e = model.confirmation.error { Text(e).font(.caption).foregroundStyle(.red) }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Applica") { Task { await model.requestApply() } }.disabled(!model.canApply)
            }
        }
        .padding(16)
        .frame(minWidth: 460, minHeight: 280, alignment: .topLeading)
        .confirmationDialog(model.confirmation.title, isPresented: Bindable(model.confirmation).dialogShown,
                            titleVisibility: .visible) {
            Button("Conferma") { Task { await model.confirmApply() } }
            Button("Annulla", role: .cancel) { model.confirmation.cancel() }
        } message: {
            // Solo testo: i file elencati sono quelli che verrebbero scritti.
            Text("Verranno creati o modificati:\n" + model.confirmation.text)
        }
    }
}
