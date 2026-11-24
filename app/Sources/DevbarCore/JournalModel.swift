import Foundation
import Observation

/// File di una voce del registro (`devbar journal`, schemas/journal.schema.json).
public struct JournalFile: Decodable, Equatable, Sendable {
    public var path: String
    public var kind: String
    public var existed: Bool
    /// Cambiato da un altro programma dopo devbar: annullare ne perde le modifiche.
    public var changed: Bool
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
    public var hasChanges: Bool { files.contains(where: \.changed) }
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
/// conferma comune (piano di `devbar undo <id>` mostrato, poi `--yes`). Se un file è
/// cambiato nel frattempo la conferma lo dice e l'azione porta `--force`.
@Observable @MainActor
public final class JournalModel {
    public static let shown = 10

    public private(set) var entries: [JournalEntry] = []
    public private(set) var error: String?
    public let confirmation: PlanConfirmation

    @ObservationIgnored private let runner: any ActionRunning
    /// Annullamento riuscito: il chiamante rilancia i check.
    @ObservationIgnored public var onApplied: () async -> Void = {}

    public init(runner: any ActionRunning) {
        self.runner = runner
        confirmation = PlanConfirmation(runner: runner)
    }

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

    public func requestUndo(_ e: JournalEntry) async {
        guard e.canUndo else { return }
        let force = e.hasChanges
        let title = force
            ? "Annullare \(e.title)? Alcuni file sono cambiati nel frattempo: le loro modifiche andranno perse."
            : "Annullare \(e.title)?"
        await confirmation.request(title: title,
                                   actions: [ConfirmableAction(title: "Annulla \(e.title)",
                                                               args: ["undo", e.id] + (force ? ["--force"] : []))])
    }

    public func confirmUndo() async {
        if await confirmation.confirm() { await onApplied() }
        await load()
    }
}
