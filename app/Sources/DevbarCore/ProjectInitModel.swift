import Foundation
import Observation

/// Riga di controllo di un progetto.
public struct ProjectCheckRow: Equatable, Sendable, Identifiable {
    public var id: String { tool }
    public var tool: String
    public var ok: Bool
    public var detail: String
    public var willWrite: [String]
}

@Observable @MainActor
public final class ProjectInitModel {
    public private(set) var repos: [RepoInfo] = []
    public private(set) var selected: String?
    public private(set) var status: ProjectStatus?
    public private(set) var loading = false
    public private(set) var error: String?
    public let confirmation: PlanConfirmation

    @ObservationIgnored private let runner: any ActionRunning

    public init(runner: any ActionRunning, locks: SectionLocks? = nil) {
        self.runner = runner
        confirmation = PlanConfirmation(runner: runner, locks: locks)
    }

    public func loadRepos() async {
        let r = await runner.run(action: ["repos"])
        repos = (try? JSONDecoder().decode([RepoInfo].self, from: r.stdout)) ?? []
    }

    /// `project-status <dir>`: sola lettura. Cartella non git: errore, nessuna riga.
    public func select(_ path: String) async {
        selected = path
        status = nil; error = nil; loading = true
        defer { loading = false }
        let r = await runner.run(action: ["run", "project-status", path])
        if r.rc < 2, let s = try? JSONDecoder().decode(ProjectStatus.self, from: r.stdout) {
            status = s
        } else {
            error = Self.errorText(r.stdout) ?? "stato del progetto non disponibile"
        }
    }

    static func errorText(_ d: Data) -> String? {
        guard case .object(let o)? = try? JSONDecoder().decode(JSONValue.self, from: d),
              case .string(let e)? = o["error"] else { return nil }
        return e
    }

    public var rows: [ProjectCheckRow] {
        (status?.checks ?? []).map { ProjectCheckRow(tool: $0.tool, ok: $0.ok, detail: $0.detail, willWrite: $0.willWrite) }
    }

    /// File che l'applicazione creerebbe o modificherebbe.
    public var willWrite: [String] { rows.flatMap(\.willWrite) }
    public var canApply: Bool { selected != nil && !willWrite.isEmpty && !confirmation.busy }

    public var selectedName: String {
        selected.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
    }

    /// `project-apply <dir>` senza --yes: il piano (i `willWrite`) si mostra e si conferma.
    public func requestApply() async {
        guard canApply, let path = selected else { return }
        await confirmation.request(title: "Applicare a \(selectedName)?",
                                   actions: [ConfirmableAction(title: "Applica a \(selectedName)",
                                                               args: ["run", "project-apply", path])])
    }

    public func confirmApply() async {
        _ = await confirmation.confirm()
        if let p = selected { await select(p) }
    }
}
