import SwiftUI
import AppKit
import Charts
import DevbarCore

/// Finestra "devbar — Dettagli": barra laterale con le aree, tabelle native a destra.
struct DetailsView: View {
    let store: StatusStore
    let actions: PanelActions

    var body: some View {
        let model = PanelModel(all: AllChecks(rows: store.results, raw: store.raw), detect: actions.detect)
        NavigationSplitView {
            List(Area.detailsAreas, selection: Bindable(actions).detailsArea) { a in
                HStack(spacing: 8) {
                    Circle().fill(tone(of: a, model).color).frame(width: 7, height: 7)
                    Text(a.title)
                }
                .tag(a)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 220)
        } detail: {
            Group {
                switch actions.detailsArea ?? .homebrew {
                case .homebrew: BrewDetails(model: model, actions: actions)
                case .vulns: VulnDetails(model: model, actions: actions)
                case .audit: AuditDetails(model: model, actions: actions)
                case .colima: ColimaDetails(feature: actions.colima)
                case .tokens, .aiSetup: TokenDetails(model: model)
                }
            }
            .navigationTitle((actions.detailsArea ?? .homebrew).title)
        }
        .frame(minWidth: 640, minHeight: 400)
        .modifier(ConfirmationHost(actions: actions, origin: .details))
    }

    /// Le aree con un modulo (`Feature`) danno il proprio tono; le altre lo prendono da `PanelModel`.
    private func tone(of area: Area, _ model: PanelModel) -> Tone {
        actions.features.first { $0.area == area }?.tone ?? model.tone(of: area)
    }
}

/// Area senza dati: strumento assente o check non configurato.
struct EmptyArea: View {
    let title: String
    let message: String
    var body: some View {
        ContentUnavailableView(title, systemImage: "circle.dashed", description: Text(message))
    }
}

/// Nota a piè di tabella, 11 pt.
struct Footnote: View {
    let text: String
    var body: some View {
        Text(text).font(Typo.note).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 6)
    }
}

// MARK: - Homebrew

struct BrewDetails: View {
    let model: PanelModel
    let actions: PanelActions

    var body: some View {
        let busy = actions.isRunning("brew")
        Group {
            if model.brewState != .shown {
                EmptyArea(title: "Homebrew", message: "Homebrew non è configurato.")
            } else if model.brewItems.isEmpty {
                EmptyArea(title: "Tutto aggiornato", message: model.brewError ?? "Nessun pacchetto da aggiornare.")
            } else {
                Table(model.brewDetailRows.sorted(using: actions.brewSort), sortOrder: Bindable(actions).brewSort) {
                    TableColumn("Pacchetto", value: \.name).width(min: 100, ideal: 150)
                    TableColumn("Installata", value: \.installed) { Text($0.installed).foregroundStyle(.secondary) }
                        .width(min: 60, ideal: 85)
                    TableColumn("Disponibile", value: \.available).width(min: 60, ideal: 85)
                    TableColumn("Tipo", value: \.kind) { Text($0.kind).foregroundStyle(.secondary) }
                        .width(56)
                    TableColumn("") { row in
                        HStack(spacing: 10) {
                            Button("Aggiorna") { Task { await actions.run(["run", "brew-upgrade", row.name], refresh: false) } }
                            Button("Escludi") { Task { await actions.run(["run", "brew-exclude", row.name]) } }
                        }
                        .buttonStyle(.link).disabled(busy)
                    }
                    .width(min: 118, ideal: 118)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                if busy { Text("in corso…").font(Typo.note).foregroundStyle(.secondary) }
                Button("Aggiorna tutto") { Task { await actions.run(["run", "brew-upgrade"], refresh: false) } }
                    .disabled(busy || !model.brewUpgradeEnabled)
                Button(model.corkButtonTitle) {
                    if model.corkInstalled {
                        Task { await actions.run(["run", "cork-open"], refresh: false) }
                    } else {
                        Task { await actions.request(.init(title: "Installa Cork", args: ["run", "cork-install"]), from: .details) }
                    }
                }
                .disabled(busy)
            }
        }
    }
}

// MARK: - Vulnerabilità

struct VulnDetails: View {
    let model: PanelModel
    let actions: PanelActions

    var body: some View {
        if !model.vulnRows.contains(where: { $0.id == "brew" }) {
            EmptyArea(title: "Vulnerabilità", message: "Il controllo delle formule Homebrew non è configurato.")
        } else {
            VStack(spacing: 0) {
                HStack {
                    Picker("Mostra", selection: Bindable(actions).vulnFilter) {
                        ForEach(VulnFilter.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    Spacer()
                    if let e = model.brewVulnError { Text(e).font(Typo.note).foregroundStyle(.secondary) }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                let rows = model.vulnDetailRows(filter: actions.vulnFilter)
                Table(actions.vulnSort.isEmpty ? rows : rows.sorted(using: actions.vulnSort),
                      sortOrder: Bindable(actions).vulnSort) {
                    TableColumn("Formula", value: \.formula).width(min: 90, ideal: 130)
                    TableColumn("ID", value: \.cve) { Text($0.cve).font(.body.monospaced()) }.width(min: 120, ideal: 150)
                    TableColumn("Gravità", value: \.severityRank) { r in
                        HStack(spacing: 6) {
                            Circle().fill(r.tone.color).frame(width: 7, height: 7)
                            Text(r.severity).foregroundStyle(r.tone == .info ? .secondary : .primary)
                        }
                    }
                    .width(110)
                    TableColumn("Correzione", value: \.fix) { Text($0.fix).foregroundStyle(.secondary) }
                        .width(90)
                }
                Divider()
                Footnote(text: "Solo formule Homebrew: i cask non sono coperti.")
            }
        }
    }
}

// MARK: - Audit repo

struct AuditDetails: View {
    let model: PanelModel
    let actions: PanelActions

    var body: some View {
        if !model.showsAudit {
            EmptyArea(title: "Audit repo", message: "Configura le cartelle dei repo nelle impostazioni (serve npm o composer).")
        } else if model.auditDetailRows.isEmpty {
            EmptyArea(title: "Nessun repo", message: "Nessun repo npm o composer trovato nelle cartelle configurate.")
        } else {
            let rows = model.auditDetailRows
            Table(actions.auditSort.isEmpty ? rows : rows.sorted(using: actions.auditSort),
                  sortOrder: Bindable(actions).auditSort) {
                TableColumn("Repo", value: \.repo) { r in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.repo)
                        if let e = r.error { Text(e).font(Typo.note).foregroundStyle(.secondary) }
                    }
                }
                .width(min: 90, ideal: 140)
                TableColumn("Tool", value: \.tool) { Text($0.tool).foregroundStyle(.secondary) }.width(70)
                TableColumn("Critiche", value: \.critical) { count($0.critical, .risk) }.width(60)
                TableColumn("Alte", value: \.high) { count($0.high, .risk) }.width(50)
                TableColumn("Moderate", value: \.moderate) { count($0.moderate, .action) }.width(66)
                TableColumn("Basse", value: \.low) { count($0.low, .action) }.width(50)
                TableColumn("") { r in
                    Button { Task { await actions.openRepo(r.path) } } label: { Image(systemName: "terminal") }
                        .buttonStyle(.borderless)
                        .help("Apri nel terminale")
                }
                .width(28)
            }
            .contextMenu(forSelectionType: AuditDetailRow.ID.self) { ids in
                if let id = ids.first, let r = rows.first(where: { $0.id == id }) {
                    Button("Apri nel terminale") { Task { await actions.openRepo(r.path) } }
                }
            }
        }
    }

    private func count(_ n: Int, _ tone: Tone) -> some View {
        Text("\(n)").monospacedDigit()
            .foregroundStyle(n > 0 ? tone.color : Color.secondary)
    }
}

// MARK: - Token

struct TokenDetails: View {
    let model: PanelModel

    var body: some View {
        Form {
            Section("RTK") {
                switch model.rtkState {
                case .shown:
                    if !model.rtkAllDaily.isEmpty {
                        Chart(model.rtkAllDaily, id: \.date) { d in
                            BarMark(x: .value("Giorno", Fmt.day(d.date)), y: .value("Token risparmiati", d.saved))
                                .foregroundStyle(Tone.info.color)
                                .cornerRadius(2)
                        }
                        .chartYAxis { AxisMarks { v in
                            AxisGridLine()
                            AxisValueLabel { if let n = v.as(Int.self) { Text(Fmt.tokens(n)) } }
                        } }
                        .frame(height: 140)
                        .padding(.vertical, 4)
                    }
                    if let s = model.rtkSaved { LabeledContent("Token risparmiati", value: Fmt.tokens(s)) }
                    LabeledContent("Percentuale", value: model.rtkLine.replacingOccurrences(of: "RTK ", with: ""))
                    if let c = model.rtkCommands { LabeledContent("Comandi", value: "\(c)") }
                case .initOnly: Text("RTK non è installato.").foregroundStyle(.secondary)
                case .hidden: Text("Nessun dato.").foregroundStyle(.secondary)
                }
            }
            Section("tokensave") {
                if let t = model.tokensave {
                    LabeledContent("Token risparmiati", value: Fmt.tokens(t.saved))
                    LabeledContent("Chiamate", value: "\(t.calls)")
                    LabeledContent("Occasioni perse", value: "\(t.missedTurns)")
                } else {
                    Text(model.tokensaveState == .initOnly ? "tokensave non è installato." : "Nessun dato.")
                        .foregroundStyle(.secondary)
                }
            }
            if model.cavemanMode != nil || model.cavemanVersion != nil {
                Section("caveman") {
                    if let m = model.cavemanMode { LabeledContent("Modalità", value: m) }
                    if let v = model.cavemanVersion { LabeledContent("Versione", value: v) }
                }
            }
            Section("Consumo Claude") {
                if model.usageMeters.isEmpty {
                    Text(model.usageNote ?? (model.usageState == .initOnly ? "claude-usage non è installato." : "Nessun dato."))
                        .foregroundStyle(.secondary)
                } else {
                    UsageMeters(meters: model.usageMeters)
                    if let n = model.usageNote { Text(n).font(Typo.note).foregroundStyle(.secondary) }
                }
            }
        }
        .formStyle(.grouped)
    }
}
