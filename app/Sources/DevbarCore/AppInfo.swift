import Foundation

/// Riferimenti dell'app mostrati nelle impostazioni.
public enum AppInfo {
    public static let repositoryURL = URL(string: "https://github.com/savez/devbar")!
    public static let issuesURL = URL(string: "https://github.com/savez/devbar/issues")!
    public static let licenseURL = URL(string: "https://github.com/savez/devbar/blob/main/LICENSE")!
    public static let supportURL = URL(string: "https://buymeacoffee.com/goeokwihgz")!
    public static let tagline = "Il Mac di sviluppo sotto controllo, dalla barra dei menu."

    /// "0.3.0" (build 123) dal dizionario dell'Info.plist: "0.3.0 (123)"; senza build "0.3.0";
    /// senza versione "sconosciuta".
    public static func versionText(_ info: [String: Any]?) -> String {
        guard let version = info?["CFBundleShortVersionString"] as? String, !version.isEmpty else { return "sconosciuta" }
        guard let build = info?["CFBundleVersion"] as? String, !build.isEmpty, build != version else { return version }
        return "\(version) (\(build))"
    }
}
