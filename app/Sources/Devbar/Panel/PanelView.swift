import SwiftUI
import AppKit
import Charts
import DevbarCore

struct PanelView: View {
    let store: StatusStore
    let actions: PanelActions
    /// Solo per le istantanee: niente `.task` che rilancia i controlli.
    var loadsOnAppear = true
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let model = PanelModel(all: AllChecks(rows: store.results, raw: store.raw), detect: actions.detect)
        let open = DetailsOpener(actions: actions, openWindow: openWindow)
        VStack(alignment: .leading, spacing: 0) {
            if store.results.isEmpty {
                Text(store.isRefreshing ? "Controllo in corso…" : "Nessun dato")
                    .font(Typo.title).foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            } else {
                rows(model, open: open)
            }
            Divider()
            FooterBar(store: store, actions: actions)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(width: 380)
        .task {
            guard loadsOnAppear else { return }
            await actions.loadDetect()
            await store.panelOpened()
        }
        .modifier(ConfirmationHost(actions: actions, origin: .panel))
    }

    /// Righe nell'ordine del pannello; la linea di separazione va tra una riga e la successiva,
    /// mai sopra la prima.
    @ViewBuilder private func rows(_ model: PanelModel, open: DetailsOpener) -> some View {
        let shown = [model.brewState == .shown, model.showsVulns, actions.colima.readout != nil,
                     model.showsTokenSection, model.showsLimits, model.caveman != nil, model.showsAISetup]
        let line = { (i: Int) in shown[..<i].contains(true) }
        if shown[0] {
            BrewRow(model: model, actions: actions, open: open)
        }
        if shown[1] {
            if line(1) { Divider() }
            VulnsRow(model: model, open: open)
        }
        if shown[2] {
            if line(2) { Divider() }
            ColimaRow(feature: actions.colima, open: open)
        }
        if shown[3] {
            if line(3) { Divider() }
            TokensRow(model: model, actions: actions, open: open)
        }
        if shown[4] {
            if line(4) { Divider() }
            LimitsRow(model: model, actions: actions)
        }
        if shown[5], let cv = model.caveman {
            if line(5) { Divider() }
            CavemanRow(panel: cv, control: actions.caveman)
        }
        if shown[6] {
            if line(6) { Divider() }
            AISetupRow(model: model, actions: actions)
        }
    }
}

// MARK: - Righe

struct BrewRow: View {
    let model: PanelModel
    let actions: PanelActions
    let open: DetailsOpener

    var body: some View {
        let r = model.brewReadout
        ReadoutRow(title: "Homebrew", subtitle: r.subtitle, readout: r.value, tone: r.tone,
                   busy: actions.isRunning("brew"), onDetails: { open(.homebrew) }, content: { EmptyView() }, accessory: {
            if model.brewUpgradeEnabled && !model.brewItems.isEmpty {
                Button("Aggiorna pacchetti") { Task { await actions.run(["run", "brew-upgrade"], refresh: false) } }
                    .controlSize(.small).disabled(actions.isRunning("brew"))
            }
        })
    }
}

struct VulnsRow: View {
    let model: PanelModel
    let open: DetailsOpener

    var body: some View {
        let r = model.vulnReadout
        ReadoutRow(title: "Vulnerabilità", subtitle: r.subtitle, note: r.note, readout: r.value, tone: r.tone,
                   onDetails: { open(model.vulnRows.contains { $0.id == "brew" } ? .vulns : .audit) },
                   content: { EmptyView() }, accessory: { EmptyView() })
    }
}

/// Una riga per strumento: colore, nome, numero (o stato) e una frase su cosa misura.
/// Il grafico a barre sta nella riga di RTK, perché è di RTK.
struct TokensRow: View {
    let model: PanelModel
    let actions: PanelActions
    let open: DetailsOpener

    var body: some View {
        let r = model.tokensReadout
        ReadoutRow(title: "Token risparmiati", subtitle: r.subtitle, readout: r.value, tone: r.tone,
                   busy: actions.isRunning("tokens"), onDetails: { open(.tokens) }) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.tokenRows) { row in TokenToolLine(row: row) }
                let inits = initTools
                if !inits.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(inits, id: \.tool) { t in
                            Button("Init \(t.title)") {
                                Task { await actions.request(.init(title: "Installa \(t.title)",
                                                                   args: ["run", "tool-install", t.tool])) }
                            }.controlSize(.small).disabled(actions.isRunning("tokens"))
                        }
                    }
                }
            }
        }
    }

    private var initTools: [(title: String, tool: String)] {
        var out: [(String, String)] = []
        if model.rtkState == .initOnly { out.append(("RTK", "rtk")) }
        if model.tokensaveState == .initOnly { out.append(("tokensave", "tokensave")) }
        if model.tokenEconomizerState == .initOnly { out.append(("TokenEconomizer", "tokeneconomizer")) }
        return out
    }
}

struct TokenToolLine: View {
    let row: TokenToolRow

    /// Un colore fisso per strumento, lo stesso in riga e nelle barre.
    static func color(for id: String) -> Color {
        switch id {
        case "rtk": return .blue
        case "tokensave": return .purple
        case "tokeneconomizer": return .teal
        default: return .orange
        }
    }

    var body: some View {
        let color = Self.color(for: row.id)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
                Text(row.title).font(Typo.title)
                if !row.daily.isEmpty {
                    MiniBars(daily: row.daily, color: color).frame(width: 56, height: 16)
                }
                Spacer(minLength: 8)
                if let v = row.value {
                    Text(v).font(Typo.title.monospacedDigit())
                } else if let active = row.active {
                    Text(active ? "attivo" : "non attivo").font(Typo.note)
                        .foregroundStyle(active ? Tone.ok.color : .secondary)
                        .fixedSize()
                        .padding(.horizontal, 7).padding(.vertical, 1)
                        .overlay(Capsule().stroke(active ? Tone.ok.color : Color.secondary.opacity(0.5), lineWidth: 1))
                }
            }
            Text(row.detail).font(Typo.note).foregroundStyle(.secondary)
                .lineLimit(2).padding(.leading, 18)
        }
    }
}

/// Limiti di consumo di Claude: non sono risparmi, hanno una sezione loro.
struct LimitsRow: View {
    let model: PanelModel
    let actions: PanelActions

    var body: some View {
        ReadoutRow(title: "Limiti di Claude", busy: actions.isRunning("tokens")) {
            VStack(alignment: .leading, spacing: 5) {
                if !model.usageMeters.isEmpty {
                    UsageMeters(meters: model.usageMeters)
                }
                if let n = model.usageNote { Text(n).font(Typo.note).foregroundStyle(.secondary) }
                if model.usageState == .initOnly {
                    Button("Init claude-usage") {
                        Task { await actions.request(.init(title: "Installa claude-usage",
                                                           args: ["run", "tool-install", "claude-usage"])) }
                    }.controlSize(.small).disabled(actions.isRunning("tokens"))
                }
            }
        }
    }
}

/// caveman: attivo globalmente, interruttore e modalità di default. Nessuna statistica.
struct CavemanRow: View {
    let panel: CavemanPanel
    let control: CavemanControl

    var body: some View {
        let busy = control.busy
        ReadoutRow(title: "caveman", subtitle: subtitle, busy: busy, content: {
            HStack(spacing: 8) {
                Circle().fill(panel.tone.color).frame(width: 8, height: 8)
                Text(panel.statusText).font(Typo.note).foregroundStyle(.secondary).fixedSize()
                Spacer(minLength: 8)
                Menu {
                    ForEach(CavemanMode.allCases, id: \.self) { m in
                        Button { Task { await control.set(m) } } label: {
                            if m == panel.mode { Label(m.menuTitle, systemImage: "checkmark") } else { Text(m.menuTitle) }
                        }
                    }
                } label: {
                    Text(panel.mode.label)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(busy)
            }
        }, accessory: {
            Toggle("caveman", isOn: Binding(
                get: { panel.active },
                set: { on in Task { await control.set(panel.toggleTarget(turningOn: on)) } }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(busy || !panel.canToggle)
        })
    }

    /// Esito dell'ultima modifica (o errore); altrimenti la nota fissa.
    private var subtitle: String {
        control.error ?? control.note ?? CavemanPanel.note
    }
}

/// Barre minime degli ultimi giorni RTK (Swift Charts, senza assi).
struct MiniBars: View {
    let daily: [DailySaving]
    var color: Color = Tone.info.color
    var body: some View {
        Chart(daily, id: \.date) { d in
            BarMark(x: .value("Giorno", d.date), y: .value("Token risparmiati", d.saved))
                .foregroundStyle(color)
                .cornerRadius(1)
        }
        .chartXAxis(.hidden).chartYAxis(.hidden)
        .help("RTK, ultimi \(daily.count) giorni")
    }
}

struct AISetupRow: View {
    let model: PanelModel
    let actions: PanelActions
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ReadoutRow(title: "AI setup") {
            // Gli harness non gestiti si gestiscono nelle impostazioni, non qui.
            FlowLayout {
                ForEach(model.aiTools, id: \.self) { t in
                    Button(t) {
                        NSApp.activate(ignoringOtherApps: true)
                        openWindow(id: WindowID.aiSetup)
                        Task { await actions.aiSetup.begin(displayTool: t) }
                    }
                }
                Button("Init progetto") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: WindowID.initProject)
                    Task { await actions.projectInit.loadRepos() }
                }
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
        }
    }
}
