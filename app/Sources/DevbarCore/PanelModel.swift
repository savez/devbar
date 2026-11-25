import Foundation

// MARK: - Formattazione

public enum Fmt {
    /// 179_000 -> "179K", 1_200_000 -> "1.2M", 950 -> "950".
    public static func tokens(_ n: Int) -> String {
        switch n {
        case ..<1_000: return "\(n)"
        case ..<1_000_000:
            let k = Double(n) / 1_000
            return k < 10 && n % 1_000 != 0 ? String(format: "%.1fK", k) : "\(Int(k.rounded()))K"
        default: return String(format: "%.1fM", Double(n) / 1_000_000)
        }
    }

    /// 8589934592 -> "8GiB", 64424509440 -> "60GiB".
    public static func gib(_ bytes: Int) -> String {
        let g = Double(bytes) / 1_073_741_824
        return g == g.rounded() ? "\(Int(g))GiB" : String(format: "%.1fGiB", g)
    }

    /// 17.69 -> "18%".
    public static func percent(_ p: Double) -> String { "\(Int(p.rounded()))%" }

    /// Reset: ISO8601 (con o senza frazioni) -> "oggi 14:30" / "domani 09:00" / "mer 09:00".
    /// Valore non interpretabile: restituito com'è; vuoto o nil: nil.
    public static func reset(_ s: String?, now: Date = Date(), calendar: Calendar = .current,
                             locale: Locale = Locale(identifier: "it_IT")) -> String? {
        guard let s, !s.isEmpty, s != "?" else { return nil }
        let f1 = ISO8601DateFormatter()
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f1.date(from: s) ?? f2.date(from: s) else { return s }
        var cal = calendar; cal.locale = locale
        let hhmm = hhmmString(d, calendar: cal)
        if cal.isDate(d, inSameDayAs: now) { return "oggi \(hhmm)" }
        if let t = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(d, inSameDayAs: t) { return "domani \(hhmm)" }
        let df = DateFormatter(); df.locale = locale; df.calendar = cal; df.timeZone = cal.timeZone
        df.dateFormat = "EEE d MMM"
        return "\(df.string(from: d)) \(hhmm)"
    }

    private static func hhmmString(_ d: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// Frazione 0...1 per una ProgressView.
    public static func fraction(_ pct: Double?) -> Double { min(1, max(0, (pct ?? 0) / 100)) }
}

// MARK: - Conferma di azioni

/// Piano restituito da `devbar run <azione>` senza `--yes`. Solo da mostrare.
public struct ActionPlan: Equatable, Sendable {
    public var lines: [String]
    public var text: String { lines.joined(separator: "\n") }

    /// Accetta `{"plan":true,"commands":[...]}`, `{"checks":[{"willWrite":[...]}]}` o testo libero
    /// ("piano: …"). Mai eseguito.
    public static func parse(_ stdout: Data) -> ActionPlan {
        if let v = try? JSONDecoder().decode(JSONValue.self, from: stdout), case .object(let o) = v {
            var lines: [String] = []
            if case .array(let cmds)? = o["commands"] {
                lines += cmds.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
            }
            if case .array(let checks)? = o["checks"] {
                for c in checks {
                    if case .object(let co) = c, case .array(let w)? = co["willWrite"] {
                        lines += w.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
                    }
                }
            }
            if !lines.isEmpty { return ActionPlan(lines: lines) }
        }
        let text = String(decoding: stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return ActionPlan(lines: text.isEmpty ? [] : text.split(separator: "\n").map(String.init))
    }
}

/// Azione che scrive o installa: prima senza `--yes` (piano), poi con.
public struct ConfirmableAction: Equatable, Sendable, Identifiable {
    public var id: String { args.joined(separator: " ") }
    public var title: String
    public var args: [String]
    public var confirmedArgs: [String] { args + ["--yes"] }
    public init(title: String, args: [String]) { self.title = title; self.args = args }
}

// MARK: - Modello del pannello

public enum SectionKind: Equatable, Sendable {
    /// Strumento presente: mostra i dati.
    case shown
    /// Strumento assente: solo il pulsante Init.
    case initOnly
    case hidden

    /// Riga assente o senza stato: nascosta; non configurata: solo Init; altrimenti i dati.
    public static func of(_ s: CheckState?, hasRow: Bool = true) -> SectionKind {
        guard let s, hasRow else { return .hidden }
        return s == .unconfigured ? .initOnly : .shown
    }
}

/// Una riga della card "Token risparmiati": uno strumento con il suo numero e cosa misura.
public struct TokenToolRow: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    /// Numero a destra ("194K"); nil per gli strumenti senza conteggio.
    public var value: String?
    /// Frase su cosa misura o sullo stato.
    public var detail: String
    /// Interruttore attivo / spento; nil per gli strumenti con un numero.
    public var active: Bool?
    /// Barre degli ultimi giorni (solo RTK).
    public var daily: [DailySaving]
}

public struct PanelModel: Equatable, Sendable {
    // Homebrew
    public var brewState: SectionKind
    public var brewHeadline: String
    public var brewItems: [BrewOutdatedItem]
    public var brewUpgradeEnabled: Bool
    /// Messaggio del check se è in errore.
    public var brewError: String?
    public var corkInstalled: Bool
    public var corkButtonTitle: String { corkInstalled ? "Apri Cork" : "Installa Cork" }

    // Vulnerabilità
    public struct VulnRow: Equatable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var summary: String
        public var hasDetails: Bool
    }
    public var vulnRows: [VulnRow]
    public var brewVulnItems: [BrewVulnItem]
    public var npmItems: [AuditItem]
    public var composerItems: [AuditItem]
    public var brewVulnError: String?

    // Token
    public var rtkState: SectionKind
    /// "RTK 18%" o il riassunto del check.
    public var rtkLine: String
    public var rtkSaved: Int?
    /// Ultimi 7 giorni (pannello).
    public var rtkDaily: [DailySaving]
    /// Tutti i giorni forniti dal motore (Dettagli).
    public var rtkAllDaily: [DailySaving]
    public var rtkCommands: Int?
    public var tokensaveState: SectionKind
    /// "tokensave 0 risparmiati, 53 occasioni perse".
    public var tokensaveLine: String
    public var tokensave: TokensaveGain?
    /// Controllo caveman (attivo, modalità): nil se non installato.
    public var caveman: CavemanPanel?
    public var cavemanMode: String? { caveman?.mode.rawValue }
    public var cavemanVersion: String? { caveman?.version }
    public var tokenEconomizerState: SectionKind
    public var tokenEconomizerActive: Bool
    public var tokenEconomizerSummary: String
    /// Una riga per strumento, nell'ordine RTK, tokensave, TokenEconomizer, caveman.
    public var tokenRows: [TokenToolRow]
    /// Somma dei token risparmiati da RTK e tokensave; nil se nessuno dei due ha dati.
    public var tokenTotal: Int?
    public var usageState: SectionKind
    public var usageFiveHour: Double?
    public var usageWeek: Double?
    public var usageFiveHourReset: String?
    public var usageWeekReset: String?
    public var usageNote: String?
    public var showsTokenSection: Bool {
        rtkState != .hidden || tokensaveState != .hidden || tokenEconomizerState != .hidden
    }
    /// "Limiti di Claude": sezione a parte, non fa parte dei risparmi.
    public var showsLimits: Bool { usageState != .hidden }

    // AI setup
    public var aiTools: [String]
    public var showsAISetup: Bool

    public init(all: AllChecks, detect: DetectResult? = nil, now: Date = Date()) {
        // Homebrew
        let bo = all.typed(BrewOutdated.self, "brew-outdated")
        let boState = all.rows["brew-outdated"]?.state
        brewState = SectionKind.of(boState)
        brewHeadline = all.rows["brew-outdated"]?.summary ?? ""
        brewItems = bo?.items ?? []
        brewUpgradeEnabled = boState == .action
        brewError = boState == .error ? (all.rows["brew-outdated"]?.summary ?? "errore") : nil
        corkInstalled = detect?.tools["cork"] ?? false

        // Vulnerabilità
        var rows: [VulnRow] = []
        let bv = all.typed(BrewVulns.self, "brew-vulns")
        brewVulnItems = bv?.items ?? []
        brewVulnError = all.rows["brew-vulns"]?.state == .error ? (all.rows["brew-vulns"]?.summary ?? "errore") : nil
        if let r = all.rows["brew-vulns"], r.state != .unconfigured {
            rows.append(.init(id: "brew", title: "brew", summary: Self.brewVulnSummary(r, bv), hasDetails: !(bv?.items.isEmpty ?? true)))
        }
        let npm = all.typed(AuditResult.self, "npm-audit")
        npmItems = npm?.items ?? []
        if let r = all.rows["npm-audit"], r.state != .unconfigured {
            rows.append(.init(id: "npm", title: "npm", summary: r.summary, hasDetails: !(npm?.items.isEmpty ?? true)))
        }
        let comp = all.typed(AuditResult.self, "composer-audit")
        composerItems = comp?.items ?? []
        if let r = all.rows["composer-audit"], r.state != .unconfigured {
            rows.append(.init(id: "composer", title: "composer", summary: r.summary, hasDetails: !(comp?.items.isEmpty ?? true)))
        }
        vulnRows = rows

        // RTK
        let rtk = all.typed(RtkGain.self, "rtk")
        rtkState = SectionKind.of(all.rows["rtk"]?.state, hasRow: all.rows["rtk"] != nil)
        rtkLine = rtk.map { "RTK \(Fmt.percent($0.pct))" } ?? (all.rows["rtk"]?.summary ?? "")
        rtkSaved = rtkState == .shown ? rtk?.saved : nil
        rtkCommands = rtk?.commands
        rtkAllDaily = rtk?.daily ?? []
        rtkDaily = Array(rtkAllDaily.suffix(7))

        // tokensave
        let ts = all.typed(TokensaveGain.self, "tokensave")
        tokensaveState = SectionKind.of(all.rows["tokensave"]?.state, hasRow: all.rows["tokensave"] != nil)
        tokensave = tokensaveState == .shown ? ts : nil
        tokensaveLine = ts.map { "tokensave \(Fmt.tokens($0.saved)) risparmiati, \($0.missedTurns) occasioni perse" }
            ?? (all.rows["tokensave"]?.summary ?? "")

        // TokenEconomizer: informativo, solo attivo / non attivo
        let te = all.typed(TokenEconomizerStatus.self, "tokeneconomizer")
        tokenEconomizerState = SectionKind.of(all.rows["tokeneconomizer"]?.state, hasRow: all.rows["tokeneconomizer"] != nil)
        tokenEconomizerActive = te?.active ?? false
        tokenEconomizerSummary = all.rows["tokeneconomizer"]?.summary ?? ""

        // caveman: solo se installato
        if let cv = all.typed(CavemanStatus.self, "caveman"), cv.result.state != .unconfigured {
            caveman = CavemanPanel(status: cv)
        } else {
            caveman = nil
        }

        // Card dei risparmi: una riga per strumento
        var trs: [TokenToolRow] = []
        if rtkState == .shown, let rtk {
            trs.append(TokenToolRow(id: "rtk", title: "RTK", value: Fmt.tokens(rtk.saved),
                                    detail: "output dei comandi ridotto del \(Fmt.percent(rtk.pct))",
                                    active: nil, daily: rtkDaily))
        }
        if tokensaveState == .shown, let ts {
            trs.append(TokenToolRow(id: "tokensave", title: "tokensave", value: Fmt.tokens(ts.saved),
                                    detail: "\(ts.missedTurns) volte l'agente ha letto file invece di usare tokensave",
                                    active: nil, daily: []))
        }
        if tokenEconomizerState == .shown {
            trs.append(TokenToolRow(id: "tokeneconomizer", title: "TokenEconomizer", value: nil,
                                    detail: tokenEconomizerActive ? "attivo" : tokenEconomizerSummary,
                                    active: tokenEconomizerActive, daily: []))
        }
        if let cv = caveman {
            trs.append(TokenToolRow(id: "caveman", title: "caveman", value: nil,
                                    detail: "risposte più corte, nessun conteggio disponibile",
                                    active: cv.active, daily: []))
        }
        tokenRows = trs
        let totals = [rtkState == .shown ? rtk?.saved : nil, tokensaveState == .shown ? ts?.saved : nil].compactMap { $0 }
        tokenTotal = totals.isEmpty ? nil : totals.reduce(0, +)

        // claude-usage
        let cu = all.typed(ClaudeUsage.self, "claude-usage")
        usageState = SectionKind.of(all.rows["claude-usage"]?.state, hasRow: all.rows["claude-usage"] != nil)
        if let u = cu?.usage, usageState == .shown {
            usageFiveHour = u.cPct; usageWeek = u.wPct
            usageFiveHourReset = Fmt.reset(u.cReset, now: now)
            usageWeekReset = Fmt.reset(u.wReset, now: now)
            usageNote = Self.usageNote(u)
        } else {
            usageNote = nil
        }

        // AI setup
        let display = ["RTK", "caveman", "tokensave", "TokenEconomizer", "statusline"]
        if let ai = detect?.aiTools {
            // Visibili solo con almeno un harness installato e supportato (calcolato dal motore).
            aiTools = display.filter { ai[AISetup.cliName($0)] == true }
        } else {
            let claudeInstalled = detect?.harnesses.first(where: { $0.id == "claude" })?.installed ?? false
            aiTools = claudeInstalled ? display : display.filter { $0 != "statusline" }
        }
        // Gli harness non gestiti si gestiscono solo nelle impostazioni: niente righe nel pannello.
        showsAISetup = detect != nil
    }

    /// auth prima di error: con credenziali assenti il binario mette anche un `error` in inglese.
    static func usageNote(_ u: ClaudeUsageValues) -> String? {
        switch u.auth {
        case "missing": return "Accesso richiesto"
        case "expired": return "Credenziali scadute"
        default: break
        }
        if let e = u.error, !e.isEmpty { return e }
        return u.stale ? "dati non aggiornati" : nil
    }

    private static func brewVulnSummary(_ r: CheckResult, _ bv: BrewVulns?) -> String {
        guard let bv, r.state != .error else { return r.summary }
        if bv.items.isEmpty { return "nessuna" }
        return bv.severe > 0 ? "\(bv.severe) alte o critiche su \(bv.items.count)" : "\(bv.items.count) basse o medie"
    }

    /// Riga di piede: ultimo problema da mostrare con discrezione. Il controllo in corso
    /// lo dice già la riga sotto la barra di salute.
    public static func footerStatus(engineBusy: Bool, refreshError: String?, isRefreshing: Bool) -> String? {
        if isRefreshing { return nil }
        if engineBusy { return "controllo già in corso" }
        return refreshError
    }

    /// Riassunto di audit per un repo: "2 critiche, 1 alta".
    public static func auditSummary(_ i: AuditItem) -> String {
        if let e = i.error { return e }
        let parts = [(i.critical, "critiche"), (i.high, "alte"), (i.moderate, "medie"), (i.low, "basse")]
            .filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
        return parts.isEmpty ? "nessuna" : parts.joined(separator: ", ")
    }
}

/// Icona della barra secondo il livello del badge.
public enum BarIcon {
    public static func symbol(_ level: CheckState) -> String {
        switch level {
        case .error: return "exclamationmark.shield"
        case .action: return "arrow.triangle.2.circlepath"
        case .ok, .unconfigured: return "checkmark.shield"
        }
    }
    /// "green" | "orange" | "red": la vista lo traduce in Color.
    public static func colorName(_ level: CheckState) -> String {
        switch level {
        case .error: return "red"
        case .action: return "orange"
        case .ok, .unconfigured: return "green"
        }
    }
    /// Numero accanto all'icona solo se > 0.
    public static func countText(_ count: Int) -> String? { count > 0 ? "\(count)" : nil }
}
