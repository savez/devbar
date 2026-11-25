import Foundation
import Observation

/// Una riga del selettore harness.
public struct HarnessRow: Equatable, Sendable, Identifiable {
    public var id: String
    /// installed | outdated | missing
    public var state: String
    /// Solo "Installa" e "Aggiorna": nessuna azione "rimuovi".
    public var actionLabel: String? {
        switch state {
        case "missing": return "Installa"
        case "outdated": return "Aggiorna"
        default: return nil
        }
    }
    public var stateLabel: String {
        switch state {
        case "installed": return "installato"
        case "outdated": return "da aggiornare"
        default: return "assente"
        }
    }
    public var selectable: Bool { actionLabel != nil }
}

/// Logica pura dell'AI setup. Nessuna scelta sta nelle viste.
public enum AISetup {
    /// Strumenti noti, nome per la CLI.
    public static let tools = ["rtk", "caveman", "tokensave", "tokeneconomizer", "statusline"]
    /// Strumenti il cui binario si può installare con `tool-install`.
    public static let binaryInstallable: Set<String> = ["rtk", "tokensave", "tokeneconomizer"]

    /// "RTK" -> "rtk": il pannello mostra i nomi, la CLI vuole il minuscolo.
    public static func cliName(_ display: String) -> String { display.lowercased() }

    /// Se nessun harness è gestito si mostrano quelli installati (e supportati) per sceglierli;
    /// altrimenti solo i gestiti supportati.
    public static func needsHarnessChoice(detect: DetectResult) -> Bool {
        !detect.harnesses.contains { $0.managed }
    }

    public static func rows(status: AIStatus, detect: DetectResult) -> [HarnessRow] {
        let choose = needsHarnessChoice(detect: detect)
        return detect.harnesses.compactMap { h in
            guard choose ? h.installed : h.managed else { return nil }
            guard let st = status.harnesses.first(where: { $0.id == h.id })?.state, st != "unsupported" else { return nil }
            return HarnessRow(id: h.id, state: st)
        }
    }

    /// Spuntati in partenza: tutto ciò che si può installare o aggiornare.
    public static func preselected(_ rows: [HarnessRow]) -> Set<String> {
        Set(rows.filter(\.selectable).map(\.id))
    }

    public static func installAction(tool: String, harnesses: [String]) -> ConfirmableAction {
        ConfirmableAction(title: "Installa \(tool) su \(harnesses.joined(separator: ", "))",
                          args: ["run", "ai-install", tool] + harnesses)
    }

    /// Nuovo harness spuntato in impostazioni: per ogni strumento già `installed` su almeno un
    /// altro harness gestito, si propone `ai-install` per il nuovo. Mai eseguito da solo.
    public static func installsForNewHarness(_ new: String, otherManaged: [String],
                                             statuses: [AIStatus]) -> [ConfirmableAction] {
        let others = Set(otherManaged).subtracting([new])
        return statuses.compactMap { s in
            guard s.installed,
                  let mine = s.harnesses.first(where: { $0.id == new })?.state,
                  mine == "missing" || mine == "outdated",
                  s.harnesses.contains(where: { others.contains($0.id) && $0.state == "installed" })
            else { return nil }
            return installAction(tool: s.tool, harnesses: [new])
        }
    }
}

/// Stato della finestra "AI setup" per uno strumento.
@Observable @MainActor
public final class AISetupModel {
    public enum Phase: Equatable, Sendable { case idle, loading, ready, failed(String) }

    public private(set) var tool = ""
    public private(set) var phase: Phase = .idle
    public private(set) var status: AIStatus?
    public private(set) var detect: DetectResult?
    public private(set) var rows: [HarnessRow] = []
    public var selected: Set<String> = []
    public let confirmation: PlanConfirmation

    @ObservationIgnored private let runner: any ActionRunning
    /// Dopo un'installazione riuscita: aggiorna pannello e config.
    @ObservationIgnored public var onApplied: () async -> Void = {}

    public init(runner: any ActionRunning, locks: SectionLocks? = nil) {
        self.runner = runner
        confirmation = PlanConfirmation(runner: runner, locks: locks)
    }

    public var displayName: String { tool }
    public var choosingHarnesses: Bool { detect.map(AISetup.needsHarnessChoice) ?? false }
    public var toolMissing: Bool { status.map { !$0.installed } ?? false }
    public var canInstallBinary: Bool { toolMissing && AISetup.binaryInstallable.contains(tool) }
    public var chosenIDs: [String] { rows.filter { selected.contains($0.id) && $0.selectable }.map(\.id) }
    public var canInstall: Bool { !toolMissing && !chosenIDs.isEmpty && !confirmation.busy }

    /// Clic su un pulsante strumento: `ai-status <tool>` (sola lettura) e `detect`.
    public func begin(displayTool: String) async {
        tool = AISetup.cliName(displayTool)
        phase = .loading
        status = nil; rows = []; selected = []
        await reload()
    }

    public func reload() async {
        let d = await runner.run(action: ["detect"])
        // ai-status esce 3 quando lo strumento manca (statusline): il JSON c'è comunque.
        let s = await runner.run(action: ["run", "ai-status", tool])
        guard let det = try? JSONDecoder().decode(DetectResult.self, from: d.stdout),
              let st = try? JSONDecoder().decode(AIStatus.self, from: s.stdout) else {
            phase = .failed("stato non disponibile")
            return
        }
        detect = det; status = st
        rows = AISetup.rows(status: st, detect: det)
        selected = AISetup.preselected(rows)
        phase = .ready
    }

    /// Piano di `ai-install` per gli harness spuntati; poi conferma nella vista.
    public func requestInstall() async {
        guard canInstall else { return }
        await confirmation.request(title: "Conferma installazione",
                                   actions: [AISetup.installAction(tool: tool, harnesses: chosenIDs)])
    }

    /// Piano di `tool-install` per il binario (rtk, tokensave).
    public func requestBinaryInstall() async {
        guard canInstallBinary else { return }
        await confirmation.request(title: "Conferma installazione",
                                   actions: [ConfirmableAction(title: "Installa \(tool)", args: ["run", "tool-install", tool])])
    }

    public func confirm() async {
        if await confirmation.confirm() { await onApplied() }
        await reload()
    }
}
