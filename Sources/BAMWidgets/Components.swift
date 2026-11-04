import SwiftUI
import WidgetKit

/// Colours match the app's System theme (`Theme.system`).
enum WidgetColor {
    static let cpu = Color.blue
    static let memory = Color.yellow
    static let disk = Color.teal
    static let battery = Color.green
    static let gpu = Color.indigo
}

enum WidgetFmt {
    /// Short memory size for tight legends: "25.6 GB", "312 MB", one decimal at most.
    static func shortBytes(_ value: UInt64) -> String {
        let gb = Double(value) / Double(1 << 30)
        if gb >= 1 {
            return "\(gb.formatted(.number.precision(.fractionLength(gb < 100 ? 1 : 0)))) GB"
        }
        return "\((Double(value) / Double(1 << 20)).formatted(.number.precision(.fractionLength(0)))) MB"
    }

    static func bytes(_ value: UInt64) -> String {
        Int64(value).formatted(.byteCount(style: .memory))
    }

    static func diskBytes(_ value: UInt64) -> String {
        Int64(value).formatted(.byteCount(style: .file))
    }

    /// Disk size split into number and unit, decimal like Finder: ("612", "GB"), ("1.2", "TB").
    static func diskValue(_ value: UInt64) -> (number: String, unit: String) {
        let gb = Double(value) / 1e9
        if gb >= 1000 { return ((gb / 1000).formatted(.number.precision(.fractionLength(1))), "TB") }
        return (gb.formatted(.number.precision(.fractionLength(gb < 10 ? 1 : 0))), "GB")
    }

    static func gigabytes(_ value: UInt64) -> String {
        (Double(value) / Double(1 << 30)).formatted(.number.precision(.fractionLength(1)))
    }

    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    static func minutes(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

/// Activity-rings style progress ring; the filled part follows the widget's accent in tinted modes.
struct Ring: View {
    var fraction: Double
    var color: Color
    var lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0.001), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
        }
        .padding(lineWidth / 2)
    }
}

/// Rounded capacity bar like the Batteries and Storage settings.
struct CapacityBar: View {
    var fraction: Double
    var color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(color)
                    .frame(width: max(height, geo.size.width * min(max(fraction, 0), 1)))
                    .widgetAccentable()
            }
        }
        .frame(height: height)
    }
}

/// Small caps-style header: symbol and title, as in Apple's widgets.
struct WidgetHeader: View {
    var title: String
    var symbol: String
    var color: Color

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .symbolRenderingMode(.hierarchical)
            .widgetAccentable()
            .lineLimit(1)
    }
}

/// Large rounded number, the visual anchor of every widget.
struct BigValue: View {
    var text: String
    var size: CGFloat = 34

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .contentTransition(.numericText())
    }
}

/// Quiet "as of 10:42" footer, since widgets only refresh every few minutes.
struct UpdatedFooter: View {
    var date: Date

    var body: some View {
        Text("As of \(date, style: .time)")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
    }
}

extension SystemEntry {
    /// Activity Monitor's memory breakdown, in the app's colours.
    var memoryParts: [(name: String, value: UInt64, color: Color)] {
        [("App", memApp, .yellow), ("Wired", memWired, .orange),
         ("Compressed", memCompressed, .purple), ("Cached", memCached, .teal)]
    }
}

/// The memory breakdown's legend as a 2×2 grid, so names and values fit even in a half-width tile.
struct MemoryLegend: View {
    var entry: SystemEntry
    var font: Font = .caption2

    var body: some View {
        let parts = entry.memoryParts
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
            ForEach(0..<2, id: \.self) { row in
                GridRow {
                    ForEach(parts[(row * 2)..<(row * 2 + 2)], id: \.name) { part in
                        HStack(spacing: 4) {
                            Circle().fill(part.color).frame(width: 6, height: 6)
                            Text(part.name).foregroundStyle(.secondary)
                            Spacer(minLength: 4)
                            Text(WidgetFmt.shortBytes(part.value)).monospacedDigit()
                        }
                    }
                }
            }
        }
        .font(font)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// Stacked capsule of the memory breakdown, scaled to total memory.
struct MemoryBar: View {
    var entry: SystemEntry
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1.5) {
                ForEach(entry.memoryParts, id: \.name) { part in
                    Rectangle().fill(part.color)
                        .frame(width: max(0, geo.size.width * Double(part.value) / Double(max(entry.memTotal, 1)) - 1.5))
                }
                Spacer(minLength: 0)
            }
            .background(.quaternary)
            .clipShape(Capsule())
            .widgetAccentable()
        }
        .frame(height: height)
    }
}

extension View {
    /// Tapping a widget opens the matching section in the app (handled by `onOpenURL`).
    func opensSection(_ section: String) -> some View {
        widgetURL(URL(string: "betteractivitymonitor://\(section)"))
    }
}

extension EnvironmentValues {
    /// The widget's size. Views read this instead of `widgetFamily`, which is read-only, so widgetshots can render
    /// every size; in the widget extension the override is nil and this is WidgetKit's own value.
    var resolvedWidgetFamily: WidgetFamily { widgetFamilyOverride ?? widgetFamily }
    @Entry var widgetFamilyOverride: WidgetFamily?
}
