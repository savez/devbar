import Testing
import Foundation
@testable import DevbarCore

/// Runner finto: risposte per argomenti; registra le chiamate.
@MainActor
final class FakeActions: ActionRunning {
    var responses: [String: (rc: Int32, out: String)] = [:]
    private(set) var calls: [[String]] = []
    func run(action args: [String]) async -> (rc: Int32, stdout: Data) {
        calls.append(args)
        let r = responses[args.joined(separator: " ")] ?? (0, "{}")
        return (r.rc, Data(r.out.utf8))
    }
    var confirmed: [[String]] { calls.filter { $0.last == "--yes" } }
}

func detectJSON(_ hs: [(String, Bool, Bool)]) -> String {
    let items = hs.map { "{\"id\":\"\($0.0)\",\"installed\":\($0.1),\"managed\":\($0.2)}" }.joined(separator: ",")
    return "{\"harnesses\":[\(items)],\"tools\":{}}"
}

func statusJSON(_ tool: String, installed: Bool = true, _ hs: [(String, String)]) -> String {
    let items = hs.map { "{\"id\":\"\($0.0)\",\"state\":\"\($0.1)\"}" }.joined(separator: ",")
    return "{\"tool\":\"\(tool)\",\"installed\":\(installed),\"harnesses\":[\(items)]}"
}

func decode<T: Decodable>(_ s: String) -> T { try! JSONDecoder().decode(T.self, from: Data(s.utf8)) }

@MainActor
struct AISetupTests {
    @Test func cliNameLowercases() {
        #expect(AISetup.cliName("RTK") == "rtk")
        #expect(AISetup.cliName("statusline") == "statusline")
    }

    @Test func noManagedShowsInstalledHarnessesPreselected() {
        let d: DetectResult = decode(detectJSON([("claude", true, false), ("opencode", true, false), ("codex", false, false)]))
        let s: AIStatus = decode(statusJSON("rtk", [("claude", "missing"), ("opencode", "unsupported"), ("codex", "missing")]))
        #expect(AISetup.needsHarnessChoice(detect: d))
        let rows = AISetup.rows(status: s, detect: d)
        #expect(rows.map(\.id) == ["claude"])   // codex non installato, opencode non supportato
        #expect(AISetup.preselected(rows) == ["claude"])
    }

    @Test func managedShowsOnlyManagedWithInstallAndUpdateLabels() {
        let d: DetectResult = decode(detectJSON([("claude", true, true), ("opencode", true, true), ("copilot", true, false)]))
        let s: AIStatus = decode(statusJSON("rtk", [("claude", "installed"), ("opencode", "outdated"), ("copilot", "missing")]))
        #expect(!AISetup.needsHarnessChoice(detect: d))
        let rows = AISetup.rows(status: s, detect: d)
        #expect(rows.map(\.id) == ["claude", "opencode"])
        #expect(rows.map(\.actionLabel) == [nil, "Aggiorna"])
        #expect(AISetup.preselected(rows) == ["opencode"])
        #expect(HarnessRow(id: "x", state: "missing").actionLabel == "Installa")
    }

    @Test func newHarnessInstallsOnlyToolsInstalledElsewhere() {
        let rtk: AIStatus = decode(statusJSON("rtk", [("claude", "installed"), ("opencode", "missing")]))
        let caveman: AIStatus = decode(statusJSON("caveman", [("claude", "missing"), ("opencode", "missing")]))
        let ts: AIStatus = decode(statusJSON("tokensave", [("claude", "installed"), ("opencode", "installed")]))
        let abs: AIStatus = decode(statusJSON("statusline", installed: false, [("claude", "installed"), ("opencode", "unsupported")]))
        let acts = AISetup.installsForNewHarness("opencode", otherManaged: ["claude"], statuses: [rtk, caveman, ts, abs])
        #expect(acts.map(\.args) == [["run", "ai-install", "rtk", "opencode"]])
    }

    @Test func newHarnessIgnoresOutdatedElsewhereAndUsesOnlyManaged() {
        let rtk: AIStatus = decode(statusJSON("rtk", [("claude", "outdated"), ("copilot", "installed"), ("opencode", "outdated")]))
        // copilot installato ma non gestito, claude gestito ma non "installed": nessuna azione
        #expect(AISetup.installsForNewHarness("opencode", otherManaged: ["claude"], statuses: [rtk]).isEmpty)
    }

    @Test func modelLoadsStatusAndRequestsPlanWithoutYes() async {
        let f = FakeActions()
        f.responses["detect"] = (0, detectJSON([("claude", true, false), ("opencode", true, false)]))
        f.responses["run ai-status rtk"] = (0, statusJSON("rtk", [("claude", "missing"), ("opencode", "missing")]))
        f.responses["run ai-install rtk claude opencode"] = (0, "{\"tool\":\"rtk\",\"plan\":true,\"commands\":[\"rtk init -g --agent claude\",\"rtk init -g --opencode\"]}")
        let m = AISetupModel(runner: f)
        await m.begin(displayTool: "RTK")
        #expect(m.phase == .ready && m.choosingHarnesses)
        #expect(m.chosenIDs == ["claude", "opencode"])
        await m.requestInstall()
        #expect(m.confirmation.dialogShown)
        #expect(m.confirmation.text == "rtk init -g --agent claude\nrtk init -g --opencode")
        #expect(f.confirmed.isEmpty)   // il piano non esegue nulla
        // untick opencode, ritenta
        m.confirmation.cancel()
        m.selected.remove("opencode")
        #expect(m.chosenIDs == ["claude"])
    }

    @Test func confirmRunsWithYesThenRefreshesStatus() async {
        let f = FakeActions()
        f.responses["detect"] = (0, detectJSON([("claude", true, false)]))
        f.responses["run ai-status rtk"] = (0, statusJSON("rtk", [("claude", "missing")]))
        let m = AISetupModel(runner: f)
        var applied = false
        m.onApplied = { applied = true }
        await m.begin(displayTool: "RTK")
        await m.requestInstall()
        f.responses["run ai-status rtk"] = (0, statusJSON("rtk", [("claude", "installed")]))
        await m.confirm()
        #expect(f.confirmed == [["run", "ai-install", "rtk", "claude", "--yes"]])
        #expect(applied)
        #expect(m.rows.first?.state == "installed")
        #expect(!m.canInstall)
    }

    @Test func missingBinaryOffersToolInstallNotAIInstall() async {
        let f = FakeActions()
        f.responses["detect"] = (0, detectJSON([("claude", true, false)]))
        f.responses["run ai-status tokensave"] = (0, statusJSON("tokensave", installed: false, [("claude", "missing")]))
        let m = AISetupModel(runner: f)
        await m.begin(displayTool: "tokensave")
        #expect(m.toolMissing && m.canInstallBinary && !m.canInstall)
        await m.requestBinaryInstall()
        #expect(m.confirmation.isPending)
        #expect(f.calls.last == ["run", "tool-install", "tokensave"])
    }

    @Test func statuslineAbsentRC3StillDecodes() async {
        let f = FakeActions()
        f.responses["detect"] = (0, detectJSON([("claude", true, true)]))
        f.responses["run ai-status statusline"] = (3, statusJSON("statusline", installed: false, [("claude", "missing")]))
        let m = AISetupModel(runner: f)
        await m.begin(displayTool: "statusline")
        #expect(m.phase == .ready && m.toolMissing && !m.canInstallBinary)
    }

    @Test func unreadableStatusFails() async {
        let f = FakeActions()
        f.responses["detect"] = (0, "boh")
        let m = AISetupModel(runner: f)
        await m.begin(displayTool: "RTK")
        #expect(m.phase == .failed("stato non disponibile"))
    }
}

@MainActor
struct PlanConfirmationTests {
    @Test func planErrorShowsNoDialog() async {
        let f = FakeActions()
        f.responses["run a"] = (2, "{\"status\":\"error\"}")
        let c = PlanConfirmation(runner: f)
        let ok = await c.request(title: "t", actions: [ConfirmableAction(title: "A", args: ["run", "a"])])
        #expect(!ok && !c.dialogShown && c.error != nil)
    }

    @Test func combinedTextAndSequentialYes() async {
        let f = FakeActions()
        f.responses["run x 1"] = (0, "{\"plan\":true,\"commands\":[\"cmd1\"]}")
        f.responses["run x 2"] = (0, "{\"plan\":true,\"commands\":[\"cmd2\"]}")
        let c = PlanConfirmation(runner: f)
        await c.request(title: "t", actions: [ConfirmableAction(title: "X1", args: ["run", "x", "1"]),
                                              ConfirmableAction(title: "X2", args: ["run", "x", "2"])])
        #expect(c.text == "X1\n  cmd1\nX2\n  cmd2")
        #expect(f.confirmed.isEmpty)
        #expect(await c.confirm())
        #expect(f.confirmed == [["run", "x", "1", "--yes"], ["run", "x", "2", "--yes"]])
        #expect(!c.isPending)
    }

    @Test func stopsAtFirstFailure() async {
        let f = FakeActions()
        f.responses["run x 1"] = (0, "{\"commands\":[\"c\"]}")
        f.responses["run x 2"] = (0, "{\"commands\":[\"c\"]}")
        f.responses["run x 1 --yes"] = (2, "{}")
        let c = PlanConfirmation(runner: f)
        await c.request(title: "t", actions: [ConfirmableAction(title: "X1", args: ["run", "x", "1"]),
                                              ConfirmableAction(title: "X2", args: ["run", "x", "2"])])
        #expect(await c.confirm() == false)
        #expect(f.confirmed.count == 1)
        #expect(c.error == "X1: fallito (rc 2)")
    }

    @Test func cancelClears() async {
        let f = FakeActions()
        f.responses["run x"] = (0, "{\"commands\":[\"c\"]}")
        let c = PlanConfirmation(runner: f)
        await c.request(title: "t", actions: [ConfirmableAction(title: "X", args: ["run", "x"])])
        c.cancel()
        #expect(!c.isPending && !c.dialogShown)
    }
}
