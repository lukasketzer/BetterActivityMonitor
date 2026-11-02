import SwiftUI
import SystemKit

/// At-a-glance page: a row of activity rings and the network and disk throughput. Everything else lives on the detail pages each element links to.
struct OverviewView: View {
    @AppStorage(SettingsKey.overviewCPU) private var showCPU = true
    @AppStorage(SettingsKey.overviewGPU) private var showGPU = true
    @AppStorage(SettingsKey.overviewMemory) private var showMemory = true
    @AppStorage(SettingsKey.overviewStorage) private var showStorage = true
    @AppStorage(SettingsKey.overviewBattery) private var showBattery = true
    @AppStorage(SettingsKey.overviewNetwork) private var showNetwork = true
    @AppStorage(SettingsKey.overviewDisks) private var showDisks = true

    var body: some View {
        DetailPage {
            VStack(alignment: .leading, spacing: 28) {
                OverviewRings(showCPU: showCPU, showGPU: showGPU, showMemory: showMemory,
                              showStorage: showStorage, showBattery: showBattery)
                if showNetwork || showDisks {
                    HStack(alignment: .top, spacing: 16) {
                        if showNetwork { NetworkPanel() }
                        if showDisks { DisksPanel() }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Toggle("CPU", isOn: $showCPU)
                    Toggle("GPU", isOn: $showGPU)
                    Toggle("Memory", isOn: $showMemory)
                    Toggle("Storage", isOn: $showStorage)
                    Toggle("Battery", isOn: $showBattery)
                    Divider()
                    Toggle("Network", isOn: $showNetwork)
                    Toggle("Disks", isOn: $showDisks)
                } label: {
                    Label("Show", systemImage: "rectangle.3.group")
                }
                .help("Choose what the overview shows")
            }
        }
    }
}

/// Activity rings for CPU, GPU, memory, startup-disk storage and battery, each linking to its detail page.
private struct OverviewRings: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.theme) private var theme
    var showCPU: Bool
    var showGPU: Bool
    var showMemory: Bool
    var showStorage: Bool
    var showBattery: Bool

    var body: some View {
        if let s = store.snapshot {
            let rings = rings(s)
            if !rings.isEmpty {
                HStack(spacing: 12) {
                    ForEach(rings, id: \.title) { ring in
                        Button { store.section = ring.destination } label: { ActivityRing(ring: ring) }
                            .buttonStyle(RingButtonStyle())
                            .help("Show \(ring.title) details")
                    }
                }
                .padding(.vertical, 22)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .glassCard(cornerRadius: 24)
            }
        }
    }

    private func rings(_ s: SystemSnapshot) -> [ActivityRing.Model] {
        var rings: [ActivityRing.Model] = []
        if showCPU {
            rings.append(.init(title: "CPU", value: Fmt.percent(s.cpu.total, digits: 0), fraction: s.cpu.total,
                               caption: "\(s.cpu.logicalCores) cores", color: theme.cpu, destination: .cpu))
        }
        if showGPU, let g = s.gpu {
            rings.append(.init(title: "GPU", value: Fmt.percent(g.utilization, digits: 0), fraction: g.utilization,
                               caption: g.coreCount.map { "\($0) cores" } ?? "Graphics", color: theme.gpu, destination: .gpu))
        }
        if showMemory {
            rings.append(.init(title: "Memory", value: Fmt.bytes(s.memory.used), fraction: s.memory.usedFraction,
                               caption: "of \(Fmt.bytes(s.memory.total))", color: theme.memApp, destination: .memory))
        }
        if showStorage, let v = s.disks.startupVolume {
            rings.append(.init(title: "Storage", value: Fmt.bytes(v.used), fraction: v.usedFraction,
                               caption: "of \(Fmt.bytes(v.total))", color: theme.diskRead, destination: .disks))
        }
        if showBattery, let b = s.battery {
            // Like the system Batteries widget: a bolt while on power, and the ring warms up as the charge runs low.
            let color = b.charge <= 0.1 ? theme.high : b.charge <= 0.2 ? theme.mid : theme.low
            let caption = b.isCharged || b.isCharging || b.isPluggedIn || b.minutesRemaining == nil
                ? batteryStatus(b) : "\(Fmt.minutes(b.minutesRemaining!)) left"
            rings.append(.init(title: "Battery", value: Fmt.percent(b.charge, digits: 0), fraction: b.charge,
                               caption: caption, color: color, destination: .energy,
                               symbol: b.isPluggedIn || b.isCharging ? "bolt.fill" : nil))
        }
        return rings
    }
}

private struct ActivityRing: View {
    struct Model {
        var title: String
        var value: String
        var fraction: Double
        var caption: String
        var color: Color
        var destination: AppSection
        /// Small glyph above the value, e.g. a bolt while the battery charges.
        var symbol: String? = nil
    }

    var ring: Model
    private let lineWidth: CGFloat = 12

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().stroke(ring.color.opacity(0.16), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: min(max(ring.fraction, 0.004), 1))
                    .stroke(ring.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.6), value: ring.fraction)
                VStack(spacing: 1) {
                    if let symbol = ring.symbol {
                        Image(systemName: symbol).font(.caption.weight(.bold)).foregroundStyle(ring.color)
                    }
                    Text(ring.value)
                        .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding(.horizontal, lineWidth + 6)
            }
            // Full size when there's room; five rings in a narrow window shrink instead of spilling out.
            .aspectRatio(1, contentMode: .fit)
            .frame(minWidth: 84, maxWidth: 118)
            VStack(spacing: 1) {
                Text(ring.title).font(.headline)
                Text(ring.caption).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ring.title) \(ring.value), \(ring.caption)")
    }
}

private struct RingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { HoverBody(configuration: configuration) }

    private struct HoverBody: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.08 : hovering ? 0.04 : 0)))
                .onHover { hovering = $0 }
        }
    }
}
