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
        // Niente icona nel Dock (Task 15 aggiunge LSUIElement nell'Info.plist).
        NSApplication.shared.setActivationPolicy(.accessory)
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

        // Il contenuto arriva con il Task 14.
        Settings { EmptyView() }
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
