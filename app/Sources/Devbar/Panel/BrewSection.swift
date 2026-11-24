import SwiftUI
import DevbarCore

struct BrewSection: View {
    let model: PanelModel
    let actions: PanelActions

    var body: some View {
        switch model.brewState {
        case .hidden: EmptyView()
        case .initOnly: EmptyView()
        case .shown:
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Homebrew").bold()
                    Text(model.brewHeadline).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    if !model.brewItems.isEmpty {
                        Button(actions.brewExpanded ? "Nascondi" : "Dettagli") { actions.brewExpanded.toggle() }.controlSize(.small)
                    }
                    Button("Aggiorna") { Task { await actions.run(["run", "brew-upgrade"], refresh: false) } }
                        .controlSize(.small).disabled(!model.brewUpgradeEnabled)
                }
                if actions.brewExpanded {
                    ForEach(model.brewItems, id: \.name) { i in
                        HStack {
                            Text(i.name)
                            Text("\(i.installed ?? "?") → \(i.current ?? "?")").foregroundStyle(.secondary)
                            Spacer()
                            Button("Aggiorna") { Task { await actions.run(["run", "brew-upgrade", i.name], refresh: false) } }
                            Button("Escludi") { Task { await actions.run(["run", "brew-exclude", i.name]) } }
                        }
                        .font(.caption).buttonStyle(.link)
                    }
                }
                Button(model.corkButtonTitle) {
                    if model.corkInstalled {
                        Task { await actions.run(["run", "cork-open"], refresh: false) }
                    } else {
                        Task { await actions.request(.init(title: "Installa Cork", args: ["run", "cork-install"])) }
                    }
                }.controlSize(.small)
            }
        }
    }
}
