import Foundation

/// Riferimenti dell'app mostrati nelle impostazioni.
public enum AppInfo {
    public static let repositoryURL = URL(string: "https://github.com/savez/devbar")!
    public static let supportURL = URL(string: "https://buymeacoffee.com/goeokwihgz")!

    /// "0.3.0" (build 123) dal dizionario dell'Info.plist: "0.3.0 (123)"; senza build "0.3.0";
    /// senza versione "sconosciuta".
    public static func versionText(_ info: [String: Any]?) -> String {
        guard let version = info?["CFBundleShortVersionString"] as? String, !version.isEmpty else { return "sconosciuta" }
        guard let build = info?["CFBundleVersion"] as? String, !build.isEmpty, build != version else { return version }
        return "\(version) (\(build))"
    }
}
