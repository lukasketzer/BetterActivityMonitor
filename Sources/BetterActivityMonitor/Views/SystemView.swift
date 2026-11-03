import AppKit
import SwiftUI
import SystemKit

/// "About This Mac"-style summary of the machine, followed by its temperature history and fans.
struct SystemView: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.theme) private var theme
    @AppStorage(SettingsKey.fahrenheit) private var fahrenheit = false

    var body: some View {
        DetailPage {
            if let s = store.snapshot {
                let hardware = hardwareRows(s)
                let software = softwareRows(s)
                VStack(alignment: .leading, spacing: 16) {
                    MachineHeader(name: MachineInfo.current.host, os: MachineInfo.current.os,
                                  subtitle: MachineInfo.current.productName,
                                  symbol: s.battery != nil ? "laptopcomputer" : "desktopcomputer",
                                  thermal: ProcessInfo.processInfo.thermalState,
                                  lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled) {
                        copySummary(hardware: hardware, software: software)
                    }
                    HStack(alignment: .top, spacing: 16) {
                        InfoGroup(title: "Hardware", rows: hardware)
                        InfoGroup(title: "Software", rows: software)
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    if store.cpuTemperature.points.count > 1 {
                        Panel("CPU Temperature", symbol: "thermometer.medium") {
                            HistoryChart(series: [ChartSeries(name: "Hottest CPU die", color: theme.temperature, history: store.cpuTemperature)],
                                         maxY: nil) { Fmt.temperature($0, fahrenheit: fahrenheit) }
                                .frame(height: 140)
                        }
                    }

                    if !s.fans.isEmpty {
                        Panel("Fans", symbol: "fan") {
                            HStack(spacing: 28) {
                                ForEach(Array(s.fans.enumerated()), id: \.offset) { index, rpm in
                                    BigStat(title: "Fan \(index + 1)", value: "\(Int(rpm)) rpm")
                                }
                                Spacer()
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }

    private func hardwareRows(_ s: SystemSnapshot) -> [InfoRow] {
        let info = MachineInfo.current
        var rows: [InfoRow] = [
            .init("Model", info.productName ?? info.model),
            .init("Model identifier", info.model),
            .init("Chip", s.cpu.model),
            .init("Cores", coreDescription(s.cpu)),
        ]
        if let g = s.gpu {
            rows.append(.init("Graphics", g.coreCount.map { "\(g.name) (\($0) cores)" } ?? g.name))
        }
        rows.append(.init("Memory", Fmt.bytes(s.memory.total)))
        if let volume = s.disks.startupVolume {
            rows.append(.init("Startup disk", "\(volume.name) · \(Fmt.bytes(volume.used)) of \(Fmt.bytes(volume.total)) used"))
        }
        for (index, display) in info.displays.enumerated() {
            rows.append(.init(info.displays.count > 1 ? "Display \(index + 1)" : "Display", display))
        }
        if let b = s.battery {
            rows.append(.init("Battery", Fmt.percent(b.charge, digits: 0) + (b.isCharging ? ", charging" : "")))
        }
        if let t = store.cpuTemperatureNow {
            rows.append(.init("CPU temperature", Fmt.temperature(t, fahrenheit: fahrenheit), color: temperatureColor(t, theme)))
        }
        if !s.fans.isEmpty {
            rows.append(.init("Fans", s.fans.map { "\(Int($0)) rpm" }.joined(separator: ", ")))
        }
        return rows
    }

    private func softwareRows(_ s: SystemSnapshot) -> [InfoRow] {
        let info = MachineInfo.current
        var rows: [InfoRow] = [
            .init("macOS", info.os),
            .init("Kernel", info.kernel),
            .init("User", info.user),
            .init("Shell", info.shell),
            .init("Uptime", Fmt.duration(s.cpu.uptime)),
        ]
        if let boot = MachineInfo.bootTime { rows.append(.init("Booted", Self.when(boot))) }
        if let wake = MachineInfo.lastWake { rows.append(.init("Last wake", Self.when(wake))) }
        rows += [
            .init("Load average", s.cpu.loadAverage.map { Fmt.number($0, digits: 2) }.joined(separator: "  ")),
            .init("Processes", "\(s.cpu.processCount) (\(s.cpu.threadCount) threads)"),
        ]
        if let ip = localAddress(s) { rows.append(.init("IP address", ip)) }
        let thermal = ProcessInfo.processInfo.thermalState
        rows.append(.init("Thermal state", thermal.label, color: thermal.color(theme)))
        rows.append(.init("Low Power Mode", ProcessInfo.processInfo.isLowPowerModeEnabled ? "On" : "Off"))
        return rows
    }

    /// "Today 09:14", "Yesterday 22:01" or "Mon 3 Nov, 09:14".
    private static func when(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today \(time)" }
        if calendar.isDateInYesterday(date) { return "Yesterday \(time)" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + ", " + time
    }

    private func copySummary(hardware: [InfoRow], software: [InfoRow]) {
        let info = MachineInfo.current
        func block(_ title: String, _ rows: [InfoRow]) -> String {
            ([title] + rows.map { "  \($0.key): \($0.value)" }).joined(separator: "\n")
        }
        let text = [info.host + " — " + info.os, block("Hardware", hardware), block("Software", software)]
            .joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func coreDescription(_ cpu: CPUStats) -> String {
        cpu.performanceCores > 0 ? "\(cpu.performanceCores) performance + \(cpu.efficiencyCores) efficiency" : "\(cpu.physicalCores) physical, \(cpu.logicalCores) logical"
    }

    private func localAddress(_ s: SystemSnapshot) -> String? {
        for interface in s.network.interfaces where interface.isUp && !interface.isLoopback {
            if let ipv4 = interface.addresses.first(where: { $0.contains(".") && !$0.contains(":") }) {
                return "\(ipv4) (\(interface.displayName))"
            }
        }
        return nil
    }
}

struct InfoRow: Identifiable {
    var id: String { key }
    var key: String
    var value: String
    var color: Color?

    init(_ key: String, _ value: String, color: Color? = nil) {
        self.key = key
        self.value = value
        self.color = color
    }
}

extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious (throttling)"
        case .critical: "Critical (throttling)"
        @unknown default: "Unknown"
        }
    }

    func color(_ theme: Theme) -> Color? {
        switch self {
        case .nominal: nil
        case .fair: theme.mid
        default: theme.high
        }
    }
}

/// Big Mac symbol with its name and macOS version, like the top of About This Mac.
struct MachineHeader: View {
    @Environment(\.theme) private var theme
    var name: String
    var os: String
    var subtitle: String?
    var symbol: String
    var thermal: ProcessInfo.ThermalState
    var lowPower: Bool
    var copy: () -> Void
    @State private var copied = false

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: symbol)
                .font(.system(size: 54, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.accent)
                .frame(width: 84)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.largeTitle.weight(.semibold))
                Text(os).font(.title3).foregroundStyle(.secondary)
                if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 6) {
                    if lowPower { badge("Low Power", symbol: "leaf.fill", color: theme.mid) }
                    badge(thermal == .nominal ? "Thermals OK" : "Thermals " + thermal.label,
                          symbol: "thermometer.medium", color: thermal.color(theme) ?? theme.low)
                }
                Button {
                    copy()
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy System Info", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .controlSize(.small)
                .help("Copy the hardware and software details as plain text")
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 22)
    }

    private func badge(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }
}

/// Titled card of label / value lines separated by hairlines, like a System Settings group.
struct InfoGroup: View {
    var title: String
    var rows: [InfoRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.headline).padding(.bottom, 8)
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider() }
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(row.key).foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Text(row.value)
                        .foregroundStyle(row.color ?? .primary)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
                .font(.callout)
                .padding(.vertical, 7)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard()
    }
}
