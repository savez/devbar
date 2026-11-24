import Testing
import Foundation
@testable import DevbarCore

/// Host finto: registra conferme chieste, refresh ed errori.
@MainActor
final class FakeHost: FeatureHost {
    private(set) var requests: [(ConfirmableAction, DialogOrigin)] = []
    private(set) var appliedCount = 0
    private(set) var errors: [String?] = []
    func request(_ action: ConfirmableAction, from origin: DialogOrigin) async { requests.append((action, origin)) }
    func applied() async { appliedCount += 1 }
    func report(error: String?) { errors.append(error) }
}

/// Modulo colima: modello (righe, riassunto, numero) e azioni (avvia/ferma, container,
/// log, installazione tramite la conferma comune).
@MainActor
struct ColimaFeatureTests {
    /// Il modulo tiene l'host `unowned`: lo tiene vivo il test.
    let host: FakeHost
    init() { host = FakeHost() }

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
        let f = ColimaFeature(runner: runner ?? FakeActions(), locks: locks ?? SectionLocks(), host: host)
        f.update(from: FeatureInput(all: try all ?? Fixture.all()))
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
        #expect(f.areas == [.colima])
        #expect(f.panel.kind == .shown)
        #expect(f.panel.toggleTitle == "Ferma")
        #expect(f.panel.summary == "attivo, 4 CPU, 8 GB")
        #expect(f.tone(of: .colima) == .info)
        // Riga e segmento hanno lo stesso tono.
        #expect(f.readout?.tone == f.tone(of: .colima))
        #expect(f.segment == StripSegment(area: .colima, tone: .info))
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
        await f.toggle()
        #expect(r.calls == [["run", "colima-stop"]])
        #expect(host.appliedCount == 1)
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
        await f.openLogs("abc")
        #expect(host.appliedCount == 0)
        await f.stopContainer("abc")
        #expect(host.appliedCount == 1)
        #expect(r.calls == [["run", "colima-logs", "abc"], ["run", "container-stop", "abc"]])
    }

    @Test func errorGoesToSinkAndClearsOnSuccess() async throws {
        let r = FakeActions()
        r.responses["run colima-stop"] = (2, "")
        let f = try feature(runner: r)
        await f.toggle()
        r.responses["run colima-stop"] = (0, "")
        await f.toggle()
        #expect(host.errors == ["run colima-stop: errore (rc 2)", nil])
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
        await f.installColima(from: .details)
        #expect(host.requests.count == 1)
        #expect(host.requests.first?.0 == ConfirmableAction(title: "Installa colima", args: ["run", "colima-install"]))
        #expect(host.requests.first?.1 == .details)
        #expect(r.calls.isEmpty)
    }

    // MARK: Sezione e azioni lunghe dichiarate dal modulo

    @Test func declaresLockSectionAndLongVerbs() {
        let spec = ColimaFeature.actions
        #expect(spec.section == "colima")
        #expect(FeatureRegistry.actionSpecs.contains { $0.section == "colima" })
        #expect(ActionSection.of(["run", "colima-start"]) == spec.section)
        #expect(ActionSection.of(["run", "container-stop", "x"]) == spec.section)
        #expect(ActionSection.of(["run", "colima-install"]) == spec.section)
        #expect(ActionTimeout.isLong(["run", "colima-start"]))
        #expect(ActionTimeout.isLong(["run", "colima-stop", "work"]))
        #expect(!ActionTimeout.isLong(["run", "colima-install", "--yes"]))
        // Le altre aree restano mappate come prima.
        #expect(ActionSection.of(["run", "brew-upgrade"]) == "brew")
        #expect(ActionSection.of(["run", "tool-install", "rtk"]) == "tokens")
    }

    @Test func acceptsDetectInInput() throws {
        let f = try feature()
        let before = f.panel
        f.update(from: FeatureInput(all: try Fixture.all(), detect: try Fixture.detect()))
        #expect(f.panel == before)
    }

    // MARK: Barra e Dettagli

    @Test func stripTakesColimaFromFeature() throws {
        let m = try Fixture.model(rich: false)
        let s = HealthStrip(model: m, features: [try feature()], badge: (.error, 12))
        #expect(s.segments.map(\.area) == [.homebrew, .vulns, .colima, .tokens, .aiSetup])
        let hidden = try feature(try AllChecks.decode(Data("{}".utf8)))
        #expect(hidden.segment == nil)
        #expect(!HealthStrip(model: m, features: [hidden], badge: (.ok, 0)).segments.contains { $0.area == .colima })
    }
}
