import Foundation
import Observation
import DevbarCore

/// Azioni del pannello: esegue solo la CLI. I piani si mostrano, non si eseguono.
@Observable @MainActor
final class PanelActions {
    let store: StatusStore
    private(set) var detect: DetectResult?
    /// Sezioni con un'azione in corso, condivise con i moduli (vedi `SectionLocks`).
    let locks = SectionLocks()
    /// Azione in attesa di conferma, con il piano restituito dalla CLI (senza --yes).
    var pending: ConfirmableAction?
    private(set) var plan: ActionPlan?
    var dialogShown = false
    /// Chi mostra la conferma: il pannello o la finestra Dettagli (solo quella che l'ha chiesta).
    private(set) var dialogOrigin: DialogOrigin = .panel
    /// Stato della finestra Dettagli (`@State` non è disponibile, vedi DevbarApp).
    var detailsArea: Area? = .homebrew
    var vulnFilter: VulnFilter = .all
    var brewSort: [KeyPathComparator<BrewDetailRow>] = [KeyPathComparator(\.name)]
    var vulnSort: [KeyPathComparator<VulnDetailRow>] = []
    var auditSort: [KeyPathComparator<AuditDetailRow>] = []
    private(set) var lastError: String?
    /// Finestre AI setup, Init progetto e impostazioni: ognuna con la sua conferma
    /// (stesso schema request/confirm del pannello, in `PlanConfirmation`).
    let aiSetup: AISetupModel
    let projectInit: ProjectInitModel
    let settings: SettingsModel
    /// Riga caveman del pannello: scrive la modalità di default (esecuzione diretta).
    let caveman: CavemanControl
    /// Aree come moduli a sé (logica e stato propri): per ora solo colima.
    let colima: ColimaFeature
    var features: [any Feature] { [colima] }

    init(store: StatusStore, configStore: ConfigStore = ConfigStore()) {
        self.store = store
        aiSetup = AISetupModel(runner: store)
        caveman = CavemanControl(runner: store)
        projectInit = ProjectInitModel(runner: store)
        settings = SettingsModel(configStore: configStore, runner: store, login: LaunchAgentManager())
        colima = ColimaFeature(runner: store, locks: locks)
        colima.confirm = { [weak self] action, origin in await self?.request(action, from: origin) }
        colima.onApplied = { [store] in await store.refresh(force: false) }
        colima.onError = { [weak self] in self?.lastError = $0 }
        let all = AllChecks(rows: store.results, raw: store.raw)
        for f in features { f.update(from: all) }
        store.onResults = { [weak self] all in self?.features.forEach { $0.update(from: all) } }
        aiSetup.onApplied = { [weak self] in await self?.refreshAfterChange(force: true) }
        caveman.onApplied = { [weak self] in await self?.refreshAfterChange(force: true) }
        settings.onSaved = { [store] in store.reloadConfig() }
        settings.onApplied = { [weak self] in await self?.refreshAfterChange(force: false) }
    }

    private func refreshAfterChange(force: Bool) async {
        store.reloadConfig()
        await store.refresh(force: force)
        await loadDetect()
    }

    func loadDetect() async {
        let r = await store.run(action: ["detect"])
        if let d = try? JSONDecoder().decode(DetectResult.self, from: r.stdout) { detect = d }
    }

    func isRunning(_ section: String) -> Bool { locks.isRunning(section) }

    /// Azione non distruttiva (avvia/ferma, apri): lancia e poi aggiorna.
    func run(_ args: [String], refresh: Bool = true) async {
        var r: (rc: Int32, stdout: Data) = (0, Data())
        guard await locks.occupy(args, { r = await store.run(action: args) }) else { return }
        lastError = SectionLocks.directError(args, rc: r.rc)
        if refresh { await store.refresh(force: false) }
    }

    /// Passo 1: senza --yes per ottenere il piano; poi la vista chiede conferma.
    func request(_ action: ConfirmableAction, from origin: DialogOrigin = .panel) async {
        guard ActionSection.of(action.args).map({ !locks.isRunning($0) }) ?? true else { return }
        let r = await store.run(action: action.args)
        guard r.rc < 2 else { lastError = "\(action.title): piano non disponibile (rc \(r.rc))"; return }
        plan = ActionPlan.parse(r.stdout)
        pending = action
        dialogOrigin = origin
        dialogShown = true
    }

    /// Passo 2: dopo conferma, con --yes.
    func confirmPending() async {
        guard let a = pending else { return }
        pending = nil; plan = nil
        var r: (rc: Int32, stdout: Data) = (0, Data())
        guard await locks.occupy(a.args, { r = await store.run(action: a.confirmedArgs) }) else { return }
        lastError = r.rc >= 2
            ? "\(a.title): " + (PlanConfirmation.engineError(r.stdout) ?? "fallito (rc \(r.rc))") : nil
        await store.refresh(force: true)
        await loadDetect()
    }

    func cancelPending() { pending = nil; plan = nil }

    func openRepo(_ path: String) async { await run(["run", "open-terminal", path], refresh: false) }
}
