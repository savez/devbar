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

    /// "N cose da fare", "1 cosa da fare", "Tutto a posto".
    static func todo(_ n: Int) -> String {
        switch n {
        case ..<1: "Tutto a posto"
        case 1: "1 cosa da fare"
        default: "\(n) cose da fare"
        }
    }

    /// "controllato alle 09:25"; durante un refresh "controllo in corso…"; mai: nil.
    static func checked(_ last: Date?, isRefreshing: Bool, calendar: Calendar = .current) -> String? {
        if isRefreshing { return "controllo in corso…" }
        guard let last else { return nil }
        let c = calendar.dateComponents([.hour, .minute], from: last)
        return String(format: "controllato alle %02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

// MARK: - Barra di salute

public struct StripSegment: Equatable, Sendable, Identifiable {
    public var area: Area
    public var tone: Tone
    public var id: Area { area }
}

public struct HealthStrip: Equatable, Sendable {
    public var segments: [StripSegment]
    /// "2026-11-24" -> "24/11"; altro: invariato.
    static func day(_ iso: String) -> String {
        let p = iso.split(separator: "-")
        return p.count == 3 ? "\(p[2])/\(p[1])" : iso
    }

    /// "N cose da fare" o "Tutto a posto": stesso numero del badge nella barra dei menu.
    public var todoText: String
    public var todoTone: Tone

    /// Segmenti delle aree ancora in `PanelModel` più quelli dei moduli (`Feature`),
    /// nell'ordine di `Area`.
    @MainActor
    public init(model: PanelModel, features: [any Feature], badge: (level: CheckState, count: Int)) {
        var s: [StripSegment] = []
        if model.brewState != .hidden { s.append(.init(area: .homebrew, tone: model.brewReadout.tone)) }
        if model.showsVulns { s.append(.init(area: .vulns, tone: model.vulnReadout.tone)) }
        if model.showsTokenSection { s.append(.init(area: .tokens, tone: model.tokensTone)) }
        if model.showsAISetup { s.append(.init(area: .aiSetup, tone: .info)) }
        s += features.compactMap(\.segment)
        let order = Area.allCases
        segments = s.sorted { order.firstIndex(of: $0.area)! < order.firstIndex(of: $1.area)! }
        todoText = Fmt.todo(badge.count)
        switch badge.level {
        case .error: todoTone = .risk
        case .action: todoTone = badge.count > 0 ? .action : .ok
        case .ok, .unconfigured: todoTone = .ok
        }
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

    /// Vulnerabilità: formule colpite da CVE alte o critiche (senza brew: repo con critiche o
    /// alte). Rosso se ci sono formule o repo gravi.
    var vulnReadout: Readout {
        guard showsVulns else { return Readout() }
        let brewShown = vulnRows.contains { $0.id == "brew" }
        let auditShown = vulnRows.contains { $0.id != "brew" }
        let affected = brewShown ? Set(brewVulnItems.map(\.formula)).count : 0
        let severe = brewShown ? severeFormulae.count : 0
        let anySevere = severe + severeRepos > 0
        let tone: Tone = brewVulnError != nil && !auditShown ? .info
            : (anySevere ? .risk : (affected + reposWithIssues > 0 ? .action : .ok))
        var sub: String?
        if brewShown {
            if let e = brewVulnError { sub = e }
            else { sub = affected == 0 ? "nessuna formula colpita" : "alte o critiche, \(affected) in totale" }
        }
        var note: String?
        if auditShown {
            let n = reposWithIssues
            note = n == 0 ? "Repo senza problemi" : (n == 1 ? "1 repo con problemi" : "\(n) repo con problemi")
        }
        if !brewShown { return Readout(value: "\(severeRepos)", tone: tone, subtitle: note) }
        return Readout(value: brewVulnError == nil ? "\(severe)" : nil, tone: tone, subtitle: sub, note: note)
    }

    /// Token risparmiati da RTK, compatti ("194K").
    var tokensReadout: Readout {
        Readout(value: rtkSaved.map(Fmt.tokens), tone: .info)
    }

    /// Sezione informativa: sempre ardesia (le soglie di consumo colorano solo gli indicatori),
    /// così la barra non mostra ambra che "N cose da fare" non conta.
    var tokensTone: Tone { .info }

    var usageMeters: [UsageMeter] {
        guard usageState == .shown else { return [] }
        return [("5h", usageFiveHour, usageFiveHourReset), ("7 giorni", usageWeek, usageWeekReset)]
            .filter { $0.1 != nil }
            .map { UsageMeter(label: $0.0, fraction: Fmt.fraction($0.1), percentText: Fmt.percent($0.1 ?? 0),
                              reset: $0.2.map { "reset \($0)" }, tone: Tone.usage($0.1)) }
    }
}
