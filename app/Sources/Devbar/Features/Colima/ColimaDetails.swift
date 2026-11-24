import SwiftUI
import DevbarCore

/// Area colima dei Dettagli: profili (Avvia/Ferma) e container attivi (Log, Ferma).
struct ColimaDetails: View {
    let feature: ColimaFeature

    var body: some View {
        let p = feature.panel
        let busy = feature.busy
        switch p.kind {
        case .hidden:
            EmptyArea(title: "colima", message: "colima non è disponibile.")
        case .initOnly:
            VStack(spacing: 12) {
                EmptyArea(title: "colima non installato", message: "Installa colima per eseguire container Docker.")
                Button("Init colima") {
                    Task { await feature.installColima(from: .details) }
                }.disabled(busy)
            }
        case .shown:
            VStack(alignment: .leading, spacing: 0) {
                section("Profili")
                Table(p.profileRows) {
                    TableColumn("Profilo", value: \.name).width(min: 80, ideal: 120)
                    TableColumn("Stato") { r in
                        HStack(spacing: 6) {
                            Circle().fill(r.running ? Tone.ok.color : Tone.info.color).frame(width: 7, height: 7)
                            Text(r.status)
                        }
                    }
                    TableColumn("CPU") { Text("\($0.cpus)").monospacedDigit() }.width(40)
                    TableColumn("Memoria", value: \.memory).width(70)
                    TableColumn("Disco", value: \.disk).width(70)
                    TableColumn("") { r in
                        Button(r.running ? "Ferma" : "Avvia") {
                            Task { await feature.toggle(r) }
                        }
                        .buttonStyle(.link).disabled(busy)
                    }
                    .width(60)
                }
                .frame(height: CGFloat(28 + 24 * max(1, p.profileRows.count)) + 8)
                section("Container")
                if p.containerRows.isEmpty {
                    Text(p.running ? "Nessun container attivo." : "colima è spento.")
                        .font(Typo.note).foregroundStyle(.secondary)
                        .padding(.horizontal, 12).padding(.bottom, 12)
                    Spacer()
                } else {
                    Table(p.containerRows) {
                        TableColumn("Nome", value: \.name)
                        TableColumn("CPU", value: \.cpu).width(70)
                        TableColumn("Memoria", value: \.mem).width(90)
                        TableColumn("") { c in
                            HStack(spacing: 10) {
                                Button("Log") { Task { await feature.openLogs(c.id) } }
                                Button("Ferma") { Task { await feature.stopContainer(c.id) } }
                                    .disabled(busy)
                            }
                            .buttonStyle(.link)
                        }
                        .width(90)
                    }
                }
            }
            .toolbar {
                if busy { ToolbarItem { Text("in corso…").font(Typo.note).foregroundStyle(.secondary) } }
            }
        }
    }

    private func section(_ t: String) -> some View {
        Text(t).font(Typo.title)
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 6)
    }
}
