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
    /// Moduli (Feature) aggiornati dalla stessa fixture.
    @MainActor static let host = FakeHost()
    @MainActor static func features(rich: Bool) throws -> [any Feature] {
        let colima = ColimaFeature(runner: FakeActions(), locks: SectionLocks(), host: host)
        colima.update(from: FeatureInput(all: try all(rich ? "all-rich" : "all")))
        return [colima]
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

@MainActor
struct TokensToneTests {
    /// Consumo al 76%: l'indicatore è ambra, la sezione Token resta informativa.
    @Test func richFixtureTokensStayInformative() throws {
        let m = try Fixture.model(rich: true)
        #expect(m.tokensTone == .info)
        #expect(m.usageMeters.first?.tone == .action)
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

    /// Il numero grande è il totale dei pacchetti colpiti (formule distinte, non CVE); quelli
    /// con gravità alta o critica stanno nella riga sotto e decidono il rosso.
    @Test func vulnsCountFormulae() throws {
        let m = try Fixture.model(rich: false)
        #expect(m.severeFormulae == ["openssl@3", "openssl@4"])
        let r = m.vulnReadout
        #expect(r.value == "6")
        #expect(r.tone == .risk)
        #expect(r.subtitle == "6 pacchetti Homebrew, 2 con gravità alta o critica")
        // npm e composer non configurati: nessuna riga repo
        #expect(r.note == nil)
    }

    @Test func vulnsWithRepos() throws {
        let r = try Fixture.model(rich: true).vulnReadout
        #expect(r.value == "10")
        #expect(r.subtitle == "7 pacchetti Homebrew, 3 con gravità alta o critica")
        #expect(r.note == "3 progetti con problemi")
    }

    @Test func vulnsOnlyModerateIsAction() throws {
        let json = #"{"npm-audit":{"status":"action","rc":0,"count":1,"summary":"","items":[{"repo":"/r","moderate":2}]}}"#
        let r = PanelModel(all: try AllChecks.decode(Data(json.utf8))).vulnReadout
        #expect(r.value == "1")
        #expect(r.tone == .action)
        #expect(r.subtitle == "1 progetto con problemi")
    }

    @Test func tokens() throws {
        let m = try Fixture.model(rich: true)
        #expect(m.tokensReadout.value == "194K")
        #expect(m.rtkLine == "RTK 18%")
        #expect(m.usageMeters.map(\.label) == ["Sessione 5 ore", "Settimana"])
        #expect(m.usageMeters.map(\.tone) == [.action, .ok])
        #expect(m.usageMeters.map(\.percentText) == ["76%", "42%"])
        #expect(m.usageMeters.first?.reset?.hasPrefix("si azzera ") == true)
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

    @Test func areaTones() throws {
        let m = try Fixture.model(rich: false)
        #expect(m.tone(of: .homebrew) == .action)
        #expect(m.tone(of: .vulns) == .risk)
        #expect(m.tone(of: .audit) == .info)
        #expect(m.tone(of: .tokens) == .info)
        #expect(Area.detailsAreas == [.homebrew, .vulns, .advisories, .audit, .colima, .tokens])
    }

    @Test func rtkAllDaily() throws {
        let m = try Fixture.model(rich: false)
        #expect(m.rtkAllDaily.count == 7)
        #expect(m.rtkSaved == 193_742)
        #expect(m.tokensave?.missedTurns == 53)
        #expect(m.cavemanMode == "caveman")
    }

    // MARK: - Card "Token risparmiati": una riga per strumento

    func withTokenEconomizer(_ all: AllChecks, state: String = "ok", active: Bool? = true) throws -> AllChecks {
        var a = all
        let activeJSON = active.map { #","active":\#($0)"# } ?? ""
        let summary = state == "unconfigured" ? "TokenEconomizer non installato"
            : (active == true ? "TokenEconomizer attivo" : "TokenEconomizer spento")
        let json = #"{"status":"\#(state)","rc":\#(state == "unconfigured" ? 3 : 1),"count":0,"summary":"\#(summary)","items":[],"checkedAt":"2026-11-24T09:25:26Z"\#(activeJSON)}"#
        a.raw["tokeneconomizer"] = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        a.rows["tokeneconomizer"] = try JSONDecoder().decode(CheckResult.self, from: Data(json.utf8))
        return a
    }

    func baseAll() throws -> AllChecks {
        let url = try #require(Bundle.module.url(forResource: "all", withExtension: "json", subdirectory: "Fixtures"))
        return try AllChecks.decode(Data(contentsOf: url))
    }

    @Test func tokenRowsOnePerTool() throws {
        let m = PanelModel(all: try withTokenEconomizer(try baseAll()))
        #expect(m.tokenRows.map(\.id) == ["rtk", "tokensave", "tokeneconomizer", "caveman"])
        let rtk = try #require(m.tokenRows.first { $0.id == "rtk" })
        #expect(rtk.title == "RTK" && rtk.value == "194K")
        #expect(rtk.detail == "output dei comandi ridotto del 18%")
        #expect(rtk.daily.count <= 7 && !rtk.daily.isEmpty)
        let ts = try #require(m.tokenRows.first { $0.id == "tokensave" })
        #expect(ts.value == "0")
        #expect(ts.detail == "53 volte l'agente ha letto file invece di usare tokensave")
        #expect(ts.daily.isEmpty)
    }

    @Test func tokenRowTokenEconomizerShowsOnlyActiveOrNot() throws {
        let on = PanelModel(all: try withTokenEconomizer(try baseAll(), active: true))
        let r1 = try #require(on.tokenRows.first { $0.id == "tokeneconomizer" })
        #expect(r1.value == nil && r1.active == true && r1.detail == "attivo")
        let off = PanelModel(all: try withTokenEconomizer(try baseAll(), active: false))
        let r2 = try #require(off.tokenRows.first { $0.id == "tokeneconomizer" })
        #expect(r2.value == nil && r2.active == false && r2.detail == "TokenEconomizer spento")
    }

    @Test func tokenEconomizerNotInstalledHasNoRowButInitButton() throws {
        let m = PanelModel(all: try withTokenEconomizer(try baseAll(), state: "unconfigured", active: nil))
        #expect(!m.tokenRows.contains { $0.id == "tokeneconomizer" })
        #expect(m.tokenEconomizerState == .initOnly)
    }

    @Test func tokenRowCavemanHasStateNoNumber() throws {
        let m = PanelModel(all: try baseAll())
        let cv = try #require(m.tokenRows.first { $0.id == "caveman" })
        #expect(cv.value == nil && cv.active == true)
        #expect(cv.detail == "risposte più corte, nessun conteggio disponibile")
    }

    @Test func tokenTotalSumsRtkAndTokensave() throws {
        let m = PanelModel(all: try baseAll())
        #expect(m.tokenTotal == 193_742)             // RTK 193742 + tokensave 0
        #expect(m.tokensReadout.value == "194K")
        #expect(m.tokensReadout.subtitle == "somma di RTK e tokensave")
        // senza RTK né tokensave: nessun numero
        let none = PanelModel(all: try AllChecks.decode(Data(#"{"brew-outdated":{"status":"ok","rc":1,"count":0,"summary":"","items":[]}}"#.utf8)))
        #expect(none.tokenTotal == nil && none.tokensReadout.value == nil)
    }

    @Test func limitsSectionIsSeparateFromTokens() throws {
        let m = try Fixture.model(rich: true)
        #expect(m.showsLimits)
        let off = try Fixture.model(rich: false)
        #expect(off.usageState == .initOnly)            // claude-usage non installato
        #expect(m.usageState == .shown)
    }

    @Test func tokenEconomizerIsInAISetupWhenSupported() throws {
        let detect = try JSONDecoder().decode(DetectResult.self, from: Data(#"{"harnesses":[{"id":"claude","installed":true,"managed":false}],"tools":{"cork":false},"aiTools":{"rtk":true,"caveman":true,"tokensave":true,"tokeneconomizer":true,"statusline":true}}"#.utf8))
        let m = PanelModel(all: try baseAll(), detect: detect)
        #expect(m.aiTools == ["RTK", "caveman", "tokensave", "TokenEconomizer", "statusline"])
        #expect(AISetup.tools.contains("tokeneconomizer"))
        #expect(AISetup.cliName("TokenEconomizer") == "tokeneconomizer")
        #expect(AISetup.binaryInstallable.contains("tokeneconomizer"))
    }
}
