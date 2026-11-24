import Foundation
import Observation
import DevbarCore

/// Azioni del pannello: esegue solo la CLI. I piani si mostrano, non si eseguono.
@Observable @MainActor
final class PanelActions {
    let store: StatusStore
    private(set) var detect: DetectResult?
    private(set) var busy = false
    /// Azione in attesa di conferma, con il piano restituito dalla CLI (senza --yes).
    var pending: ConfirmableAction?
    private(set) var plan: ActionPlan?
    var dialogShown = false
    /// Stato di espansione delle liste dettagli (`@State` non è disponibile, vedi DevbarApp).
    var brewExpanded = false
    var expandedVulns: Set<String> = []
    private(set) var lastError: String?
    /// Task 14 collega qui i flussi AI setup (strumento) e Init progetto.
    var onAISetup: (String) -> Void = { _ in }
    var onInitProject: () -> Void = {}
    var onAdoptHarness: (String) -> Void = { _ in }

    init(store: StatusStore) { self.store = store }

    func loadDetect() async {
        let r = await store.run(action: ["detect"])
        if let d = try? JSONDecoder().decode(DetectResult.self, from: r.stdout) { detect = d }
    }

    /// Azione non distruttiva (avvia/ferma, apri): lancia e poi aggiorna.
    func run(_ args: [String], refresh: Bool = true) async {
        busy = true; defer { busy = false }
        let r = await store.run(action: args)
        lastError = r.rc >= 2 ? "\(args.prefix(2).joined(separator: " ")): errore (rc \(r.rc))" : nil
        if refresh { await store.refresh(force: false) }
    }

    /// Passo 1: senza --yes per ottenere il piano; poi la vista chiede conferma.
    func request(_ action: ConfirmableAction) async {
        busy = true; defer { busy = false }
        let r = await store.run(action: action.args)
        guard r.rc < 2 else { lastError = "\(action.title): piano non disponibile (rc \(r.rc))"; return }
        plan = ActionPlan.parse(r.stdout)
        pending = action
        dialogShown = true
    }

    /// Passo 2: dopo conferma, con --yes.
    func confirmPending() async {
        guard let a = pending else { return }
        pending = nil; plan = nil
        busy = true; defer { busy = false }
        let r = await store.run(action: a.confirmedArgs)
        lastError = r.rc >= 2 ? "\(a.title): fallito (rc \(r.rc))" : nil
        await store.refresh(force: true)
        await loadDetect()
    }

    func cancelPending() { pending = nil; plan = nil }

    func openRepo(_ path: String) async { await run(["run", "open-terminal", path], refresh: false) }
}
