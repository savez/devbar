import SwiftUI
import Charts
import DevbarCore

struct TokensSection: View {
    let model: PanelModel
    let actions: PanelActions

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: "Token")
            switch model.rtkState {
            case .shown:
                HStack {
                    Text(model.rtkLine)
                    Spacer()
                    if !model.rtkDaily.isEmpty {
                        Chart(model.rtkDaily, id: \.date) { d in
                            BarMark(x: .value("Giorno", d.date), y: .value("Token salvati", d.saved))
                        }
                        .chartXAxis(.hidden).chartYAxis(.hidden)
                        .frame(width: 90, height: 24)
                        Text("7gg").font(.caption).foregroundStyle(.secondary)
                    }
                }
            case .initOnly: initRow("RTK", tool: "rtk")
            case .hidden: EmptyView()
            }
            switch model.tokensaveState {
            case .shown: Text(model.tokensaveLine)
            case .initOnly: initRow("tokensave", tool: "tokensave")
            case .hidden: EmptyView()
            }
            if let c = model.cavemanLine { Text(c) }
            switch model.usageState {
            case .shown:
                VStack(alignment: .leading, spacing: 2) {
                    usageBar("5h", model.usageFiveHour, model.usageFiveHourReset)
                    usageBar("settimana", model.usageWeek, model.usageWeekReset)
                    if let n = model.usageNote { Text(n).font(.caption2).foregroundStyle(.secondary) }
                }
            case .initOnly: initRow("claude-usage", tool: "claude-usage")
            case .hidden: EmptyView()
            }
        }
        .font(.callout)
    }

    private func initRow(_ title: String, tool: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            InitButton(title: "Init \(title)") {
                Task { await actions.request(.init(title: "Installa \(title)", args: ["run", "tool-install", tool])) }
            }.disabled(actions.isRunning("tokens"))
        }
    }

    private func usageBar(_ label: String, _ pct: Double?, _ reset: String?) -> some View {
        HStack {
            Text("Claude \(label)").frame(width: 110, alignment: .leading)
            ProgressView(value: Fmt.fraction(pct))
            Text(pct.map { Fmt.percent($0) } ?? "—").frame(width: 36, alignment: .trailing)
            if let reset { Text(reset).font(.caption2).foregroundStyle(.secondary) }
        }
    }
}
