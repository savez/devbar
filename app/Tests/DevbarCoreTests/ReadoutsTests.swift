import Testing
import Foundation
@testable import DevbarCore

/// Fixture reali (`all.json`) e arricchite (`all-rich.json`: audit, container, consumo Claude).
enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
    static func all(_ name: String = "all") throws -> AllChecks { try AllChecks.decode(data(name)) }
    static func detect(_ name: String = "detect") throws -> DetectResult {
        try JSONDecoder().decode(DetectResult.self, from: data(name))
    }
    static func model(rich: Bool) throws -> PanelModel {
        PanelModel(all: try all(rich ? "all-rich" : "all"), detect: try detect(rich ? "detect-rich" : "detect"),
                   now: ISO8601DateFormatter().date(from: "2026-11-24T10:00:00Z")!)
    }
}

struct ToneTests {
    @Test func usageThresholds() {
        #expect(Tone.usage(nil) == .info)
        #expect(Tone.usage(0) == .ok)
        #expect(Tone.usage(69.9) == .ok)
        #expect(Tone.usage(70) == .action)
        #expect(Tone.usage(90) == .action)
        #expect(Tone.usage(90.1) == .risk)
    }

    @Test func approvedHues() {
        #expect(Tone.ok.hex == 0x3FA34D)
        #expect(Tone.action.hex == 0xE0A526)
        #expect(Tone.risk.hex == 0xD6453D)
        #expect(Tone.info.hex == 0x8A8F98)
    }

    @Test func checkStateTone() {
        #expect(Tone.of(.ok) == .ok)
        #expect(Tone.of(.action) == .action)
        // un check fallito non è un rischio
        #expect(Tone.of(.error) == .info)
        #expect(Tone.of(.unconfigured) == .info)
        #expect(Tone.of(nil) == .info)
    }

    @Test func severityTone() {
        #expect(Tone.severity("critical") == .risk)
        #expect(Tone.severity("HIGH") == .risk)
        #expect(Tone.severity("MEDIUM") == .action)
        #expect(Tone.severity("UNKNOWN") == .info)
    }
}

struct FmtExtraTests {
    @Test func gigabytes() {
        #expect(Fmt.gb(8_589_934_592) == "8 GB")
        #expect(Fmt.gb(1_610_612_736) == "1.5 GB")
    }

    @Test func todoText() {
        #expect(Fmt.todo(0) == "Tutto a posto")
        #expect(Fmt.todo(1) == "1 cosa da fare")
        #expect(Fmt.todo(12) == "12 cose da fare")
    }

    @Test func checkedText() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let d = ISO8601DateFormatter().date(from: "2026-11-24T09:05:00Z")!
        #expect(Fmt.checked(d, isRefreshing: false, calendar: cal) == "controllato alle 09:05")
        #expect(Fmt.checked(d, isRefreshing: true, calendar: cal) == "controllo in corso…")
        #expect(Fmt.checked(nil, isRefreshing: false, calendar: cal) == nil)
    }

    @Test func chartDay() {
        #expect(Fmt.day("2026-11-24") == "24/11")
        #expect(Fmt.day("boh") == "boh")
    }

    @Test func compactTokens() {
        #expect(Fmt.tokens(193_742) == "194K")
        #expect(Fmt.tokens(187_000) == "187K")
    }
}

struct HealthStripTests {
    @Test func realFixtureSegments() throws {
        let m = try Fixture.model(rich: false)
        let s = HealthStrip(model: m, badge: (.error, 12))
        #expect(s.segments.map(\.area) == [.homebrew, .vulns, .colima, .tokens, .aiSetup])
        #expect(s.segments.map(\.tone) == [.action, .risk, .info, .info, .info])
        #expect(s.todoText == "12 cose da fare")
        #expect(s.todoTone == .risk)
    }

    /// Consumo al 76%: l'indicatore è ambra, il segmento Token resta informativo.
    @Test func richFixtureTokensStayInformative() throws {
        let m = try Fixture.model(rich: true)
        let s = HealthStrip(model: m, badge: (.error, 15))
        #expect(s.segments.first { $0.area == .tokens }?.tone == .info)
        #expect(m.usageMeters.first?.tone == .action)
    }

    @Test func allQuiet() throws {
        let s = HealthStrip(model: PanelModel(all: try AllChecks.decode(Data("{}".utf8))), badge: (.ok, 0))
        #expect(s.segments.isEmpty)
        #expect(s.todoText == "Tutto a posto")
        #expect(s.todoTone == .ok)
    }

    /// Il numero sotto la barra è quello del badge: 6 pacchetti + 6 formule colpite.
    @MainActor @Test func todoMatchesBadge() async throws {
        let runner = FakeRunner(["check all": .init(rc: 0, stdout: String(decoding: try Fixture.data("all"), as: UTF8.self))])
        let store = StatusStore(runner: runner, allTimeout: 5, actionTimeout: 5)
        await store.refresh(force: false)
        let m = PanelModel(all: AllChecks(rows: store.results, raw: store.raw))
        #expect(HealthStrip(model: m, badge: store.badge).todoText == "12 cose da fare")
    }
}

struct ReadoutTests {
    @Test func homebrew() throws {
        let r = try Fixture.model(rich: false).brewReadout
        #expect(r.value == "6")
        #expect(r.tone == .action)
        #expect(r.subtitle == "pacchetti da aggiornare")
    }

    @Test func homebrewUpToDate() throws {
        let json = #"{"brew-outdated":{"status":"ok","rc":1,"count":0,"summary":"","items":[]}}"#
        let r = PanelModel(all: try AllChecks.decode(Data(json.utf8))).brewReadout
        #expect(r.value == "0")
        #expect(r.tone == .ok)
        #expect(r.subtitle == "aggiornato")
    }

    @Test func homebrewError() throws {
        let json = #"{"brew-outdated":{"status":"error","rc":2,"count":0,"summary":"timeout","items":[]}}"#
        let r = PanelModel(all: try AllChecks.decode(Data(json.utf8))).brewReadout
        #expect(r.value == nil)
        #expect(r.tone == .info)
        #expect(r.subtitle == "timeout")
    }

    /// Formule distinte con CVE alte o critiche, non il numero di CVE (`severe` = 8).
    @Test func vulnsCountFormulae() throws {
        let m = try Fixture.model(rich: false)
        #expect(m.severeFormulae == ["openssl@3", "openssl@4"])
        let r = m.vulnReadout
        #expect(r.value == "2")
        #expect(r.tone == .risk)
        #expect(r.subtitle == "alte o critiche, 6 in totale")
        // npm e composer non configurati: nessuna riga repo
        #expect(r.note == nil)
    }

    @Test func vulnsWithRepos() throws {
        let r = try Fixture.model(rich: true).vulnReadout
        #expect(r.value == "3")
        #expect(r.subtitle == "alte o critiche, 7 in totale")
        #expect(r.note == "3 repo con problemi")
    }

    @Test func vulnsOnlyModerateIsAction() throws {
        let json = #"{"npm-audit":{"status":"action","rc":0,"count":1,"summary":"","items":[{"repo":"/r","moderate":2}]}}"#
        let r = PanelModel(all: try AllChecks.decode(Data(json.utf8))).vulnReadout
        #expect(r.value == "0")
        #expect(r.tone == .action)
        #expect(r.subtitle == "1 repo con problemi")
    }

    @Test func colima() throws {
        let plain = try Fixture.model(rich: false).colimaReadout
        #expect(plain.value == nil)
        #expect(plain.subtitle == "attivo, 4 CPU, 8 GB")
        let rich = try Fixture.model(rich: true).colimaReadout
        #expect(rich.value == "2")
        #expect(rich.note == "container attivi")
    }

    @Test func tokens() throws {
        let m = try Fixture.model(rich: true)
        #expect(m.tokensReadout.value == "194K")
        #expect(m.rtkLine == "RTK 18%")
        #expect(m.usageMeters.map(\.label) == ["5h", "7 giorni"])
        #expect(m.usageMeters.map(\.tone) == [.action, .ok])
        #expect(m.usageMeters.map(\.percentText) == ["76%", "42%"])
        #expect(m.usageMeters.first?.reset == "reset oggi 14:30" || m.usageMeters.first?.reset?.hasPrefix("reset ") == true)
        // senza claude-usage configurato: nessun indicatore
        #expect(try Fixture.model(rich: false).usageMeters.isEmpty)
    }
}

struct DetailsTests {
    @Test func brewRows() throws {
        let rows = try Fixture.model(rich: false).brewDetailRows
        #expect(rows.count == 6)
        #expect(rows[0] == BrewDetailRow(name: "aws-c-mqtt", installed: "1.1.3_1", available: "1.1.4", kind: "Formula"))
        #expect(rows.filter { $0.kind == "Cask" }.count == 4)
        let byName = rows.sorted(using: [KeyPathComparator(\BrewDetailRow.name, order: .reverse)])
        #expect(byName.first?.name == "tunnelblick")
    }

    @Test func vulnFilterAndOrder() throws {
        let m = try Fixture.model(rich: true)
        let all = m.vulnDetailRows(filter: .all)
        #expect(all.count == m.brewVulnItems.count)
        // dalle più gravi
        #expect(all.first?.formula == "curl")
        #expect(all.first?.severity == "Critica")
        #expect(all.first?.tone == .risk)
        let severe = m.vulnDetailRows(filter: .severe)
        #expect(severe.count == 9)
        #expect(severe.allSatisfy { $0.severityRank >= 3 })
        #expect(Set(severe.map(\.formula)) == ["curl", "openssl@3", "openssl@4"])
        #expect(all.last?.fix == "nessuna" || all.last?.fix == "disponibile")
    }

    @Test func auditRows() throws {
        let m = try Fixture.model(rich: true)
        #expect(m.showsAudit)
        let rows = m.auditDetailRows
        #expect(rows.map(\.repo) == ["shop", "blog", "tools", "legacy"])
        #expect(rows.map(\.tool) == ["npm", "npm", "npm", "composer"])
        #expect(rows.map(\.tone) == [.risk, .action, .ok, .info])
        #expect(m.tone(of: .audit) == .risk)
        #expect(!(try Fixture.model(rich: false).showsAudit))
    }

    @Test func colimaRows() throws {
        let m = try Fixture.model(rich: true)
        #expect(m.colimaProfileRows.map(\.name) == ["default", "lab"])
        #expect(m.colimaProfileRows.map(\.status) == ["attivo", "spento"])
        #expect(m.colimaProfileRows.first?.memory == "8 GB")
        #expect(m.containerRows.map(\.name) == ["postgres", "redis"])
    }

    @Test func areaTones() throws {
        let m = try Fixture.model(rich: false)
        #expect(m.tone(of: .homebrew) == .action)
        #expect(m.tone(of: .vulns) == .risk)
        #expect(m.tone(of: .audit) == .info)
        #expect(m.tone(of: .colima) == .info)
        #expect(m.tone(of: .tokens) == .info)
        #expect(Area.detailsAreas == [.homebrew, .vulns, .audit, .colima, .tokens])
    }

    @Test func rtkAllDaily() throws {
        let m = try Fixture.model(rich: false)
        #expect(m.rtkAllDaily.count == 7)
        #expect(m.rtkSaved == 193_742)
        #expect(m.tokensave?.missedTurns == 53)
        #expect(m.cavemanMode == "caveman")
    }
}
