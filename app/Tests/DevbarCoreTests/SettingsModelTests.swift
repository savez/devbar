import Testing
import Foundation
@testable import DevbarCore

@MainActor
final class FakeLogin: LoginItemManaging {
    var enabled = false
    var failEnable = false
    var onCall: () -> Void = {}
    private(set) var enableCalls: [String] = []
    private(set) var disableCalls = 0
    func isEnabled() -> Bool { enabled }
    func enable(executablePath: String) throws {
        onCall()
        enableCalls.append(executablePath)
        if failEnable { throw LoginItemError(message: "boom") }
        enabled = true
    }
    func disable() throws { onCall(); disableCalls += 1; enabled = false }
}

@MainActor
struct SettingsModelTests {
    func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("devbar-settings-\(UUID().uuidString)/config.json")
    }
    func make(url: URL, actions: FakeActions? = nil, login: FakeLogin? = nil) -> SettingsModel {
        SettingsModel(configStore: ConfigStore(url: url), runner: actions ?? FakeActions(), login: login ?? FakeLogin(),
                      executablePath: "/x/Devbar")
    }
    func disk(_ url: URL) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: Any] ?? [:]
    }

    @Test func checkIntervalsAutosave() async {
        let url = tempURL()
        let m = make(url: url)
        await m.load()
        m.setVulnEvery("1w")
        m.setBrewHours(3)
        #expect(disk(url)["vulnCheckEvery"] as? String == "1w")
        #expect(disk(url)["brewCheckHours"] as? Int == 3)
        m.setVulnEvery("3d")            // fuori elenco: ignorato
        m.setBrewHours(5)
        #expect(m.config.vulnCheckEvery == "1w" && m.config.brewCheckHours == 3)
    }

    @Test func dailyTimeOnlyForEveryDay() async {
        let m = make(url: tempURL())
        await m.load()
        #expect(m.showsDailyTime)                       // default: ogni giorno
        m.setVulnEvery("12h"); #expect(!m.showsDailyTime)
        m.setVulnEvery("1w"); #expect(!m.showsDailyTime)
        m.setVulnEvery("1d"); #expect(m.showsDailyTime)
    }

    @Test func checkIntervalOptions() {
        #expect(SettingsModel.vulnOptions.map(\.id) == ["12h", "1d", "1w"])
        #expect(SettingsModel.vulnOptions.map(\.title) == ["Ogni 12 ore", "Ogni giorno", "Ogni settimana"])
        #expect(SettingsModel.brewOptions.map(\.hours) == [1, 3, 6, 12, 24])
        #expect(SettingsModel.brewOptions.map(\.title) == ["Ogni ora", "Ogni 3 ore", "Ogni 6 ore", "Ogni 12 ore", "Ogni giorno"])
    }

    @Test func editsAutosave() async {
        let url = tempURL()
        let m = make(url: url)
        await m.load()
        m.addRoots(["/a", "/b", "/a"])
        m.removeRoot("/b")
        m.setDepth(12)
        m.setDailyTime(hour: 7, minute: 5)
        m.setTerminal("Ghostty")
        m.setTerminal("Warp")           // non valido: ignorato
        m.newExclude = " wget "; m.addExclude()
        let d = disk(url)
        #expect(d["repoRoots"] as? [String] == ["/a"])
        #expect(d["scanDepth"] as? Int == 8)
        #expect(d["dailyCheckTime"] as? String == "07:05")
        #expect(d["terminal"] as? String == "Ghostty")
        #expect(d["brewExclude"] as? [String] == ["wget"])
        m.setDepth(0)
        #expect(disk(url)["scanDepth"] as? Int == 1)
        m.setDailyTime(hour: 25, minute: 0)
        #expect(m.config.dailyCheckTime == "07:05")
        #expect(m.dailyTimeParts == (7, 5))
    }

    @Test func brokenConfigNotSavedUntilOverwriteConfirmed() async throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{ rotto".write(to: url, atomically: true, encoding: .utf8)
        let m = make(url: url)
        await m.load()
        #expect(m.configError?.hasPrefix("config non valida") == true)
        m.addRoots(["/a"])
        #expect(m.overwritePromptShown)
        #expect(try String(contentsOf: url, encoding: .utf8) == "{ rotto")   // intatta
        await m.confirmOverwrite()
        #expect(disk(url)["repoRoots"] as? [String] == ["/a"])
        #expect(m.configError == nil)
        m.setDepth(3)   // ora salva senza chiedere
        #expect(!m.overwritePromptShown && disk(url)["scanDepth"] as? Int == 3)
    }

    @Test func cancelOverwriteKeepsFile() async throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "[1]".write(to: url, atomically: true, encoding: .utf8)
        let m = make(url: url)
        await m.load()
        m.setTerminal("iTerm")
        m.cancelOverwrite()
        #expect(try String(contentsOf: url, encoding: .utf8) == "[1]")
        #expect(m.config == DevbarConfig() && !m.overwritePromptShown)
    }

    @Test func newHarnessPreparesPlanForToolsInstalledElsewhereAndNeverRunsIt() async throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"harnesses":["claude"]}"#.write(to: url, atomically: true, encoding: .utf8)
        let f = FakeActions()
        f.responses["detect"] = (0, detectJSON([("claude", true, true), ("opencode", true, false)]))
        f.responses["run ai-status rtk"] = (0, statusJSON("rtk", [("claude", "installed"), ("opencode", "missing")]))
        f.responses["run ai-status caveman"] = (0, statusJSON("caveman", [("claude", "missing"), ("opencode", "missing")]))
        f.responses["run ai-status tokensave"] = (0, statusJSON("tokensave", [("claude", "installed"), ("opencode", "missing")]))
        f.responses["run ai-status statusline"] = (3, statusJSON("statusline", installed: false, [("claude", "missing")]))
        f.responses["run ai-install rtk opencode"] = (0, "{\"commands\":[\"rtk init -g --opencode\"]}")
        f.responses["run ai-install tokensave opencode"] = (0, "{\"commands\":[\"tokensave install --agent opencode\"]}")
        let m = make(url: url, actions: f)
        await m.load()
        #expect(m.harnessRows.map(\.id) == ["claude", "opencode"])
        await m.setHarness("opencode", on: true)
        #expect(disk(url)["harnesses"] as? [String] == ["claude", "opencode"])
        #expect(m.confirmation.dialogShown)
        #expect(m.confirmation.text.contains("rtk init -g --opencode"))
        #expect(m.confirmation.text.contains("tokensave install --agent opencode"))
        #expect(!m.confirmation.text.contains("caveman"))
        #expect(f.confirmed.isEmpty)
        await m.confirmInstalls()
        #expect(f.confirmed == [["run", "ai-install", "rtk", "opencode", "--yes"],
                                ["run", "ai-install", "tokensave", "opencode", "--yes"]])
    }

    @Test func firstHarnessEverHasNoPlan() async {
        let url = tempURL()
        let f = FakeActions()
        f.responses["run ai-status rtk"] = (0, statusJSON("rtk", [("claude", "missing")]))
        let m = make(url: url, actions: f)
        await m.load()
        await m.setHarness("claude", on: true)
        #expect(!m.confirmation.isPending)
        await m.setHarness("claude", on: false)
        #expect(disk(url)["harnesses"] as? [String] == [])
    }

    @Test func launchAtLoginUsesLoginItemAndSaves() async {
        let url = tempURL()
        let l = FakeLogin()
        let m = make(url: url, login: l)
        await m.load()
        m.setLaunchAtLogin(false)
        #expect(l.disableCalls == 1 && disk(url)["launchAtLogin"] as? Bool == false)
        m.setLaunchAtLogin(true)
        #expect(l.enableCalls == ["/x/Devbar"] && disk(url)["launchAtLogin"] as? Bool == true)
    }

    @Test func launchAtLoginFailureKeepsConfig() async {
        let url = tempURL()
        let l = FakeLogin(); l.failEnable = true
        let m = make(url: url, login: l)
        await m.load()
        m.setLaunchAtLogin(false)
        m.setLaunchAtLogin(true)
        #expect(m.loginError != nil)
        #expect(disk(url)["launchAtLogin"] as? Bool == false)
    }

    @Test func didCloseAppliesOnlyIfChanged() async {
        let m = make(url: tempURL())
        var n = 0
        m.onApplied = { n += 1 }
        await m.load()
        await m.didClose()
        #expect(n == 0)
        m.setDepth(2)
        await m.didClose()
        await m.didClose()
        #expect(n == 1)
    }

    @Test func configIsWrittenBeforeLoginSideEffect() async {
        let url = tempURL()
        let l = FakeLogin()
        var seen: [Bool?] = []
        l.onCall = { seen.append(self.disk(url)["launchAtLogin"] as? Bool) }
        let m = make(url: url, login: l)
        await m.load()
        m.setLaunchAtLogin(false)
        m.setLaunchAtLogin(true)
        #expect(seen == [false, true])
    }

    @Test func brokenConfigDefersLoginUntilOverwriteConfirmed() async throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{ rotto".write(to: url, atomically: true, encoding: .utf8)
        let l = FakeLogin()
        let m = make(url: url, login: l)
        await m.load()
        m.setLaunchAtLogin(false)
        #expect(m.overwritePromptShown && l.disableCalls == 0 && l.enableCalls.isEmpty)
        await m.confirmOverwrite()
        #expect(l.disableCalls == 1 && disk(url)["launchAtLogin"] as? Bool == false)
    }

    @Test func cancelOverwriteRestoresPreviousToggleAndNoLoginCall() async throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{ rotto".write(to: url, atomically: true, encoding: .utf8)
        let l = FakeLogin()
        let m = make(url: url, login: l)
        await m.load()
        #expect(m.config.launchAtLogin)
        m.setLaunchAtLogin(false)
        m.cancelOverwrite()
        #expect(m.config.launchAtLogin)
        #expect(l.disableCalls == 0 && l.enableCalls.isEmpty)
        #expect(try String(contentsOf: url, encoding: .utf8) == "{ rotto")
    }

    @Test func gatedSaveDoesNotMarkDirty() async throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{ rotto".write(to: url, atomically: true, encoding: .utf8)
        let m = make(url: url)
        var n = 0
        m.onApplied = { n += 1 }
        await m.load()
        m.setDepth(2)
        m.cancelOverwrite()
        await m.didClose()
        #expect(n == 0)
    }
}
