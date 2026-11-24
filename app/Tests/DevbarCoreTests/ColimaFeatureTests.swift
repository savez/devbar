import Testing
import Foundation
@testable import DevbarCore

/// Modulo colima: modello (righe, riassunto, numero) e azioni (avvia/ferma, container,
/// log, installazione tramite la conferma comune).
@MainActor
struct ColimaFeatureTests {
    func mutate(_ patch: (inout [String: JSONValue]) -> Void) throws -> AllChecks {
        var a = try Fixture.all()
        guard case .object(var o)? = a.raw["colima"] else { Issue.record("riga colima assente"); return a }
        patch(&o)
        a.raw["colima"] = .object(o)
        a.rows["colima"] = try JSONDecoder().decode(CheckResult.self, from: JSONEncoder().encode(JSONValue.object(o)))
        return a
    }

    func feature(_ all: AllChecks? = nil, runner: FakeActions? = nil,
                 locks: SectionLocks? = nil) throws -> ColimaFeature {
        let f = ColimaFeature(runner: runner ?? FakeActions(), locks: locks ?? SectionLocks())
        f.update(from: try all ?? Fixture.all())
        return f
    }

    // MARK: Modello

    @Test func stoppedProfileNotRunning() throws {
        let d = Data(#"{"status":"ok","rc":1,"profiles":[{"name":"default","status":"Stopped"}]}"#.utf8)
        let c = try JSONDecoder().decode(ColimaStatus.self, from: d)
        #expect(!c.running)
        #expect(c.containers.isEmpty)
    }

    @Test func realOutput() throws {
        let f = try feature()
        #expect(f.area == .colima)
        #expect(f.panel.kind == .shown)
        #expect(f.panel.toggleTitle == "Ferma")
        #expect(f.panel.summary == "attivo, 4 CPU, 8 GB")
        #expect(f.tone == .info)
    }

    @Test func stoppedShowsAvvia() throws {
        let a = try mutate { o in
            o["profiles"] = .array([.object(["name": .string("default"), "status": .string("Stopped"),
                "cpus": .number(4), "memoryBytes": .number(8_589_934_592), "diskBytes": .number(64_424_509_440)])])
        }
        let f = try feature(a)
        #expect(f.panel.toggleTitle == "Avvia")
        #expect(f.panel.summary == "spento")
    }

    @Test func missingShowsInit() throws {
        let a = try mutate { $0["status"] = .string("unconfigured"); $0["rc"] = .number(3) }
        let f = try feature(a)
        #expect(f.panel.kind == .initOnly)
        #expect(f.readout == Readout(tone: .info, subtitle: "non installato"))
    }

    @Test func hiddenWithoutRow() throws {
        let f = try feature(try AllChecks.decode(Data("{}".utf8)))
        #expect(f.panel.kind == .hidden)
        #expect(f.readout == nil)
    }

    @Test func readout() throws {
        let plain = try #require(try feature().readout)
        #expect(plain.value == nil)
        #expect(plain.subtitle == "attivo, 4 CPU, 8 GB")
        let rich = try #require(try feature(try Fixture.all("all-rich")).readout)
        #expect(rich.value == "2")
        #expect(rich.note == "container attivi")
    }

    @Test func detailRows() throws {
        let p = try feature(try Fixture.all("all-rich")).panel
        #expect(p.profileRows.map(\.name) == ["default", "lab"])
        #expect(p.profileRows.map(\.status) == ["attivo", "spento"])
        #expect(p.profileRows.first?.memory == "8 GB")
        #expect(p.containerRows.map(\.name) == ["postgres", "redis"])
    }

    // MARK: Azioni

    @Test func toggleStopsRunningDefaultProfileWithoutName() async throws {
        let r = FakeActions()
        let f = try feature(runner: r)
        var applied = 0
        f.onApplied = { applied += 1 }
        await f.toggle()
        #expect(r.calls == [["run", "colima-stop"]])
        #expect(applied == 1)
    }

    @Test func profileRowAppendsNameUnlessDefault() async throws {
        let r = FakeActions()
        let f = try feature(try Fixture.all("all-rich"), runner: r)
        for row in f.panel.profileRows { await f.toggle(row) }
        #expect(r.calls == [["run", "colima-stop"], ["run", "colima-start", "lab"]])
    }

    @Test func logsDoNotRefreshContainerStopDoes() async throws {
        let r = FakeActions()
        let f = try feature(runner: r)
        var applied = 0
        f.onApplied = { applied += 1 }
        await f.openLogs("abc")
        #expect(applied == 0)
        await f.stopContainer("abc")
        #expect(applied == 1)
        #expect(r.calls == [["run", "colima-logs", "abc"], ["run", "container-stop", "abc"]])
    }

    @Test func errorGoesToSinkAndClearsOnSuccess() async throws {
        let r = FakeActions()
        r.responses["run colima-stop"] = (2, "")
        let f = try feature(runner: r)
        var errors: [String?] = []
        f.onError = { errors.append($0) }
        await f.toggle()
        r.responses["run colima-stop"] = (0, "")
        await f.toggle()
        #expect(errors == ["run colima-stop: errore (rc 2)", nil])
    }

    /// Nessun doppio `colima start`: con la sezione occupata il secondo clic non parte.
    @Test func noDoubleStartWhileBusy() async throws {
        let r = FakeActions()
        let locks = SectionLocks()
        let f = try feature(runner: r, locks: locks)
        var inner = true
        _ = await locks.occupy(["run", "colima-install"]) {
            #expect(f.busy)
            await f.toggle()
            inner = f.busy
        }
        #expect(inner)
        #expect(r.calls.isEmpty)
        #expect(!f.busy)
    }

    @Test func installGoesThroughCommonConfirmation() async throws {
        let r = FakeActions()
        let f = try feature(runner: r)
        var asked: [(ConfirmableAction, DialogOrigin)] = []
        f.confirm = { asked.append(($0, $1)) }
        await f.installColima(from: .details)
        #expect(asked.count == 1)
        #expect(asked.first?.0 == ConfirmableAction(title: "Installa colima", args: ["run", "colima-install"]))
        #expect(asked.first?.1 == .details)
        #expect(r.calls.isEmpty)
    }

    // MARK: Barra e Dettagli

    @Test func stripTakesColimaFromFeature() throws {
        let m = try Fixture.model(rich: false)
        let s = HealthStrip(model: m, features: [try feature()], badge: (.error, 12))
        #expect(s.segments.map(\.area) == [.homebrew, .vulns, .colima, .tokens, .aiSetup])
        let hidden = try feature(try AllChecks.decode(Data("{}".utf8)))
        #expect(!HealthStrip(model: m, features: [hidden], badge: (.ok, 0)).segments.contains { $0.area == .colima })
    }
}
