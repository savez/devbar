import Testing
import Foundation
@testable import DevbarCore

@MainActor
struct JournalModelTests {
    static func entry(_ id: String, undone: Bool = false, changed: Bool = false, files: Int = 1,
                      command: String = "run ai-install rtk copilot --yes") -> String {
        let fs = (0..<files).map { i in
            "{\"path\":\"/Users/x/f\(i)\",\"kind\":\"file\",\"existed\":true,\"sha256Before\":null,\"sha256After\":null,\"changed\":\(changed && i == 0)}"
        }.joined(separator: ",")
        return "{\"id\":\"\(id)\",\"time\":\"2026-11-24T10:15:00Z\",\"command\":\"\(command)\",\"undone\":\(undone),\"files\":[\(fs)]}"
    }
    static func list(_ es: [String]) -> String { "{\"entries\":[\(es.joined(separator: ","))]}" }

    @Test func loadsAtMostTenEntries() async {
        let a = FakeActions()
        a.responses["journal --limit 10"] = (0, Self.list((0..<12).map { Self.entry("e\($0)") }))
        let m = JournalModel(runner: a)
        await m.load()
        #expect(m.entries.count == 10)
        #expect(m.entries.first?.id == "e0")
        #expect(m.error == nil)
    }

    @Test func brokenOutputShowsError() async {
        let a = FakeActions()
        a.responses["journal --limit 10"] = (2, "boom")
        let m = JournalModel(runner: a)
        await m.load()
        #expect(m.entries.isEmpty)
        #expect(m.error != nil)
    }

    @Test func rowTexts() {
        let e: JournalEntry = decode(Self.entry("a", files: 3))
        #expect(e.title == "ai-install rtk copilot")
        #expect(e.filesText == "3 file")
        #expect(e.canUndo)
        let u: JournalEntry = decode(Self.entry("b", undone: true))
        #expect(!u.canUndo)
        #expect(JournalEntry.timeText("2026-11-24T10:15:00Z", timeZone: TimeZone(identifier: "UTC")!) == "24/11 10:15")
    }

    @Test func undoShowsPlanThenRunsWithYes() async {
        let a = FakeActions()
        a.responses["journal --limit 10"] = (0, Self.list([Self.entry("abc")]))
        a.responses["undo abc"] = (0, "{\"plan\":true,\"commands\":[\"ripristina ~/f0\"],\"needsForce\":false}")
        a.responses["undo abc --yes"] = (0, "{\"applied\":true,\"id\":\"abc\",\"commands\":[]}")
        let m = JournalModel(runner: a)
        var applied = 0
        m.onApplied = { applied += 1 }
        await m.load()
        await m.requestUndo(m.entries[0])
        #expect(m.confirmation.dialogShown)
        #expect(m.confirmation.text == "ripristina ~/f0")
        #expect(a.confirmed.isEmpty)
        await m.confirmUndo()
        #expect(a.confirmed == [["undo", "abc", "--yes"]])
        #expect(applied == 1)
        #expect(a.calls.filter { $0 == ["journal", "--limit", "10"] }.count == 2)
    }

    @Test func changedFileAsksWithForceAndWarning() async {
        let a = FakeActions()
        a.responses["journal --limit 10"] = (0, Self.list([Self.entry("abc")]))
        // needsForce viene dal piano (stato attuale), non dall'elenco
        a.responses["undo abc"] = (0, "{\"plan\":true,\"commands\":[\"ripristina ~/f0\"],\"needsForce\":true}")
        a.responses["undo abc --force"] = (0, "{\"plan\":true,\"commands\":[\"ripristina ~/f0 — ATTENZIONE\"],\"needsForce\":true}")
        let m = JournalModel(runner: a)
        await m.load()
        await m.requestUndo(m.entries[0])
        #expect(m.confirmation.title.contains("cambiat"))
        #expect(m.confirmation.text.contains("ATTENZIONE"))
        await m.confirmUndo()
        #expect(a.confirmed == [["undo", "abc", "--force", "--yes"]])
    }

    @Test func planUnavailableShowsErrorAndRunsNothing() async {
        let a = FakeActions()
        a.responses["journal --limit 10"] = (0, Self.list([Self.entry("abc")]))
        a.responses["undo abc"] = (2, "{\"status\":\"error\",\"error\":\"x\"}")
        let m = JournalModel(runner: a)
        await m.load()
        await m.requestUndo(m.entries[0])
        #expect(!m.confirmation.dialogShown)
        #expect(m.confirmation.error != nil)
        #expect(a.confirmed.isEmpty)
    }

    @Test func cancelRunsNothing() async {
        let a = FakeActions()
        a.responses["journal --limit 10"] = (0, Self.list([Self.entry("abc")]))
        a.responses["undo abc"] = (0, "{\"plan\":true,\"commands\":[\"x\"],\"needsForce\":false}")
        let m = JournalModel(runner: a)
        await m.load()
        await m.requestUndo(m.entries[0])
        m.confirmation.cancel()
        #expect(a.confirmed.isEmpty)
    }

    @Test func engineRefusalIsShown() async {
        let a = FakeActions()
        a.responses["journal --limit 10"] = (0, Self.list([Self.entry("abc")]))
        a.responses["undo abc"] = (0, "{\"plan\":true,\"commands\":[\"x\"],\"needsForce\":false}")
        a.responses["undo abc --yes"] = (2, "{\"status\":\"error\",\"error\":\"file cambiati da un altro programma\"}")
        let m = JournalModel(runner: a)
        var applied = 0
        m.onApplied = { applied += 1 }
        await m.load()
        await m.requestUndo(m.entries[0])
        await m.confirmUndo()
        #expect(m.confirmation.error?.contains("cambiati") == true)
        #expect(applied == 0)
    }

    @Test func undoneEntryCannotBeUndone() async {
        let a = FakeActions()
        a.responses["journal --limit 10"] = (0, Self.list([Self.entry("abc", undone: true)]))
        let m = JournalModel(runner: a)
        await m.load()
        await m.requestUndo(m.entries[0])
        #expect(!a.calls.contains { $0.first == "undo" })
    }
}

struct JournalTimeoutTests {
    @Test func undoWithYesIsLong() {
        #expect(ActionTimeout.isLong(["undo", "abc", "--yes"]))
        #expect(ActionTimeout.isLong(["undo", "abc", "--force", "--yes"]))
        #expect(!ActionTimeout.isLong(["undo", "abc"]))
        #expect(!ActionTimeout.isLong(["journal"]))
    }
}
