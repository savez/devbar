import Foundation
import Observation

/// Stato delle impostazioni. Ogni modifica si salva subito in config.json, così chiudere la
/// finestra non perde nulla. Config illeggibile (Ruling H): non si scrive finché l'utente non
/// conferma di sovrascriverla.
@Observable @MainActor
public final class SettingsModel {
    public static let terminals = ["Terminal", "iTerm", "Ghostty"]
    public static let depthRange = 1...8

    public private(set) var config = DevbarConfig()
    public private(set) var configError: String?
    public private(set) var detect: DetectResult?
    public private(set) var saveError: String?
    public private(set) var loginError: String?
    /// Dialogo "Sovrascrivere la config?" in attesa.
    public var overwritePromptShown = false
    public var newExclude = ""
    public let confirmation: PlanConfirmation

    @ObservationIgnored private let configStore: ConfigStore
    @ObservationIgnored private let runner: any ActionRunning
    @ObservationIgnored private let login: any LoginItemManaging
    @ObservationIgnored private let executablePath: String
    @ObservationIgnored private var overwriteConfirmed = false
    /// La config rotta è già stata sostituita da quella mostrata (dopo la conferma).
    @ObservationIgnored private var replacedBroken = false
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var deferredHarnessPlan: String?
    @ObservationIgnored private var deferredLogin: Bool?
    /// Ultimo stato mostrato/salvato: `cancelOverwrite` ci torna.
    @ObservationIgnored private var committed = DevbarConfig()
    /// La config su disco è cambiata: il chiamante la ricarica nello store.
    @ObservationIgnored public var onSaved: () -> Void = {}
    /// Finestra chiusa dopo modifiche, o installazioni fatte: il chiamante rilancia i check.
    @ObservationIgnored public var onApplied: () async -> Void = {}

    public init(configStore: ConfigStore, runner: any ActionRunning, login: any LoginItemManaging,
                executablePath: String = Bundle.main.executablePath ?? CommandLine.arguments[0]) {
        self.configStore = configStore
        self.runner = runner
        self.login = login
        self.executablePath = executablePath
        confirmation = PlanConfirmation(runner: runner)
    }

    // MARK: - Caricamento

    public func load() async {
        let (c, err) = configStore.load()
        config = c; committed = c; configError = err
        overwriteConfirmed = false; overwritePromptShown = false; replacedBroken = false
        saveError = nil; loginError = nil
        let r = await runner.run(action: ["detect"])
        detect = try? JSONDecoder().decode(DetectResult.self, from: r.stdout)
    }

    /// Harness da mostrare: gli installati, più quelli in config non (più) rilevati.
    public var harnessRows: [(id: String, installed: Bool, checked: Bool)] {
        var ids = (detect?.harnesses ?? []).filter(\.installed).map(\.id)
        for h in config.harnesses where !ids.contains(h) { ids.append(h) }
        return ids.map { id in
            (id, detect?.harnesses.first(where: { $0.id == id })?.installed ?? false, config.harnesses.contains(id))
        }
    }

    // MARK: - Salvataggio

    /// true se scritto su disco. Con config rotta e senza conferma non scrive e chiede.
    /// `change` si applica alla config mostrata e, al salvataggio, all'ultima versione del
    /// file (ConfigStore.update): le scritture del motore fatte dopo `load()` restano.
    @discardableResult
    private func persist(_ change: (inout DevbarConfig) -> Void) -> Bool {
        change(&config)
        if configError != nil && !overwriteConfirmed {
            overwritePromptShown = true
            return false
        }
        do {
            if overwriteConfirmed && configError == nil && !replacedBroken {
                // config rotta sostituita: si scrive tutta la config mostrata, una volta
                try configStore.save(config)
                replacedBroken = true
            } else {
                config = try configStore.update(change)
            }
            saveError = nil; dirty = true; committed = config
            onSaved()
            return true
        } catch {
            saveError = "salvataggio fallito: \(error.localizedDescription)"
            return false
        }
    }

    /// Sì al dialogo: da qui la config rotta viene sostituita dalle impostazioni mostrate.
    public func confirmOverwrite() async {
        overwriteConfirmed = true
        overwritePromptShown = false
        configError = nil
        let saved = persist { _ in }
        if saved, let on = deferredLogin { deferredLogin = nil; applyLogin(on) }
        deferredLogin = nil
        if let id = deferredHarnessPlan { deferredHarnessPlan = nil; await planInstalls(forNew: id, otherManaged: []) }
    }

    /// No al dialogo: niente scritto, le impostazioni tornano ai valori letti (i default).
    public func cancelOverwrite() {
        overwritePromptShown = false
        deferredHarnessPlan = nil
        deferredLogin = nil
        config = committed
    }

    // MARK: - Modifiche

    public func addRoots(_ paths: [String]) {
        let new = paths.filter { !$0.isEmpty }
        guard new.contains(where: { !config.repoRoots.contains($0) }) else { return }
        persist { c in for p in new where !c.repoRoots.contains(p) { c.repoRoots.append(p) } }
    }

    public func removeRoot(_ path: String) {
        persist { $0.repoRoots.removeAll { $0 == path } }
    }

    public func setDepth(_ d: Int) {
        let v = min(Self.depthRange.upperBound, max(Self.depthRange.lowerBound, d))
        guard v != config.scanDepth else { return }
        persist { $0.scanDepth = v }
    }

    /// Orario "HH:mm"; valori fuori scala vengono scartati.
    public func setDailyTime(hour: Int, minute: Int) {
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { return }
        let t = String(format: "%02d:%02d", hour, minute)
        guard t != config.dailyCheckTime else { return }
        persist { $0.dailyCheckTime = t }
    }

    public var dailyTimeParts: (hour: Int, minute: Int) {
        let p = config.dailyCheckTime.split(separator: ":").compactMap { Int($0) }
        if p.count == 2, (0..<24).contains(p[0]), (0..<60).contains(p[1]) { return (p[0], p[1]) }
        return (9, 0)
    }

    public func setTerminal(_ t: String) {
        guard Self.terminals.contains(t), t != config.terminal else { return }
        persist { $0.terminal = t }
    }

    public func addExclude() {
        let p = newExclude.trimmingCharacters(in: .whitespacesAndNewlines)
        newExclude = ""
        guard !p.isEmpty, !config.brewExclude.contains(p) else { return }
        persist { c in if !c.brewExclude.contains(p) { c.brewExclude.append(p) } }
    }

    public func removeExclude(_ p: String) {
        persist { $0.brewExclude.removeAll { $0 == p } }
    }

    /// Spunta o toglie un harness. Spuntarne uno nuovo prepara (non esegue) l'ai-install per
    /// gli strumenti già installati su un altro harness gestito: la conferma è nella vista.
    public func setHarness(_ id: String, on: Bool) async {
        // stato più recente: ai-install può aver aggiunto harness dopo `load()`
        let latest = configStore.load()
        let before = latest.error == nil ? latest.0.harnesses : config.harnesses
        if on {
            guard !before.contains(id) else { config.harnesses = before; return }
        } else {
            guard before.contains(id) else { config.harnesses = before; return }
        }
        persist { c in
            if on { if !c.harnesses.contains(id) { c.harnesses.append(id) } } else { c.harnesses.removeAll { $0 == id } }
        }
        guard on else { return }
        if overwritePromptShown { deferredHarnessPlan = id; return }
        await planInstalls(forNew: id, otherManaged: before)
    }

    func planInstalls(forNew id: String, otherManaged: [String]) async {
        var statuses: [AIStatus] = []
        for t in AISetup.tools {
            let r = await runner.run(action: ["run", "ai-status", t])
            if let s = try? JSONDecoder().decode(AIStatus.self, from: r.stdout) { statuses.append(s) }
        }
        let others = otherManaged.isEmpty ? config.harnesses : otherManaged
        let actions = AISetup.installsForNewHarness(id, otherManaged: others, statuses: statuses)
        guard !actions.isEmpty else { return }
        await confirmation.request(title: "Configurare \(id) come gli altri harness?", actions: actions)
    }

    public func confirmInstalls() async {
        if await confirmation.confirm() { await onApplied() }
    }

    // MARK: - Avvio al login

    /// Prima si salva la config; il plist/launchctl cambia solo dopo un salvataggio riuscito
    /// (con config rotta, solo dopo la conferma di sovrascrittura).
    public func setLaunchAtLogin(_ on: Bool) {
        loginError = nil
        guard on != config.launchAtLogin else { return }
        if persist({ $0.launchAtLogin = on }) { applyLogin(on) } else if overwritePromptShown { deferredLogin = on }
    }

    private func applyLogin(_ on: Bool) {
        do {
            if on { try login.enable(executablePath: executablePath) } else { try login.disable() }
        } catch {
            loginError = "avvio al login: \(error.localizedDescription)"
            persist { $0.launchAtLogin = !on }
        }
    }

    // MARK: - Chiusura

    /// Finestra chiusa: se qualcosa è cambiato, i check ripartono con la nuova config.
    public func didClose() async {
        guard dirty else { return }
        dirty = false
        await onApplied()
    }
}
