import Foundation

// MARK: - Tono

/// Colore semantico di una riga, di un segmento o di un indicatore. La vista lo traduce in Color.
public enum Tone: String, Equatable, Sendable, CaseIterable {
    /// muschio: tutto in ordine
    case ok
    /// ambra: c'è qualcosa da fare
    case action
    /// rosso segnale: vulnerabilità gravi, consumo oltre il 90%
    case risk
    /// ardesia: sezioni informative e non configurate
    case info

    /// Tinte approvate (sRGB, 0xRRGGBB).
    public var hex: UInt32 {
        switch self {
        case .ok: 0x3FA34D
        case .action: 0xE0A526
        case .risk: 0xD6453D
        case .info: 0x8A8F98
        }
    }

    /// Consumo Claude: ok sotto il 70%, action fino al 90% compreso, risk oltre.
    public static func usage(_ pct: Double?) -> Tone {
        guard let pct else { return .info }
        if pct < 70 { return .ok }
        return pct <= 90 ? .action : .risk
    }

    /// Stato di un check: un errore del check non è un rischio, si mostra in ardesia.
    public static func of(_ s: CheckState?) -> Tone {
        switch s {
        case .ok: .ok
        case .action: .action
        case .error, .unconfigured, nil: .info
        }
    }
}

// MARK: - Aree

/// Aree del pannello e della finestra Dettagli.
public enum Area: String, Equatable, Hashable, Sendable, CaseIterable, Identifiable {
    case homebrew, vulns, audit, colima, tokens, aiSetup
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .homebrew: "Homebrew"
        case .vulns: "Vulnerabilità"
        case .audit: "Audit repo"
        case .colima: "colima"
        case .tokens: "Token"
        case .aiSetup: "AI setup"
        }
    }

    /// Aree della barra laterale dei Dettagli, nell'ordine.
    public static let detailsAreas: [Area] = [.homebrew, .vulns, .audit, .colima, .tokens]
}

// MARK: - Formattazione extra

public extension Fmt {
    /// 8589934592 -> "8 GB" (base 1024, come colima), 1.5 GiB -> "1.5 GB".
    static func gb(_ bytes: Int) -> String {
        let g = Double(bytes) / 1_073_741_824
        return g == g.rounded() ? "\(Int(g)) GB" : String(format: "%.1f GB", g)
    }

    /// "2026-11-24" -> "24/11"; altro: invariato.
    static func day(_ iso: String) -> String {
        let p = iso.split(separator: "-")
        return p.count == 3 ? "\(p[2])/\(p[1])" : iso
    }

    /// "controllato alle 09:25"; durante un refresh "controllo in corso…"; mai: nil.
    static func checked(_ last: Date?, isRefreshing: Bool, calendar: Calendar = .current) -> String? {
        if isRefreshing { return "controllo in corso…" }
        guard let last else { return nil }
        let c = calendar.dateComponents([.hour, .minute], from: last)
        return String(format: "controllato alle %02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

// MARK: - Righe del pannello

/// Numero a destra di una riga, con il suo tono. `value` nil: nessun numero.
public struct Readout: Equatable, Sendable {
    public var value: String?
    public var tone: Tone
    public var subtitle: String?
    public var note: String?
    public init(value: String? = nil, tone: Tone = .info, subtitle: String? = nil, note: String? = nil) {
        self.value = value; self.tone = tone; self.subtitle = subtitle; self.note = note
    }
}

/// Indicatore del consumo Claude (finestra 5h o 7 giorni).
public struct UsageMeter: Equatable, Sendable, Identifiable {
    public var id: String { label }
    public var label: String
    public var fraction: Double
    public var percentText: String
    public var reset: String?
    public var tone: Tone
}

public extension PanelModel {
    static let severeLevels: Set<String> = ["HIGH", "CRITICAL"]

    /// Homebrew: numero di pacchetti da aggiornare.
    var brewReadout: Readout {
        guard brewState == .shown else { return Readout() }
        if brewError != nil { return Readout(tone: .info, subtitle: brewError) }
        let n = brewItems.count
        return Readout(value: "\(n)", tone: n > 0 ? .action : .ok,
                       subtitle: n > 0 ? (n == 1 ? "pacchetto da aggiornare" : "pacchetti da aggiornare") : "aggiornato")
    }

    /// Formule colpite da vulnerabilità alte o critiche (distinte).
    var severeFormulae: [String] {
        Array(Set(brewVulnItems.filter { Self.severeLevels.contains($0.severity.uppercased()) }.map(\.formula))).sorted()
    }

    /// Repo npm/composer con vulnerabilità critiche o alte.
    var severeRepos: Int { (npmItems + composerItems).filter { $0.critical > 0 || $0.high > 0 }.count }

    /// Repo npm/composer con un problema qualsiasi (vulnerabilità o errore di audit).
    var reposWithIssues: Int {
        (npmItems + composerItems).filter { $0.error != nil || $0.critical + $0.high + $0.moderate + $0.low > 0 }.count
    }

    var showsVulns: Bool { !vulnRows.isEmpty }

    /// Pacchetti Homebrew colpiti (formule distinte, non CVE).
    var vulnPackages: Int { vulnRows.contains { $0.id == "brew" } ? Set(brewVulnItems.map(\.formula)).count : 0 }

    /// Progetti con problemi in npm/composer.
    var vulnProjects: Int { vulnRows.contains { $0.id != "brew" } ? reposWithIssues : 0 }

    /// Totale delle vulnerabilità da sistemare: il numero grande della riga e quello nella barra dei menu.
    var vulnTotal: Int { vulnPackages + vulnProjects }

    /// Vulnerabilità: il numero grande è il totale da sistemare (pacchetti Homebrew colpiti più
    /// progetti con problemi in npm/composer). Rosso se almeno uno è grave (alta o critica).
    var vulnReadout: Readout {
        guard showsVulns else { return Readout() }
        let brewShown = vulnRows.contains { $0.id == "brew" }
        let auditShown = vulnRows.contains { $0.id != "brew" }
        let affected = vulnPackages
        let severe = brewShown ? severeFormulae.count : 0
        let projects = vulnProjects
        let anySevere = severe + severeRepos > 0
        let total = vulnTotal
        let tone: Tone = brewVulnError != nil && !auditShown ? .info
            : (anySevere ? .risk : (total > 0 ? .action : .ok))
        var sub: String?
        if brewShown {
            if let e = brewVulnError { sub = e }
            else if affected == 0 { sub = "nessun pacchetto Homebrew colpito" }
            else {
                let pkg = affected == 1 ? "1 pacchetto Homebrew" : "\(affected) pacchetti Homebrew"
                sub = severe > 0 ? "\(pkg), \(severe) con gravità alta o critica" : pkg
            }
        }
        var note: String?
        if auditShown {
            note = projects == 0 ? "Progetti senza problemi" : (projects == 1 ? "1 progetto con problemi" : "\(projects) progetti con problemi")
        }
        let hasValue = !(brewShown && brewVulnError != nil)
        return Readout(value: hasValue ? "\(total)" : nil, tone: tone, subtitle: brewShown ? sub : note, note: brewShown ? note : nil)
    }

    /// Somma dei token risparmiati da RTK e tokensave, compatta ("194K").
    var tokensReadout: Readout {
        Readout(value: tokenTotal.map(Fmt.tokens), tone: .info,
                subtitle: tokenTotal == nil ? nil : "somma di RTK e tokensave")
    }

    /// Sezione informativa: sempre ardesia (le soglie di consumo colorano solo gli indicatori).
    var tokensTone: Tone { .info }

    var usageMeters: [UsageMeter] {
        guard usageState == .shown else { return [] }
        return [("Sessione 5 ore", usageFiveHour, usageFiveHourReset), ("Settimana", usageWeek, usageWeekReset)]
            .filter { $0.1 != nil }
            .map { UsageMeter(label: $0.0, fraction: Fmt.fraction($0.1), percentText: Fmt.percent($0.1 ?? 0),
                              reset: $0.2.map { "si azzera \($0)" }, tone: Tone.usage($0.1)) }
    }
}
