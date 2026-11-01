import SwiftUI
import SystemKit

struct ContentView: View {
    @Environment(SystemStore.self) private var store
    @AppStorage(SettingsKey.theme) private var themeID = Theme.system.id

    var body: some View {
        @Bindable var store = store
        let theme = Theme.named(themeID)

        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        } detail: {
            detail
                .modifier(FreezeDuringLiveResize())
                .navigationTitle(store.section?.title ?? "BetterActivityMonitor")
                .toolbar {
                    ToolbarItem(placement: .navigation) { RefreshIntervalControl() }
                }
        }
        // Showing the sidebar pushes the detail aside instead of floating over it.
        .navigationSplitViewStyle(.balanced)
        .environment(\.theme, theme)
        .tint(theme.accent)
        .preferredColorScheme(theme.prefersDark ? .dark : nil)
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { store.pendingSignal != nil },
                                                             set: { if !$0 { store.pendingSignal = nil } }),
                            presenting: store.pendingSignal) { pending in
            Button(pending.signal.number == SIGKILL ? "Force Quit" : "Send \(pending.signal.name)",
                   role: pending.signal.number == SIGKILL ? .destructive : nil) {
                store.perform(pending)
            }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(pending.signal.number == SIGKILL
                 ? "Unsaved changes will be lost. \(pending.names.joined(separator: ", "))"
                 : "\(pending.signal.summary) → \(pending.names.joined(separator: ", "))")
        }
        .alert("Couldn't Signal Process", isPresented: Binding(get: { store.controlError != nil },
                                                              set: { if !$0 { store.controlError = nil } }),
               presenting: store.controlError) { error in
            if let retry = error.retry {
                Button("Retry as Administrator…") { store.perform(retry, asAdmin: true) }
            }
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
    }

    private var confirmTitle: String {
        guard let pending = store.pendingSignal else { return "" }
        let target = pending.names.count == 1 ? "“\(pending.names[0])”" : "\(pending.names.count) processes"
        switch pending.signal.number {
        case SIGKILL: return "Force quit \(target)?"
        case SIGTERM: return "Quit \(target)?"
        default: return "Send \(pending.signal.name) to \(target)?"
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch store.section ?? .overview {
        case .overview: OverviewView()
        case .processes: ProcessesView()
        case .cpu: CPUView()
        case .memory: MemoryView()
        case .disks: DisksView()
        case .network: NetworkView()
        case .sensors: SensorsView()
        case .battery: BatteryView()
        case .energy: EnergyView()
        }
    }
}

/// Keeps the detail content at its pre-resize size (pinned top-left) while the window is being
/// resized, then lays it out once at the final size. SwiftUI otherwise recomputes the whole page on every
/// drag frame (~34 ms on the Overview, twice the 60 fps budget); with an unchanged size it has nothing to redo.
private struct FreezeDuringLiveResize: ViewModifier {
    @Environment(SystemStore.self) private var store
    @AppStorage(SettingsKey.freezeDuringResize) private var enabled = true
    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        let resizing = store.isLiveResizing || store.simulatedLiveResize
        let frozen = enabled && resizing && size != .zero
        content
            .frame(width: frozen ? size.width : nil, height: frozen ? size.height : nil)
            // min 0: the wrapper always takes the window's size, so frozen content larger than the window
            // runs off the bottom/right edge instead of growing the wrapper and getting centred. No .clipped():
            // it pushed the page out of the safe area, under the sidebar and toolbar.
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { newSize in
                // A start notification without a matching end (e.g. the system constraining the window)
                // must not leave the page frozen: only a resize actually in progress counts.
                if store.isLiveResizing, !NSApp.windows.contains(where: \.inLiveResize) { store.isLiveResizing = false }
                if !(store.isLiveResizing || store.simulatedLiveResize) { size = newSize }
            }
    }
}

/// Sidebar with live mini-graphs next to each section.
private struct Sidebar: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var store = store
        List(selection: $store.section) {
            Section("Monitor") {
                row(.overview, value: nil)
                row(.processes, value: store.snapshot.map { "\($0.cpu.processCount)" })
            }
            Section("Resources") {
                row(.cpu, value: store.snapshot.map { Fmt.percent($0.cpu.total, digits: 0) },
                    graph: store.cpuTotal.values, max: 1, color: theme.cpu)
                row(.memory, value: store.snapshot.map { Fmt.percent($0.memory.usedFraction, digits: 0) },
                    graph: store.memUsed.values, max: 1, color: theme.memApp)
                row(.disks, value: store.snapshot.map { Fmt.rate($0.disks.readRate + $0.disks.writeRate) },
                    graph: zip(store.diskRead.values, store.diskWrite.values).map(+), max: 1, color: theme.diskRead)
                row(.network, value: store.snapshot.map { Fmt.rate($0.network.rateIn + $0.network.rateOut) },
                    graph: zip(store.netIn.values, store.netOut.values).map(+), max: 1, color: theme.netIn)
                row(.sensors, value: store.snapshot?.gpu.map { Fmt.percent($0.utilization, digits: 0) },
                    graph: store.gpu.values, max: 1, color: theme.gpu)
                if store.snapshot?.battery != nil {
                    row(.battery, value: store.snapshot?.battery.map { Fmt.percent($0.charge, digits: 0) })
                }
                row(.energy, value: store.systemPower.map(Fmt.watts),
                    graph: store.processPower.values, max: 1, color: theme.mid)
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ section: AppSection, value: String?, graph: [Double]? = nil, max: Double = 1, color: Color = .accentColor) -> some View {
        HStack(spacing: 6) {
            Label(section.title, systemImage: section.symbol)
            Spacer(minLength: 4)
            if let graph, graph.count > 1 {
                Sparkline(values: Array(graph.suffix(30)), maxValue: max, color: color, capacity: 30)
                    .frame(width: 36, height: 14)
            }
            if let value {
                Text(value).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .tag(section)
    }
}
