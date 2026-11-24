import Testing
import Foundation
@testable import DevbarCore

struct ModelsTests {
    func fixture(_ name: String) throws -> Data {
        let url = try try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    func decode<T: Decodable>(_ t: T.Type, _ name: String) throws -> T {
        try JSONDecoder().decode(T.self, from: fixture(name))
    }

    // MARK: check all

    @Test func testCheckAllRealOutput() throws {
        let all = try AllChecks.decode(fixture("all"))
        #expect(Set(all.rows.keys) == ["brew-outdated", "brew-vulns", "npm-audit", "composer-audit",
            "colima", "rtk", "tokensave", "caveman", "claude-usage", "harnesses"])
        #expect(all.rows["brew-outdated"]?.state == .action)
        #expect(all.rows["colima"]?.state == .ok)
        #expect(all.rows["npm-audit"]?.state == .unconfigured)
        #expect(all.rows["brew-outdated"]?.count == 6)
        #expect(all.rows["brew-outdated"]?.checkedAt != nil)
    }

    @Test func testTypedRows() throws {
        let all = try AllChecks.decode(fixture("all"))
        let bo = try try #require(all.typed(BrewOutdated.self, "brew-outdated"))
        #expect(bo.items.count == 6)
        #expect(bo.items[0].kind == "formula")
        let bv = try try #require(all.typed(BrewVulns.self, "brew-vulns"))
        #expect(bv.items.count == bv.result.count)
        #expect(bv.severe > 0)
        let col = try try #require(all.typed(ColimaStatus.self, "colima"))
        #expect(col.running)
        #expect(col.profiles.first?.name == "default")
        let rtk = try try #require(all.typed(RtkGain.self, "rtk"))
        #expect(rtk.saved > 0)
        #expect(!rtk.daily.isEmpty)
        let ts = try try #require(all.typed(TokensaveGain.self, "tokensave"))
        #expect(ts.missedTurns == 53)
        let cav = try try #require(all.typed(CavemanStatus.self, "caveman"))
        #expect(cav.mode == "full")
        let aud = try try #require(all.typed(AuditResult.self, "npm-audit"))
        #expect(aud.items.isEmpty)
        let cu = try try #require(all.typed(ClaudeUsage.self, "claude-usage"))
        #expect(cu.result.state == .unconfigured)
        #expect(cu.usage == nil)
    }

    @Test func testBusy() throws {
        let all = try AllChecks.decode(fixture("busy"))
        #expect(all.rows["_all"]?.state == .error)
        #expect(all.rows["_all"]?.summary == "busy")
    }

    // MARK: tolleranza

    @Test func testRcMapping() throws {
        for (rc, st) in [(0, CheckState.action), (1, .ok), (2, .error), (3, .unconfigured)] {
            let d = Data(#"{"rc":\#(rc),"status":"zzz"}"#.utf8)
            #expect(try JSONDecoder().decode(CheckResult.self, from: d).state == st)
        }
    }

    @Test func testStatusFallbackWhenRcAbsent() throws {
        let d = Data(#"{"status":"action","count":2,"summary":"x","extra":{"a":1}}"#.utf8)
        let r = try JSONDecoder().decode(CheckResult.self, from: d)
        #expect(r.state == .action)
        #expect(r.count == 2)
        #expect(r.items == [])
        #expect(r.checkedAt == nil)
    }

    @Test func testBadRowBecomesErrorOnlyForThatRow() throws {
        let d = Data(#"{"good":{"status":"ok","rc":1},"bad":{"count":"x"},"worse":42}"#.utf8)
        let all = try AllChecks.decode(d)
        #expect(all.rows["good"]?.state == .ok)
        #expect(all.rows["bad"]?.state == .error)
        #expect(all.rows["worse"]?.state == .error)
    }

    @Test func testTypedUnknownAndMalformedItems() throws {
        let d = Data(#"{"status":"action","rc":0,"count":2,"summary":"s","new":1,"items":[{"name":"a","kind":"cask","zz":1},{"nokey":true}]}"#.utf8)
        let bo = try JSONDecoder().decode(BrewOutdated.self, from: d)
        #expect(bo.items.map(\.name) == ["a"])
    }

    @Test func testCavemanEmptyStringsAreMissing() throws {
        let d = Data(#"{"status":"ok","rc":1,"mode":"","version":""}"#.utf8)
        let c = try JSONDecoder().decode(CavemanStatus.self, from: d)
        #expect(c.mode == nil)
        #expect(c.version == nil)
    }

    @Test func testColimaStoppedNotRunning() throws {
        let d = Data(#"{"status":"ok","rc":1,"profiles":[{"name":"default","status":"Stopped"}]}"#.utf8)
        let c = try JSONDecoder().decode(ColimaStatus.self, from: d)
        #expect(!c.running)
        #expect(c.containers.isEmpty)
    }

    @Test func testClaudeUsageValues() throws {
        let d = Data(#"{"status":"ok","rc":1,"usage":{"c_pct":42,"c_reset":"2026-11-24T18:00:00Z","w_pct":17,"w_reset":null,"stale":false,"auth":"valid","error":null}}"#.utf8)
        let u = try JSONDecoder().decode(ClaudeUsage.self, from: d)
        #expect(u.usage?.cPct == 42)
        #expect(u.usage?.wReset == nil)
        #expect(u.usage?.auth == "valid")
    }

    // MARK: altri comandi

    @Test func testDetect() throws {
        let r = try decode(DetectResult.self, "detect")
        #expect(r.harnesses.count == 6)
        #expect(r.harnesses[0].id == "claude")
        #expect(r.tools["brew"] == true)
    }

    @Test func testRepos() throws {
        let r = try decode([RepoInfo].self, "repos")
        #expect(r.count == 1)
        #expect(r[0].name == "b")
        #expect(r[0].npm)
        #expect(!r[0].composer)
    }

    @Test func testAIStatus() throws {
        let r = try decode(AIStatus.self, "ai-status-rtk")
        #expect(r.tool == "rtk")
        #expect(r.harnesses.count == 6)
        #expect(r.harnesses.first { $0.id == "opencode" }?.state == "outdated")
    }

    @Test func testProjectStatus() throws {
        let r = try decode(ProjectStatus.self, "project-status")
        #expect(r.checks.map(\.tool) == ["rtk", "caveman", "tokensave"])
        #expect(r.checks[0].ok)
        #expect(r.checks[1].willWrite.count == 6)
    }
}
