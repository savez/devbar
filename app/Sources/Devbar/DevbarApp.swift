import SwiftUI
import AppKit
import DevbarCore

/// Punto d'ingresso: `--render-snapshots <dir> <fixtures>` disegna il pannello e i Dettagli in PNG
/// con dati finti ed esce, senza avviare l'app né lanciare la CLI.
@main
enum Main {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-snapshots"), args.count > i + 2 {
            MainActor.assumeIsolated { Snapshots.run(outDir: args[i + 1], fixtures: args[i + 2]) }
            exit(0)
        }
        DevbarApp.main()
    }
}

struct DevbarApp: App {
    // `@State` è un macro (SwiftUIMacros) assente nelle Command Line Tools: stato in un
    // oggetto @Observable creato una volta sola.
    private let store: StatusStore
    private let actions: PanelActions

    init() {
        // Il plist del LaunchAgent ha una sola fonte (DevbarCore.LaunchAgent): `just install` lo chiede qui.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--print-launch-agent-plist"), args.count > i + 1,
           let data = try? LaunchAgent.plist(executablePath: args[i + 1]) {
            FileHandle.standardOutput.write(data)
            exit(0)
        }
        // Istanza unica: se ne gira già un'altra con lo stesso bundle id, si esce in silenzio.
        if let id = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: id).map(\.processIdentifier)
            if SingleInstance.shouldExit(ownPID: ProcessInfo.processInfo.processIdentifier, otherPIDs: others) { exit(0) }
        }
        // Posizione iniziale dell'icona (a destra): senza, Hidden Bar e simili la nascondono.
        StatusItemPosition.seedIfNeeded()
        // Niente icona nel Dock (LSUIElement nell'Info.plist, qui anche per `swift run`).
        NSApplication.shared.setActivationPolicy(.accessory)
        // Avvio al login: allinea il plist alla config, solo dal bundle installato in ~/Applications.
        if let exe = Bundle.main.executablePath,
           LoginReconciler.shouldReconcile(bundlePath: Bundle.main.bundlePath, home: NSHomeDirectory()) {
            let (cfg, err) = ConfigStore().load()
            if err == nil {
                _ = try? LoginReconciler.reconcile(launchAtLogin: cfg.launchAtLogin, plistURL: LaunchAgent.plistURL(), executablePath: exe)
            }
        }
        let s = StatusStore()
        store = s
        actions = PanelActions(store: s)
        s.startObserving()
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(store: store, actions: actions)
        } label: {
            BarLabel(store: store)
        }
        .menuBarExtraStyle(.window)

        Settings { SettingsView(model: actions.settings, journal: actions.journal) }

        Window("AI setup", id: WindowID.aiSetup) { HarnessPicker(model: actions.aiSetup) }
            .windowResizability(.contentSize)
        Window("Init progetto", id: WindowID.initProject) { ProjectInitView(model: actions.projectInit) }
            .windowResizability(.contentSize)
        Window("devbar — Dettagli", id: WindowID.details) { DetailsView(store: store, actions: actions) }
            .defaultSize(width: 760, height: 480)
    }
}

/// Icona fissa e template (monocromatica): niente stato, niente colore, niente conteggio.
/// L'icona dinamica era sospettata di confondere Hidden Bar; lo stato si vede nel pannello.
struct BarLabel: View {
    let store: StatusStore
    var body: some View {
        Image(nsImage: Self.glyph)
    }

    /// La "d." dell'icona dell'app (Icon/AppIcon.svg), disegnata in coordinate del SVG.
    static let glyph: NSImage = {
        let box = CGRect(x: 240, y: 210, width: 544, height: 526)
        let height = 18.0
        let scale = height / box.height
        let img = NSImage(size: NSSize(width: box.width * scale, height: height), flipped: true) { _ in
            let t = NSAffineTransform()
            t.scale(by: scale)
            t.translateX(by: -box.minX, yBy: -box.minY)
            t.concat()
            NSColor.black.set()
            let ring = NSBezierPath(ovalIn: CGRect(x: 443 - 150, y: 530 - 150, width: 300, height: 300))
            ring.lineWidth = 88
            ring.stroke()
            let stem = NSBezierPath()
            stem.move(to: NSPoint(x: 593, y: 260))
            stem.line(to: NSPoint(x: 593, y: 680))
            stem.lineWidth = 88
            stem.lineCapStyle = .round
            stem.stroke()
            NSBezierPath(ovalIn: CGRect(x: 729 - 46, y: 680 - 46, width: 92, height: 92)).fill()
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "devbar"
        return img
    }()
}
