import Foundation
import Observation

/// Modalità di default offribili (le one-shot commit/review/compress non c'entrano).
public enum CavemanMode: String, CaseIterable, Sendable {
    case off, manual, caveman, ultracave, megacave

    public var label: String {
        switch self {
        case .off: "Spento"
        case .manual: "Manuale"
        case .caveman: "caveman"
        case .ultracave: "ultracave"
        case .megacave: "megacave"
        }
    }

    public var summary: String {
        switch self {
        case .off: "mai attivo"
        case .manual: "solo con /caveman"
        case .caveman: "conciso, grammatica ridotta"
        case .ultracave: "ancora più stringato"
        case .megacave: "massima compressione"
        }
    }

    /// Voce di menu: "ultracave: ancora più stringato".
    public var menuTitle: String { "\(label): \(summary)" }
}

/// Stato del controllo caveman nel pannello (nessuna statistica di risparmio).
public struct CavemanPanel: Equatable, Sendable {
    public var mode: CavemanMode
    public var lastMode: CavemanMode
    public var pluginEnabled: Bool
    public var active: Bool
    public var version: String?

    public init(status s: CavemanStatus) {
        mode = s.mode.flatMap(CavemanMode.init(rawValue:)) ?? .caveman
        let last = s.lastMode.flatMap(CavemanMode.init(rawValue:)) ?? .caveman
        lastMode = last == .off ? .caveman : last
        pluginEnabled = s.pluginEnabled
        active = s.active
        version = s.version
    }

    public var statusText: String {
        if !pluginEnabled { return "plugin disattivato" }
        return active ? "attivo" : "spento"
    }

    public var tone: Tone {
        if !pluginEnabled { return .action }
        return active ? .ok : .info
    }

    /// Con il plugin disattivato cambiare il default non serve: l'interruttore resta fermo.
    public var canToggle: Bool { pluginEnabled }

    /// Acceso: ultima modalità non spenta (o caveman); spento: "off".
    public func toggleTarget(turningOn: Bool) -> CavemanMode {
        guard turningOn else { return .off }
        return mode == .off ? lastMode : mode
    }

    public static let note = "vale per le nuove sessioni"
}

/// Scrive la modalità di default via `devbar run caveman-mode <modo> --yes`.
/// Scelta: esecuzione diretta senza conferma. È una scrittura reversibile di una sola chiave;
/// l'output del motore (cosa è stato scritto) resta come nota dopo l'azione.
@Observable @MainActor
public final class CavemanControl {
    public private(set) var busy = false
    public private(set) var note: String?
    public private(set) var error: String?
    @ObservationIgnored public var onApplied: (() async -> Void)?
    @ObservationIgnored private let runner: any ActionRunning

    public init(runner: any ActionRunning) { self.runner = runner }

    public func set(_ mode: CavemanMode) async {
        guard !busy else { return }
        busy = true
        let r = await runner.run(action: ["run", "caveman-mode", mode.rawValue, "--yes"])
        if r.rc >= 2 {
            error = "caveman: " + (PlanConfirmation.engineError(r.stdout) ?? "fallito (rc \(r.rc))")
            note = nil
        } else {
            error = nil
            let lines = ActionPlan.parse(r.stdout).lines
            note = lines.isEmpty ? CavemanPanel.note : lines.joined(separator: ", ")
        }
        await onApplied?()
        busy = false
    }
}
