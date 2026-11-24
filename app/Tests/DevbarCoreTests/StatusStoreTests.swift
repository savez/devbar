import Testing
import Foundation
@testable import DevbarCore

// MARK: - Runner finto

/// Runner finto: risposte per argomenti, ritardo opzionale che rispetta il timeout
/// (come CLIRunner: allo scadere torna rc 2), conteggio delle chiamate.
actor FakeRunner: CLIRunning {
    struct Reply: Sendable {
        var rc: Int32
        var stdout: String
        var delay: TimeInterval = 0
    }

    private var replies: [String: Reply]
    private(set) var calls: [[String]] = []

    init(_ replies: [String: Reply]) { self.replies = replies }

    func set(_ key: String, _ r: Reply) { replies[key] = r }

    /// Chiave: argomenti senza `--force`, uniti da spazio.
    static func key(_ args: [String]) -> String { args.filter { $0 != "--force" }.joined(separator: " ") }

    func run(_ args: [String], timeout: TimeInterval) async -> (rc: Int32, stdout: Data, stderr: String) {
        calls.append(args)
        let r = replies[Self.key(args)] ?? Reply(rc: 2, stdout: "")
        if r.delay > 0 {
            let wait = min(r.delay, timeout)
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            if r.delay > timeout { return (2, Data(), "timeout") }
        }
        return (r.rc, Data(r.stdout.utf8), "")
    }

    func count(_ key: String) -> Int { calls.filter { Self.key($0) == key }.count }
}

/// Orologio finto, regolabile dai test.
final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { t } }
    func advance(_ s: TimeInterval) { lock.withLock { t += s } }
}

// MARK: - JSON di prova

func row(_ status: String, rc: Int, count: Int = 0, extra: String = "") -> String {
    #"{"status":"\#(status)","rc":\#(rc),"count":\#(count),"summary":"s","items":[]\#(extra)}"#
}

func allJSON(_ rows: [String: String]) -> String {
    "{" + rows.map { #""\#($0.key)":\#($0.value)"# }.joined(separator: ",") + "}"
}

let quietRows: [String: String] = [
    "brew-outdated": row("ok", rc: 1),
    "brew-vulns": row("ok", rc: 1, extra: #","severe":0"#),
    "npm-audit": row("unconfigured", rc: 3),
    "composer-audit": row("unconfigured", rc: 3),
    "colima": row("ok", rc: 1),
    "rtk": row("ok", rc: 1),
    "tokensave": row("ok", rc: 1),
    "caveman": row("ok", rc: 1),
    "claude-usage": row("unconfigured", rc: 3),
    "harnesses": row("ok", rc: 1),
]

func rows(_ overrides: [String: String]) -> [String: String] {
    quietRows.merging(overrides) { _, new in new }
}

// MARK: - StatusStore

@MainActor
struct StatusStoreTests {
    func makeStore(_ runner: FakeRunner, clock: FakeClock = FakeClock(),
                   allTimeout: TimeInterval = 5) -> StatusStore {
        StatusStore(runner: runner, now: { clock.now }, allTimeout: allTimeout, actionTimeout: 5)
    }

    @Test func testSevereVulnsMakeBadgeError() async {
        let items = #"[{"formula":"openssl@3","id":"CVE-1","severity":"HIGH","fixAvailable":true},{"formula":"curl","id":"CVE-2","severity":"CRITICAL","fixAvailable":false},{"formula":"curl","id":"CVE-3","severity":"LOW","fixAvailable":false}]"#
        let vulns = #"{"status":"action","rc":0,"count":3,"summary":"s","severe":2,"items":\#(items)}"#
        let runner = FakeRunner(["check all": .init(rc: 1, stdout: allJSON(rows(["brew-vulns": vulns])))])
        let store = makeStore(runner)
        await store.refresh(force: false)
        #expect(store.results["brew-vulns"]?.state == .action)
        #expect(store.badge.level == .error)
        // formule distinte (openssl@3, curl), non le 3 vulnerabilità
        #expect(store.badge.count == 2)
    }

    /// Icona rossa: il numero è quello della riga Vulnerabilità (pacchetti colpiti più progetti
    /// con problemi), senza gli aggiornamenti Homebrew.
    @Test func testRedBadgeShowsVulnerabilityTotalNotEverything() async {
        func item(_ f: String, _ sev: String) -> String { #"{"formula":"\#(f)","id":"CVE-\#(f)","severity":"\#(sev)","fixAvailable":true}"# }
        let brew = (1...6).map { item("pkg\($0)", $0 <= 2 ? "HIGH" : "LOW") }.joined(separator: ",")
        let vulns = #"{"status":"action","rc":0,"count":9,"summary":"s","severe":2,"items":[\#(brew)]}"#
        let repos = (1...4).map { #"{"repo":"/r\#($0)","critical":0,"high":0,"moderate":1,"low":0}"# }.joined(separator: ",")
        let npm = #"{"status":"action","rc":0,"count":4,"summary":"s","items":[\#(repos)]}"#
        let runner = FakeRunner(["check all": .init(rc: 1, stdout: allJSON(rows([
            "brew-outdated": row("action", rc: 0, count: 3),
            "brew-vulns": vulns,
            "npm-audit": npm,
        ])))])
        let store = makeStore(runner)
        await store.refresh(force: false)
        #expect(store.badge.level == .error)
        #expect(store.badge.count == 10)   // 6 pacchetti + 4 progetti, non 3 + 6 + 4 = 13
        let m = PanelModel(all: AllChecks(rows: store.results, raw: store.raw))
        #expect(m.vulnReadout.value == "10")
    }

    @Test func testAuditCriticalMakesBadgeError() async {
        let audit = #"{"status":"action","rc":0,"count":1,"summary":"s","items":[{"repo":"/r","critical":0,"high":1,"moderate":0,"low":0}]}"#
        let runner = FakeRunner(["check all": .init(rc: 1, stdout: allJSON(rows(["npm-audit": audit])))])
        let store = makeStore(runner)
        await store.refresh(force: false)
        #expect(store.badge.level == .error)
        #expect(store.badge.count == 1)
    }

    @Test func testModerateOnlyAuditIsAction() async {
        let audit = #"{"status":"action","rc":0,"count":1,"summary":"s","items":[{"repo":"/r","critical":0,"high":0,"moderate":4,"low":0}]}"#
        let runner = FakeRunner(["check all": .init(rc: 1, stdout: allJSON(rows(["composer-audit": audit])))])
        let store = makeStore(runner)
        await store.refresh(force: false)
        #expect(store.badge.level == .action)
        #expect(store.badge.count == 1)
    }

    @Test func testBadgeCountExcludesInformativeAndErrors() async {
        let runner = FakeRunner(["check all": .init(rc: 1, stdout: allJSON(rows([
            "brew-outdated": row("action", rc: 0, count: 6),
            "harnesses": row("action", rc: 0, count: 2),
            "tokensave": row("action", rc: 0, count: 53),
            "caveman": row("action", rc: 0, count: 1),
            "colima": row("error", rc: 2, count: 9),
        ])))])
        let store = makeStore(runner)
        await store.refresh(force: false)
        // harnesses è informativo: solo brew-outdated (6) conta
        #expect(store.badge.count == 6)
        #expect(store.badge.level == .action)
    }

    @Test func testAllQuietIsOk() async {
        let runner = FakeRunner(["check all": .init(rc: 1, stdout: allJSON(quietRows))])
        let store = makeStore(runner)
        await store.refresh(force: false)
        #expect(store.badge.level == .ok)
        #expect(store.badge.count == 0)
        #expect(store.lastRefresh != nil)
        #expect(!store.isRefreshing)
    }

    @Test func testFailedCheckDoesNotRaiseBadge() async {
        let runner = FakeRunner(["check all": .init(rc: 1, stdout: allJSON(rows([
            "brew-vulns": row("error", rc: 2),
        ])))])
        let store = makeStore(runner)
        await store.refresh(force: false)
        #expect(store.results["brew-vulns"]?.state == .error)
        #expect(store.badge.level == .ok)
    }

    @Test func testHangingCheckBecomesErrorOthersUpdated() async {
        // Il motore uccide il check bloccato e lo riporta come riga "timeout".
        let runner = FakeRunner(["check all": .init(rc: 1, stdout: allJSON(rows([
            "brew-outdated": row("action", rc: 0, count: 4),
            "npm-audit": #"{"rc":2,"status":"error","summary":"timeout"}"#,
        ])))])
        let store = makeStore(runner)
        await store.refresh(force: false)
        #expect(store.results["npm-audit"]?.state == .error)
        #expect(store.results["npm-audit"]?.summary == "timeout")
        #expect(store.results["brew-outdated"]?.state == .action)
        #expect(store.results["brew-outdated"]?.count == 4)
        #expect(store.results["colima"]?.state == .ok)
        #expect(store.refreshError == nil)
        #expect(store.badge.count == 4)
        #expect(await runner.calls.count == 1)
    }

    @Test func testBackstopTimeoutKeepsPreviousResults() async {
        let runner = FakeRunner(["check all": .init(rc: 1, stdout: allJSON(rows([
            "brew-outdated": row("action", rc: 0, count: 6),
        ])))])
        let clock = FakeClock()
        let store = makeStore(runner, clock: clock, allTimeout: 0.05)
        await store.refresh(force: false)
        let first = store.lastRefresh
        clock.advance(60)
        await runner.set("check all", .init(rc: 1, stdout: allJSON(quietRows), delay: 30))
        let start = Date()
        await store.refresh(force: false)
        #expect(Date().timeIntervalSince(start) < 2)
        #expect(store.refreshError != nil)
        #expect(!store.engineBusy)
        #expect(store.results["brew-outdated"]?.count == 6)
        #expect(store.badge.count == 6)
        #expect(store.lastRefresh == first)
        #expect(await runner.calls.count == 2)
    }

    @Test func testGlobalNonBusyErrorIsRefreshError() async {
        let runner = FakeRunner(["check all": .init(rc: 1, stdout: allJSON(rows([
            "brew-outdated": row("action", rc: 0, count: 6),
        ])))])
        let store = makeStore(runner)
        await store.refresh(force: false)
        await runner.set("check all", .init(rc: 2, stdout: #"{"status":"error","error":"jq mancante"}"#))
        await store.refresh(force: false)
        #expect(!store.engineBusy)
        #expect(store.refreshError == "jq mancante")
        #expect(store.results["_all"] == nil)
        #expect(store.results["brew-outdated"]?.count == 6)
        // Un refresh riuscito azzera l'errore.
        await runner.set("check all", .init(rc: 1, stdout: allJSON(quietRows)))
        await store.refresh(force: false)
        #expect(store.refreshError == nil)
        #expect(store.badge.count == 0)
    }

    @Test func testPanelOpenedTwiceWithinFiveMinutesRunsOnce() async {
        let clock = FakeClock()
        let runner = FakeRunner(["check all": .init(rc: 1, stdout: allJSON(quietRows))])
        let store = makeStore(runner, clock: clock)
        await store.panelOpened()
        clock.advance(4 * 60)
        await store.panelOpened()
        #expect(await runner.count("check all") == 1)
        clock.advance(2 * 60)
        await store.panelOpened()
        #expect(await runner.count("check all") == 2)
    }

    @Test func testConcurrentRefreshRunsOnce() async {
        let runner = FakeRunner(["check all": .init(rc: 1, stdout: allJSON(quietRows), delay: 0.05)])
        let store = makeStore(runner)
        async let a: Void = store.refresh(force: false)
        async let b: Void = store.refresh(force: true)
        _ = await (a, b)
        #expect(await runner.count("check all") == 1)
    }

    @Test func testBusyKeepsPreviousResults() async {
        let runner = FakeRunner(["check all": .init(rc: 1, stdout: allJSON(rows([
            "brew-outdated": row("action", rc: 0, count: 6),
        ])))])
        let store = makeStore(runner)
        await store.refresh(force: false)
        #expect(!store.engineBusy)
        await runner.set("check all", .init(rc: 2, stdout: #"{"status":"error","error":"busy"}"#))
        await store.refresh(force: true)
        #expect(store.engineBusy)
        #expect(store.refreshError == nil)
        #expect(store.results["_all"] == nil)
        #expect(store.results["brew-outdated"]?.count == 6)
        #expect(store.badge.count == 6)
    }

    /// Il punto d'aggancio dei moduli: solo dopo un refresh riuscito, mai su motore
    /// occupato, errore globale o output non decodificabile.
    @Test func testOnResultsOnlyOnSuccessfulRefresh() async {
        let runner = FakeRunner(["check all": .init(rc: 1, stdout: allJSON(quietRows))])
        let store = makeStore(runner)
        var seen: [Int] = []
        store.onResults = { seen.append($0.rows.count) }
        await store.refresh(force: false)
        #expect(seen == [quietRows.count])
        await runner.set("check all", .init(rc: 2, stdout: #"{"status":"error","error":"busy"}"#))
        await store.refresh(force: true)
        await runner.set("check all", .init(rc: 2, stdout: #"{"status":"error","error":"jq mancante"}"#))
        await store.refresh(force: true)
        await runner.set("check all", .init(rc: 2, stdout: "non json"))
        await store.refresh(force: true)
        #expect(seen == [quietRows.count])
        await runner.set("check all", .init(rc: 1, stdout: allJSON(rows(["rtk": row("ok", rc: 1)]))))
        await store.refresh(force: true)
        #expect(seen.count == 2)
    }

    @Test func testForceFlagPassed() async {
        let runner = FakeRunner(["check all": .init(rc: 1, stdout: allJSON(quietRows))])
        let store = makeStore(runner)
        await store.refresh(force: true)
        #expect(await runner.calls.first == ["check", "all", "--force"])
        await store.refresh(force: false)
        #expect(await runner.calls.last == ["check", "all"])
    }

    @Test func testRunActionPassesThrough() async {
        let runner = FakeRunner(["run brew-upgrade wget": .init(rc: 0, stdout: "ok")])
        let store = makeStore(runner)
        let r = await store.run(action: ["run", "brew-upgrade", "wget"])
        #expect(r.rc == 0)
        #expect(String(decoding: r.stdout, as: UTF8.self) == "ok")
    }

    @Test func testBrokenConfigReported() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("devbar-ss-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let u = dir.appendingPathComponent("config.json")
        try "{ rotto".write(to: u, atomically: true, encoding: .utf8)
        let store = StatusStore(runner: FakeRunner([:]), configStore: ConfigStore(url: u))
        store.reloadConfig()
        #expect(store.configError != nil)
        #expect(store.config == DevbarConfig())
    }
}

// MARK: - Timer giornaliero

struct DailyScheduleTests {
    var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }

    func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.calendar = cal; f.timeZone = cal.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }

    @Test func testLaterToday() {
        #expect(StatusStore.nextDailyFire(after: date("2026-11-24 08:00"), time: "09:00", calendar: cal)
            == date("2026-11-24 09:00"))
    }

    @Test func testPassedGoesTomorrow() {
        #expect(StatusStore.nextDailyFire(after: date("2026-11-24 09:00"), time: "09:00", calendar: cal)
            == date("2026-11-25 09:00"))
        #expect(StatusStore.nextDailyFire(after: date("2026-11-24 22:10"), time: "07:30", calendar: cal)
            == date("2026-11-25 07:30"))
    }

    @Test func testInvalidTimeFallsBackToDefault() {
        #expect(StatusStore.nextDailyFire(after: date("2026-11-24 08:00"), time: "25:99", calendar: cal)
            == date("2026-11-24 09:00"))
        #expect(StatusStore.nextDailyFire(after: date("2026-11-24 08:00"), time: "boh", calendar: cal)
            == date("2026-11-24 09:00"))
    }
}

// MARK: - CLIRunner

struct CLIRunnerTests {
    @Test func testLocateOrder() {
        let all: Set<String> = ["/x/devbar", "/opt/homebrew/bin/devbar", "/h/.local/bin/devbar"]
        #expect(CLIRunner.locate(environment: ["DEVBAR_BIN": "/x/devbar"], home: "/h", resourceDirectory: nil,
                                 isExecutable: all.contains) == "/x/devbar")
        #expect(CLIRunner.locate(environment: [:], home: "/h", resourceDirectory: nil, isExecutable: all.contains)
            == "/h/.local/bin/devbar")
        #expect(CLIRunner.locate(environment: [:], home: "/h", resourceDirectory: nil,
                                 isExecutable: { $0 == "/opt/homebrew/bin/devbar" }) == "/opt/homebrew/bin/devbar")
        #expect(CLIRunner.locate(environment: [:], home: "/h", resourceDirectory: nil, isExecutable: { _ in false }) == nil)
    }

    @Test func testLocatePrefersBundledEngine() {
        let bundled = "/App/Contents/Resources/engine/bin/devbar"
        let all: Set<String> = ["/x/devbar", bundled, "/opt/homebrew/bin/devbar", "/h/.local/bin/devbar"]
        // DEVBAR_BIN batte il motore nel bundle.
        #expect(CLIRunner.locate(environment: ["DEVBAR_BIN": "/x/devbar"], home: "/h",
                                 resourceDirectory: "/App/Contents/Resources", isExecutable: all.contains) == "/x/devbar")
        // Il bundle batte ~/.local/bin e Homebrew.
        #expect(CLIRunner.locate(environment: [:], home: "/h",
                                 resourceDirectory: "/App/Contents/Resources", isExecutable: all.contains) == bundled)
        // Motore assente nel bundle: si ricade su ~/.local/bin.
        #expect(CLIRunner.locate(environment: [:], home: "/h", resourceDirectory: "/App/Contents/Resources",
                                 isExecutable: { $0 == "/h/.local/bin/devbar" }) == "/h/.local/bin/devbar")
    }

    @Test func testChildPath() {
        #expect(CLIRunner.childPath(inherited: "/usr/bin:/bin", home: "/h")
            == "/opt/homebrew/bin:/usr/local/bin:/h/.local/bin:/usr/bin:/bin")
        #expect(CLIRunner.childPath(inherited: nil, home: "/h")
            == "/opt/homebrew/bin:/usr/local/bin:/h/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
    }

    func script(_ body: String) throws -> (URL, String) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("devbar-run-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let u = dir.appendingPathComponent("devbar")
        try ("#!/bin/sh\n" + body + "\n").write(to: u, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: u.path)
        return (dir, u.path)
    }

    @Test func testRealProcessOutputAndRc() async throws {
        let (dir, bin) = try script(#"echo "{\"a\":\"$1\"}"; echo "$PATH" >&2; exit 3"#)
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = await CLIRunner(environment: ["DEVBAR_BIN": bin, "PATH": "/usr/bin:/bin"], home: "/h").run(["x"], timeout: 10)
        #expect(r.rc == 3)
        #expect(String(decoding: r.stdout, as: UTF8.self) == "{\"a\":\"x\"}\n")
        #expect(r.stderr.hasPrefix("/opt/homebrew/bin:/usr/local/bin:/h/.local/bin:/usr/bin:/bin"))
    }

    @Test func testLargeOutputNoDeadlock() async throws {
        let (dir, bin) = try script("head -c 2000000 /dev/zero | tr '\\0' a; head -c 300000 /dev/zero | tr '\\0' b >&2; exit 0")
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = await CLIRunner(environment: ["DEVBAR_BIN": bin]).run([], timeout: 20)
        #expect(r.rc == 0)
        #expect(r.stdout.count == 2_000_000)
        #expect(r.stderr.count == 300_000)
    }

    @Test func testTimeoutKillsProcessTree() async throws {
        let (dir, bin) = try script("sleep 60 & echo $! > \"$(dirname \"$0\")/bg.pid\"; sleep 60")
        defer { try? FileManager.default.removeItem(at: dir) }
        let start = Date()
        let r = await CLIRunner(environment: ["DEVBAR_BIN": bin]).run([], timeout: 0.3)
        #expect(r.rc == 2)
        #expect(Date().timeIntervalSince(start) < 3)
        let text = try String(contentsOf: dir.appendingPathComponent("bg.pid"), encoding: .utf8)
        let bg = try #require(pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)))
        // Il nipote in background muore con il gruppo (con un semplice kill(pid) resterebbe vivo).
        // Breve attesa: l'orfano ucciso va raccolto da launchd prima che kill(…, 0) fallisca.
        var alive = true
        for _ in 0..<20 where alive {
            alive = kill(bg, 0) == 0
            if alive { try await Task.sleep(nanoseconds: 50_000_000) }
        }
        if alive { kill(bg, SIGKILL) }
        #expect(!alive)
    }

    @Test func testTimeoutEscalatesToKill() async throws {
        let (dir, bin) = try script("trap '' TERM; while :; do sleep 0.1; done")
        defer { try? FileManager.default.removeItem(at: dir) }
        let start = Date()
        let r = await CLIRunner(environment: ["DEVBAR_BIN": bin]).run([], timeout: 0.2)
        #expect(r.rc == 2)
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test func testMissingBinary() async {
        let r = await CLIRunner(environment: ["DEVBAR_BIN": "/nonexistent/devbar"], home: "/nonexistent", isExecutable: { _ in false })
            .run(["check", "all"], timeout: 1)
        #expect(r.rc == 2)
        #expect(r.stdout.isEmpty)
        #expect(!r.stderr.isEmpty)
    }
}
