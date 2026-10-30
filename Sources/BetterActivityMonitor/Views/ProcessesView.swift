import SwiftUI
import SystemKit

struct ProcessesView: View {
    @Environment(SystemStore.self) private var store
    @AppStorage(SettingsKey.treeView) private var tree = false
    @AppStorage(SettingsKey.processScope) private var scope: ProcessScope = .all

    var body: some View {
        @Bindable var store = store
        ProcessTable()
            .searchable(text: $store.filterText, placement: .toolbar, prompt: "Name, PID, user or path")
            .inspector(isPresented: $store.showInspector) {
                ProcessInspector()
                    .inspectorColumnWidth(min: 300, ideal: 340, max: 520)
            }
            .toolbar { ProcessToolbar() }
            .safeAreaInset(edge: .bottom, spacing: 0) { ProcessFooter() }
            .navigationSubtitle("\(store.processes.count) processes")
    }
}

struct ProcessToolbar: ToolbarContent {
    @Environment(SystemStore.self) private var store
    @AppStorage(SettingsKey.treeView) private var tree = false
    @AppStorage(SettingsKey.processScope) private var scope: ProcessScope = .all

    var body: some ToolbarContent {
        @Bindable var store = store
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                store.requestQuit(store.selection)
            } label: {
                Label("Quit Process", systemImage: "xmark.octagon")
            }
            .help("Quit the selected processes (SIGTERM). Right-click a row for more signals.")
            .disabled(store.selection.isEmpty)

            Menu {
                ProcessMenu(pids: Array(store.selection))
            } label: {
                Label("Actions", systemImage: "ellipsis.circle")
            }
            .disabled(store.selection.isEmpty)

            Picker("Show", selection: $scope) {
                ForEach(ProcessScope.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
            .help("Filter which processes are shown")

            Toggle(isOn: $tree) { Label("Tree", systemImage: "list.bullet.indent") }
                .help("Show processes as a parent/child tree (⌘T)")

            Toggle(isOn: $store.paused) { Label("Pause", systemImage: store.paused ? "play.fill" : "pause.fill") }
                .help("Freeze the process list so rows stop moving (graphs keep updating)")

            Toggle(isOn: $store.showInspector) { Label("Inspector", systemImage: "sidebar.trailing") }
                .help("Show details for the selected process (⌘I)")
        }
    }
}

private struct ProcessFooter: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        if let s = store.snapshot {
            HStack(spacing: 18) {
                footerItem("CPU", Fmt.percent(s.cpu.total), color: theme.meter(s.cpu.total))
                footerItem("Memory", "\(Fmt.bytes(s.memory.used)) / \(Fmt.bytes(s.memory.total))", color: theme.meter(s.memory.usedFraction))
                footerItem("Threads", "\(s.cpu.threadCount)")
                footerItem("Processes", "\(s.cpu.processCount)")
                if !store.selection.isEmpty { footerItem("Selected", "\(store.selection.count)") }
                Spacer()
                if store.paused {
                    Label("Paused", systemImage: "pause.circle.fill").foregroundStyle(.orange)
                }
                let hidden = store.processes.filter { !$0.hasTaskInfo }.count
                if hidden > 0 {
                    Label("\(hidden) restricted", systemImage: "lock")
                        .foregroundStyle(.secondary)
                        .help("macOS doesn't expose CPU/memory of other users' processes to unprivileged apps.")
                }
            }
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .glassCard(cornerRadius: 20)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }

    private func footerItem(_ label: String, _ value: String, color: Color = .primary) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit().foregroundStyle(color)
        }
    }
}
