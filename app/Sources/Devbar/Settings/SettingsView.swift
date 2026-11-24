import SwiftUI
import DevbarCore

struct SettingsView: View {
    let model: SettingsModel

    var body: some View {
        Form {
            if let e = model.configError {
                Section {
                    Text(e).foregroundStyle(.red)
                    Text("Le modifiche non vengono salvate finché non confermi di sovrascrivere la config.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let e = model.saveError { Text(e).foregroundStyle(.red) }

            Section("Cartelle dei repo") {
                ForEach(model.config.repoRoots, id: \.self) { r in
                    HStack {
                        Text(r).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Rimuovi") { model.removeRoot(r) }.buttonStyle(.link)
                    }
                }
                Button("Aggiungi cartella…") {
                    model.addRoots(FolderPicker.choose(multiple: true, prompt: "Aggiungi"))
                }
                Stepper("Profondità: \(model.config.scanDepth)",
                        value: Binding(get: { model.config.scanDepth }, set: { model.setDepth($0) }),
                        in: SettingsModel.depthRange)
            }

            Section("Controllo giornaliero") {
                DatePicker("Orario", selection: timeBinding, displayedComponents: .hourAndMinute)
            }

            Section("Harness gestiti") {
                ForEach(model.harnessRows, id: \.id) { h in
                    Toggle(isOn: Binding(get: { h.checked },
                                         set: { on in Task { await model.setHarness(h.id, on: on) } })) {
                        Text(h.installed ? h.id : "\(h.id) (non trovato)")
                    }
                }
                if model.harnessRows.isEmpty { Text("Nessun harness trovato.").foregroundStyle(.secondary) }
            }

            Section("Pacchetti brew esclusi") {
                ForEach(model.config.brewExclude, id: \.self) { p in
                    HStack {
                        Text(p)
                        Spacer()
                        Button("Rimuovi") { model.removeExclude(p) }.buttonStyle(.link)
                    }
                }
                HStack {
                    TextField("Pacchetto", text: Bindable(model).newExclude).onSubmit { model.addExclude() }
                    Button("Aggiungi") { model.addExclude() }
                }
            }

            Section("Terminale") {
                Picker("Terminale", selection: Binding(get: { model.config.terminal }, set: { model.setTerminal($0) })) {
                    ForEach(SettingsModel.terminals, id: \.self) { Text($0).tag($0) }
                }
            }

            Section("Avvio") {
                Toggle("Avvio al login", isOn: Binding(get: { model.config.launchAtLogin },
                                                       set: { model.setLaunchAtLogin($0) }))
                if let e = model.loginError { Text(e).font(.caption).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 560)
        .task { await model.load() }
        .onDisappear { Task { await model.didClose() } }
        .confirmationDialog("Sovrascrivere la config non valida?", isPresented: Bindable(model).overwritePromptShown,
                            titleVisibility: .visible) {
            Button("Sovrascrivi", role: .destructive) { Task { await model.confirmOverwrite() } }
            Button("Annulla", role: .cancel) { model.cancelOverwrite() }
        } message: {
            Text("Il file config.json non è leggibile: salvando, il suo contenuto viene sostituito dalle impostazioni mostrate.")
        }
        .confirmationDialog(model.confirmation.title, isPresented: Bindable(model.confirmation).dialogShown,
                            titleVisibility: .visible) {
            Button("Conferma") { Task { await model.confirmInstalls() } }
            Button("Annulla", role: .cancel) { model.confirmation.cancel() }
        } message: {
            // Solo testo: i comandi non vengono eseguiti da qui.
            Text(model.confirmation.text)
        }
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                let p = model.dailyTimeParts
                return Calendar.current.date(bySettingHour: p.hour, minute: p.minute, second: 0, of: Date()) ?? Date()
            },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                model.setDailyTime(hour: c.hour ?? 9, minute: c.minute ?? 0)
            })
    }
}
