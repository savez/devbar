import Foundation
import Observation

/// Esegue azioni `devbar run …` / `detect` / `repos`. Finto nei test; `StatusStore` lo adotta.
@MainActor
public protocol ActionRunning: AnyObject {
    func run(action args: [String]) async -> (rc: Int32, stdout: Data)
}

extension StatusStore: ActionRunning {}

/// Flusso di conferma per azioni che scrivono: prima senza `--yes` (piano, solo testo),
/// poi, dopo conferma, con `--yes`. Una conferma sola può coprire più azioni.
/// Le righe del piano si mostrano e basta: non vengono mai eseguite.
@Observable @MainActor
public final class PlanConfirmation {
    public struct Step: Equatable, Sendable {
        public var action: ConfirmableAction
        public var lines: [String]
    }

    public private(set) var steps: [Step] = []
    public private(set) var title = ""
    public var dialogShown = false
    public private(set) var busy = false
    public private(set) var error: String?

    @ObservationIgnored private let runner: any ActionRunning
    /// Sezioni condivise col pannello (`SectionLocks`): un `--yes` non parte se la sua sezione
    /// è occupata (es. undo durante un ai-install).
    @ObservationIgnored private let locks: SectionLocks?

    public init(runner: any ActionRunning, locks: SectionLocks? = nil) {
        self.runner = runner
        self.locks = locks
    }

    /// Una delle azioni ha la sezione occupata da un'altra in corso.
    private func blocked(_ actions: [ConfirmableAction]) -> ConfirmableAction? {
        guard let locks else { return nil }
        return actions.first { a in ActionSection.of(a.args).map(locks.isRunning) ?? false }
    }

    private static func busyText(_ a: ConfirmableAction) -> String {
        "\(a.title): un'altra modifica è in corso, riprova quando è finita"
    }

    /// Testo da mostrare nella conferma.
    public var text: String {
        if steps.count == 1 { return steps[0].lines.joined(separator: "\n") }
        return steps.map { s in ([s.action.title] + s.lines.map { "  " + $0 }).joined(separator: "\n") }
            .joined(separator: "\n")
    }

    public var isPending: Bool { !steps.isEmpty }

    /// Passo 1. Se anche un solo piano non è disponibile (rc ≥ 2) non si chiede nulla.
    /// `adjust`: dai piani letti (uno per azione, in ordine) titolo e azioni da confermare, senza
    /// rileggere i piani (es. undo: `--force` se il piano dice needsForce). Stesso numero di azioni.
    @discardableResult
    public func request(title: String, actions: [ConfirmableAction],
                        adjust: ((_ plans: [Data]) -> (title: String, actions: [ConfirmableAction]))? = nil) async -> Bool {
        guard !actions.isEmpty, !busy else { return false }
        if let a = blocked(actions) {
            error = Self.busyText(a)
            steps = []; dialogShown = false
            return false
        }
        busy = true; defer { busy = false }
        var title = title
        var collected: [Step] = []
        var plans: [Data] = []
        for a in actions {
            let r = await runner.run(action: a.args)
            guard r.rc < 2 else {
                error = "\(a.title): piano non disponibile (rc \(r.rc))"
                steps = []; dialogShown = false
                return false
            }
            plans.append(r.stdout)
            collected.append(Step(action: a, lines: ActionPlan.parse(r.stdout).lines))
        }
        if let adjust {
            let adjusted = adjust(plans)
            title = adjusted.title
            for (i, a) in adjusted.actions.enumerated() where i < collected.count { collected[i].action = a }
        }
        guard collected.contains(where: { !$0.lines.isEmpty }) else {
            error = "\(title): nessun piano"
            steps = []; dialogShown = false
            return false
        }
        error = nil
        self.title = title
        steps = collected
        dialogShown = true
        return true
    }

    /// Passo 2: tutte le azioni con `--yes`, in ordine; ci si ferma al primo errore.
    /// Torna true se tutte sono riuscite.
    @discardableResult
    public func confirm() async -> Bool {
        let todo = steps
        steps = []; dialogShown = false
        guard !todo.isEmpty else { return false }
        busy = true; defer { busy = false }
        error = nil
        for s in todo {
            var r: (rc: Int32, stdout: Data) = (0, Data())
            if let locks {
                guard await locks.occupy(s.action.args, { r = await runner.run(action: s.action.confirmedArgs) }) else {
                    error = Self.busyText(s.action)
                    return false
                }
            } else {
                r = await runner.run(action: s.action.confirmedArgs)
            }
            if r.rc >= 2 {
                error = "\(s.action.title): " + (Self.engineError(r.stdout) ?? "fallito (rc \(r.rc))")
                return false
            }
        }
        return true
    }

    public func cancel() { steps = []; dialogShown = false }

    /// Campo `error` del JSON del motore, se c'è.
    public nonisolated static func engineError(_ d: Data) -> String? {
        guard case .object(let o)? = try? JSONDecoder().decode(JSONValue.self, from: d),
              case .string(let e)? = o["error"], !e.isEmpty else { return nil }
        return e
    }
}
