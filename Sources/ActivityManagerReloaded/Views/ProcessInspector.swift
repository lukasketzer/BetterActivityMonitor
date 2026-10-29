import SwiftUI
import SystemKit

struct ProcessInspector: View {
    @Environment(SystemStore.self) private var store

    var body: some View {
        if store.selection.count == 1, let pid = store.selection.first, let entry = store.process(pid) {
            InspectorContent(entry: entry)
                .id(pid)
        } else if store.selection.count > 1 {
            EmptyState(title: "\(store.selection.count) Processes", symbol: "square.stack.3d.up",
                       message: "Select a single process to see its details.")
        } else {
            EmptyState(title: "No Process Selected", symbol: "cursorarrow.click",
                       message: "Select a process to inspect it. Double-click a row to open this panel.")
        }
    }
}

private struct InspectorContent: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.theme) private var theme
    var entry: ProcessEntry
    @State private var details: ProcessDetails?
    @State private var showEnvironment = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                graphs
                actions
                infoGrid
                pathsSection
                if let details, !details.ports.isEmpty { portsSection(details.ports) }
                if let details, !details.environment.isEmpty {
                    DisclosureGroup("Environment (\(details.environment.count))", isExpanded: $showEnvironment) {
                        Text(details.environment.joined(separator: "\n"))
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if !entry.hasTaskInfo {
                    Label("This process belongs to another user. macOS hides its CPU, memory and file details from unprivileged apps.",
                          systemImage: "lock.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .task(id: entry.pid) {
            let pid = entry.pid
            while !Task.isCancelled {
                details = await Task.detached { ProcessDetails.fetch(pid: pid) }.value
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let icon = store.apps[entry.pid]?.icon {
                Image(nsImage: icon).resizable().frame(width: 40, height: 40)
            } else {
                Image(systemName: "terminal").font(.title).frame(width: 40, height: 40).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading) {
                Text(store.displayName(entry)).font(.title3.bold()).lineLimit(1)
                Text("PID \(entry.pid) · \(entry.user)").foregroundStyle(.secondary).font(.callout)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .glassCard(cornerRadius: 16)
    }

    private var graphs: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let cpu = store.processCPU[entry.pid] {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("CPU").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(Fmt.number(entry.cpu) + "%").font(.caption.monospacedDigit())
                    }
                    HistoryChart(series: [ChartSeries(name: "CPU", color: theme.cpu, history: cpu)],
                                 maxY: max(100, cpu.maxValue), showsYAxis: false) { Fmt.number($0) + "%" }
                        .frame(height: 60)
                }
            }
            if let mem = store.processMemory[entry.pid], entry.hasTaskInfo {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Memory").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(Fmt.bytes(entry.memory)).font(.caption.monospacedDigit())
                    }
                    HistoryChart(series: [ChartSeries(name: "Memory", color: theme.memApp, history: mem)],
                                 maxY: nil, showsYAxis: false) { Fmt.bytes($0) }
                        .frame(height: 60)
                }
            }
        }
    }

    private var actions: some View {
        HStack {
            Button("Quit") { store.requestQuit([entry.pid]) }
            Button("Force Quit", role: .destructive) { store.requestForceQuit([entry.pid]) }
            Menu("Signal") {
                ForEach(ProcessControl.signals) { signal in
                    Button("\(signal.number)  \(signal.name) — \(signal.summary)") { store.request(signal, for: [entry.pid]) }
                }
            }
            .fixedSize()
        }
        .controlSize(.small)
    }

    private var infoGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
            StatRow("State", entry.state.rawValue)
            StatRow("Parent", parentDescription)
            StatRow("User", "\(entry.user) (\(entry.uid))")
            StatRow("Started", Fmt.startDate.string(from: entry.startTime))
            StatRow("Running for", Fmt.duration(Date().timeIntervalSince(entry.startTime)))
            StatRow("Nice", "\(entry.nice)")
            if entry.hasTaskInfo {
                Divider().gridCellUnsizedAxes(.horizontal)
                StatRow("CPU time", Fmt.cpuTime(entry.cpuTime))
                StatRow("Threads", "\(entry.threads)")
                StatRow("Memory", Fmt.bytes(entry.memory))
                StatRow("Real memory", Fmt.bytes(entry.resident))
                StatRow("Disk read", "\(Fmt.bytes(entry.diskReadTotal)) · \(Fmt.rate(entry.diskReadRate))")
                StatRow("Disk written", "\(Fmt.bytes(entry.diskWriteTotal)) · \(Fmt.rate(entry.diskWriteRate))")
                StatRow("Idle wake ups", Fmt.number(entry.idleWakeupsPerSecond) + "/s")
            }
            if let details {
                if let files = details.openFiles { StatRow("Open files", "\(files)") }
                if let sockets = details.sockets { StatRow("Sockets", "\(sockets)") }
            }
        }
    }

    private var parentDescription: String {
        guard let parent = store.process(entry.ppid) else { return "\(entry.ppid)" }
        return "\(store.displayName(parent)) (\(entry.ppid))"
    }

    @ViewBuilder
    private var pathsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !entry.path.isEmpty {
                labeled("Executable") {
                    HStack(alignment: .top) {
                        Text(entry.path).textSelection(.enabled)
                        Spacer(minLength: 0)
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)])
                        } label: { Image(systemName: "magnifyingglass.circle") }
                            .buttonStyle(.borderless)
                            .help("Reveal in Finder")
                    }
                }
            }
            if let details, !details.arguments.isEmpty {
                labeled("Command line") { Text(details.commandLine).textSelection(.enabled) }
            }
            if let cwd = details?.workingDirectory {
                labeled("Working directory") { Text(cwd).textSelection(.enabled) }
            }
        }
    }

    private func portsSection(_ ports: [ProcessDetails.Port]) -> some View {
        labeled("Network ports") {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(ports.prefix(30), id: \.self) { port in
                    HStack {
                        Text(port.proto).foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
                        Text(":\(port.localPort)").monospacedDigit()
                        if let remote = port.remote { Text("→ \(remote)").foregroundStyle(.secondary).lineLimit(1) }
                        Spacer()
                        Text(port.state).font(.caption).foregroundStyle(port.state == "LISTEN" ? theme.low : .secondary)
                    }
                }
            }
        }
    }

    private func labeled(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content().font(.callout.monospaced())
        }
    }
}
