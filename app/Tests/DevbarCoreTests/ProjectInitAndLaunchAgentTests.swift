import Testing
import Foundation
@testable import DevbarCore

@MainActor
struct ProjectInitModelTests {
    let statusOK = """
    {"path":"/r/app","checks":[
     {"tool":"rtk","ok":true,"detail":"hook globale installato","willWrite":[]},
     {"tool":"caveman","ok":false,"detail":"da scrivere","willWrite":["AGENTS.md",".clinerules/caveman.md"]},
     {"tool":"tokensave","ok":false,"detail":"indice assente","willWrite":["/r/app/.tokensave/"]}]}
    """

    @Test func loadsReposAndStatusRows() async {
        let f = FakeActions()
        f.responses["repos"] = (0, "[{\"path\":\"/r/app\",\"name\":\"app\",\"npm\":true,\"composer\":false,\"tokensave\":false}]")
        f.responses["run project-status /r/app"] = (0, statusOK)
        let m = ProjectInitModel(runner: f)
        await m.loadRepos()
        #expect(m.repos.map(\.name) == ["app"])
        await m.select("/r/app")
        #expect(m.rows.map(\.tool) == ["rtk", "caveman", "tokensave"])
        #expect(m.willWrite == ["AGENTS.md", ".clinerules/caveman.md", "/r/app/.tokensave/"])
        #expect(m.canApply)
    }

    @Test func nothingToWriteDisablesApply() async {
        let f = FakeActions()
        f.responses["run project-status /r/app"] = (0, #"{"path":"/r/app","checks":[{"tool":"rtk","ok":true,"detail":"ok","willWrite":[]}]}"#)
        let m = ProjectInitModel(runner: f)
        await m.select("/r/app")
        #expect(!m.canApply)
        await m.requestApply()
        #expect(!m.confirmation.isPending)
    }

    @Test func notAGitRepoShowsError() async {
        let f = FakeActions()
        f.responses["run project-status /tmp/x"] = (2, #"{"status":"error","error":"non è un repo git: /tmp/x"}"#)
        let m = ProjectInitModel(runner: f)
        await m.select("/tmp/x")
        #expect(m.error == "non è un repo git: /tmp/x" && m.rows.isEmpty && !m.canApply)
    }

    @Test func applyShowsPlanThenYes() async {
        let f = FakeActions()
        f.responses["run project-status /r/app"] = (0, statusOK)
        f.responses["run project-apply /r/app"] = (0, statusOK)
        let m = ProjectInitModel(runner: f)
        await m.select("/r/app")
        await m.requestApply()
        #expect(m.confirmation.text == "AGENTS.md\n.clinerules/caveman.md\n/r/app/.tokensave/")
        #expect(f.confirmed.isEmpty)
        await m.confirmApply()
        #expect(f.confirmed == [["run", "project-apply", "/r/app", "--yes"]])
        #expect(f.calls.last == ["run", "project-status", "/r/app"])   // rilegge lo stato
    }
}

@MainActor
struct LaunchAgentTests {
    @Test func plistContent() throws {
        let data = try LaunchAgent.plist(executablePath: "/Users/u/Applications/devbar.app/Contents/MacOS/Devbar")
        let d = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(d["Label"] as? String == "it.savez.devbar")
        #expect(d["ProgramArguments"] as? [String] == ["/Users/u/Applications/devbar.app/Contents/MacOS/Devbar"])
        #expect(d["RunAtLoad"] as? Bool == true)
        #expect(d["ProcessType"] as? String == "Interactive")
        #expect(d["LimitLoadToSessionType"] as? String == "Aqua")
        #expect(d.count == 5)
        #expect(LaunchAgent.plistURL(home: "/h").path == "/h/Library/LaunchAgents/it.savez.devbar.plist")
    }

    final class FakeCtl: LaunchctlRunning, @unchecked Sendable {
        private let lock = NSLock()
        private var _calls: [[String]] = []
        var bootstrapRC: Int32 = 0
        var printRC: Int32 = 113   // non caricato
        var calls: [[String]] { lock.withLock { _calls } }
        func launchctl(_ args: [String]) -> Int32 {
            lock.withLock { _calls.append(args) }
            switch args.first {
            case "bootstrap": return bootstrapRC
            case "print": return printRC
            default: return 0
            }
        }
    }

    @Test func enableWritesPlistAndBootstraps_disableRemoves() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("la-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("it.savez.devbar.plist")
        let ctl = FakeCtl()
        let m = LaunchAgentManager(plistURL: url, uid: 501, launchctl: ctl)
        #expect(!m.isEnabled())
        try m.enable(executablePath: "/x/Devbar")
        #expect(m.isEnabled())
        #expect(ctl.calls == [["print", "gui/501/it.savez.devbar"], ["bootstrap", "gui/501", url.path]])
        try m.disable()
        #expect(!m.isEnabled())
        #expect(!ctl.calls.contains { $0.first == "bootout" })   // disable non uccide l'app
    }

    @Test func enableWhenAlreadyLoadedSkipsBootstrap() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("la-\(UUID().uuidString)")
        let ctl = FakeCtl(); ctl.printRC = 0
        let m = LaunchAgentManager(plistURL: dir.appendingPathComponent("p.plist"), uid: 501, launchctl: ctl)
        try m.enable(executablePath: "/x")
        #expect(ctl.calls == [["print", "gui/501/it.savez.devbar"]])
    }

    @Test func bootstrapFailureThrows() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("la-\(UUID().uuidString)")
        let ctl = FakeCtl(); ctl.bootstrapRC = 5
        let m = LaunchAgentManager(plistURL: dir.appendingPathComponent("p.plist"), uid: 501, launchctl: ctl)
        #expect(throws: LoginItemError.self) { try m.enable(executablePath: "/x") }
    }
}

struct LoginReconcilerTests {
    func tmpPlist() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("devbar-\(UUID().uuidString)/LaunchAgents/it.savez.devbar.plist")
    }

    @Test func writesMissingPlistWhenEnabled() throws {
        let url = tmpPlist()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
        let o = try LoginReconciler.reconcile(launchAtLogin: true, plistURL: url, executablePath: "/A/devbar")
        #expect(o == .wrote)
        let d = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any]
        #expect((d?["ProgramArguments"] as? [String]) == ["/A/devbar"])
    }

    @Test func removesPlistWhenDisabled() throws {
        let url = tmpPlist()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
        try LoginReconciler.reconcile(launchAtLogin: true, plistURL: url, executablePath: "/A/devbar")
        #expect(try LoginReconciler.reconcile(launchAtLogin: false, plistURL: url, executablePath: "/A/devbar") == .removed)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func noChangeWhenAlreadyInSync() throws {
        let url = tmpPlist()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
        #expect(try LoginReconciler.reconcile(launchAtLogin: false, plistURL: url, executablePath: "/A") == .unchanged)
        try LoginReconciler.reconcile(launchAtLogin: true, plistURL: url, executablePath: "/A")
        let before = try Data(contentsOf: url)
        #expect(try LoginReconciler.reconcile(launchAtLogin: true, plistURL: url, executablePath: "/B") == .unchanged)
        #expect(try Data(contentsOf: url) == before)
    }

    @Test func singleInstanceGuard() {
        #expect(!SingleInstance.shouldExit(ownPID: 10, otherPIDs: []))
        #expect(!SingleInstance.shouldExit(ownPID: 10, otherPIDs: [10]))
        #expect(SingleInstance.shouldExit(ownPID: 10, otherPIDs: [10, 22]))
    }
}
