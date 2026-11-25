import Testing
import Foundation
@testable import DevbarCore

/// Contratto motore <-> app. Le fixture in Fixtures/contract sono l'output reale del motore
/// (rigenerate da `just contract`, validate contro schemas/). Qui si decodifica con i modelli
/// e si verifica che ogni campo che l'app usa ci sia davvero e sia valorizzato: i modelli
/// hanno default tolleranti, quindi una decodifica che non lancia non basta.
struct ContractTests {
    func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/contract"))
        return try Data(contentsOf: url)
    }

    func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try JSONDecoder().decode(T.self, from: data(name))
    }

    func object(_ name: String) throws -> [String: JSONValue] {
        guard case .object(let o) = try JSONDecoder().decode(JSONValue.self, from: data(name)) else {
            Issue.record("\(name): non è un oggetto")
            return [:]
        }
        return o
    }

    /// Le chiavi che il modello legge devono essere presenti nel JSON (i default non le coprono).
    func expectKeys(_ keys: [String], in o: [String: JSONValue], _ name: String) {
        for k in keys { #expect(o[k] != nil, "\(name): manca la chiave \(k)") }
    }

    let envelope = ["status", "count", "summary", "items", "checkedAt"]

    @Test func checkEnvelopeOfEveryCheck() throws {
        for name in ["brew-outdated", "brew-vulns", "npm-audit", "composer-audit", "colima", "rtk",
                     "tokensave", "tokeneconomizer", "caveman", "claude-usage", "harnesses"] {
            let o = try object(name)
            expectKeys(envelope, in: o, name)
            let r = try decode(CheckResult.self, name)
            #expect(!r.summary.isEmpty, "\(name): summary vuoto")
            #expect(r.checkedAt != nil, "\(name): checkedAt")
        }
    }

    @Test func brewOutdated() throws {
        let b = try decode(BrewOutdated.self, "brew-outdated")
        #expect(b.result.state == .action)
        #expect(b.items.count == b.result.count && !b.items.isEmpty)
        for i in b.items {
            #expect(!i.name.isEmpty)
            #expect(["formula", "cask"].contains(i.kind))
            #expect(i.installed != nil && i.current != nil)
        }
        expectKeys(["name", "kind", "installed", "current"], in: try firstItem("brew-outdated"), "brew-outdated item")
    }

    @Test func brewVulns() throws {
        let b = try decode(BrewVulns.self, "brew-vulns")
        expectKeys(["severe"], in: try object("brew-vulns"), "brew-vulns")
        #expect(b.severe > 0)
        #expect(b.items.count == b.result.count)
        for i in b.items { #expect(!i.formula.isEmpty && !i.id.isEmpty && i.severity != "") }
        expectKeys(["formula", "id", "severity", "fixAvailable"], in: try firstItem("brew-vulns"), "brew-vulns item")
    }

    @Test func audits() throws {
        for name in ["npm-audit", "composer-audit"] {
            let a = try decode(AuditResult.self, name)
            #expect(a.result.state == .action)
            #expect(a.items.count == a.result.count && !a.items.isEmpty)
            for i in a.items {
                #expect(!i.repo.isEmpty)
                #expect(i.critical + i.high + i.moderate + i.low > 0)
                #expect(i.error == nil)
            }
            expectKeys(["repo", "critical", "high", "moderate", "low"], in: try firstItem(name), "\(name) item")
        }
        let e = try decode(AuditResult.self, "npm-audit.error")
        #expect(e.result.state == .error)
        #expect(e.items.first?.error?.isEmpty == false)
    }

    @Test func colima() throws {
        let c = try decode(ColimaStatus.self, "colima")
        expectKeys(["profiles", "containers"], in: try object("colima"), "colima")
        #expect(c.running)
        let p = try #require(c.profiles.first)
        #expect(!p.name.isEmpty && p.status == "Running" && p.cpus > 0 && p.memoryBytes > 0 && p.diskBytes > 0)
        expectKeys(["name", "status", "cpus", "memoryBytes", "diskBytes"], in: try nested("colima", "profiles"), "colima profile")
        let k = try #require(c.containers.first)
        #expect(!k.id.isEmpty && !k.name.isEmpty && !k.cpu.isEmpty && !k.mem.isEmpty)
        expectKeys(["id", "name", "cpu", "mem"], in: try nested("colima", "containers"), "colima container")
    }

    @Test func rtk() throws {
        let r = try decode(RtkGain.self, "rtk")
        expectKeys(["saved", "input", "pct", "commands", "daily"], in: try object("rtk"), "rtk")
        #expect(r.saved > 0 && r.input > 0 && r.pct > 0 && r.commands > 0)
        #expect(!r.daily.isEmpty && r.daily.count <= 7)
        #expect(r.daily.allSatisfy { !$0.date.isEmpty })
        expectKeys(["date", "saved"], in: try nested("rtk", "daily"), "rtk daily")
    }

    @Test func tokensave() throws {
        let t = try decode(TokensaveGain.self, "tokensave")
        expectKeys(["saved", "calls", "usd", "missedTurns"], in: try object("tokensave"), "tokensave")
        #expect(t.saved > 0 && t.calls > 0 && t.usd > 0)
    }

    @Test func tokeneconomizer() throws {
        let t = try decode(TokenEconomizerStatus.self, "tokeneconomizer")
        expectKeys(["active"], in: try object("tokeneconomizer"), "tokeneconomizer")
        #expect(t.active == false)
        let on = try decode(TokenEconomizerStatus.self, "tokeneconomizer.active")
        #expect(on.active == true && !on.result.summary.isEmpty)
    }

    @Test func caveman() throws {
        let c = try decode(CavemanStatus.self, "caveman")
        expectKeys(["pluginEnabled", "mode", "rawMode", "version", "lastMode", "active"], in: try object("caveman"), "caveman")
        #expect(c.mode != nil && c.rawMode != nil && c.version != nil && c.lastMode != nil)
        #expect(c.pluginEnabled && c.active)
        let panel = CavemanPanel(status: c)
        #expect(panel.mode == .ultracave)
        #expect(panel.version == "4.10.0")
    }

    @Test func claudeUsage() throws {
        let u = try decode(ClaudeUsage.self, "claude-usage")
        let v = try #require(u.usage)
        #expect(v.cPct != nil && v.cReset != nil && v.wPct != nil && v.wReset != nil)
        // Regressione: auth è una stringa nel binario reale, non un Bool.
        #expect(v.auth == "valid")
        guard case .object(let usage)? = try object("claude-usage")["usage"] else { Issue.record("usage"); return }
        expectKeys(["c_pct", "c_reset", "w_pct", "w_reset", "stale", "auth", "error"], in: usage, "claude-usage.usage")

        let m = try decode(ClaudeUsage.self, "claude-usage.missing")
        #expect(m.usage?.auth == "missing")
        #expect(m.usage?.error?.isEmpty == false)
    }

    @Test func harnesses() throws {
        let r = try decode(CheckResult.self, "harnesses")
        #expect(r.state == .action && r.count == r.items.count && r.count > 0)
        #expect(r.items.allSatisfy { if case .string(let s) = $0 { return !s.isEmpty } else { return false } })
    }

    @Test func checkAll() throws {
        let all = try AllChecks.decode(data("all"))
        let names = ["brew-outdated", "brew-vulns", "npm-audit", "composer-audit", "colima", "rtk",
                     "tokensave", "tokeneconomizer", "caveman", "claude-usage", "harnesses"]
        #expect(Set(all.rows.keys) == Set(names))
        for n in names {
            let o = try #require(all.raw[n])
            guard case .object(let row) = o else { Issue.record("\(n)"); continue }
            expectKeys(envelope + ["rc"], in: row, "all.\(n)")
            #expect(all.rows[n]?.state != nil)
        }
        #expect(all.typed(BrewOutdated.self, "brew-outdated")?.items.isEmpty == false)
        #expect(all.typed(BrewVulns.self, "brew-vulns")?.severe ?? 0 > 0)
        #expect(all.typed(AuditResult.self, "npm-audit")?.items.isEmpty == false)
        #expect(all.typed(AuditResult.self, "composer-audit")?.items.isEmpty == false)
        #expect(all.typed(ColimaStatus.self, "colima")?.running == true)
        #expect(all.typed(RtkGain.self, "rtk")?.saved ?? 0 > 0)
        #expect(all.typed(TokensaveGain.self, "tokensave")?.calls ?? 0 > 0)
        #expect(all.typed(CavemanStatus.self, "caveman")?.mode != nil)
        #expect(all.typed(ClaudeUsage.self, "claude-usage")?.usage?.auth == "valid")
    }

    @Test func detect() throws {
        let d = try decode(DetectResult.self, "detect")
        expectKeys(["harnesses", "tools", "aiTools"], in: try object("detect"), "detect")
        #expect(d.harnesses.count == 6)
        #expect(d.harnesses.first?.id == "claude")
        for t in ["brew", "colima", "npm", "composer", "rtk", "tokensave", "claude-usage", "cork"] {
            #expect(d.tools[t] != nil, "tools.\(t)")
        }
        let ai = try #require(d.aiTools)
        for t in ["rtk", "caveman", "tokensave", "statusline"] { #expect(ai[t] != nil, "aiTools.\(t)") }
        expectKeys(["id", "installed", "managed"], in: try nested("detect", "harnesses"), "detect harness")
    }

    @Test func repos() throws {
        let r = try decode([RepoInfo].self, "repos")
        #expect(r.count == 2)
        for i in r { #expect(!i.path.isEmpty && !i.name.isEmpty) }
        #expect(r.contains { $0.npm } && r.contains { $0.composer } && r.contains { $0.tokensave })
        guard case .array(let a) = try JSONDecoder().decode(JSONValue.self, from: data("repos")),
              case .object(let first)? = a.first else { Issue.record("repos"); return }
        expectKeys(["path", "name", "npm", "composer", "tokensave"], in: first, "repos item")
    }

    @Test func checkTimeoutsMatchApp() throws {
        let t = try decode([String: Double].self, "check-timeouts")
        #expect(t == StatusStore.checkTimeouts)
    }

    @Test func aiStatus() throws {
        let s = try decode(AIStatus.self, "ai-status")
        expectKeys(["tool", "installed", "harnesses"], in: try object("ai-status"), "ai-status")
        #expect(s.tool == "rtk" && s.installed && s.harnesses.count == 6)
        #expect(s.harnesses.contains { $0.state == "installed" })
        expectKeys(["id", "state"], in: try nested("ai-status", "harnesses"), "ai-status harness")
    }

    @Test func projectStatus() throws {
        let p = try decode(ProjectStatus.self, "project-status")
        #expect(!p.path.isEmpty)
        #expect(p.checks.map(\.tool) == ["rtk", "caveman", "tokensave"])
        for c in p.checks { #expect(!c.detail.isEmpty) }
        #expect(p.checks.contains { !$0.willWrite.isEmpty })
        expectKeys(["tool", "ok", "detail", "willWrite"], in: try nested("project-status", "checks"), "project-status check")
    }

    @Test func plans() throws {
        let plan = ActionPlan.parse(try data("plan"))
        #expect(plan.lines == ["rtk init -g --auto-patch"])
        let m = ActionPlan.parse(try data("caveman-mode.plan"))
        #expect(m.lines.count == 2 && m.text.contains("vale per le nuove sessioni"))
        let applied = ActionPlan.parse(try data("caveman-mode"))
        #expect(applied.lines.count == 2)
        let o = try object("caveman-mode.plan")
        expectKeys(["plan", "file", "key", "value", "commands"], in: o, "caveman-mode.plan")
        expectKeys(["applied", "value", "commands"], in: try object("caveman-mode"), "caveman-mode")
    }

    @Test func toolInstallTerminal() throws {
        let o = try object("tool-install")
        expectKeys(["tool", "terminal"], in: o, "tool-install")
        #expect(o["terminal"] == .bool(true))
        #expect(o["tool"] == .string("claude-usage"))
    }

    @Test func journalAndUndo() throws {
        let l = try decode(JournalList.self, "journal")
        let e = try #require(l.entries.first)
        expectKeys(["id", "time", "command", "undone", "files"], in: try nested("journal", "entries"), "journal entry")
        #expect(!e.id.isEmpty && !e.files.isEmpty && e.canUndo)
        #expect(e.title == "caveman-mode megacave")
        // piano di undo: lo legge PlanConfirmation (righe da `commands`)
        #expect(!ActionPlan.parse(try data("undo.plan")).lines.isEmpty)
        expectKeys(["plan", "needsForce", "files"], in: try object("undo.plan"), "undo.plan")
        #expect(PlanConfirmation.engineError(try data("undo.error")) != nil)
    }

    // MARK: helpers

    func firstItem(_ name: String) throws -> [String: JSONValue] {
        try nested(name, "items")
    }

    /// Primo oggetto dell'array `key` del top level.
    func nested(_ name: String, _ key: String) throws -> [String: JSONValue] {
        guard case .array(let a)? = try object(name)[key], case .object(let first)? = a.first else {
            Issue.record("\(name).\(key): array di oggetti vuoto o assente")
            return [:]
        }
        return first
    }
}
