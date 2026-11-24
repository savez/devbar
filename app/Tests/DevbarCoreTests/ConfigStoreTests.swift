import Testing
import Foundation
@testable import DevbarCore

final class ConfigStoreTests {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("devbar-cfg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: dir) }

    @Test func testMissingFileGivesDefaults() {
        let (c, err) = ConfigStore(url: dir.appendingPathComponent("nope/config.json")).load()
        #expect(c == DevbarConfig())
        #expect(err == nil)
        #expect(c.scanDepth == 4)
        #expect(c.dailyCheckTime == "09:00")
        #expect(c.terminal == "Terminal")
        #expect(c.launchAtLogin)
    }

    @Test func testBrokenJSONGivesDefaultsAndError() throws {
        let u = dir.appendingPathComponent("config.json")
        try "{ rotto".write(to: u, atomically: true, encoding: .utf8)
        let (c, err) = ConfigStore(url: u).load()
        #expect(c == DevbarConfig())
        #expect(err != nil)
    }

    @Test func testNonObjectJSONIsError() throws {
        let u = dir.appendingPathComponent("config.json")
        try "[1,2]".write(to: u, atomically: true, encoding: .utf8)
        #expect(ConfigStore(url: u).load().error != nil)
    }

    @Test func testPartialFileKeepsOtherDefaults() throws {
        let u = dir.appendingPathComponent("config.json")
        try #"{"scanDepth":7,"terminal":3}"#.write(to: u, atomically: true, encoding: .utf8)
        let (c, err) = ConfigStore(url: u).load()
        #expect(err == nil)
        #expect(c.scanDepth == 7)
        #expect(c.terminal == "Terminal")
    }

    @Test func testSaveLoadRoundTripPreservesUnknownKeys() throws {
        let u = dir.appendingPathComponent("sub/config.json")
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"x":1,"scanDepth":2}"#.write(to: u, atomically: true, encoding: .utf8)
        let store = ConfigStore(url: u)
        var (c, _) = store.load()
        c.repoRoots = ["/tmp/a"]
        c.launchAtLogin = false
        try store.save(c)
        let (back, err) = store.load()
        #expect(err == nil)
        #expect(back == c)
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: u)) as? [String: Any]
        #expect(raw?["x"] as? Int == 1)
    }

    @Test func testSaveCreatesMissingDirectory() throws {
        let u = dir.appendingPathComponent("a/b/config.json")
        try ConfigStore(url: u).save(DevbarConfig())
        #expect(FileManager.default.fileExists(atPath: u.path))
    }

    @Test func testEnvOverride() {
        #expect(ConfigStore.defaultURL(environment: ["DEVBAR_CONFIG": "/x/y.json"]).path == "/x/y.json")
    }
}
