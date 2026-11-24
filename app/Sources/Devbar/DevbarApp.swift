import SwiftUI
import AppKit
import DevbarCore

@main
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
        // Niente icona nel Dock (LSUIElement nell'Info.plist, qui anche per `swift run`).
        NSApplication.shared.setActivationPolicy(.accessory)
        // Avvio al login: allinea il plist alla config, solo se si gira da bundle installato.
        if let exe = Bundle.main.executablePath, Bundle.main.bundlePath.hasSuffix(".app") {
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

        Settings { SettingsView(model: actions.settings) }

        Window("AI setup", id: WindowID.aiSetup) { HarnessPicker(model: actions.aiSetup) }
            .windowResizability(.contentSize)
        Window("Init progetto", id: WindowID.initProject) { ProjectInitView(model: actions.projectInit) }
            .windowResizability(.contentSize)
    }
}

struct BarLabel: View {
    let store: StatusStore
    var body: some View {
        let b = store.badge
        // Le label di MenuBarExtra sono template: il colore va "cotto" in un NSImage non template.
        HStack(spacing: 2) {
            Image(nsImage: Self.image(symbol: BarIcon.symbol(b.level), color: Self.nsColor(BarIcon.colorName(b.level))))
            if let t = BarIcon.countText(b.count) { Text(t) }
        }
    }

    static func nsColor(_ n: String) -> NSColor {
        switch n { case "red": .systemRed; case "orange": .systemOrange; default: .systemGreen }
    }

    static func image(symbol: String, color: NSColor) -> NSImage {
        let base = NSImage(systemSymbolName: symbol, accessibilityDescription: "devbar")
        let img = base?.withSymbolConfiguration(.init(paletteColors: [color])) ?? NSImage()
        img.isTemplate = false
        return img
    }
}
