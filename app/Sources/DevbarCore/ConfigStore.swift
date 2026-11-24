import Foundation

/// Config di devbar. Chiavi e default come nei Global Constraints.
public struct DevbarConfig: Codable, Equatable, Sendable {
    public var repoRoots: [String] = []
    public var scanDepth: Int = 4
    public var dailyCheckTime: String = "09:00"
    public var harnesses: [String] = []
    public var brewExclude: [String] = []
    public var terminal: String = "Terminal"
    public var launchAtLogin: Bool = true

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case repoRoots, scanDepth, dailyCheckTime, harnesses, brewExclude, terminal, launchAtLogin
    }

    /// Tollerante: chiavi mancanti o di tipo errato tornano al default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DevbarConfig()
        repoRoots = (try? c.decodeIfPresent([String].self, forKey: .repoRoots)) ?? d.repoRoots
        scanDepth = (try? c.decodeIfPresent(Int.self, forKey: .scanDepth)) ?? d.scanDepth
        dailyCheckTime = (try? c.decodeIfPresent(String.self, forKey: .dailyCheckTime)) ?? d.dailyCheckTime
        harnesses = (try? c.decodeIfPresent([String].self, forKey: .harnesses)) ?? d.harnesses
        brewExclude = (try? c.decodeIfPresent([String].self, forKey: .brewExclude)) ?? d.brewExclude
        terminal = (try? c.decodeIfPresent(String.self, forKey: .terminal)) ?? d.terminal
        launchAtLogin = (try? c.decodeIfPresent(Bool.self, forKey: .launchAtLogin)) ?? d.launchAtLogin
    }
}

public final class ConfigStore {
    public let url: URL

    /// `DEVBAR_CONFIG` ha la precedenza, poi `~/.config/devbar/config.json`.
    public static func defaultURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let p = environment["DEVBAR_CONFIG"], !p.isEmpty { return URL(fileURLWithPath: p) }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/devbar/config.json")
    }

    public init(url: URL = ConfigStore.defaultURL()) { self.url = url }

    /// File assente: default, nessun errore. JSON rotto: default + messaggio.
    public func load() -> (DevbarConfig, error: String?) {
        guard FileManager.default.fileExists(atPath: url.path) else { return (DevbarConfig(), nil) }
        do {
            let data = try Data(contentsOf: url)
            guard (try JSONSerialization.jsonObject(with: data)) is [String: Any] else {
                return (DevbarConfig(), "config non valida: non è un oggetto JSON")
            }
            return (try JSONDecoder().decode(DevbarConfig.self, from: data), nil)
        } catch {
            return (DevbarConfig(), "config non valida: \(error.localizedDescription)")
        }
    }

    /// Scrittura atomica; le chiavi sconosciute già nel file restano.
    public func save(_ config: DevbarConfig) throws {
        var dict: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let old = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            dict = old
        }
        let encoded = try JSONEncoder().encode(config)
        if let known = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] {
            dict.merge(known) { _, new in new }
        }
        let out = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try out.write(to: url, options: .atomic)
    }
}
