import SwiftUI
import SystemKit
import WidgetKit

/// A fresh reading plus the metrics the widget was configured to show.
struct MetricsEntry: TimelineEntry {
    var system: SystemEntry
    var metrics: [WidgetMetric]
    var date: Date { system.date }
}

func metricsEntry(metrics: [WidgetMetric], context: TimelineProviderContext) -> MetricsEntry {
    MetricsEntry(system: context.isPreview ? .placeholder : .sample(), metrics: metrics)
}

// MARK: Metric presentation

extension WidgetMetric {
    var tint: Color {
        switch self {
        case .cpu: WidgetColor.cpu
        case .gpu: WidgetColor.gpu
        case .memory: WidgetColor.memory
        case .disk: WidgetColor.disk
        case .battery: WidgetColor.battery
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "cube.transparent"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .battery: "battery.75percent"
        }
    }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .disk: "Disk"
        case .battery: "Battery"
        }
    }

    /// The app section a tap opens.
    var section: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "gpu"
        case .memory: "memory"
        case .disk: "disks"
        case .battery: "energy"
        }
    }

    func current(in e: SystemEntry) -> Double? {
        switch self {
        case .cpu: e.cpu
        case .gpu: e.gpu
        case .memory: e.memFraction
        case .disk: e.mainVolume?.usedFraction
        case .battery: e.battery?.charge
        }
    }
}

/// Health-style value: big rounded number with a small unit beside it.
struct ValueWithUnit: View {
    var number: String
    var unit: String
    var size: CGFloat

    /// Memory reads as GB in use; everything else as a percentage.
    init(metric: WidgetMetric, entry: SystemEntry, size: CGFloat) {
        self.size = size
        guard let fraction = metric.current(in: entry) else { number = "—"; unit = ""; return }
        if metric == .memory {
            number = WidgetFmt.gigabytes(entry.memUsed); unit = "GB"
        } else {
            number = String(format: "%.0f", fraction * 100); unit = "%"
        }
    }

    init(number: String, unit: String, size: CGFloat) {
        self.number = number; self.unit = unit; self.size = size
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(number)
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(unit)
                .font(.system(size: size * 0.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}
