import SwiftUI
import DevbarCore

struct AISetupSection: View {
    let model: PanelModel
    let actions: PanelActions

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: "AI setup")
            // Harness installati ma non gestiti: segnalati, mai toccati.
            ForEach(model.unmanagedHarnesses, id: \.self) { id in
                HStack {
                    Text("Trovato \(id): gestirlo?").font(.caption)
                    Spacer()
                    Button("Gestisci") { actions.onAdoptHarness(id) }.controlSize(.small)
                }
            }
            HStack {
                ForEach(model.aiTools, id: \.self) { t in
                    Button(t) { actions.onAISetup(t) }.controlSize(.small)
                }
            }
            Button("Init progetto") { actions.onInitProject() }.controlSize(.small)
        }
    }
}
