import SwiftUI

struct ChartSeries: Identifiable {
    var id: String { name }
    var name: String
    var color: Color
    var history: History
    /// Plot below the axis (btop-style mirrored upload/download graphs).
    var mirrored = false
}

/// Time-series graph drawn with Canvas (Swift Charts is too heavy to redraw every second).
/// Hovering shows a rule and every series' value at that moment.
struct HistoryChart: View {
    var series: [ChartSeries]
    /// Fixed upper bound (e.g. 1 for percentages); nil scales to the data.
    var maxY: Double?
    var stacked = false
    var showsYAxis = true
    var format: (Double) -> String

    @AppStorage(SettingsKey.graphStyle) private var style: GraphStyle = .area
    @State private var hoverX: CGFloat?
    @State private var anchor = TooltipAnchor()

    private let axisWidth: CGFloat = 58

    var body: some View {
        GeometryReader { geo in
            let plot = CGSize(width: max(geo.size.width - (showsYAxis ? axisWidth : 0), 10), height: geo.size.height)
            let model = Model(series: series, stacked: stacked, maxY: maxY)
            let info = hoverX.flatMap { model.index(atX: $0, width: plot.width) }
                .map { tooltipInfo(model, index: $0, plotWidth: plot.width) }
            // The tooltip floats in its own window above the whole container (see FloatingTooltip),
            // so it is never clipped by the card and never affects the chart's layout.
            Canvas { context, _ in draw(model, in: &context, plot: plot) }
                .background(TooltipAnchorView(anchor: anchor))
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let p): hoverX = p.x <= plot.width ? p.x : nil
                    case .ended: hoverX = nil
                    }
                }
                .onChange(of: info, initial: true) { _, info in
                    if let info {
                        FloatingTooltip.shared.show(ChartTooltip(info: info), atX: info.x, from: anchor)
                    } else {
                        FloatingTooltip.shared.hide(from: anchor)
                    }
                }
                .onDisappear { FloatingTooltip.shared.hide(from: anchor) }
        }
    }

    // MARK: Model

    private struct Model {
        var series: [ChartSeries]
        var values: [[Double]]     // stacked if requested, signed for mirrored series
        var capacity: Int
        var bottom: Double
        var top: Double

        init(series: [ChartSeries], stacked: Bool, maxY: Double?) {
            self.series = series
            capacity = max(series.map(\.history.capacity).max() ?? 2, 2)
            var values = series.map { s in s.history.points.map { s.mirrored ? -$0.value : $0.value } }
            if stacked {
                for i in values.indices.dropFirst() {
                    let below = values[i - 1]
                    let n = min(values[i].count, below.count)
                    for j in 0..<n {
                        values[i][values[i].count - n + j] += below[below.count - n + j]
                    }
                }
            }
            self.values = values

            let positive = zip(series, values).filter { !$0.0.mirrored }.flatMap(\.1).max() ?? 0
            let negative = zip(series, values).filter { $0.0.mirrored }.flatMap(\.1).min()
            var top = maxY ?? max(positive * 1.15, .leastNonzeroMagnitude)
            var bottom = negative.map { maxY.map { -$0 } ?? min($0 * 1.15, -.leastNonzeroMagnitude) } ?? 0
            if negative != nil, maxY == nil {
                // Symmetric axis so up/down rates are visually comparable.
                let m = max(top, -bottom, 1)
                top = m
                bottom = -m
            }
            self.top = max(top, bottom + 0.000001)
            self.bottom = bottom
        }

        var pointCount: Int { values.map(\.count).max() ?? 0 }

        func x(_ index: Int, width: CGFloat) -> CGFloat {
            let step = width / CGFloat(capacity - 1)
            return width - CGFloat(pointCount - 1 - index) * step
        }

        func y(_ value: Double, height: CGFloat) -> CGFloat {
            height * CGFloat((top - value) / (top - bottom))
        }

        func index(atX x: CGFloat, width: CGFloat) -> Int? {
            guard pointCount > 0 else { return nil }
            let step = width / CGFloat(capacity - 1)
            let fromEnd = Int(((width - x) / step).rounded())
            let index = pointCount - 1 - fromEnd
            return index >= 0 && index < pointCount ? index : nil
        }
    }

    // MARK: Drawing

    private func draw(_ m: Model, in context: inout GraphicsContext, plot: CGSize) {
        let h = plot.height, w = plot.width

        // Grid + labels.
        let ticks = m.bottom < 0 ? [m.top, 0, m.bottom] : [m.top, m.top / 2, 0]
        for tick in ticks {
            let y = min(max(m.y(tick, height: h), 0.5), h - 0.5)
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: w, y: y))
            context.stroke(line, with: .color(.secondary.opacity(tick == 0 ? 0.35 : 0.15)), lineWidth: 0.5)
            if showsYAxis {
                context.draw(Text(format(abs(tick))).font(.caption2).foregroundStyle(.secondary),
                             at: CGPoint(x: w + 6, y: y), anchor: tick == m.top ? .topLeading : tick == m.bottom && m.bottom < 0 ? .bottomLeading : .leading)
            }
        }

        let baseline = m.y(0, height: h)
        // Draw stacked series top-down so lower layers stay visible.
        for (s, values) in zip(m.series, m.values).reversed() where values.count > 1 {
            let points = values.indices.map { CGPoint(x: m.x($0, width: w), y: m.y(values[$0], height: h)) }
            switch style {
            case .bars:
                let barWidth = max(w / CGFloat(m.capacity - 1) * 0.75, 1)
                for p in points {
                    let rect = CGRect(x: p.x - barWidth / 2, y: min(p.y, baseline), width: barWidth, height: abs(baseline - p.y))
                    context.fill(Path(rect), with: .color(s.color.opacity(0.85)))
                }
            case .line, .area:
                var line = Path()
                line.addLines(points)
                if style == .area {
                    var area = line
                    area.addLine(to: CGPoint(x: points.last!.x, y: baseline))
                    area.addLine(to: CGPoint(x: points.first!.x, y: baseline))
                    area.closeSubpath()
                    let edge = s.mirrored ? h : 0
                    context.fill(area, with: .linearGradient(
                        Gradient(colors: [s.color.opacity(stacked ? 0.75 : 0.5), s.color.opacity(stacked ? 0.35 : 0.06)]),
                        startPoint: CGPoint(x: 0, y: edge), endPoint: CGPoint(x: 0, y: baseline)))
                }
                context.stroke(line, with: .color(s.color), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
            }
        }

        if let hoverX, let index = m.index(atX: hoverX, width: w) {
            let x = m.x(index, width: w)
            var rule = Path()
            rule.move(to: CGPoint(x: x, y: 0))
            rule.addLine(to: CGPoint(x: x, y: h))
            context.stroke(rule, with: .color(.primary.opacity(0.4)), lineWidth: 1)
            for (s, values) in zip(m.series, m.values) where index < values.count {
                let p = CGPoint(x: x, y: m.y(values[index], height: h))
                context.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)), with: .color(s.color))
            }
        }
    }

    private func tooltipInfo(_ m: Model, index: Int, plotWidth: CGFloat) -> ChartTooltip.Info {
        ChartTooltip.Info(
            x: m.x(index, width: plotWidth),
            date: m.series.first?.history.points[safe: index]?.date,
            rows: m.series.map { s in
                .init(name: s.name, color: s.color, value: s.history.points[safe: index].map { format($0.value) } ?? "—")
            })
    }
}

/// Content of a HistoryChart hover tooltip; shown through `FloatingTooltip`.
struct ChartTooltip: View {
    struct Info: Equatable {
        struct Row: Equatable { var name: String; var color: Color; var value: String }
        var x: CGFloat
        var date: Date?
        var rows: [Row]
    }

    var info: Info

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let date = info.date {
                Text(date, format: .dateTime.hour().minute().second())
                    .font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(info.rows, id: \.name) { row in
                HStack(spacing: 5) {
                    Circle().fill(row.color).frame(width: 7, height: 7)
                    Text(row.name).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(row.value).monospacedDigit()
                }
                .font(.caption)
            }
        }
        .padding(8)
        .frame(minWidth: 130)
        .glassCard(cornerRadius: 10)
    }
}
