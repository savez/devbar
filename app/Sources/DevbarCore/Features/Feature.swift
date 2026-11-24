import Foundation
import Observation

// MARK: - Modulo di un'area

/// Un'area del pannello che possiede logica e stato propri (modello + view-model), aggiornata
/// dai risultati di `check all`. Il pannello, la barra di salute e la barra laterale dei
/// Dettagli ne leggono solo tono e numero. Volutamente minimo: ciò che serve a un'area sola
/// resta nel suo modulo.
@MainActor public protocol Feature: AnyObject, Observable {
    var area: Area { get }
    var tone: Tone { get }
    /// Riga del pannello; nil: area nascosta (niente riga né segmento nella barra).
    var readout: Readout? { get }
    func update(from all: AllChecks)
}

public extension Feature {
    /// Segmento della barra di salute, se l'area è visibile.
    var segment: StripSegment? { readout == nil ? nil : StripSegment(area: area, tone: tone) }
}

// MARK: - Servizi comuni ai moduli

/// Chi mostra la conferma: il pannello o la finestra Dettagli (solo quella che l'ha chiesta).
public enum DialogOrigin: Sendable { case panel, details }

/// Sezioni (ActionSection) con un'azione in corso: i loro pulsanti sono disattivati,
/// così un doppio clic non lancia due `colima start`. Condiviso da `PanelActions`
/// (conferma comune) e dai moduli (azioni dirette).
@Observable @MainActor
public final class SectionLocks {
    public private(set) var running: Set<String> = []

    public init() {}

    public func isRunning(_ section: String) -> Bool { running.contains(section) }

    /// Segna la sezione dell'azione come occupata finché `body` gira. false se lo era già.
    public func occupy(_ args: [String], _ body: () async -> Void) async -> Bool {
        let section = ActionSection.of(args)
        if let section {
            guard !running.contains(section) else { return false }
            running.insert(section)
        }
        await body()
        if let section { running.remove(section) }
        return true
    }

    /// Errore di un'azione diretta da mostrare nel piede: nil se riuscita (rc < 2).
    public nonisolated static func directError(_ args: [String], rc: Int32) -> String? {
        rc >= 2 ? "\(args.prefix(2).joined(separator: " ")): errore (rc \(rc))" : nil
    }
}
