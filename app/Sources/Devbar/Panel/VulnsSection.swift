import SwiftUI
import DevbarCore

struct VulnsSection: View {
    let model: PanelModel
    let actions: PanelActions

    var body: some View {
        if !model.vulnRows.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Vulnerabilità").bold()
                ForEach(model.vulnRows) { row in
                    HStack {
                        Text(row.title).frame(width: 70, alignment: .leading)
                        Text(row.summary).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        if row.hasDetails {
                            Button(actions.expandedVulns.contains(row.id) ? "Nascondi" : "Dettagli") {
                                if actions.expandedVulns.contains(row.id) { actions.expandedVulns.remove(row.id) } else { actions.expandedVulns.insert(row.id) }
                            }.controlSize(.small)
                        }
                    }
                    if actions.expandedVulns.contains(row.id) { details(row.id) }
                }
                Text("brew: solo formule").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder private func details(_ id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            switch id {
            case "brew":
                ForEach(Array(model.brewVulnItems.enumerated()), id: \.offset) { _, v in
                    Text("\(v.formula)  \(v.severity.lowercased())  \(v.fixAvailable ? "correzione disponibile" : "nessuna correzione")")
                }
            default:
                ForEach(id == "npm" ? model.npmItems : model.composerItems, id: \.repo) { i in
                    HStack {
                        Text(URL(fileURLWithPath: i.repo).lastPathComponent)
                        Text(PanelModel.auditSummary(i)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Apri repo") { Task { await actions.openRepo(i.repo) } }.buttonStyle(.link)
                    }
                }
            }
        }
        .font(.caption).padding(.leading, 12)
    }
}
