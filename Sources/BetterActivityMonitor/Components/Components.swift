import SwiftUI

/// Rounded card used for dashboard boxes (btop's "boxes").
struct Panel<Content: View, Accessory: View>: View {
    @Environment(SystemStore.self) private var store
    var title: String
    var symbol: String
    /// Section the title navigates to when clicked.
    var destination: AppSection?
    /// When set, the panel is a disclosure: clicking the header shows or hides the content.
    var expanded: Binding<Bool>?
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content
    @State private var auditKey = UUID()

    init(_ title: String, symbol: String, destination: AppSection? = nil,
         expanded: Binding<Bool>? = nil,
         @ViewBuilder accessory: () -> Accessory = { EmptyView() }, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.destination = destination
        self.expanded = expanded
        self.accessory = accessory()
        self.content = content()
    }

    private var isCollapsed: Bool { expanded?.wrappedValue == false }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let expanded {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { expanded.wrappedValue.toggle() }
                } label: {
                    headerRow(chevron: true).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(expanded.wrappedValue ? "Hide \(title)" : "Show \(title)")
                .accessibilityLabel(title)
                .accessibilityValue(expanded.wrappedValue ? "Expanded" : "Collapsed")
            } else if let destination {
                HStack(spacing: 6) {
                    Button { store.section = destination } label: { header }
                        .buttonStyle(.plain)
                        .help("Show \(title) details")
                    trailing
                }
            } else {
                headerRow(chevron: false)
            }
            if !isCollapsed { content }
        }
        .layoutAudit(title, key: auditKey, content: true)
        .padding(.horizontal, 14)
        .padding(.vertical, isCollapsed ? 11 : 14)
        // A collapsed disclosure keeps its compact height instead of stretching to its neighbours.
        .frame(maxWidth: .infinity, maxHeight: isCollapsed ? nil : .infinity, alignment: .topLeading)
        .glassCard()
        .layoutAudit(title, key: auditKey)
    }

    private func headerRow(chevron: Bool) -> some View {
        HStack(spacing: 6) {
            header
            trailing
            if chevron, let expanded {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded.wrappedValue ? 90 : 0))
                    .frame(width: 14, height: 14)
            }
        }
    }

    @ViewBuilder private var trailing: some View {
        Spacer(minLength: 4)
        accessory
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(.tint)
            Text(title).font(.headline)
            if destination != nil {
                Image(systemName: "chevron.right").font(.caption2.bold()).foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Horizontal meter with btop-style colour grading.
struct MeterBar: View {
    var fraction: Double
    var color: Color?
    var height: CGFloat = 6
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(color ?? theme.meter(fraction))
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

/// Stacked horizontal bar (memory breakdown, volume usage).
struct StackedBar: View {
    struct Part: Identifiable {
        var id: String { label }
        var label: String
        var value: Double
        var color: Color
    }

    var parts: [Part]
    var total: Double
    var height: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(parts) { part in
                    Rectangle()
                        .fill(part.color.gradient)
                        .frame(width: total > 0 ? max(0, part.value / total * geo.size.width - 1) : 0)
                        .help("\(part.label): \(Fmt.bytes(part.value))")
                }
                Spacer(minLength: 0)
            }
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .frame(height: height)
    }
}

struct LegendItem: View {
    var color: Color
    var label: String
    var value: String
    var font: Font = .callout

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 8)
            Text(value).monospacedDigit().lineLimit(1).fixedSize()
        }
        .font(font)
    }
}

/// Label/value line for info grids.
struct StatRow: View {
    var label: String
    var value: String
    var color: Color?

    init(_ label: String, _ value: String, color: Color? = nil) {
        self.label = label
        self.value = value
        self.color = color
    }

    var body: some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.leading)
            Text(value).monospacedDigit().foregroundStyle(color ?? .primary).gridColumnAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}

/// Large number with caption.
struct BigStat: View {
    var title: String
    var value: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(color)
                .contentTransition(.numericText())
        }
    }
}

/// Lightweight Canvas graph for small multiples (per-core, sidebar, rows).
struct Sparkline: View {
    var values: [Double]
    var maxValue: Double = 1
    var color: Color
    var capacity: Int?
    var filled = true

    var body: some View {
        Canvas { context, size in
            let count = max(capacity ?? values.count, 2)
            guard values.count > 1 else { return }
            let step = size.width / CGFloat(count - 1)
            let offset = CGFloat(count - values.count) * step
            let top = max(maxValue, values.max() ?? 0, .leastNonzeroMagnitude)
            func point(_ i: Int) -> CGPoint {
                CGPoint(x: offset + CGFloat(i) * step,
                        y: size.height - CGFloat(values[i] / top) * (size.height - 1))
            }
            var line = Path()
            line.move(to: point(0))
            for i in 1..<values.count { line.addLine(to: point(i)) }
            if filled {
                var area = line
                area.addLine(to: CGPoint(x: point(values.count - 1).x, y: size.height))
                area.addLine(to: CGPoint(x: offset, y: size.height))
                area.closeSubpath()
                context.fill(area, with: .linearGradient(
                    Gradient(colors: [color.opacity(0.55), color.opacity(0.08)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            }
            context.stroke(line, with: .color(color), lineWidth: 1.2)
        }
    }
}

struct EmptyState: View {
    var title: String
    var symbol: String
    var message: String

    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message))
    }
}

/// Row of headline numbers on a glass strip at the top of each detail view.
struct StatStrip<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var auditKey = UUID()

    var body: some View {
        HStack(spacing: 28) {
            content
            Spacer(minLength: 0)
        }
        .layoutAudit("Stat strip", key: auditKey, content: true)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassCard(cornerRadius: 22)
        .layoutAudit("Stat strip", key: auditKey)
    }
}

/// Scrollable detail page with the ambient backdrop and grouped glass.
struct DetailPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            GlassGroup(spacing: 16) { content }
        }
        .background(AmbientBackground())
    }
}
