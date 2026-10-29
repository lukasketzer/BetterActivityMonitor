import SwiftUI

/// btop-style dashboard: resource boxes on top, the live process table below. The split is draggable.
struct OverviewView: View {
    @Environment(SystemStore.self) private var store
    @AppStorage(SettingsKey.overviewCPU) private var showCPU = true
    @AppStorage(SettingsKey.overviewGPU) private var showGPU = true
    @AppStorage(SettingsKey.overviewMemory) private var showMemory = true
    @AppStorage(SettingsKey.overviewNetwork) private var showNetwork = true
    @AppStorage(SettingsKey.overviewDisks) private var showDisks = true
    @AppStorage(SettingsKey.overviewSensors) private var showSensors = true
    @AppStorage(SettingsKey.overviewProcesses) private var showProcesses = true

    private enum Box: Hashable { case gpu, memory, network, disks, sensors }

    var body: some View {
        @Bindable var store = store
        let lower = [(showMemory, Box.memory), (showNetwork, .network), (showDisks, .disks), (showSensors, .sensors)]
            .filter(\.0).map(\.1)
        let hasTop = showCPU || (showGPU && store.snapshot?.gpu != nil)
        VSplitView {
            if hasTop || !lower.isEmpty {
                GeometryReader { geo in
                    // Boxes stretch to fill the pane; when it is too short for their natural height,
                    // they scroll instead of overflowing into each other (see DashboardLayout).
                    ScrollView { boxes(grid: lower, size: geo.size) }
                }
                .frame(minHeight: 200, idealHeight: 440)
                .background(AmbientBackground())
            }
            if showProcesses {
                ProcessTable()
                    .frame(minHeight: 160)
            }
        }
        .searchable(text: $store.filterText, placement: .toolbar, prompt: "Filter processes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Toggle("CPU", isOn: $showCPU)
                    Toggle("GPU", isOn: $showGPU)
                    Toggle("Memory", isOn: $showMemory)
                    Toggle("Network", isOn: $showNetwork)
                    Toggle("Disks", isOn: $showDisks)
                    Toggle("Sensors", isOn: $showSensors)
                    Toggle("Processes", isOn: $showProcesses)
                } label: {
                    Label("Boxes", systemImage: "rectangle.3.group")
                }
                .help("Choose which boxes the overview shows")
            }
            ProcessToolbar()
        }
        .inspector(isPresented: $store.showInspector) {
            ProcessInspector().inspectorColumnWidth(min: 300, ideal: 340, max: 520)
        }
    }

    private func boxes(grid: [Box], size: CGSize) -> some View {
        let width = size.width
        // The CPU box needs ~480 pt; next to it the GPU box needs another ~250. Narrower than that,
        // the GPU box joins the grid below instead of being squeezed out of the window.
        let hasGPU = showGPU && store.snapshot?.gpu != nil
        let gpuOnTop = hasGPU && (!showCPU || width >= 820)
        let lower = hasGPU && !gpuOnTop ? [.gpu] + grid : grid
        // Four boxes side by side get too narrow for their legends below ~1000 pt; wrap into two columns.
        let columns = width >= 1000 || lower.count <= 2 ? max(lower.count, 1) : 2
        let top = showCPU || gpuOnTop ? 1 : 0
        return GlassGroup(spacing: 12) {
            DashboardLayout(viewportHeight: size.height) {
                if showCPU { CPUPanel().dashboardRow(0) }
                if gpuOnTop { GPUPanel().dashboardRow(0, fixedWidth: showCPU ? 340 : nil) }
                ForEach(Array(lower.enumerated()), id: \.element) { index, box in
                    card(box).dashboardRow(top + index / columns)
                }
            }
        }
    }

    @ViewBuilder
    private func card(_ box: Box) -> some View {
        switch box {
        case .gpu: GPUPanel()
        case .memory: MemoryPanel()
        case .network: NetworkPanel()
        case .disks: DisksPanel()
        case .sensors: SensorsPanel()
        }
    }
}
