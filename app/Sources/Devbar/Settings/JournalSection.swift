import SwiftUI
import DevbarCore

/// "Ultime modifiche": file di altri programmi scritti da devbar, con "Annulla".
/// Caricamento e conferma (piano di `devbar undo`) sono su SettingsView: i modificatori di
/// una Section in un Form raggruppato finirebbero su ogni riga.
struct JournalSection: View {
    let model: JournalModel

    var body: some View {
        Section("Ultime modifiche") {
            if let e = model.error { Text(e).font(.caption).foregroundStyle(.red) }
            ForEach(model.entries) { e in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.title).lineLimit(1).truncationMode(.middle)
                        Text("\(JournalEntry.timeText(e.time)) · \(e.filesText)")
                            .font(.caption).foregroundStyle(.secondary)
                        if e.hasChanges && e.canUndo {
                            Text("Un file è stato cambiato da un altro programma dopo devbar.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                    if e.undone {
                        Text("annullata").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("Annulla") { Task { await model.requestUndo(e) } }
                            .buttonStyle(.link)
                            .disabled(model.confirmation.busy)
                    }
                }
            }
            if model.entries.isEmpty && model.error == nil {
                Text("Nessuna modifica registrata.").foregroundStyle(.secondary)
            }
            if model.confirmation.busy { Text("in corso…").font(.caption).foregroundStyle(.secondary) }
            if let e = model.confirmation.error { Text(e).font(.caption).foregroundStyle(.red) }
        }
    }
}
