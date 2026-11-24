import Foundation

/// LaunchAgent di devbar. Il Task 15 installa lo stesso plist: la generazione sta qui, una sola.
public enum LaunchAgent {
    public static let label = "it.savez.devbar"

    public static func plistURL(home: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: home).appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    /// Plist XML: Label, ProgramArguments = [eseguibile], RunAtLoad, ProcessType Interactive,
    /// LimitLoadToSessionType Aqua.
    public static func plist(executablePath: String) throws -> Data {
        let dict: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
        ]
        return try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }
}

/// Avvio al login. Finto nei test: l'app non deve fare bootstrap/bootout nei test.
@MainActor
public protocol LoginItemManaging: AnyObject {
    func isEnabled() -> Bool
    func enable(executablePath: String) throws
    func disable() throws
}

/// Esegue `launchctl`. Finto nei test.
public protocol LaunchctlRunning: Sendable {
    /// Ritorna il codice di uscita.
    func launchctl(_ args: [String]) -> Int32
}

public struct SystemLaunchctl: LaunchctlRunning {
    public init() {}
    public func launchctl(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return 127 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}

public struct LoginItemError: Error, Equatable, LocalizedError, Sendable {
    public var message: String
    public var errorDescription: String? { message }
}

/// Scrive/rimuove il plist; `launchctl bootstrap gui/<uid>` solo se non già caricato. Mai bootout.
@MainActor
public final class LaunchAgentManager: LoginItemManaging {
    private let plistURL: URL
    private let uid: UInt32
    private let launchctl: any LaunchctlRunning

    public init(plistURL: URL = LaunchAgent.plistURL(), uid: UInt32 = getuid(),
                launchctl: any LaunchctlRunning = SystemLaunchctl()) {
        self.plistURL = plistURL
        self.uid = uid
        self.launchctl = launchctl
    }

    private var domain: String { "gui/\(uid)" }

    public func isEnabled() -> Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    public func enable(executablePath: String) throws {
        let data = try LaunchAgent.plist(executablePath: executablePath)
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: plistURL, options: .atomic)
        // Già caricato (es. avviato da launchd): niente bootstrap, e mai bootout del proprio job.
        if launchctl.launchctl(["print", "\(domain)/\(LaunchAgent.label)"]) == 0 { return }
        let rc = launchctl.launchctl(["bootstrap", domain, plistURL.path])
        guard rc == 0 else { throw LoginItemError(message: "launchctl bootstrap fallito (rc \(rc))") }
    }

    public func disable() throws {
        // Solo il plist: un bootout ucciderebbe l'app se l'ha avviata launchd.
        // Semplicemente non partirà al prossimo login.
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
    }
}
