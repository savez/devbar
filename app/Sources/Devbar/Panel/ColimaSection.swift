import SwiftUI
import DevbarCore

struct ColimaSection: View {
    let model: PanelModel
    let actions: PanelActions

    var body: some View {
        switch model.colimaState {
        case .hidden: EmptyView()
        case .initOnly:
            HStack {
                Text("colima").bold()
                Spacer()
                InitButton(title: "Init colima") {
                    Task { await actions.request(.init(title: "Installa colima", args: ["run", "colima-install"])) }
                }
            }
        case .shown:
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("colima").bold()
                    Image(systemName: "circle.fill").font(.system(size: 7))
                        .foregroundStyle(model.colimaRunning ? .green : .secondary)
                    Text(model.colimaSummary).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button(model.colimaToggleTitle) {
                        let verb = model.colimaRunning ? "colima-stop" : "colima-start"
                        var args = ["run", verb]
                        if let p = model.colimaProfile, p != "default" { args.append(p) }
                        Task { await actions.run(args) }
                    }.controlSize(.small)
                }
                ForEach(model.colimaContainers, id: \.id) { c in
                    HStack {
                        Text(c.name)
                        Text("\(c.cpu) \(c.mem)").foregroundStyle(.secondary)
                        Spacer()
                        Button("Log") { Task { await actions.run(["run", "colima-logs", c.id], refresh: false) } }
                        Button("Ferma") { Task { await actions.run(["run", "container-stop", c.id]) } }
                    }
                    .font(.caption).buttonStyle(.link)
                }
            }
        }
    }
}
