import Foundation

public enum DevbarCore {
    public static let version = "0.1.0"
}

// MARK: - JSON generico

/// Valore JSON arbitrario, per campi `items` che il core non tipizza.
public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .null }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

// MARK: - Stato

public enum CheckState: Equatable, Sendable {
    case action, ok, error, unconfigured

    /// rc: 0 action, 1 ok, 2 error, 3 unconfigured.
    public init?(rc: Int) {
        switch rc {
        case 0: self = .action
        case 1: self = .ok
        case 2: self = .error
        case 3: self = .unconfigured
        default: return nil
        }
    }

    public init?(status: String) {
        switch status {
        case "action": self = .action
        case "ok": self = .ok
        case "error": self = .error
        case "unconfigured": self = .unconfigured
        default: return nil
        }
    }
}

// MARK: - Helper di decodifica tollerante

private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

private func top(_ decoder: Decoder) throws -> KeyedDecodingContainer<AnyKey> {
    try decoder.container(keyedBy: AnyKey.self)
}

private extension KeyedDecodingContainer where K == AnyKey {
    func opt<T: Decodable>(_ key: String) -> T? {
        (try? decodeIfPresent(T.self, forKey: AnyKey(key))) ?? nil
    }
    /// Stringa vuota = assente.
    func optText(_ key: String) -> String? {
        guard let s: String = opt(key), !s.isEmpty else { return nil }
        return s
    }
    func list<T: Decodable>(_ key: String) -> [T] {
        // Elemento malformato: scartato, non invalida la lista.
        guard var arr = try? nestedUnkeyedContainer(forKey: AnyKey(key)) else { return [] }
        var out: [T] = []
        while !arr.isAtEnd {
            if let v = try? arr.decode(T.self) { out.append(v) } else { _ = try? arr.decode(JSONValue.self) }
        }
        return out
    }
}

// MARK: - CheckResult

/// Oggetto comune a tutti i check. Decodifica tollerante: chiavi sconosciute ignorate.
public struct CheckResult: Decodable, Equatable, Sendable {
    public var state: CheckState
    public var count: Int
    public var summary: String
    public var items: [JSONValue]
    public var checkedAt: String?

    public init(state: CheckState, count: Int = 0, summary: String = "", items: [JSONValue] = [], checkedAt: String? = nil) {
        self.state = state; self.count = count; self.summary = summary
        self.items = items; self.checkedAt = checkedAt
    }

    public static func failure(_ message: String) -> CheckResult {
        CheckResult(state: .error, summary: message)
    }

    public init(from decoder: Decoder) throws {
        let c = try top(decoder)
        let rc: Int? = c.opt("rc")
        let status: String? = c.opt("status")
        guard let st = rc.flatMap(CheckState.init(rc:)) ?? status.flatMap(CheckState.init(status:)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "né rc né status riconoscibili"))
        }
        state = st
        count = c.opt("count") ?? 0
        let err: String? = c.opt("error")
        summary = c.opt("summary") ?? err ?? ""
        items = c.opt("items") ?? []
        checkedAt = c.opt("checkedAt")
    }
}

// MARK: - Risultati tipizzati

public struct BrewOutdatedItem: Decodable, Equatable, Sendable {
    public var name: String
    public var kind: String
    public var installed: String?
    public var current: String?
    public init(from decoder: Decoder) throws {
        let c = try top(decoder)
        name = try c.decode(String.self, forKey: AnyKey("name"))
        kind = c.opt("kind") ?? "formula"
        installed = c.opt("installed"); current = c.opt("current")
    }
}

public struct BrewOutdated: Decodable, Equatable, Sendable {
    public var result: CheckResult
    public var items: [BrewOutdatedItem]
    public init(from decoder: Decoder) throws {
        result = try CheckResult(from: decoder)
        items = try top(decoder).list("items")
    }
}

public struct BrewVulnItem: Decodable, Equatable, Sendable {
    public var formula: String
    public var id: String
    public var severity: String
    public var fixAvailable: Bool
    public init(from decoder: Decoder) throws {
        let c = try top(decoder)
        formula = try c.decode(String.self, forKey: AnyKey("formula"))
        id = c.opt("id") ?? ""
        severity = c.opt("severity") ?? "UNKNOWN"
        fixAvailable = c.opt("fixAvailable") ?? false
    }
}

public struct BrewVulns: Decodable, Equatable, Sendable {
    public var result: CheckResult
    public var items: [BrewVulnItem]
    public var severe: Int
    public init(from decoder: Decoder) throws {
        result = try CheckResult(from: decoder)
        let c = try top(decoder)
        items = c.list("items")
        severe = c.opt("severe") ?? 0
    }
}

public struct AuditItem: Decodable, Equatable, Sendable {
    public var repo: String
    public var critical: Int
    public var high: Int
    public var moderate: Int
    public var low: Int
    public var error: String?
    public init(from decoder: Decoder) throws {
        let c = try top(decoder)
        repo = try c.decode(String.self, forKey: AnyKey("repo"))
        critical = c.opt("critical") ?? 0
        high = c.opt("high") ?? 0
        moderate = c.opt("moderate") ?? 0
        low = c.opt("low") ?? 0
        error = c.opt("error")
    }
}

/// npm-audit e composer-audit.
public struct AuditResult: Decodable, Equatable, Sendable {
    public var result: CheckResult
    public var items: [AuditItem]
    public init(from decoder: Decoder) throws {
        result = try CheckResult(from: decoder)
        items = try top(decoder).list("items")
    }
}

public struct ColimaProfile: Decodable, Equatable, Sendable {
    public var name: String
    public var status: String
    public var cpus: Int
    public var memoryBytes: Int
    public var diskBytes: Int
    public var isRunning: Bool { status == "Running" }
    public init(from decoder: Decoder) throws {
        let c = try top(decoder)
        name = try c.decode(String.self, forKey: AnyKey("name"))
        status = c.opt("status") ?? "Unknown"
        cpus = c.opt("cpus") ?? 0
        memoryBytes = c.opt("memoryBytes") ?? 0
        diskBytes = c.opt("diskBytes") ?? 0
    }
}

public struct ColimaContainer: Decodable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var cpu: String
    public var mem: String
    public init(from decoder: Decoder) throws {
        let c = try top(decoder)
        id = c.opt("id") ?? ""
        name = c.opt("name") ?? ""
        cpu = c.opt("cpu") ?? ""
        mem = c.opt("mem") ?? ""
    }
}

public struct ColimaStatus: Decodable, Equatable, Sendable {
    public var result: CheckResult
    public var profiles: [ColimaProfile]
    public var containers: [ColimaContainer]
    /// Il JSON non ha una chiave `running`: si deriva dai profili.
    public var running: Bool { profiles.contains { $0.isRunning } }
    public init(from decoder: Decoder) throws {
        result = try CheckResult(from: decoder)
        let c = try top(decoder)
        profiles = c.list("profiles")
        containers = c.list("containers")
    }
}

public struct DailySaving: Decodable, Equatable, Sendable {
    public var date: String
    public var saved: Int
    public init(from decoder: Decoder) throws {
        let c = try top(decoder)
        date = try c.decode(String.self, forKey: AnyKey("date"))
        saved = c.opt("saved") ?? 0
    }
}

public struct RtkGain: Decodable, Equatable, Sendable {
    public var result: CheckResult
    public var saved: Int
    public var input: Int
    public var pct: Double
    public var commands: Int
    public var daily: [DailySaving]
    public init(from decoder: Decoder) throws {
        result = try CheckResult(from: decoder)
        let c = try top(decoder)
        saved = c.opt("saved") ?? 0
        input = c.opt("input") ?? 0
        pct = c.opt("pct") ?? 0
        commands = c.opt("commands") ?? 0
        daily = c.list("daily")
    }
}

public struct TokensaveGain: Decodable, Equatable, Sendable {
    public var result: CheckResult
    public var saved: Int
    public var calls: Int
    public var usd: Double
    public var missedTurns: Int
    public init(from decoder: Decoder) throws {
        result = try CheckResult(from: decoder)
        let c = try top(decoder)
        saved = c.opt("saved") ?? 0
        calls = c.opt("calls") ?? 0
        usd = c.opt("usd") ?? 0
        missedTurns = c.opt("missedTurns") ?? 0
    }
}

public struct CavemanStatus: Decodable, Equatable, Sendable {
    public var result: CheckResult
    /// Modalità canonica (valori legacy già mappati dal motore). nil se assente o "".
    public var mode: String?
    /// Come scritta nel config del plugin.
    public var rawMode: String?
    public var version: String?
    /// Ultima modalità non spenta (per riaccendere), canonica.
    public var lastMode: String?
    public var pluginEnabled: Bool
    public var active: Bool
    public init(from decoder: Decoder) throws {
        result = try CheckResult(from: decoder)
        let c = try top(decoder)
        mode = c.optText("mode")
        rawMode = c.optText("rawMode")
        version = c.optText("version")
        lastMode = c.optText("lastMode")
        pluginEnabled = c.opt("pluginEnabled") ?? false
        active = c.opt("active") ?? false
    }
}

public struct ClaudeUsageValues: Decodable, Equatable, Sendable {
    public var cPct: Double?
    public var cReset: String?
    public var wPct: Double?
    public var wReset: String?
    public var stale: Bool
    /// "valid" | "missing" | "expired" (stringa nel binario reale).
    public var auth: String?
    public var error: String?
    public init(from decoder: Decoder) throws {
        let c = try top(decoder)
        cPct = c.opt("c_pct"); cReset = c.opt("c_reset")
        wPct = c.opt("w_pct"); wReset = c.opt("w_reset")
        stale = c.opt("stale") ?? false
        auth = c.opt("auth"); error = c.opt("error")
    }
}

public struct ClaudeUsage: Decodable, Equatable, Sendable {
    public var result: CheckResult
    public var usage: ClaudeUsageValues?
    public init(from decoder: Decoder) throws {
        result = try CheckResult(from: decoder)
        usage = try top(decoder).opt("usage")
    }
}

// MARK: - detect, repos, ai-status, project-status

public struct HarnessInfo: Decodable, Equatable, Sendable {
    public var id: String
    public var installed: Bool
    public var managed: Bool
    public init(from decoder: Decoder) throws {
        let c = try top(decoder)
        id = try c.decode(String.self, forKey: AnyKey("id"))
        installed = c.opt("installed") ?? false
        managed = c.opt("managed") ?? false
    }
}

public struct DetectResult: Decodable, Equatable, Sendable {
    public var harnesses: [HarnessInfo]
    public var tools: [String: Bool]
    /// Per strumento AI (rtk, caveman, tokensave, statusline): almeno un harness
    /// installato e supportato. nil se il motore non lo fornisce.
    public var aiTools: [String: Bool]?
    public init(from decoder: Decoder) throws {
        let c = try top(decoder)
        harnesses = c.list("harnesses")
        tools = c.opt("tools") ?? [:]
        aiTools = c.opt("aiTools")
    }
}

public struct RepoInfo: Decodable, Equatable, Sendable {
    public var path: String
    public var name: String
    public var npm: Bool
    public var composer: Bool
    public var tokensave: Bool
    public init(from decoder: Decoder) throws {
        let c = try top(decoder)
        path = try c.decode(String.self, forKey: AnyKey("path"))
        name = c.opt("name") ?? URL(fileURLWithPath: path).lastPathComponent
        npm = c.opt("npm") ?? false
        composer = c.opt("composer") ?? false
        tokensave = c.opt("tokensave") ?? false
    }
}

public struct AIHarnessState: Decodable, Equatable, Sendable {
    public var id: String
    /// installed | outdated | missing | unsupported (altri valori conservati).
    public var state: String
    public init(from decoder: Decoder) throws {
        let c = try top(decoder)
        id = try c.decode(String.self, forKey: AnyKey("id"))
        state = c.opt("state") ?? "missing"
    }
}

public struct AIStatus: Decodable, Equatable, Sendable {
    public var tool: String
    public var installed: Bool
    public var harnesses: [AIHarnessState]
    public init(from decoder: Decoder) throws {
        let c = try top(decoder)
        tool = try c.decode(String.self, forKey: AnyKey("tool"))
        installed = c.opt("installed") ?? false
        harnesses = c.list("harnesses")
    }
}

public struct ProjectCheck: Decodable, Equatable, Sendable {
    public var tool: String
    public var ok: Bool
    public var detail: String
    /// Solo da mostrare, mai da eseguire.
    public var willWrite: [String]
    public init(from decoder: Decoder) throws {
        let c = try top(decoder)
        tool = try c.decode(String.self, forKey: AnyKey("tool"))
        ok = c.opt("ok") ?? false
        detail = c.opt("detail") ?? ""
        willWrite = c.opt("willWrite") ?? []
    }
}

public struct ProjectStatus: Decodable, Equatable, Sendable {
    public var path: String
    public var checks: [ProjectCheck]
    public init(from decoder: Decoder) throws {
        let c = try top(decoder)
        path = try c.decode(String.self, forKey: AnyKey("path"))
        checks = c.list("checks")
    }
}

// MARK: - check all

/// Risposta di `devbar check all`: un risultato per riga. Una riga non decodificabile
/// diventa uno stato di errore solo per quella riga.
public struct AllChecks: Equatable, Sendable {
    public var rows: [String: CheckResult]
    /// Il JSON grezzo di ogni riga, per i decoder tipizzati.
    public var raw: [String: JSONValue]

    public init(rows: [String: CheckResult], raw: [String: JSONValue]) { self.rows = rows; self.raw = raw }

    public static func decode(_ data: Data) throws -> AllChecks {
        let top = try JSONDecoder().decode([String: JSONValue].self, from: data)
        // Risposta "busy" o errore globale: {"status":"error","error":"busy"}.
        if top["status"] != nil, case .string = top["status"]! {
            let r = (try? decodeRow(.object(top))) ?? .failure("risposta non valida")
            return AllChecks(rows: ["_all": r], raw: ["_all": .object(top)])
        }
        var rows: [String: CheckResult] = [:]
        for (k, v) in top {
            do { rows[k] = try decodeRow(v) }
            catch { rows[k] = .failure("output non valido: \(k)") }
        }
        return AllChecks(rows: rows, raw: top)
    }

    private static func decodeRow(_ v: JSONValue) throws -> CheckResult {
        try JSONDecoder().decode(CheckResult.self, from: JSONEncoder().encode(v))
    }

    /// Decodifica tipizzata di una riga; nil se assente o malformata.
    public func typed<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let v = raw[name], let d = try? JSONEncoder().encode(v) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }
}
