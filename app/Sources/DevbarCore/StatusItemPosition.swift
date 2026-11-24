import Foundation

/// Posizione iniziale dell'icona nella barra dei menu.
///
/// macOS ricorda dove sta un'icona solo se trova una posizione salvata nelle preferenze
/// dell'app. Senza, la mette all'estrema sinistra dell'area delle icone, dove app come
/// Hidden Bar la nascondono. SwiftUI (`MenuBarExtra`) assegna al suo elemento il nome
/// automatico `Item-0`: si scrive una posizione iniziale solo se non ce n'è già una, così
/// quella scelta dall'utente trascinando l'icona non viene mai sovrascritta.
public enum StatusItemPosition {
    public static let defaultsKey = "NSStatusItem Preferred Position Item-0"
    /// Distanza dal bordo destro: appena a sinistra delle icone di sistema.
    public static let initialValue = 40.0

    /// Scrive la posizione iniziale se manca. true se l'ha scritta.
    @discardableResult
    public static func seedIfNeeded(_ defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: defaultsKey) == nil else { return false }
        defaults.set(initialValue, forKey: defaultsKey)
        return true
    }
}
