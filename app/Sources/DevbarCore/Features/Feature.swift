import Foundation
import Observation

// MARK: - Modulo di un'area

/// Ingresso di un modulo: risultati di `check all` e, quando caricato, `detect`.
public struct FeatureInput: Sendable {
    public var all: AllChecks
    public var detect: DetectResult?
    public init(all: AllChecks, detect: DetectResult? = nil) { self.all = all; self.detect = detect }
}

/// Un'area del pannello che possiede logica e stato propri (modello + view-model), aggiornata
/// dai risultati di `check all` e da `detect`. Il pannello, la barra di salute e la barra
/// laterale dei Dettagli ne leggono solo tono e numero. Volutamente minimo: ciò che serve a
/// un'area sola resta nel suo modulo.
@MainActor public protocol Feature: AnyObject, Observable {
    /// Aree dei Dettagli possedute dal modulo; la prima è quella della riga del pannello.
    var areas: [Area] { get }
    /// Pallino di un'area posseduta nella barra laterale dei Dettagli.
    func tone(of area: Area) -> Tone
    /// Riga del pannello; nil: area nascosta (niente riga né segmento nella barra).
    /// Il suo tono colora anche il segmento: riga e barra non possono divergere.
    var readout: Readout? { get }
    func update(from input: FeatureInput)
    /// Sezione di lock e verbi lunghi delle azioni del modulo (letti anche fuori dal main actor).
    nonisolated static var actions: FeatureActionSpec { get }
}

/// Azioni `devbar run <verbo>` di un modulo: quali verbi gli appartengono (per prefisso),
/// la sezione che occupano mentre girano e quali restano in background a lungo.
public struct FeatureActionSpec: Sendable, Equatable {
    public var section: String
    public var verbPrefixes: [String]
    public var longVerbs: Set<String>
    public init(section: String, verbPrefixes: [String], longVerbs: Set<String> = []) {
        self.section = section; self.verbPrefixes = verbPrefixes; self.longVerbs = longVerbs
    }
    public func owns(_ verb: String) -> Bool { verbPrefixes.contains { verb.hasPrefix($0) } }
}

/// Moduli registrati, consultati da `ActionSection` e `ActionTimeout`. Le aree non ancora
/// migrate restano scritte lì finché non diventano moduli.
public enum FeatureRegistry {
    public static let actionSpecs: [FeatureActionSpec] = [ColimaFeature.actions]

    static func spec(forVerb verb: String) -> FeatureActionSpec? { actionSpecs.first { $0.owns(verb) } }
}

/// Servizi del pannello per i moduli, passati alla creazione: conferma comune (piano senza
/// `--yes`, dialogo, poi `--yes`), refresh dopo un'azione, errore nel piede.
@MainActor public protocol FeatureHost: AnyObject {
    func request(_ action: ConfirmableAction, from origin: DialogOrigin) async
    /// Dopo un'azione che cambia lo stato: rilancia i controlli.
    func applied() async
    /// Esito dell'ultima azione diretta per il piede del pannello (nil: riuscita).
    func report(error: String?)
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
