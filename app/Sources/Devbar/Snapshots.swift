import SwiftUI
import AppKit
import DevbarCore

/// Risponde da file a `check all` e `detect`; tutto il resto torna rc 1 senza output.
/// Nessun processo viene lanciato.
private struct FixtureRunner: CLIRunning {
    let all: Data
    let detect: Data
    func run(_ args: [String], timeout: TimeInterval) async -> (rc: Int32, stdout: Data, stderr: String) {
        switch args.first {
        case "check": return (0, all, "")
        case "detect": return (0, detect, "")
        default: return (1, Data(), "")
        }
    }
}

/// Istantanee per la revisione visiva (`Devbar --render-snapshots <dir> <fixtures>`).
/// Per ogni coppia di fixture (`all`/`detect`, `all-rich`/`detect-rich`) disegna il pannello
/// e ogni area dei Dettagli, in chiaro e in scuro, a 2x. `ImageRenderer` non disegna le viste
/// AppKit (Table, List, NavigationSplitView): si usa una finestra fuori schermo.
@MainActor
enum Snapshots {
    static func run(outDir: String, fixtures: String) {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let out = URL(fileURLWithPath: outDir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let fix = URL(fileURLWithPath: fixtures)
        let checkedAt = ISO8601DateFormatter().date(from: "2026-11-24T09:25:00Z")!
        for (name, all, detect) in [("base", "all", "detect"), ("rich", "all-rich", "detect-rich")] {
            guard let a = try? Data(contentsOf: fix.appendingPathComponent("\(all).json")),
                  let d = try? Data(contentsOf: fix.appendingPathComponent("\(detect).json")) else {
                FileHandle.standardError.write(Data("fixture mancante: \(all)/\(detect)\n".utf8))
                continue
            }
            let store = StatusStore(runner: FixtureRunner(all: a, detect: d), now: { checkedAt },
                                    configStore: ConfigStore(url: out.appendingPathComponent("none.json")))
            let actions = PanelActions(store: store,
                                       configStore: ConfigStore(url: out.appendingPathComponent("none.json")))
            wait { await store.refresh(force: false); await actions.loadDetect() }
            for dark in [false, true] {
                let suffix = "\(name)-\(dark ? "dark" : "light")"
                render(PanelView(store: store, actions: actions, loadsOnAppear: false)
                        .background(Color(nsColor: .windowBackgroundColor)),
                       width: 380, height: nil, dark: dark, to: out.appendingPathComponent("panel-\(suffix).png"))
                for area in Area.detailsAreas {
                    actions.detailsArea = area
                    render(DetailsView(store: store, actions: actions), width: 760, height: 480, dark: dark,
                           to: out.appendingPathComponent("details-\(area.rawValue)-\(suffix).png"))
                }
            }
        }
    }

    private static func wait(_ body: @escaping @MainActor () async -> Void) {
        var done = false
        Task { @MainActor in await body(); done = true }
        while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    private static func render<V: View>(_ view: V, width: CGFloat, height: CGFloat?, dark: Bool, to url: URL) {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let h = height ?? host.fittingSize.height
        let rect = NSRect(x: 0, y: 0, width: width, height: h)
        let window = NSWindow(contentRect: rect, styleMask: height == nil ? [.borderless] : [.titled, .resizable],
                              backing: .buffered, defer: false)
        window.appearance = host.appearance
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
        // Con la barra del titolo si cattura la cornice (sfondo della finestra e toolbar).
        let target: NSView = height == nil ? host : (window.contentView?.superview ?? host)
        let bounds = target.bounds
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * scale),
                                         pixelsHigh: Int(bounds.height * scale), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = bounds.size
        target.cacheDisplay(in: bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
        print(url.path)
    }
}
