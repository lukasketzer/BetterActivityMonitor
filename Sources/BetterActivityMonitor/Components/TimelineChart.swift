import SwiftUI
import SystemKit

struct TimelineSeries: Identifiable {
    var id: String { name }
    var name: String
    var color: Color
    var values: [HistoryValue]
}

/// Lines that may break into segments: wherever two points are further apart than `maxGap`
/// (the app wasn't running), the line stops instead of bridging the hole.
enum TimelineSegments {
    static func split(_ values: [HistoryValue], maxGap: TimeInterval) -> [[HistoryValue]] {
        var segments: [[HistoryValue]] = []
        for value in values {
            if let last = segments.last?.last, value.date.timeIntervalSince(last.date) <= maxGap {
                segments[segments.count - 1].append(value)
            } else {
                segments.append([value])
            }
        }
        return segments
    }

    /// The value at or just before `date`, if it lies within `maxGap`.
    static func value(in values: [HistoryValue], at date: Date, maxGap: TimeInterval) -> Double? {
        var low = 0, high = values.count
        while low < high {
            let mid = (low + high) / 2
            if values[mid].date <= date { low = mid + 1 } else { high = mid }
        }
        guard low > 0 else { return nil }
        let candidate = values[low - 1]
        return date.timeIntervalSince(candidate.date) <= maxGap ? candidate.value : nil
    }
}

/// Graph over a fixed time range, drawn with Canvas like `HistoryChart` but positioned by time, so
/// several charts line up and share one hover position.
struct TimelineChart: View {
    var series: [TimelineSeries]
    var range: ClosedRange<Date>
    /// Seconds per data point; gaps longer than two buckets break the line.
    var bucket: TimeInterval
    var maxY: Double?
    /// Shaded spans behind the lines (memory pressure), as (start, color).
    var bands: [(Date, Color)] = []
    @Binding var hover: Date?
    var onSelect: (Date) -> Void = { _ in }
    var format: (Double) -> String

    @AppStorage(SettingsKey.graphStyle) private var style: GraphStyle = .area
    private let axisWidth: CGFloat = 58

    private var maxGap: TimeInterval { bucket * 2.5 }

    var body: some View {
        GeometryReader { geo in
            let plot = CGSize(width: max(geo.size.width - axisWidth, 10), height: geo.size.height)
            let top = maxY ?? max((series.flatMap(\.values).map(\.value).max() ?? 0) * 1.15, .leastNonzeroMagnitude)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in draw(in: &context, plot: plot, top: top) }
                if let hover, series.contains(where: { !$0.values.isEmpty }) {
                    let x = x(of: hover, width: plot.width)
                    tooltip(at: hover)
                        .fixedSize()
                        .alignmentGuide(.leading) { d in -(x + 10 + d.width > plot.width ? x - d.width - 10 : x + 10) }
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): hover = p.x <= plot.width ? date(atX: p.x, width: plot.width) : nil
                case .ended: hover = nil
                }
            }
            .onTapGesture { location in
                if location.x <= plot.width { onSelect(date(atX: location.x, width: plot.width)) }
            }
        }
    }

    private var span: TimeInterval { max(range.upperBound.timeIntervalSince(range.lowerBound), 1) }

    private func x(of date: Date, width: CGFloat) -> CGFloat {
        CGFloat(date.timeIntervalSince(range.lowerBound) / span) * width
    }

    private func date(atX x: CGFloat, width: CGFloat) -> Date {
        range.lowerBound.addingTimeInterval(Double(x / width) * span)
    }

    private func draw(in context: inout GraphicsContext, plot: CGSize, top: Double) {
        let w = plot.width, h = plot.height
        func y(_ v: Double) -> CGFloat { h - CGFloat(v / top) * h }

        for (start, color) in bands {
            let x0 = x(of: start, width: w)
            let x1 = x(of: start.addingTimeInterval(bucket), width: w)
            context.fill(Path(CGRect(x: x0, y: 0, width: max(x1 - x0, 1), height: h)), with: .color(color.opacity(0.15)))
        }

        for tick in [top, top / 2, 0] {
            let ty = min(max(y(tick), 0.5), h - 0.5)
            var line = Path()
            line.move(to: CGPoint(x: 0, y: ty))
            line.addLine(to: CGPoint(x: w, y: ty))
            context.stroke(line, with: .color(.secondary.opacity(tick == 0 ? 0.35 : 0.15)), lineWidth: 0.5)
            context.draw(Text(format(tick)).font(.caption2).foregroundStyle(.secondary),
                         at: CGPoint(x: w + 6, y: ty), anchor: tick == top ? .topLeading : .leading)
        }

        for s in series.reversed() {
            for segment in TimelineSegments.split(s.values, maxGap: maxGap) {
                let points = segment.map { CGPoint(x: x(of: $0.date, width: w), y: y($0.value)) }
                if points.count == 1 || style == .bars {
                    let barWidth = max(x(of: range.lowerBound.addingTimeInterval(bucket), width: w) * 0.75, 1.5)
                    for p in points {
                        context.fill(Path(CGRect(x: p.x - barWidth / 2, y: p.y, width: barWidth, height: h - p.y)),
                                     with: .color(s.color.opacity(0.85)))
                    }
                    continue
                }
                var line = Path()
                line.addLines(points)
                if style == .area {
                    var area = line
                    area.addLine(to: CGPoint(x: points.last!.x, y: h))
                    area.addLine(to: CGPoint(x: points.first!.x, y: h))
                    area.closeSubpath()
                    context.fill(area, with: .linearGradient(Gradient(colors: [s.color.opacity(0.45), s.color.opacity(0.05)]),
                                                             startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
                }
                context.stroke(line, with: .color(s.color), style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
            }
        }

        if let hover {
            let hx = x(of: hover, width: w)
            var rule = Path()
            rule.move(to: CGPoint(x: hx, y: 0))
            rule.addLine(to: CGPoint(x: hx, y: h))
            context.stroke(rule, with: .color(.primary.opacity(0.4)), lineWidth: 1)
        }
    }

    private func tooltip(at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(date, format: span > 86_400 ? .dateTime.weekday().day().hour().minute() : .dateTime.hour().minute())
                .font(.caption2).foregroundStyle(.secondary)
            ForEach(series) { s in
                HStack(spacing: 5) {
                    Circle().fill(s.color).frame(width: 7, height: 7)
                    Text(s.name).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(TimelineSegments.value(in: s.values, at: date, maxGap: bucket).map(format) ?? "—").monospacedDigit()
                }
                .font(.caption)
            }
        }
        .padding(8)
        .frame(minWidth: 130)
        .glassCard(cornerRadius: 10)
    }
}

/// Time labels under a stack of `TimelineChart`s.
struct TimelineAxis: View {
    var range: ClosedRange<Date>
    private let axisWidth: CGFloat = 58

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width - axisWidth, 10)
            let span = range.upperBound.timeIntervalSince(range.lowerBound)
            ForEach(0..<5, id: \.self) { i in
                let date = range.lowerBound.addingTimeInterval(span * Double(i) / 4)
                Text(date, format: span > 86_400 ? .dateTime.month(.abbreviated).day() : .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .position(x: width * CGFloat(i) / 4, y: 8)
            }
        }
        .frame(height: 16)
    }
}
