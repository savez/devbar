import Foundation

// MARK: - Righe della finestra Dettagli

public struct BrewDetailRow: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var installed: String
    public var available: String
    /// "Formula" | "Cask"
    public var kind: String
}

public struct VulnDetailRow: Equatable, Sendable, Identifiable {
    public var id: String { "\(formula) \(cve)" }
    public var formula: String
    public var cve: String
    /// "Critica", "Alta", "Media", "Bassa", "Sconosciuta"
    public var severity: String
    /// 4 critica … 0 sconosciuta: per ordinare per gravità.
    public var severityRank: Int
    public var fix: String
    public var tone: Tone
}

public struct AuditDetailRow: Equatable, Sendable, Identifiable {
    public var id: String { "\(tool) \(path)" }
    public var repo: String
    public var path: String
    /// "npm" | "composer"
    public var tool: String
    public var critical: Int
    public var high: Int
    public var moderate: Int
    public var low: Int
    public var error: String?
    public var tone: Tone {
        if error != nil { return .info }
        if critical + high > 0 { return .risk }
        return moderate + low > 0 ? .action : .ok
    }
}

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

public enum VulnFilter: String, Equatable, Sendable, CaseIterable, Identifiable {
    case all, severe
    public var id: String { rawValue }
    public var title: String { self == .all ? "Tutte" : "Alte e critiche" }
}

public extension Tone {
    /// Gravità di una CVE: alta/critica rischio, media/bassa da fare, sconosciuta ardesia.
    static func severity(_ s: String) -> Tone {
        switch s.uppercased() {
        case "CRITICAL", "HIGH": .risk
        case "MEDIUM", "MODERATE", "LOW": .action
        default: .info
        }
    }
}

public extension PanelModel {
    var brewDetailRows: [BrewDetailRow] {
        brewItems.map {
            BrewDetailRow(name: $0.name, installed: $0.installed ?? "?", available: $0.current ?? "?",
                          kind: $0.kind == "cask" ? "Cask" : "Formula")
        }
    }

    /// Righe CVE filtrate, di default dalle più gravi.
    func vulnDetailRows(filter: VulnFilter) -> [VulnDetailRow] {
        brewVulnItems
            .filter { filter == .all || Self.severeLevels.contains($0.severity.uppercased()) }
            .map { v in
                let (label, rank) = Self.severityLabel(v.severity)
                return VulnDetailRow(formula: v.formula, cve: v.id, severity: label, severityRank: rank,
                                     fix: v.fixAvailable ? "disponibile" : "nessuna", tone: Tone.severity(v.severity))
            }
            .sorted { ($0.severityRank, $1.formula, $1.cve) > ($1.severityRank, $0.formula, $0.cve) }
    }

    static func severityLabel(_ s: String) -> (String, Int) {
        switch s.uppercased() {
        case "CRITICAL": ("Critica", 4)
        case "HIGH": ("Alta", 3)
        case "MEDIUM", "MODERATE": ("Media", 2)
        case "LOW": ("Bassa", 1)
        default: ("Sconosciuta", 0)
        }
    }

    var auditDetailRows: [AuditDetailRow] {
        let tag = { (tool: String, items: [AuditItem]) in
            items.map { i in
                AuditDetailRow(repo: URL(fileURLWithPath: i.repo).lastPathComponent, path: i.repo, tool: tool,
                               critical: i.critical, high: i.high, moderate: i.moderate, low: i.low, error: i.error)
            }
        }
        return tag("npm", npmItems) + tag("composer", composerItems)
    }

    /// L'area Audit repo ha senso solo se npm o composer sono configurati.
    var showsAudit: Bool { vulnRows.contains { $0.id != "brew" } }

    var colimaProfileRows: [ColimaProfileRow] {
        colimaProfiles.map {
            ColimaProfileRow(name: $0.name, status: $0.isRunning ? "attivo" : "spento", cpus: $0.cpus,
                             memory: Fmt.gb($0.memoryBytes), disk: Fmt.gb($0.diskBytes), running: $0.isRunning)
        }
    }

    var containerRows: [ContainerRow] {
        colimaContainers.map { ContainerRow(id: $0.id, name: $0.name, cpu: $0.cpu, mem: $0.mem) }
    }

    /// Pallino di stato per un'area della barra laterale.
    func tone(of area: Area) -> Tone {
        switch area {
        case .homebrew: brewReadout.tone
        case .vulns: vulnRows.contains { $0.id == "brew" } ? brewOnlyVulnTone : .info
        case .audit:
            auditDetailRows.contains { $0.tone == .risk } ? .risk
                : (auditDetailRows.contains { $0.tone == .action } ? .action : (showsAudit ? .ok : .info))
        case .colima, .aiSetup: .info
        case .tokens: tokensTone
        }
    }

    private var brewOnlyVulnTone: Tone {
        if brewVulnError != nil { return .info }
        if !severeFormulae.isEmpty { return .risk }
        return brewVulnItems.isEmpty ? .ok : .action
    }
}
