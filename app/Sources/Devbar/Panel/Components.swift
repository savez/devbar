import SwiftUI
import AppKit
import DevbarCore

// MARK: - Palette

/// Le tinte approvate (DevbarCore.Tone.hex) come Color.
enum Palette {
    static func color(_ t: Tone) -> Color {
        let h = t.hex
        return Color(.sRGB, red: Double((h >> 16) & 0xFF) / 255, green: Double((h >> 8) & 0xFF) / 255,
                     blue: Double(h & 0xFF) / 255)
    }
}

extension Tone {
    var color: Color { Palette.color(self) }
}

enum Typo {
    static let title = Font.system(size: 13, weight: .semibold)
    static let note = Font.system(size: 11)
    static let readout = Font.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit()
}

enum WindowID {
    static let aiSetup = "ai-setup"
    static let initProject = "init-project"
    static let details = "details"
}

// MARK: - Riga del pannello

/// Riga unica per tutte le sezioni: titolo e sottotitolo a sinistra, eventuale contenuto sotto,
/// azioni, numero a destra e chevron verso i Dettagli.
struct ReadoutRow<Content: View, Accessory: View>: View {
    let title: String
    var subtitle: String?
    /// Seconda riga di sottotitolo.
    var note: String?
    var readout: String?
    var tone: Tone = .info
    var busy = false
    var onDetails: (() -> Void)?
    @ViewBuilder var content: Content
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if Content.self != EmptyView.self {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 26)
            }
        }
        .padding(.vertical, 10)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.title)
                ForEach([subtitle, note].compactMap { $0 }, id: \.self) { line in
                    Text(line).font(Typo.note).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if busy {
                Text("in corso…").font(Typo.note).foregroundStyle(.secondary)
            }
            accessory
            if let readout {
                Text(readout).font(Typo.readout).foregroundStyle(tone.color)
                    .lineLimit(1).fixedSize()
            }
            if let onDetails {
                Button(action: onDetails) {
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Dettagli")
            } else {
                Color.clear.frame(width: 16, height: 1)
            }
        }
    }
}

extension ReadoutRow where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, note: String? = nil, readout: String? = nil, tone: Tone = .info,
         busy: Bool = false, onDetails: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, note: note, readout: readout, tone: tone, busy: busy,
                  onDetails: onDetails, content: content, accessory: { EmptyView() })
    }
}

// MARK: - Barra di salute

struct HealthStripView: View {
    let strip: HealthStrip
    let checked: String?
    let onSelect: (Area) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 2) {
                ForEach(Array(strip.segments.enumerated()), id: \.element.id) { i, seg in
                    let first = i == 0, last = i == strip.segments.count - 1
                    Button { onSelect(seg.area) } label: {
                        UnevenRoundedRectangle(topLeadingRadius: first ? 3 : 0, bottomLeadingRadius: first ? 3 : 0,
                                               bottomTrailingRadius: last ? 3 : 0, topTrailingRadius: last ? 3 : 0)
                            .fill(seg.tone.color)
                            .frame(maxWidth: .infinity)
                            .frame(height: 6)
                            .contentShape(Rectangle().inset(by: -4))
                    }
                    .buttonStyle(.plain)
                    .help(seg.area.title)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(strip.todoText).font(Typo.title)
                Spacer()
                if let checked { Text(checked).font(Typo.note).foregroundStyle(.secondary) }
            }
        }
        .padding(.bottom, 10)
    }
}

// MARK: - Indicatore di consumo

/// Indicatori del consumo Claude in griglia: barre della stessa larghezza, a capsula sottile.
struct UsageMeters: View {
    let meters: [UsageMeter]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 5) {
            ForEach(meters) { m in
                GridRow {
                    Text(m.label).font(Typo.note).foregroundStyle(.secondary)
                    Capsule().fill(Color.secondary.opacity(0.18))
                        .frame(height: 4)
                        .frame(minWidth: 60, maxWidth: .infinity)
                        .overlay(alignment: .leading) {
                            GeometryReader { g in
                                Capsule().fill(m.tone.color).frame(width: max(4, g.size.width * m.fraction))
                            }
                        }
                    Text(m.percentText).font(Typo.note.monospacedDigit()).gridColumnAlignment(.trailing)
                    Text(m.reset ?? "").font(Typo.note).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                }
            }
        }
    }
}

// MARK: - Disposizione a capo

/// Dispone i figli in righe, andando a capo quando non c'è più spazio (pulsanti AI setup).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let w = rows.map { $0.width }.max() ?? 0
        let h = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: min(proposal.width ?? w, w), height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.indices {
                let s = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
                x += s.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let s = subviews[i].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? s.width : rows[rows.count - 1].width + spacing + s.width
            if extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row(indices: [i], width: s.width, height: s.height))
            } else {
                rows[rows.count - 1].indices.append(i)
                rows[rows.count - 1].width = extra
                rows[rows.count - 1].height = max(rows[rows.count - 1].height, s.height)
            }
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

// MARK: - Conferma

/// Conferma condivisa da pannello e Dettagli: compare solo dove è stata chiesta.
struct ConfirmationHost: ViewModifier {
    let actions: PanelActions
    let origin: DialogOrigin

    func body(content: Content) -> some View {
        content.confirmationDialog(actions.pending?.title ?? "Conferma",
                                   isPresented: Binding(get: { actions.dialogShown && actions.dialogOrigin == origin },
                                                        set: { actions.dialogShown = $0 }),
                                   titleVisibility: .visible) {
            Button("Conferma") { Task { await actions.confirmPending() } }
            Button("Annulla", role: .cancel) { actions.cancelPending() }
        } message: {
            // Solo testo: le righe del piano non vengono mai eseguite.
            Text(actions.plan?.text ?? "")
        }
    }
}

// MARK: - Apertura delle finestre

/// Apre la finestra Dettagli sull'area scelta.
struct DetailsOpener {
    let actions: PanelActions
    let openWindow: OpenWindowAction

    @MainActor func callAsFunction(_ area: Area) {
        actions.detailsArea = area
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: WindowID.details)
    }
}
