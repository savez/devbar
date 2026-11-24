import Testing
import Foundation
@testable import DevbarCore

// Correzioni della revisione finale dello step 1.

// MARK: - 1. Timeout per azione

@MainActor
struct ActionTimeoutTests {
    @Test func longActionsGetLongTimeoutPlansDoNot() {
        #expect(ActionTimeout.isLong(["run", "colima-start"]))
        #expect(ActionTimeout.isLong(["run", "colima-stop", "work"]))
        #expect(ActionTimeout.isLong(["run", "ai-install", "caveman", "claude", "--yes"]))
        #expect(ActionTimeout.isLong(["run", "project-apply", "/p", "--yes"]))
        // piani (senza --yes) e azioni brevi o nel terminale: timeout breve
        #expect(!ActionTimeout.isLong(["run", "ai-install", "caveman", "claude"]))
        #expect(!ActionTimeout.isLong(["run", "project-apply", "/p"]))
        #expect(!ActionTimeout.isLong(["run", "tool-install", "rtk", "--yes"]))
        #expect(!ActionTimeout.isLong(["run", "colima-install", "--yes"]))
        #expect(!ActionTimeout.isLong(["run", "container-stop", "abc"]))
        #expect(!ActionTimeout.isLong(["detect"]))
    }

    @Test func storeUsesLongTimeoutForLongActions() async {
        let runner = FakeRunner([
            "run colima-start": .init(rc: 0, stdout: "", delay: 0.3),
            "run cork-open": .init(rc: 0, stdout: "", delay: 0.3),
        ])
        let store = StatusStore(runner: runner, allTimeout: 5, actionTimeout: 0.05, longActionTimeout: 5)
        #expect(await store.run(action: ["run", "colima-start"]).rc == 0)
        #expect(await store.run(action: ["run", "cork-open"]).rc == 2)
    }

    @Test func defaultLongTimeoutIs600() {
        #expect(StatusStore.defaultLongActionTimeout == 600)
    }
}

// MARK: - 2. PATH del figlio

struct ChildPathTests {
    @Test func includesLocalBin() {
        #expect(CLIRunner.childPath(inherited: "/usr/bin:/bin", home: "/h")
            == "/opt/homebrew/bin:/usr/local/bin:/h/.local/bin:/usr/bin:/bin")
    }
}

// MARK: - 3. claude-usage auth stringa

struct ClaudeUsageAuthTests {
    func model(_ usage: String) throws -> PanelModel {
        let json = #"{"claude-usage":{"status":"ok","rc":1,"count":0,"summary":"s","items":[],"usage":\#(usage)}}"#
        return PanelModel(all: try AllChecks.decode(Data(json.utf8)))
    }

    @Test func realShapeDecodes() throws {
        let m = try model(#"{"c_pct":42,"c_reset":"3h 12m","w_pct":67,"w_reset":"2d 4h","stale":false,"auth":"valid","error":null}"#)
        #expect(m.usageFiveHour == 42)
        #expect(m.usageWeek == 67)
        #expect(m.usageFiveHourReset == "3h 12m")
        #expect(m.usageWeekReset == "2d 4h")
        #expect(m.usageNote == nil)
    }

    @Test func missingAndExpiredWinOverError() throws {
        let missing = try model(#"{"c_pct":0,"c_reset":"?","w_pct":0,"w_reset":"?","stale":false,"auth":"missing","error":"no credentials found"}"#)
        #expect(missing.usageNote == "Accesso richiesto")
        #expect(missing.usageFiveHourReset == nil)
        let expired = try model(#"{"c_pct":0,"c_reset":"?","w_pct":0,"w_reset":"?","stale":false,"auth":"expired"}"#)
        #expect(expired.usageNote == "Credenziali scadute")
        let stale = try model(#"{"c_pct":80,"c_reset":"<1m","w_pct":90,"w_reset":"3d09h","stale":true,"auth":"valid"}"#)
        #expect(stale.usageNote == "dati non aggiornati")
    }
}

// MARK: - 4. Impostazioni: niente sovrascritture delle scritture del motore

@MainActor
struct SettingsMergeTests {
    func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("devbar-merge-\(UUID().uuidString)/config.json")
    }
    func disk(_ url: URL) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: Any] ?? [:]
    }
    func write(_ url: URL, _ json: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)
    }

    @Test func engineWritesSurviveLaterSettingsEdit() async throws {
        let url = tempURL()
        try write(url, #"{"brewExclude":["a"],"harnesses":["claude"]}"#)
        let m = SettingsModel(configStore: ConfigStore(url: url), runner: FakeActions(), login: FakeLogin(),
                              executablePath: "/x/Devbar")
        await m.load()
        // il motore scrive dopo il caricamento (brew-exclude, ai-install)
        try write(url, #"{"brewExclude":["a","b"],"harnesses":["claude","codex"],"extra":1}"#)
        m.setDepth(6)
        var d = disk(url)
        #expect(d["scanDepth"] as? Int == 6)
        #expect(d["brewExclude"] as? [String] == ["a", "b"])
        #expect(d["harnesses"] as? [String] == ["claude", "codex"])
        #expect(d["extra"] as? Int == 1)
        #expect(m.config.brewExclude == ["a", "b"])
        // rimozione: delta sul file, non l'array in memoria
        try write(url, #"{"brewExclude":["a","b","c"],"harnesses":["claude","codex"],"scanDepth":6}"#)
        m.removeExclude("a")
        d = disk(url)
        #expect(d["brewExclude"] as? [String] == ["b", "c"])
        #expect(m.config.brewExclude == ["b", "c"])
    }

    @Test func harnessToggleUsesLatestFile() async throws {
        let url = tempURL()
        try write(url, #"{"harnesses":["claude"]}"#)
        let m = SettingsModel(configStore: ConfigStore(url: url), runner: FakeActions(), login: FakeLogin(),
                              executablePath: "/x/Devbar")
        await m.load()
        try write(url, #"{"harnesses":["claude","codex"]}"#)
        await m.setHarness("opencode", on: true)
        #expect(disk(url)["harnesses"] as? [String] == ["claude", "codex", "opencode"])
    }

    @Test func configStoreUpdateRefusesBrokenFile() throws {
        let url = tempURL()
        try write(url, "non json")
        #expect(throws: (any Error).self) { _ = try ConfigStore(url: url).update { $0.scanDepth = 2 } }
        #expect(String(decoding: try Data(contentsOf: url), as: UTF8.self) == "non json")
    }
}

// MARK: - 8. Errore del motore mostrato

@MainActor
struct ConfirmErrorTests {
    @Test func engineErrorTextShown() async {
        let a = FakeActions()
        a.responses["run project-apply /p"] = (0, #"{"path":"/p","checks":[{"tool":"caveman","ok":false,"willWrite":["AGENTS.md"]}]}"#)
        a.responses["run project-apply /p --yes"] = (3, #"{"status":"error","error":"tokensave non installato: nessun file scritto"}"#)
        let c = PlanConfirmation(runner: a)
        await c.request(title: "t", actions: [ConfirmableAction(title: "Applica", args: ["run", "project-apply", "/p"])])
        #expect(await c.confirm() == false)
        #expect(c.error?.contains("tokensave non installato") == true)
    }
}

// MARK: - 9. Timeout di riserva dalla tabella del motore

struct BackstopTests {
    @Test func backstopIsSumOfCheckTimeoutsPlusMargin() {
        let t = StatusStore.checkTimeouts
        #expect(StatusStore.defaultAllTimeout == t.values.reduce(0, +) + 5 * TimeInterval(t.count))
        #expect(t["npm-audit"] == 300)
    }

    @Test func tableMatchesEngine() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let p = Process()
        p.executableURL = repo.appendingPathComponent("bin/devbar")
        p.arguments = ["check-timeouts"]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env.removeValue(forKey: "DEVBAR_CHECK_TIMEOUT")
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        try p.run()
        p.waitUntilExit()
        let engine = try JSONDecoder().decode([String: Double].self, from: out.fileHandleForReading.readDataToEndOfFile())
        #expect(engine == StatusStore.checkTimeouts)
    }
}

// MARK: - 11. Sezioni occupate

struct ActionSectionTests {
    @Test func sections() {
        #expect(ActionSection.of(["run", "colima-start"]) == "colima")
        #expect(ActionSection.of(["run", "container-stop", "x"]) == "colima")
        #expect(ActionSection.of(["run", "colima-install"]) == "colima")
        #expect(ActionSection.of(["run", "brew-upgrade", "wget"]) == "brew")
        #expect(ActionSection.of(["run", "brew-exclude", "wget"]) == "brew")
        #expect(ActionSection.of(["run", "cork-install"]) == "brew")
        #expect(ActionSection.of(["run", "tool-install", "rtk"]) == "tokens")
        #expect(ActionSection.of(["detect"]) == nil)
    }
}

// MARK: - 12. Badge

@MainActor
struct BadgeTests {
    @Test func harnessesInformativeAndBrewVulnsCountsFormulae() async {
        let vulns = #"{"status":"action","rc":0,"count":4,"summary":"s","severe":0,"items":[{"formula":"ffmpeg","id":"1"},{"formula":"ffmpeg","id":"2"},{"formula":"yarn","id":"3"},{"formula":"ffmpeg","id":"4"}]}"#
        let runner = FakeRunner(["check all": .init(rc: 1, stdout: allJSON(rows([
            "brew-vulns": vulns,
            "harnesses": row("action", rc: 0, count: 3),
        ])))])
        let store = StatusStore(runner: runner, allTimeout: 5, actionTimeout: 5)
        await store.refresh(force: false)
        #expect(store.badge.count == 2)
        #expect(store.badge.level == .action)
    }

    @Test func onlyHarnessesIsOk() async {
        let runner = FakeRunner(["check all": .init(rc: 1, stdout: allJSON(rows([
            "harnesses": row("action", rc: 0, count: 3),
        ])))])
        let store = StatusStore(runner: runner, allTimeout: 5, actionTimeout: 5)
        await store.refresh(force: false)
        #expect(store.badge.count == 0)
        #expect(store.badge.level == .ok)
    }
}

// MARK: - 13. Pulsanti AI setup

struct AIToolButtonsTests {
    func detect(_ ai: String?) -> DetectResult {
        let extra = ai.map { ",\"aiTools\":\($0)" } ?? ""
        let json = #"{"harnesses":[{"id":"codex","installed":true,"managed":false}],"tools":{}\#(extra)}"#
        return try! JSONDecoder().decode(DetectResult.self, from: Data(json.utf8))
    }

    @Test func onlyToolsWithASupportedInstalledHarness() throws {
        let all = try AllChecks.decode(Data("{}".utf8))
        let m = PanelModel(all: all, detect: detect(#"{"rtk":false,"caveman":false,"tokensave":true,"statusline":false}"#))
        #expect(m.aiTools == ["tokensave"])
        let none = PanelModel(all: all, detect: detect(#"{"rtk":false,"caveman":false,"tokensave":false,"statusline":false}"#))
        #expect(none.aiTools.isEmpty)
    }
}

// MARK: - T15. Allineamento avvio al login solo dal bundle installato

struct ReconcileGateTests {
    @Test func onlyFromInstalledBundle() {
        #expect(LoginReconciler.shouldReconcile(bundlePath: "/Users/u/Applications/devbar.app", home: "/Users/u"))
        #expect(LoginReconciler.shouldReconcile(bundlePath: "/Users/u/Applications/devbar.app/", home: "/Users/u"))
        #expect(!LoginReconciler.shouldReconcile(bundlePath: "/r/app/.build/devbar.app", home: "/Users/u"))
        #expect(!LoginReconciler.shouldReconcile(bundlePath: "/Applications/devbar.app", home: "/Users/u"))
    }
}
