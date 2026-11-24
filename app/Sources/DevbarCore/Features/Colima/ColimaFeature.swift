import Foundation
import Observation

/// Area colima: stato (da `check all`) e azioni. Le azioni dirette passano dal runner comune
/// (`StatusStore`) e occupano la sezione dichiarata in `actions` nei `SectionLocks` condivisi,
/// così non partono due `colima start`; l'installazione passa dalla conferma comune dell'host.
@Observable @MainActor
public final class ColimaFeature: Feature {
    public let areas: [Area] = [.colima]
    public private(set) var panel: ColimaPanel

    /// `colima-*` e `container-*` occupano "colima"; avvio e arresto restano in background.
    public nonisolated static let actions = FeatureActionSpec(
        section: "colima", verbPrefixes: ["colima-", "container-"], longVerbs: ["colima-start", "colima-stop"])

    @ObservationIgnored private let runner: any ActionRunning
    @ObservationIgnored private let locks: SectionLocks
    /// `unowned`: l'host (PanelActions) possiede il modulo.
    @ObservationIgnored private unowned let host: any FeatureHost

    public init(runner: any ActionRunning, locks: SectionLocks, host: any FeatureHost) {
        self.runner = runner
        self.locks = locks
        self.host = host
        panel = ColimaPanel(all: AllChecks(rows: [:], raw: [:]))
    }

    // MARK: Feature

    /// Sezione informativa: sempre ardesia.
    public func tone(of area: Area) -> Tone { .info }
    public var readout: Readout? {
        guard panel.kind != .hidden else { return nil }
        var r = panel.readout
        r.tone = tone(of: .colima)
        return r
    }

    public func update(from input: FeatureInput) {
        let p = ColimaPanel(all: input.all)
        if p != panel { panel = p }
    }

    // MARK: Azioni

    /// Un'azione colima è in corso (anche l'installazione confermata).
    public var busy: Bool { locks.isRunning(Self.actions.section) }

    /// Avvia o ferma il profilo del pannello.
    public func toggle() async {
        await run(ColimaPanel.toggleArgs(running: panel.running, profile: panel.profile), refresh: true)
    }

    /// Avvia o ferma un profilo della tabella dei Dettagli.
    public func toggle(_ row: ColimaProfileRow) async {
        await run(ColimaPanel.toggleArgs(running: row.running, profile: row.name), refresh: true)
    }

    public func stopContainer(_ id: String) async { await run(["run", "container-stop", id], refresh: true) }

    /// Apre i log nel terminale: niente da ricontrollare.
    public func openLogs(_ id: String) async { await run(["run", "colima-logs", id], refresh: false) }

    public func installColima(from origin: DialogOrigin = .panel) async {
        await host.request(ConfirmableAction(title: "Installa colima", args: ["run", "colima-install"]), from: origin)
    }

    private func run(_ args: [String], refresh: Bool) async {
        var r: (rc: Int32, stdout: Data) = (0, Data())
        guard await locks.occupy(args, { r = await runner.run(action: args) }) else { return }
        host.report(error: SectionLocks.directError(args, rc: r.rc))
        if refresh { await host.applied() }
    }
}
