import Foundation
import Observation
import AppKit
import Network

/// Stato dei check per la UI. Esegue solo la CLI: nessuna logica di check qui.
@Observable @MainActor
public final class StatusStore {
    /// Check solo informativi: non contribuiscono mai al badge (né al conteggio né al colore).
    public static let informative: Set<String> = ["colima", "rtk", "tokensave", "caveman", "claude-usage", "harnesses"]
    /// Timeout per check del motore dentro `check all` (stessi valori di `devbar check-timeouts`,
    /// verificati da un test). Il motore uccide il check oltre il suo timeout.
    public nonisolated static let checkTimeouts: [String: TimeInterval] = [
        "brew-outdated": 60, "brew-vulns": 60, "npm-audit": 300, "composer-audit": 300,
        "colima": 60, "rtk": 60, "tokensave": 60, "caveman": 60, "claude-usage": 60, "harnesses": 60,
    ]
    /// Riserva per `check all`: caso peggiore del motore (somma dei timeout) + 5 s per check.
    public nonisolated static var defaultAllTimeout: TimeInterval {
        checkTimeouts.values.reduce(0, +) + 5 * TimeInterval(checkTimeouts.count)
    }
    /// Azioni lunghe in background (colima start/stop, ai-install e project-apply con --yes).
    public nonisolated static let defaultLongActionTimeout: TimeInterval = 600
    /// `panelOpened()` rilancia solo se l'ultimo refresh è più vecchio di così.
    public static let panelThrottle: TimeInterval = 5 * 60

    public private(set) var results: [String: CheckResult] = [:]
    /// JSON grezzo per riga, per i decoder tipizzati (`AllChecks.typed`).
    public private(set) var raw: [String: JSONValue] = [:]
    public private(set) var isRefreshing = false
    public private(set) var lastRefresh: Date?
    /// Ultimo `check all` trovato occupato (lock del motore): risultati precedenti mantenuti.
    public private(set) var engineBusy = false
    /// Ultimo refresh fallito (timeout di riserva, output non valido, errore globale del
    /// motore): risultati precedenti mantenuti. nil dopo un refresh riuscito.
    public private(set) var refreshError: String?
    public private(set) var config = DevbarConfig()
    /// "config non valida: …" da mostrare nelle impostazioni.
    public private(set) var configError: String?

    private let runner: any CLIRunning
    private let now: @Sendable () -> Date
    private let configStore: ConfigStore
    private let allTimeout: TimeInterval
    private let actionTimeout: TimeInterval
    private let longActionTimeout: TimeInterval

    /// Dopo ogni refresh riuscito, con i nuovi risultati: aggiorna i moduli (`Feature`).
    @ObservationIgnored public var onResults: ((AllChecks) -> Void)?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var dailyTask: Task<Void, Never>?

    /// - Parameters:
    ///   - allTimeout: `check all`: solo riserva (`defaultAllTimeout`), il motore dà già a ogni
    ///     check il suo timeout e mette "timeout" nella riga bloccata.
    ///   - actionTimeout: azioni brevi e piani (30 s).
    ///   - longActionTimeout: azioni lunghe in background (`ActionTimeout.isLong`, 600 s).
    public init(runner: any CLIRunning = CLIRunner(),
                now: @escaping @Sendable () -> Date = { Date() },
                configStore: ConfigStore = ConfigStore(),
                allTimeout: TimeInterval = StatusStore.defaultAllTimeout,
                actionTimeout: TimeInterval = 30,
                longActionTimeout: TimeInterval = StatusStore.defaultLongActionTimeout) {
        self.runner = runner
        self.now = now
        self.configStore = configStore
        self.allTimeout = allTimeout
        self.actionTimeout = actionTimeout
        self.longActionTimeout = longActionTimeout
    }

    // MARK: - Badge

    /// `level`: error solo per vulnerabilità gravi (brew-vulns `severe>0`, audit con
    /// critical/high>0); action se almeno un check è action; altrimenti ok.
    /// `count`: il numero che accompagna l'icona. Con l'icona rossa (scudo) è il totale delle
    /// vulnerabilità, lo stesso numero grande della riga Vulnerabilità; negli altri casi è la
    /// somma dei `count` dei check in stato action, esclusi gli informativi.
    public var badge: (level: CheckState, count: Int) {
        let counted = results.filter { !Self.informative.contains($0.key) && $0.value.state == .action }
        let all = AllChecks(rows: results, raw: raw)
        // brew-vulns conta le formule colpite, non le CVE.
        let count = counted.reduce(0) { sum, kv in
            if kv.key == "brew-vulns", let bv = all.typed(BrewVulns.self, "brew-vulns"), !bv.items.isEmpty {
                return sum + Set(bv.items.map(\.formula)).count
            }
            return sum + kv.value.count
        }
        let severeVulns = (all.typed(BrewVulns.self, "brew-vulns")?.severe ?? 0) > 0
        let severeAudit = ["npm-audit", "composer-audit"].contains { name in
            all.typed(AuditResult.self, name)?.items.contains { $0.critical > 0 || $0.high > 0 } ?? false
        }
        if severeVulns || severeAudit { return (.error, PanelModel(all: all).vulnTotal) }
        // Un check fallito (stato error) non alza il badge: rosso solo per vulnerabilità.
        return (counted.isEmpty ? .ok : .action, count)
    }

    // MARK: - Refresh

    /// `devbar check all [--force]`. Se è già in corso un refresh, la chiamata è ignorata.
    /// Un check bloccato arriva dal motore come riga in errore ("timeout"); le altre righe
    /// si aggiornano. Motore occupato o refresh fallito: risultati precedenti mantenuti.
    public func refresh(force: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let r = await runner.run(["check", "all"] + (force ? ["--force"] : []), timeout: allTimeout)
        guard let all = try? AllChecks.decode(r.stdout) else {
            engineBusy = false
            let detail = r.stderr.split(separator: "\n").last.map(String.init) ?? ""
            refreshError = detail.isEmpty ? "devbar: output non valido (rc \(r.rc))" : detail
            return
        }
        if let global = all.rows["_all"] {
            if case .object(let o)? = all.raw["_all"], o["error"] == .string("busy") {
                // Lock del motore: un altro check all è in corso.
                engineBusy = true
            } else {
                engineBusy = false
                refreshError = global.summary.isEmpty ? "devbar: errore" : global.summary
            }
            return
        }
        engineBusy = false
        refreshError = nil
        results = all.rows
        raw = all.raw
        lastRefresh = now()
        onResults?(all)
    }

    /// Apertura del pannello: rilancia solo se l'ultimo refresh ha più di 5 minuti.
    public func panelOpened() async {
        if let last = lastRefresh, now().timeIntervalSince(last) < Self.panelThrottle { return }
        await refresh(force: false)
    }

    /// Azione non interattiva (`run …`, `detect`, `repos`): 30 s, 600 s per quelle lunghe.
    public func run(action args: [String]) async -> (rc: Int32, stdout: Data) {
        let r = await runner.run(args, timeout: ActionTimeout.isLong(args) ? longActionTimeout : actionTimeout)
        return (r.rc, r.stdout)
    }

    // MARK: - Config

    public func reloadConfig() {
        let (c, err) = configStore.load()
        config = c
        configError = err
    }

    // MARK: - Eventi

    /// Avvio, risveglio, rete tornata disponibile, timer giornaliero (`--force` solo qui).
    public func startObserving() {
        stopObserving()
        reloadConfig()

        let wake = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.refresh(force: false) }
                // Dopo il sonno l'orario del prossimo giro va ricalcolato.
                self.scheduleDaily()
            }
        }
        observers.append(wake)

        let monitor = NWPathMonitor()
        // Il monitor notifica subito lo stato corrente: si reagisce solo al ritorno a satisfied.
        let tracker = PathTracker()
        monitor.pathUpdateHandler = { [weak self] path in
            guard tracker.becameSatisfied(path.status == .satisfied) else { return }
            Task { @MainActor in await self?.refresh(force: false) }
        }
        monitor.start(queue: .main)
        pathMonitor = monitor

        scheduleDaily()
        Task { await refresh(force: false) }
    }

    public func stopObserving() {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        pathMonitor?.cancel()
        pathMonitor = nil
        dailyTask?.cancel()
        dailyTask = nil
    }

    private func scheduleDaily() {
        dailyTask?.cancel()
        dailyTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.reloadConfig()
                let fire = Self.nextDailyFire(after: self.now(), time: self.config.dailyCheckTime)
                let delay = max(1, fire.timeIntervalSince(self.now()))
                // Se il Mac dorme all'orario, ci pensa il refresh del risveglio.
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if Task.isCancelled { return }
                await self.refresh(force: true)
            }
        }
    }

    /// Prossimo `HH:mm` locale strettamente dopo `date`; orario non valido: 09:00.
    public nonisolated static func nextDailyFire(after date: Date, time: String,
                                                 calendar: Calendar = .current) -> Date {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        var (h, m) = (9, 0)
        if parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) {
            (h, m) = (parts[0], parts[1])
        }
        return calendar.nextDate(after: date, matching: DateComponents(hour: h, minute: m, second: 0),
                                 matchingPolicy: .nextTime) ?? date.addingTimeInterval(24 * 3600)
    }
}

/// Transizioni di rete; usato solo dalla coda main del monitor.
private final class PathTracker: @unchecked Sendable {
    private var satisfied: Bool?
    /// true solo al passaggio da non soddisfatto a soddisfatto (non alla prima notifica).
    func becameSatisfied(_ now: Bool) -> Bool {
        defer { satisfied = now }
        return now && satisfied == false
    }
}

/// Azioni lunghe che restano in background (le installazioni brew/cask/tool si aprono nel
/// terminale dal motore e tornano subito). I piani (senza `--yes`) sono sempre brevi.
public enum ActionTimeout {
    public static func isLong(_ args: [String]) -> Bool {
        // undo --yes ripristina anche cartelle (tar): ucciderlo a metà lascerebbe un file spostato da parte
        if args.first == "undo" { return args.contains("--yes") }
        guard args.first == "run", args.count > 1 else { return false }
        if let spec = FeatureRegistry.spec(forVerb: args[1]) { return spec.longVerbs.contains(args[1]) }
        switch args[1] {
        case "ai-install", "project-apply": return args.contains("--yes")
        default: return false
        }
    }
}

/// Sezione del pannello di un'azione: mentre gira, i pulsanti di quella sezione sono disattivati.
public enum ActionSection {
    /// AI setup, Init progetto e undo: scrivono negli stessi file di altri programmi (e il
    /// registro delle modifiche), quindi mai insieme.
    public static let ai = "ai"

    public static func of(_ args: [String]) -> String? {
        if args.first == "undo" { return ai }
        guard args.first == "run", args.count > 1 else { return nil }
        let verb = args[1]
        if verb == "ai-install" || verb == "project-apply" { return ai }
        if let spec = FeatureRegistry.spec(forVerb: verb) { return spec.section }
        if verb.hasPrefix("brew-") || verb.hasPrefix("cork-") { return "brew" }
        if verb == "tool-install" { return "tokens" }
        return nil
    }
}
