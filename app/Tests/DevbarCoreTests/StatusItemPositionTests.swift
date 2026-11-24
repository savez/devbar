import Foundation
import Testing
@testable import DevbarCore

struct StatusItemPositionTests {
    private func suite() -> UserDefaults {
        let d = UserDefaults(suiteName: "devbar.test.\(UUID().uuidString)")!
        return d
    }

    @Test func seedsWhenMissing() {
        let d = suite()
        #expect(StatusItemPosition.seedIfNeeded(d))
        #expect(d.double(forKey: StatusItemPosition.defaultsKey) == StatusItemPosition.initialValue)
    }

    /// La posizione scelta dall'utente (trascinando l'icona) non si tocca.
    @Test func keepsUserPosition() {
        let d = suite()
        d.set(300.0, forKey: StatusItemPosition.defaultsKey)
        #expect(!StatusItemPosition.seedIfNeeded(d))
        #expect(d.double(forKey: StatusItemPosition.defaultsKey) == 300.0)
    }

    @Test func secondCallIsNoOp() {
        let d = suite()
        #expect(StatusItemPosition.seedIfNeeded(d))
        #expect(!StatusItemPosition.seedIfNeeded(d))
    }
}
