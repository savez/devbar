import Testing
import Foundation
@testable import DevbarCore

@MainActor
struct CavemanControlTests {
    @Test func modesAreTheFiveDefaults() {
        #expect(CavemanMode.allCases.map(\.rawValue) == ["off", "manual", "caveman", "ultracave", "megacave"])
        #expect(CavemanMode.off.label == "Spento")
        #expect(CavemanMode.manual.label == "Manuale")
        #expect(CavemanMode.allCases.allSatisfy { !$0.summary.isEmpty })
    }

    @Test func setModeRunsDirectlyWithYesAndShowsNote() async {
        let r = FakeActions()
        r.responses["run caveman-mode ultracave --yes"] = (0, #"{"applied":true,"value":"ultracave","commands":["Scrive defaultMode = \"ultracave\"","vale per le nuove sessioni"]}"#)
        let c = CavemanControl(runner: r)
        var applied = 0
        c.onApplied = { applied += 1 }
        await c.set(.ultracave)
        #expect(r.calls == [["run", "caveman-mode", "ultracave", "--yes"]])
        #expect(c.note?.contains("vale per le nuove sessioni") == true)
        #expect(c.error == nil)
        #expect(!c.busy)
        #expect(applied == 1)
    }

    @Test func setModeFailureShowsEngineError() async {
        let r = FakeActions()
        r.responses["run caveman-mode off --yes"] = (2, #"{"status":"error","error":"config caveman non valida"}"#)
        let c = CavemanControl(runner: r)
        await c.set(.off)
        #expect(c.error == "caveman: config caveman non valida")
        #expect(c.note == nil)
    }
}
