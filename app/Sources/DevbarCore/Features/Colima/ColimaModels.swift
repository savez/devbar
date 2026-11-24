import Foundation

// MARK: - JSON del check `colima`

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

// MARK: - Righe della finestra Dettagli

public struct ColimaProfileRow: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var status: String
    public var cpus: Int
    public var memory: String
    public var disk: String
    public var running: Bool
}

public struct ContainerRow: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var cpu: String
    public var mem: String
}

// MARK: - Stato dell'area

/// Stato di colima per il pannello e i Dettagli, calcolato da `check all`.
public struct ColimaPanel: Equatable, Sendable {
    public var kind: SectionKind
    public var summary: String
    public var running: Bool
    /// Profilo attivo (o il primo): quello che Avvia/Ferma del pannello comanda.
    public var profile: String?
    public var profiles: [ColimaProfile]
    public var containers: [ColimaContainer]

    public init(all: AllChecks) {
        let col = all.typed(ColimaStatus.self, "colima")
        kind = SectionKind.of(all.rows["colima"]?.state, hasRow: all.rows["colima"] != nil)
        running = col?.running ?? false
        containers = col?.containers ?? []
        profiles = col?.profiles ?? []
        let prof = col?.profiles.first(where: { $0.isRunning }) ?? col?.profiles.first
        profile = prof?.name
        if let p = prof {
            summary = (col?.running ?? false) ? "attivo, \(p.cpus) CPU, \(Fmt.gb(p.memoryBytes))" : "spento"
        } else {
            summary = all.rows["colima"]?.summary ?? ""
        }
    }

    /// "Avvia" se spento, "Ferma" se acceso.
    public var toggleTitle: String { running ? "Ferma" : "Avvia" }

    /// Stato e risorse; container attivi come numero.
    public var readout: Readout {
        switch kind {
        case .hidden: return Readout()
        case .initOnly: return Readout(tone: .info, subtitle: "non installato")
        case .shown:
            let n = containers.count
            return Readout(value: running && n > 0 ? "\(n)" : nil, tone: .info, subtitle: summary,
                           note: running && n > 0 ? (n == 1 ? "container attivo" : "container attivi") : nil)
        }
    }

    public var profileRows: [ColimaProfileRow] {
        profiles.map {
            ColimaProfileRow(name: $0.name, status: $0.isRunning ? "attivo" : "spento", cpus: $0.cpus,
                             memory: Fmt.gb($0.memoryBytes), disk: Fmt.gb($0.diskBytes), running: $0.isRunning)
        }
    }

    public var containerRows: [ContainerRow] {
        containers.map { ContainerRow(id: $0.id, name: $0.name, cpu: $0.cpu, mem: $0.mem) }
    }

    /// `run colima-start|colima-stop [profilo]`: il profilo "default" non si nomina.
    static func toggleArgs(running: Bool, profile: String?) -> [String] {
        var args = ["run", running ? "colima-stop" : "colima-start"]
        if let profile, profile != "default" { args.append(profile) }
        return args
    }
}
