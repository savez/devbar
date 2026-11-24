import Testing
import Foundation
@testable import DevbarCore

struct PanelModelTests {
    func all() throws -> AllChecks {
        let url = try #require(Bundle.module.url(forResource: "all", withExtension: "json", subdirectory: "Fixtures"))
        return try AllChecks.decode(Data(contentsOf: url))
    }
    func detect(claude: Bool = true, cork: Bool = false) -> DetectResult {
        let json = """
        {"harnesses":[{"id":"claude","installed":\(claude),"managed":false}],"tools":{"cork":\(cork)}}
        """
        return try! JSONDecoder().decode(DetectResult.self, from: Data(json.utf8))
    }
    func mutate(_ name: String, _ patch: (inout [String: JSONValue]) -> Void) throws -> AllChecks {
        var a = try all()
        guard case .object(var o)? = a.raw[name] else { Issue.record("riga assente \(name)"); return a }
        patch(&o)
        a.raw[name] = .object(o)
        a.rows[name] = try JSONDecoder().decode(CheckResult.self, from: JSONEncoder().encode(JSONValue.object(o)))
        return a
    }

    @Test func formatters() {
        #expect(Fmt.tokens(179_000) == "179K")
        #expect(Fmt.tokens(950) == "950")
        #expect(Fmt.tokens(1_200_000) == "1.2M")
        #expect(Fmt.gib(8_589_934_592) == "8GiB")
        #expect(Fmt.gib(64_424_509_440) == "60GiB")
        #expect(Fmt.percent(17.69) == "18%")
        #expect(Fmt.fraction(142) == 1)
        #expect(Fmt.fraction(nil) == 0)
    }

    @Test func resetTimes() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = ISO8601DateFormatter().date(from: "2026-11-24T10:00:00Z")!
        #expect(Fmt.reset("2026-11-24T14:30:00Z", now: now, calendar: cal) == "oggi 14:30")
        #expect(Fmt.reset("2026-11-25T09:00:00Z", now: now, calendar: cal) == "domani 09:00")
        #expect(Fmt.reset("2026-11-27T09:00:00.000Z", now: now, calendar: cal)?.hasSuffix("09:00") == true)
        #expect(Fmt.reset("boh", now: now, calendar: cal) == "boh")
        #expect(Fmt.reset("", now: now, calendar: cal) == nil)
        #expect(Fmt.reset(nil, now: now, calendar: cal) == nil)
    }

    @Test func realOutputSections() throws {
        let m = PanelModel(all: try all(), detect: detect())
        #expect(m.brewState == .shown)
        #expect(m.brewUpgradeEnabled)
        #expect(m.corkButtonTitle == "Installa Cork")
        // npm e composer sono unconfigured: nascosti. Resta brew.
        #expect(m.vulnRows.map(\.id) == ["brew"])
        #expect(m.colimaState == .shown)
        #expect(m.colimaToggleTitle == "Ferma")
        #expect(m.colimaSummary == "attivo, 4 CPU, 8 GB")
        #expect(m.rtkState == .shown)
        #expect(m.rtkLine == "RTK 18%")
        #expect(m.rtkDaily.count <= 7 && !m.rtkDaily.isEmpty)
        #expect(m.usageState == .initOnly)
        #expect(m.tokensaveLine == "tokensave 0 risparmiati, 53 occasioni perse")
    }

    @Test func corkInstalledLabel() throws {
        #expect(PanelModel(all: try all(), detect: detect(cork: true)).corkButtonTitle == "Apri Cork")
    }

    @Test func colimaStoppedShowsAvvia() throws {
        let a = try mutate("colima") { o in
            o["profiles"] = .array([.object(["name": .string("default"), "status": .string("Stopped"),
                "cpus": .number(4), "memoryBytes": .number(8_589_934_592), "diskBytes": .number(64_424_509_440)])])
        }
        let m = PanelModel(all: a, detect: detect())
        #expect(m.colimaToggleTitle == "Avvia")
        #expect(m.colimaSummary == "spento")
    }

    @Test func colimaMissingShowsInit() throws {
        let a = try mutate("colima") { $0["status"] = .string("unconfigured"); $0["rc"] = .number(3) }
        #expect(PanelModel(all: a, detect: detect()).colimaState == .initOnly)
    }

    @Test func statuslineOnlyWithClaude() throws {
        #expect(PanelModel(all: try all(), detect: detect(claude: true)).aiTools == ["RTK", "caveman", "tokensave", "statusline"])
        #expect(PanelModel(all: try all(), detect: detect(claude: false)).aiTools == ["RTK", "caveman", "tokensave"])
    }

    @Test func cavemanPanelFromCheck() throws {
        let c = try #require(PanelModel(all: try all(), detect: detect()).caveman)
        #expect(c.mode == .caveman)
        #expect(c.active)
        #expect(c.statusText == "attivo")
        #expect(c.tone == .ok)
        #expect(c.version == "4.2.0")
    }

    @Test func cavemanHiddenWhenNotInstalled() throws {
        let a = try mutate("caveman") { $0["status"] = .string("unconfigured"); $0["rc"] = .number(3) }
        let m = PanelModel(all: a, detect: detect())
        #expect(m.caveman == nil)
        #expect(!m.showsTokenSection || m.rtkState != .hidden)
    }

    @Test func cavemanOffAndPluginDisabled() throws {
        let off = try mutate("caveman") { $0["mode"] = .string("off"); $0["active"] = .bool(false) }
        let o = try #require(PanelModel(all: off, detect: detect()).caveman)
        #expect(o.statusText == "spento")
        #expect(o.tone == .info)
        #expect(o.toggleTarget(turningOn: true) == .caveman)
        #expect(o.toggleTarget(turningOn: false) == .off)
        let dis = try mutate("caveman") { $0["pluginEnabled"] = .bool(false); $0["active"] = .bool(false) }
        let d = try #require(PanelModel(all: dis, detect: detect()).caveman)
        #expect(d.statusText == "plugin disattivato")
        #expect(d.tone == .action)
        #expect(!d.canToggle)
    }

    @Test func cavemanTurningOnRestoresLastMode() throws {
        let a = try mutate("caveman") { $0["mode"] = .string("off"); $0["active"] = .bool(false); $0["lastMode"] = .string("ultracave") }
        let c = try #require(PanelModel(all: a, detect: detect()).caveman)
        #expect(c.toggleTarget(turningOn: true) == .ultracave)
    }

    @Test func claudeUsageConfigured() throws {
        let a = try mutate("claude-usage") { o in
            o["status"] = .string("ok"); o["rc"] = .number(1)
            // forma reale del binario claude-usage (reset relativi, auth stringa)
            o["usage"] = .object(["c_pct": .number(42), "w_pct": .number(18), "c_reset": .string("3h 12m"),
                                  "w_reset": .string("?"), "stale": .bool(false), "auth": .string("valid")])
        }
        let m = PanelModel(all: a, detect: detect())
        #expect(m.usageState == .shown)
        #expect(m.usageFiveHour == 42)
        #expect(m.usageWeek == 18)
        #expect(m.usageFiveHourReset == "3h 12m")
        #expect(m.usageWeekReset == nil)
        #expect(m.usageNote == nil)
    }

    @Test func planParsing() {
        let json = #"{"tool":"rtk","plan":true,"commands":["brew install rtk-ai/tap/rtk","prosa libera"]}"#
        #expect(ActionPlan.parse(Data(json.utf8)).lines == ["brew install rtk-ai/tap/rtk", "prosa libera"])
        let text = "piano: brew install --cask cork (rilancia con --yes per eseguire)\n"
        #expect(ActionPlan.parse(Data(text.utf8)).lines.count == 1)
        #expect(ActionPlan.parse(Data()).lines.isEmpty)
        let ps = #"{"path":"/p","checks":[{"tool":"rtk","ok":false,"willWrite":["/p/CLAUDE.md"]}]}"#
        #expect(ActionPlan.parse(Data(ps.utf8)).lines == ["/p/CLAUDE.md"])
    }

    @Test func confirmedArgsAddYes() {
        let a = ConfirmableAction(title: "x", args: ["run", "cork-install"])
        #expect(a.args == ["run", "cork-install"])
        #expect(a.confirmedArgs == ["run", "cork-install", "--yes"])
    }

    @Test func footerAndAudit() {
        #expect(PanelModel.footerStatus(engineBusy: false, refreshError: nil, isRefreshing: false) == nil)
        #expect(PanelModel.footerStatus(engineBusy: true, refreshError: "x", isRefreshing: false) == "controllo già in corso")
        #expect(PanelModel.footerStatus(engineBusy: false, refreshError: "x", isRefreshing: false) == "x")
        // il controllo in corso lo mostra la riga della barra di salute
        #expect(PanelModel.footerStatus(engineBusy: false, refreshError: "x", isRefreshing: true) == nil)
        let i = try! JSONDecoder().decode(AuditItem.self, from: Data(#"{"repo":"/r","critical":2,"high":1}"#.utf8))
        #expect(PanelModel.auditSummary(i) == "2 critiche, 1 alte")
    }
}

struct BarIconTests {
    @Test func symbolsAndColors() {
        #expect(BarIcon.symbol(.ok) == "checkmark.shield")
        #expect(BarIcon.symbol(.action) == "arrow.triangle.2.circlepath")
        #expect(BarIcon.symbol(.error) == "exclamationmark.shield")
        #expect(BarIcon.colorName(.ok) == "green")
        #expect(BarIcon.colorName(.action) == "orange")
        #expect(BarIcon.colorName(.error) == "red")
        #expect(BarIcon.countText(0) == nil)
        #expect(BarIcon.countText(4) == "4")
    }
}
