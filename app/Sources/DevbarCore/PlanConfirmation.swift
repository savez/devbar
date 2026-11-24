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

    public init(runner: any ActionRunning) { self.runner = runner }

    /// Testo da mostrare nella conferma.
    public var text: String {
        if steps.count == 1 { return steps[0].lines.joined(separator: "\n") }
        return steps.map { s in ([s.action.title] + s.lines.map { "  " + $0 }).joined(separator: "\n") }
            .joined(separator: "\n")
    }

    public var isPending: Bool { !steps.isEmpty }

    /// Passo 1. Se anche un solo piano non è disponibile (rc ≥ 2) non si chiede nulla.
    @discardableResult
    public func request(title: String, actions: [ConfirmableAction]) async -> Bool {
        guard !actions.isEmpty, !busy else { return false }
        busy = true; defer { busy = false }
        var collected: [Step] = []
        for a in actions {
            let r = await runner.run(action: a.args)
            guard r.rc < 2 else {
                error = "\(a.title): piano non disponibile (rc \(r.rc))"
                steps = []; dialogShown = false
                return false
            }
            collected.append(Step(action: a, lines: ActionPlan.parse(r.stdout).lines))
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
            let r = await runner.run(action: s.action.confirmedArgs)
            if r.rc >= 2 { error = "\(s.action.title): fallito (rc \(r.rc))"; return false }
        }
        return true
    }

    public func cancel() { steps = []; dialogShown = false }
}
