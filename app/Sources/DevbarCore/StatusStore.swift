import Foundation
import Observation
import AppKit
import Network

/// Stato dei check per la UI. Esegue solo la CLI: nessuna logica di check qui.
@Observable @MainActor
public final class StatusStore {
    /// Check di `devbar check all`, nell'ordine di visualizzazione.
    public static let checkNames = ["brew-outdated", "brew-vulns", "npm-audit", "composer-audit",
                                    "colima", "rtk", "tokensave", "caveman", "claude-usage", "harnesses"]
    /// Check solo informativi: non contribuiscono mai al badge.
    public static let informative: Set<String> = ["colima", "rtk", "tokensave", "caveman", "claude-usage"]
    /// `panelOpened()` rilancia solo se l'ultimo refresh è più vecchio di così.
    public static let panelThrottle: TimeInterval = 5 * 60

    public private(set) var results: [String: CheckResult] = [:]
    /// JSON grezzo per riga, per i decoder tipizzati (`AllChecks.typed`).
    public private(set) var raw: [String: JSONValue] = [:]
    public private(set) var isRefreshing = false
    public private(set) var lastRefresh: Date?
    /// Ultimo `check all` trovato occupato (lock del motore): risultati precedenti mantenuti.
    public private(set) var engineBusy = false
    public private(set) var config = DevbarConfig()
    /// "config non valida: …" da mostrare nelle impostazioni.
    public private(set) var configError: String?

    private let runner: any CLIRunning
    private let now: @Sendable () -> Date
    private let configStore: ConfigStore
    private let allTimeout: TimeInterval
    private let checkTimeout: TimeInterval
    private let actionTimeout: TimeInterval

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var dailyTask: Task<Void, Never>?

    /// - Parameters:
    ///   - allTimeout: `check all` (120 s).
    ///   - checkTimeout: ogni check singolo, quando `check all` non termina (60 s).
    ///   - actionTimeout: azioni non interattive (30 s).
    public init(runner: any CLIRunning = CLIRunner(),
                now: @escaping @Sendable () -> Date = { Date() },
                configStore: ConfigStore = ConfigStore(),
                allTimeout: TimeInterval = 120,
                checkTimeout: TimeInterval = 60,
                actionTimeout: TimeInterval = 30) {
        self.runner = runner
        self.now = now
        self.configStore = configStore
        self.allTimeout = allTimeout
        self.checkTimeout = checkTimeout
        self.actionTimeout = actionTimeout
    }

    // MARK: - Badge

    /// `count`: somma dei `count` dei check in stato action, esclusi gli informativi.
    /// `level`: error solo per vulnerabilità gravi (brew-vulns `severe>0`, audit con
    /// critical/high>0); action se almeno un check è action; altrimenti ok.
    public var badge: (level: CheckState, count: Int) {
        let counted = results.filter { !Self.informative.contains($0.key) && $0.value.state == .action }
        let count = counted.values.reduce(0) { $0 + $1.count }
        let all = AllChecks(rows: results, raw: raw)
        let severeVulns = (all.typed(BrewVulns.self, "brew-vulns")?.severe ?? 0) > 0
        let severeAudit = ["npm-audit", "composer-audit"].contains { name in
            all.typed(AuditResult.self, name)?.items.contains { $0.critical > 0 || $0.high > 0 } ?? false
        }
        if severeVulns || severeAudit { return (.error, count) }
        // Un check fallito (stato error) non alza il badge: rosso solo per vulnerabilità.
        return (counted.isEmpty ? .ok : .action, count)
    }

    // MARK: - Refresh

    /// `devbar check all [--force]`. Se è già in corso un refresh, la chiamata è ignorata.
    /// Se `check all` non termina entro il timeout, ripiega sui check singoli in parallelo,
    /// ognuno col suo timeout: la riga bloccata va in errore, le altre si aggiornano.
    public func refresh(force: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let flag = force ? ["--force"] : []
        let r = await runner.run(["check", "all"] + flag, timeout: allTimeout)
        if let all = try? AllChecks.decode(r.stdout) {
            if all.rows["_all"] != nil {
                // Motore occupato (o errore globale): si tengono i risultati precedenti.
                engineBusy = true
                return
            }
            engineBusy = false
            results = all.rows
            raw = all.raw
            lastRefresh = now()
            return
        }

        engineBusy = false
        var newResults: [String: CheckResult] = [:]
        var newRaw: [String: JSONValue] = [:]
        let runner = self.runner, timeout = checkTimeout
        await withTaskGroup(of: (String, CheckResult, JSONValue?).self) { group in
            for name in Self.checkNames {
                group.addTask {
                    let r = await runner.run(["check", name] + flag, timeout: timeout)
                    return Self.decodeSingle(name: name, rc: r.rc, stdout: r.stdout, stderr: r.stderr)
                }
            }
            for await (name, result, json) in group {
                newResults[name] = result
                if let json { newRaw[name] = json }
            }
        }
        results = newResults
        raw = newRaw
        lastRefresh = now()
    }

    /// Output di `devbar check <name>`: un oggetto senza `rc`, si aggiunge quello di uscita.
    nonisolated static func decodeSingle(name: String, rc: Int32, stdout: Data, stderr: String)
        -> (String, CheckResult, JSONValue?) {
        if case .object(var obj)? = try? JSONDecoder().decode(JSONValue.self, from: stdout) {
            obj["rc"] = .number(Double(rc))
            let json = JSONValue.object(obj)
            if let data = try? JSONEncoder().encode(json),
               let result = try? JSONDecoder().decode(CheckResult.self, from: data) {
                return (name, result, json)
            }
        }
        let msg = stderr.split(separator: "\n").last.map(String.init) ?? ""
        return (name, .failure(msg.isEmpty ? "output non valido: \(name)" : msg), nil)
    }

    /// Apertura del pannello: rilancia solo se l'ultimo refresh ha più di 5 minuti.
    public func panelOpened() async {
        if let last = lastRefresh, now().timeIntervalSince(last) < Self.panelThrottle { return }
        await refresh(force: false)
    }

    /// Azione non interattiva (`run …`, `detect`, `repos`), timeout 30 s.
    public func run(action args: [String]) async -> (rc: Int32, stdout: Data) {
        let r = await runner.run(args, timeout: actionTimeout)
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
