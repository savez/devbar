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
        HStack(spacing: 2) {
            Image(systemName: BarIcon.symbol(b.level))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Self.color(BarIcon.colorName(b.level)))
            if let t = BarIcon.countText(b.count) { Text(t) }
        }
    }
    static func color(_ n: String) -> Color {
        switch n { case "red": .red; case "orange": .orange; default: .green }
    }
}
