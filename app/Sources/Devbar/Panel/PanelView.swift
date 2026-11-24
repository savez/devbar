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
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let model = PanelModel(all: AllChecks(rows: store.results, raw: store.raw), detect: actions.detect)
        let open = DetailsOpener(actions: actions, openWindow: openWindow)
        VStack(alignment: .leading, spacing: 0) {
            if store.results.isEmpty {
                Text(store.isRefreshing ? "Controllo in corso…" : "Nessun dato")
                    .font(Typo.title).foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            } else {
                HealthStripView(strip: HealthStrip(model: model, features: actions.features, badge: store.badge),
                                checked: Fmt.checked(store.lastRefresh, isRefreshing: store.isRefreshing),
                                onSelect: { area in
                                    // AI setup non ha Dettagli: gli harness si gestiscono nelle impostazioni.
                                    if area == .aiSetup {
                                        NSApp.activate(ignoringOtherApps: true)
                                        openSettings()
                                    } else {
                                        open(area)
                                    }
                                })
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

    @ViewBuilder private func rows(_ model: PanelModel, open: DetailsOpener) -> some View {
        if model.brewState == .shown {
            Divider()
            BrewRow(model: model, actions: actions, open: open)
        }
        if model.showsVulns {
            Divider()
            VulnsRow(model: model, open: open)
        }
        if actions.colima.readout != nil {
            Divider()
            ColimaRow(feature: actions.colima, open: open)
        }
        if model.showsTokenSection {
            Divider()
            TokensRow(model: model, actions: actions, open: open)
        }
        if let cv = model.caveman {
            Divider()
            CavemanRow(panel: cv, control: actions.caveman)
        }
        if model.showsAISetup {
            Divider()
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

struct TokensRow: View {
    let model: PanelModel
    let actions: PanelActions
    let open: DetailsOpener

    var body: some View {
        let r = model.tokensReadout
        ReadoutRow(title: "Token risparmiati", readout: r.value, tone: r.tone,
                   busy: actions.isRunning("tokens"), onDetails: { open(.tokens) }) {
            VStack(alignment: .leading, spacing: 5) {
                if model.rtkState == .shown || model.tokensaveState == .shown {
                    HStack(spacing: 8) {
                        if model.rtkState == .shown {
                            if !model.rtkDaily.isEmpty { MiniBars(daily: model.rtkDaily).frame(width: 80, height: 18) }
                            Text(model.rtkLine).font(Typo.note).foregroundStyle(.secondary)
                        }
                    }
                    if model.tokensaveState == .shown {
                        Text(model.tokensaveLine).font(Typo.note).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                if !model.usageMeters.isEmpty {
                    UsageMeters(meters: model.usageMeters).padding(.top, 2)
                }
                if let n = model.usageNote { Text(n).font(Typo.note).foregroundStyle(.secondary) }
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
                    .padding(.top, 2)
                }
            }
        }
    }

    private var initTools: [(title: String, tool: String)] {
        var out: [(String, String)] = []
        if model.rtkState == .initOnly { out.append(("RTK", "rtk")) }
        if model.tokensaveState == .initOnly { out.append(("tokensave", "tokensave")) }
        if model.usageState == .initOnly { out.append(("claude-usage", "claude-usage")) }
        return out
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
    var body: some View {
        Chart(daily, id: \.date) { d in
            BarMark(x: .value("Giorno", d.date), y: .value("Token risparmiati", d.saved))
                .foregroundStyle(Tone.info.color)
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
