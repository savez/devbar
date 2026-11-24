import Foundation
import Observation

/// Area colima: stato (da `check all`) e azioni. Le azioni dirette passano dal runner comune
/// (`StatusStore`) e occupano la sezione "colima" nei `SectionLocks` condivisi, così non
/// partono due `colima start`; l'installazione passa dalla conferma comune del pannello.
@Observable @MainActor
public final class ColimaFeature: Feature {
    public let area: Area = .colima
    public private(set) var panel: ColimaPanel

    /// Conferma comune (piano senza `--yes`, dialogo, poi `--yes`): la fornisce `PanelActions`.
    @ObservationIgnored public var confirm: ((ConfirmableAction, DialogOrigin) async -> Void)?
    /// Dopo un'azione che cambia lo stato: rilancia i controlli.
    @ObservationIgnored public var onApplied: (() async -> Void)?
    /// Esito dell'ultima azione diretta per il piede del pannello (nil: riuscita).
    @ObservationIgnored public var onError: ((String?) -> Void)?
    @ObservationIgnored private let runner: any ActionRunning
    @ObservationIgnored private let locks: SectionLocks

    public init(runner: any ActionRunning, locks: SectionLocks) {
        self.runner = runner
        self.locks = locks
        panel = ColimaPanel(all: AllChecks(rows: [:], raw: [:]))
    }

    // MARK: Feature

    /// Sezione informativa: sempre ardesia.
    public var tone: Tone { .info }
    public var readout: Readout? { panel.kind == .hidden ? nil : panel.readout }

    public func update(from all: AllChecks) {
        let p = ColimaPanel(all: all)
        if p != panel { panel = p }
    }

    // MARK: Azioni

    /// Un'azione colima è in corso (anche l'installazione confermata).
    public var busy: Bool { locks.isRunning("colima") }

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
        await confirm?(ConfirmableAction(title: "Installa colima", args: ["run", "colima-install"]), origin)
    }

    private func run(_ args: [String], refresh: Bool) async {
        var r: (rc: Int32, stdout: Data) = (0, Data())
        guard await locks.occupy(args, { r = await runner.run(action: args) }) else { return }
        onError?(SectionLocks.directError(args, rc: r.rc))
        if refresh { await onApplied?() }
    }
}
