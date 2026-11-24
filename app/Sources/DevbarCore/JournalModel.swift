import Foundation
import Observation

/// File di una voce del registro (`devbar journal`, schemas/journal.schema.json).
public struct JournalFile: Decodable, Equatable, Sendable {
    public var path: String
    public var kind: String
    public var existed: Bool
}

/// Voce del registro: tutti i file scritti da una `devbar run …`.
public struct JournalEntry: Decodable, Equatable, Sendable, Identifiable {
    public var id: String
    public var time: String
    public var command: String
    public var undone: Bool
    public var files: [JournalFile]

    /// Comando senza `run` e `--yes`: "ai-install rtk copilot".
    public var title: String {
        command.split(separator: " ").map(String.init)
            .filter { $0 != "--yes" }
            .drop(while: { $0 == "run" })
            .joined(separator: " ")
    }
    public var filesText: String { "\(files.count) file" }
    public var canUndo: Bool { !undone }

    /// "dd/MM HH:mm" nell'ora locale (o nel fuso dato); il testo grezzo se non è una data.
    public static func timeText(_ iso: String, timeZone: TimeZone = .current) -> String {
        guard let d = ISO8601DateFormatter().date(from: iso) else { return iso }
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.timeZone = timeZone
        f.dateFormat = "dd/MM HH:mm"
        return f.string(from: d)
    }
}

struct JournalList: Decodable { var entries: [JournalEntry] }

/// "Ultime modifiche" nelle Impostazioni: le ultime voci del registro e "Annulla", con la
/// conferma comune (piano di `devbar undo <id>` mostrato, poi `--yes`). L'elenco non calcola
/// hash: se un file è cambiato nel frattempo lo dice il piano, e l'azione porta `--force`.
@Observable @MainActor
public final class JournalModel {
    public static let shown = 10

    public private(set) var entries: [JournalEntry] = []
    public private(set) var error: String?
    public let confirmation: PlanConfirmation

    @ObservationIgnored private let runner: any ActionRunning
    /// Sezioni condivise col pannello: undo e AI setup / Init progetto mai insieme.
    public let locks: SectionLocks
    /// Annullamento riuscito: il chiamante rilancia i check.
    @ObservationIgnored public var onApplied: () async -> Void = {}

    public init(runner: any ActionRunning, locks: SectionLocks = SectionLocks()) {
        self.runner = runner
        self.locks = locks
        confirmation = PlanConfirmation(runner: runner, locks: locks)
    }

    /// Un'altra modifica (AI setup, Init progetto, undo) è in corso: "Annulla" disattivato.
    public var blocked: Bool { locks.isRunning(ActionSection.ai) }

    public func load() async {
        let r = await runner.run(action: ["journal", "--limit", String(Self.shown)])
        if r.rc < 2, let l = try? JSONDecoder().decode(JournalList.self, from: r.stdout) {
            entries = Array(l.entries.prefix(Self.shown))
            error = nil
        } else {
            entries = []
            error = "registro delle modifiche non disponibile"
        }
    }

    /// Il piano di `undo <id>` (letto una volta sola) dice, sullo stato attuale, se un file è
    /// cambiato da un altro programma (`needsForce`): la conferma lo avvisa e l'azione porta
    /// `--force` (il piano non dipende da `--force`, solo l'esecuzione).
    public func requestUndo(_ e: JournalEntry) async {
        guard e.canUndo, !confirmation.busy else { return }
        let action = ConfirmableAction(title: "Annulla \(e.title)", args: ["undo", e.id])
        await confirmation.request(title: "Annullare \(e.title)?", actions: [action]) { plans in
            guard Self.needsForce(plans.first) else { return ("Annullare \(e.title)?", [action]) }
            return ("Annullare \(e.title)? Alcuni file sono cambiati nel frattempo: la loro versione resta nel registro delle modifiche (kept).",
                    [ConfirmableAction(title: action.title, args: action.args + ["--force"])])
        }
    }

    nonisolated static func needsForce(_ plan: Data?) -> Bool {
        guard let plan, case .object(let o)? = try? JSONDecoder().decode(JSONValue.self, from: plan),
              case .bool(let b)? = o["needsForce"] else { return false }
        return b
    }

    public func confirmUndo() async {
        if await confirmation.confirm() { await onApplied() }
        await load()
    }
}
