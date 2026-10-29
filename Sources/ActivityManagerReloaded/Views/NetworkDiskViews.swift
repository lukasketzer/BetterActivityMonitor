import SwiftUI
import SystemKit

// MARK: Network

struct NetworkPanel: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        Panel("Network", symbol: "network", destination: .network) {
            if let n = store.snapshot?.network {
                HStack(spacing: 8) {
                    Label(Fmt.rate(n.rateIn), systemImage: "arrow.down").foregroundStyle(theme.netIn)
                    Label(Fmt.rate(n.rateOut), systemImage: "arrow.up").foregroundStyle(theme.netOut)
                }
                .monospacedDigit()
            }
        } content: {
            VStack(alignment: .leading, spacing: 6) {
                HistoryChart(series: [
                    ChartSeries(name: "Download", color: theme.netIn, history: store.netIn),
                    ChartSeries(name: "Upload", color: theme.netOut, history: store.netOut, mirrored: true),
                ], maxY: nil) { Fmt.rate($0) }
                    .frame(minHeight: 80)
                if let n = store.snapshot?.network {
                    HStack {
                        Text("Total ↓ \(Fmt.bytes(n.totalIn))").foregroundStyle(theme.netIn)
                        Spacer()
                        Text("↑ \(Fmt.bytes(n.totalOut))").foregroundStyle(theme.netOut)
                    }
                    .font(.caption.monospacedDigit())
                }
            }
        }
    }
}

struct NetworkView: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.theme) private var theme
    @AppStorage("network.interface") private var selected = ""
    @AppStorage("network.showInactive") private var showInactive = false

    var body: some View {
        DetailPage {
            if let n = store.snapshot?.network {
                let interfaces = n.interfaces.filter { showInactive || ($0.isUp && $0.bytesIn + $0.bytesOut > 0) }
                VStack(alignment: .leading, spacing: 16) {
                    StatStrip {
                        BigStat(title: "Download", value: Fmt.rate(n.rateIn), color: theme.netIn)
                        BigStat(title: "Upload", value: Fmt.rate(n.rateOut), color: theme.netOut)
                        BigStat(title: "Received", value: Fmt.bytes(n.totalIn))
                        BigStat(title: "Sent", value: Fmt.bytes(n.totalOut))
                        Spacer()
                    }

                    Panel(selectedTitle(n), symbol: "chart.xyaxis.line") {
                        Picker("Interface", selection: $selected) {
                            Text("All interfaces").tag("")
                            ForEach(interfaces) { Text("\($0.displayName) (\($0.name))").tag($0.name) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    } content: {
                        HistoryChart(series: [
                            ChartSeries(name: "Download", color: theme.netIn,
                                        history: selected.isEmpty ? store.netIn : store.interfaceIn[selected] ?? History(capacity: 1)),
                            ChartSeries(name: "Upload", color: theme.netOut,
                                        history: selected.isEmpty ? store.netOut : store.interfaceOut[selected] ?? History(capacity: 1),
                                        mirrored: true),
                        ], maxY: nil) { Fmt.rate($0) }
                            .frame(height: 200)
                    }

                    Panel("Interfaces", symbol: "point.3.connected.trianglepath.dotted") {
                        Toggle("Show inactive", isOn: $showInactive).toggleStyle(.checkbox)
                    } content: {
                        VStack(spacing: 8) {
                            ForEach(interfaces) { iface in
                                InterfaceRow(iface: iface, isSelected: iface.name == selected) {
                                    selected = selected == iface.name ? "" : iface.name
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }

    private func selectedTitle(_ n: NetworkStats) -> String {
        guard let iface = n.interfaces.first(where: { $0.name == selected }) else { return "Throughput" }
        return "Throughput — \(iface.displayName)"
    }
}

private struct InterfaceRow: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.theme) private var theme
    var iface: NetworkInterface
    var isSelected: Bool
    var select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .frame(width: 22)
                    .foregroundStyle(iface.isUp ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(iface.displayName)  ").font(.callout.weight(.medium)) + Text(iface.name).font(.caption).foregroundStyle(.secondary)
                    Text(iface.addresses.prefix(2).joined(separator: "  ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(minWidth: 220, alignment: .leading)
                Sparkline(values: store.interfaceIn[iface.name]?.values ?? [], maxValue: 1, color: theme.netIn,
                          capacity: Defaults.historyLength)
                    .frame(height: 22)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("↓ \(Fmt.rate(iface.rateIn))").foregroundStyle(theme.netIn)
                    Text("↑ \(Fmt.rate(iface.rateOut))").foregroundStyle(theme.netOut)
                }
                .font(.caption.monospacedDigit())
                .frame(width: 100, alignment: .trailing)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Fmt.bytes(iface.bytesIn)) in")
                    Text("\(Fmt.bytes(iface.bytesOut)) out")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Packets: \(iface.packetsIn) in / \(iface.packetsOut) out · Errors: \(iface.errorsIn) / \(iface.errorsOut). Click to graph this interface.")
    }

    private var symbol: String {
        if iface.isLoopback { return "arrow.triangle.2.circlepath" }
        let name = iface.displayName.lowercased()
        if name.contains("wi-fi") { return "wifi" }
        if name.contains("ethernet") || name.contains("thunderbolt") { return "cable.connector" }
        if iface.name.hasPrefix("utun") || iface.name.hasPrefix("ipsec") { return "lock.shield" }
        if name.contains("bluetooth") { return "dot.radiowaves.left.and.right" }
        return "network"
    }
}

// MARK: Disks

struct DisksPanel: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        Panel("Disks", symbol: "internaldrive", destination: .disks) {
            if let d = store.snapshot?.disks {
                HStack(spacing: 8) {
                    Text("R \(Fmt.rate(d.readRate))").foregroundStyle(theme.diskRead)
                    Text("W \(Fmt.rate(d.writeRate))").foregroundStyle(theme.diskWrite)
                }
                .monospacedDigit()
            }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                if let d = store.snapshot?.disks {
                    ForEach(d.volumes.prefix(3)) { volume in VolumeLine(volume: volume, compact: true) }
                }
                HistoryChart(series: [
                    ChartSeries(name: "Read", color: theme.diskRead, history: store.diskRead),
                    ChartSeries(name: "Write", color: theme.diskWrite, history: store.diskWrite, mirrored: true),
                ], maxY: nil, showsYAxis: false) { Fmt.rate($0) }
                    .frame(minHeight: 50)
            }
        }
    }
}

struct VolumeLine: View {
    @Environment(\.theme) private var theme
    var volume: Volume
    var compact = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(URL(fileURLWithPath: volume.path))
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Image(systemName: volume.isRemovable ? "externaldrive" : "internaldrive").foregroundStyle(.secondary)
                    Text(volume.name).lineLimit(1)
                    if !compact { Text(volume.format).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Text("\(Fmt.bytes(volume.used)) / \(Fmt.bytes(volume.total))")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                .font(compact ? .caption : .callout)
                MeterBar(fraction: volume.usedFraction, height: compact ? 5 : 8)
                if !compact {
                    Text("\(Fmt.bytes(volume.available)) available · \(Fmt.percent(volume.usedFraction, digits: 0)) used · \(volume.path)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(volume.path) in Finder")
    }
}

struct DisksView: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        DetailPage {
            if let d = store.snapshot?.disks {
                VStack(alignment: .leading, spacing: 16) {
                    StatStrip {
                        BigStat(title: "Read", value: Fmt.rate(d.readRate), color: theme.diskRead)
                        BigStat(title: "Write", value: Fmt.rate(d.writeRate), color: theme.diskWrite)
                        BigStat(title: "Data read", value: Fmt.bytes(d.totalRead))
                        BigStat(title: "Data written", value: Fmt.bytes(d.totalWritten))
                        Spacer()
                    }

                    Panel("Disk Activity", symbol: "chart.xyaxis.line") {
                        HistoryChart(series: [
                            ChartSeries(name: "Read", color: theme.diskRead, history: store.diskRead),
                            ChartSeries(name: "Write", color: theme.diskWrite, history: store.diskWrite, mirrored: true),
                        ], maxY: nil) { Fmt.rate($0) }
                            .frame(height: 200)
                    }

                    Panel("Volumes", symbol: "externaldrive.connected.to.line.below") {
                        VStack(spacing: 12) {
                            ForEach(d.volumes) { VolumeLine(volume: $0) }
                        }
                    }

                    HStack(alignment: .top, spacing: 16) {
                        Panel("Devices", symbol: "internaldrive") {
                            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                                GridRow {
                                    Text("Device"); Text("Read/s"); Text("Write/s"); Text("IOPS r/w")
                                }
                                .font(.caption).foregroundStyle(.secondary)
                                ForEach(d.devices) { dev in
                                    GridRow {
                                        Text(dev.bsdName)
                                        Text(Fmt.rate(dev.readRate)).foregroundStyle(theme.diskRead)
                                        Text(Fmt.rate(dev.writeRate)).foregroundStyle(theme.diskWrite)
                                        Text("\(Fmt.compact(dev.readsPerSecond)) / \(Fmt.compact(dev.writesPerSecond))")
                                    }
                                    .font(.callout.monospacedDigit())
                                }
                            }
                        }
                        Panel("Top Disk Activity", symbol: "arrow.up.arrow.down") {
                            TopProcessList(entries: store.top(by: \.diskTotalRate, count: 8)) {
                                "\(Fmt.rate($0.diskReadRate)) / \(Fmt.rate($0.diskWriteRate))"
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
            }
        }
    }
}

extension ProcessEntry {
    var diskTotalRate: Double { diskReadRate + diskWriteRate }
}
