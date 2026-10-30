import SwiftUI
import SystemKit

struct ProcessTable: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.theme) private var theme
    @AppStorage(SettingsKey.treeView) private var tree = false
    @AppStorage(SettingsKey.useRegex) private var regex = false
    @AppStorage(SettingsKey.processScope) private var scope: ProcessScope = .all
    @AppStorage(SettingsKey.cpuPerCore) private var cpuPerCore = true
    @AppStorage("ProcessTable.sortColumn") private var sortColumn: String = ProcessColumn.cpu.rawValue
    @AppStorage("ProcessTable.sortAscending") private var sortAscending = false
    /// Rows are cached and rebuilt only when inputs change, not on every unrelated redraw.
    @State private var rows: [ProcessRow] = []
    @State private var cpuScale = 100.0

    private var sort: Binding<ProcessSort> {
        Binding {
            ProcessSort(column: ProcessColumn(rawValue: sortColumn) ?? .cpu, ascending: sortAscending)
        } set: {
            sortColumn = $0.column.rawValue
            sortAscending = $0.ascending
        }
    }

    var body: some View {
        @Bindable var store = store
        NativeProcessTable(rows: rows, tree: tree, cpuScale: cpuScale, theme: theme,
                           selection: $store.selection, sort: sort, store: store)
            .onChange(of: store.processGeneration, initial: true) { rebuild() }
            .onChange(of: sortColumn) { rebuild() }
            .onChange(of: sortAscending) { rebuild() }
            .onChange(of: store.filterText) { rebuild() }
            .onChange(of: store.collapsed) { rebuild() }
            .onChange(of: tree) { rebuild() }
            .onChange(of: regex) { rebuild() }
            .onChange(of: scope) { rebuild() }
            .onChange(of: cpuPerCore) { rebuild() }
            .overlay {
                if rows.isEmpty && !store.processes.isEmpty {
                    ContentUnavailableView.search(text: store.filterText)
                }
            }
    }

    private func rebuild() {
        rows = store.rows(scope: scope, sort: sort.wrappedValue.comparators, tree: tree, regex: regex)
        cpuScale = cpuPerCore ? 100 : 100 / Double(store.coreCount)
    }
}

/// Toolbar actions for the selected processes.
struct ProcessMenu: View {
    @Environment(SystemStore.self) private var store
    var pids: [pid_t]

    var body: some View {
        if pids.isEmpty {
            Text("No Selection")
        } else {
            Button("Get Info") { if let pid = pids.first { store.reveal(pid) } }
            Divider()
            Button("Quit (SIGTERM)") { store.requestQuit(pids) }
            Button("Force Quit (SIGKILL)") { store.requestForceQuit(pids) }
            Menu("Send Signal") {
                ForEach(ProcessControl.signals) { signal in
                    Button("\(signal.number)  \(signal.name) — \(signal.summary)") { store.request(signal, for: pids) }
                }
            }
            if pids.count == 1, let pid = pids.first {
                Menu("Priority (nice)") {
                    ForEach([-20, -10, -5, 0, 5, 10, 19], id: \.self) { value in
                        Button(value == 0 ? "0 (Normal)" : "\(value)") { store.renice(pid, to: value) }
                    }
                }
                if let entry = store.process(pid), !entry.path.isEmpty {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)])
                    }
                }
            }
        }
    }
}
