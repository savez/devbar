import SwiftUI
import DevbarCore

/// Riga colima del pannello: stato e risorse, Avvia/Ferma o Init.
struct ColimaRow: View {
    let feature: ColimaFeature
    let open: DetailsOpener

    var body: some View {
        let p = feature.panel
        let r = p.readout
        let busy = feature.busy
        switch p.kind {
        case .hidden: EmptyView()
        case .initOnly:
            ReadoutRow(title: "colima", subtitle: r.subtitle, busy: busy, content: { EmptyView() }, accessory: {
                Button("Init colima") {
                    Task { await feature.installColima(from: .panel) }
                }.controlSize(.small).disabled(busy)
            })
        case .shown:
            ReadoutRow(title: "colima", subtitle: r.subtitle, note: r.note, readout: r.value, tone: r.tone, busy: busy,
                       onDetails: { open(.colima) }, content: { EmptyView() }, accessory: {
                Button(p.toggleTitle) {
                    Task { await feature.toggle() }
                }.controlSize(.small).disabled(busy)
            })
        }
    }
}
