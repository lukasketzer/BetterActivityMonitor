import SwiftUI
import SystemKit

/// Network section: the throughput overview plus connection pages built from `nettop` (no root needed).
struct NetworkView: View {
    @Environment(SystemStore.self) private var store
    @AppStorage(SettingsKey.networkPage) private var page: NetworkPage = .overview
    @AppStorage(SettingsKey.networkShowLoopback) private var showLoopback = false
    /// Developer aid for per-page profiling and layout checks: `BAM_NETWORK_PAGE=connections`.
    /// Overrides the shown page without writing the user's saved choice.
    @State private var forcedPage = ProcessInfo.processInfo.environment["BAM_NETWORK_PAGE"].flatMap(NetworkPage.init(rawValue:))

    private var current: NetworkPage { forcedPage ?? page }

    var body: some View {
        Group {
            switch current {
            case .overview: NetworkOverviewPage()
            case .connections: ConnectionsPage()
            case .listening: ListeningPage()
            case .log: ConnectionLogPage()
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Page", selection: Binding { current } set: { forcedPage = nil; page = $0 }) {
                    ForEach(NetworkPage.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
        .onAppear { updateMode() }
        .onChange(of: current) { updateMode() }
        .onChange(of: showLoopback) { updateMode() }
        .onDisappear { store.setConnectionMode(.off) }
    }

    /// Only the connection pages run nettop. Listening and loopback sockets need the full
    /// (about 2× costlier) run; see `ConnectionMode`.
    private func updateMode() {
        let mode: ConnectionMode = switch current {
        case .overview: .off
        case .listening: .all
        case .connections, .log: showLoopback ? .all : .external
        }
        store.setConnectionMode(mode)
    }
}

private extension SystemStore {
    /// Full process names: nettop truncates them to 15 characters.
    func processNames() -> [pid_t: String] {
        var names: [pid_t: String] = [:]
        for entry in snapshot?.processes ?? [] { names[entry.pid] = displayName(entry) }
        return names
    }
}

/// Table cells don't reliably inherit `@Observable` environment objects (reading the store here crashed
/// the Listening table), so the icon is passed in by the page.
private struct ProcessCell: View {
    var pid: pid_t
    var name: String
    var icon: NSImage?

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            } else {
                Image(systemName: "terminal").font(.caption).frame(width: 16).foregroundStyle(.tertiary)
            }
            Text(name).lineLimit(1)
        }
        .help("\(name) (PID \(pid))")
    }
}

private struct ConnectionsLoading: View {
    var body: some View {
        ProgressView("Reading connections…").frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private let filterPrompt = "Text, or proc: port: host: state: proto: scope:"

// MARK: Connections

private struct ConnectionsPage: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.theme) private var theme
    @AppStorage(SettingsKey.networkShowLoopback) private var showLoopback = false
    @AppStorage("network.groupByProcess") private var grouped = false
    @State private var query = ""
    @State private var rows: [ConnectionRow] = []
    @State private var count = 0
    @State private var selection: Set<ConnectionRow.ID> = []
    @State private var sortOrder = [KeyPathComparator(\ConnectionRow.total, order: .reverse)]

    var body: some View {
        Group {
            if store.snapshot?.connections == nil {
                ConnectionsLoading()
            } else {
                table
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: filterPrompt)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: $grouped) { Label("Group by Process", systemImage: "rectangle.3.group") }
                    .help("Group connections under their process")
                Toggle(isOn: $showLoopback) { Label("Loopback", systemImage: "arrow.triangle.2.circlepath") }
                    .help("Include connections within this Mac (127.0.0.1, ::1)")
            }
        }
        .navigationSubtitle("\(count) connections")
        .onChange(of: store.snapshot?.timestamp, initial: true) { rebuild() }
        .onChange(of: query) { rebuild() }
        .onChange(of: grouped) { rebuild() }
        .onChange(of: showLoopback) { rebuild() }
        .onChange(of: sortOrder) { rebuild() }
    }

    private var table: some View {
        Table(rows, children: \.children, selection: $selection, sortOrder: $sortOrder) {
            // Split in two: a single builder this large is too slow to type-check.
            identityColumns
            trafficColumns
        }
        .monospacedDigit()
        .contextMenu(forSelectionType: ConnectionRow.ID.self) { ids in
            if let row = row(ids.first) {
                Button("Show Process") { store.reveal(row.pid) }
                Button("Only This Process") { query = "pid:\(row.pid)" }
                if row.children == nil {
                    Button("Copy Remote Address") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(row.remote, forType: .string)
                    }
                }
            }
        } primaryAction: { ids in
            if let row = row(ids.first) { store.reveal(row.pid) }
        }
        .overlay {
            if rows.isEmpty {
                EmptyState(title: query.isEmpty ? "No Connections" : "No Matches", symbol: "network",
                           message: query.isEmpty ? "No process has an open connection right now." : "No connection matches “\(query)”.")
            }
        }
    }

    typealias Columns = TableColumnBuilder<ConnectionRow, KeyPathComparator<ConnectionRow>>

    @Columns private var identityColumns: some TableColumnContent<ConnectionRow, KeyPathComparator<ConnectionRow>> {
        TableColumn("Process", value: \.process) { ProcessCell(pid: $0.pid, name: $0.process, icon: store.apps[$0.pid]?.icon) }
            .width(min: 120, ideal: 160)
        TableColumn("Proto", value: \.proto).width(50)
        TableColumn("Remote", value: \.remote) { Text($0.remote).textSelection(.enabled) }
            .width(min: 140, ideal: 220)
        TableColumn("Service", value: \.service).width(min: 50, ideal: 70)
        TableColumn("Scope", value: \.scope).width(min: 50, ideal: 70)
        TableColumn("State", value: \.state).width(min: 60, ideal: 85)
    }

    @Columns private var trafficColumns: some TableColumnContent<ConnectionRow, KeyPathComparator<ConnectionRow>> {
        TableColumn("↓/s", value: \.rateIn) { Text(Fmt.rate($0.rateIn)).foregroundStyle(theme.netIn) }
            .width(min: 60, ideal: 70).alignment(.trailing)
        TableColumn("↑/s", value: \.rateOut) { Text(Fmt.rate($0.rateOut)).foregroundStyle(theme.netOut) }
            .width(min: 60, ideal: 70).alignment(.trailing)
        TableColumn("Total", value: \.total) { Text(Fmt.bytes($0.total)) }
            .width(min: 55, ideal: 65).alignment(.trailing)
        TableColumn("RTT", value: \.rtt) { Text($0.rtt < 0 ? "" : String(format: "%.0f ms", $0.rtt)) }
            .width(min: 45, ideal: 55).alignment(.trailing)
        TableColumn("Re-tx", value: \.retransmits) { Text($0.retransmits == 0 ? "" : Fmt.bytes($0.retransmits)) }
            .width(min: 45, ideal: 55).alignment(.trailing)
        TableColumn("Local", value: \.local) { Text($0.local).foregroundStyle(.secondary) }
            .width(min: 120, ideal: 200)
        TableColumn("Interface", value: \.interface).width(min: 50, ideal: 60)
    }

    private func row(_ id: ConnectionRow.ID?) -> ConnectionRow? {
        guard let id else { return nil }
        for row in rows {
            if row.id == id { return row }
            if let child = row.children?.first(where: { $0.id == id }) { return child }
        }
        return nil
    }

    private func rebuild() {
        guard let stats = store.snapshot?.connections else { rows = []; count = 0; return }
        let now = store.snapshot?.timestamp ?? Date()
        let names = store.processNames()
        let filter = ConnectionFilter(query)
        // Listening and unconnected sockets live on the Listening page.
        let flat = stats.flows.compactMap { flow -> ConnectionRow? in
            guard !flow.isListening, !flow.remote.isWildcard,
                  showLoopback || flow.scope != .loopback else { return nil }
            let name = names[flow.pid] ?? flow.processName
            guard filter.isEmpty || filter.matches(flow, process: name) else { return nil }
            return ConnectionRow.flow(flow, process: name, now: now)
        }
        count = flat.count
        if grouped {
            rows = Dictionary(grouping: flat, by: \.pid).map { pid, children in
                ConnectionRow.group(pid: pid, process: children[0].process, children: children.sorted(using: sortOrder))
            }
            .sorted(using: sortOrder)
        } else {
            rows = flat.sorted(using: sortOrder)
        }
    }
}

// MARK: Listening

struct ListeningRow: Identifiable, Hashable {
    var id: String
    var pid: pid_t
    var process: String
    var proto: String
    var address: String
    var port: Int
    var service: String
    var reach: String
}

private struct ListeningPage: View {
    @Environment(SystemStore.self) private var store
    @State private var query = ""
    @State private var rows: [ListeningRow] = []
    @State private var sortOrder = [KeyPathComparator(\ListeningRow.port)]

    var body: some View {
        Group {
            if store.snapshot?.connections?.mode != .all {
                ConnectionsLoading()
            } else {
                Table(rows, sortOrder: $sortOrder) {
                    TableColumn("Process", value: \.process) { ProcessCell(pid: $0.pid, name: $0.process, icon: store.apps[$0.pid]?.icon) }
                        .width(min: 140, ideal: 200)
                    TableColumn("Proto", value: \.proto).width(50)
                    TableColumn("Port", value: \.port) { Text(String($0.port)) }.width(60).alignment(.trailing)
                    TableColumn("Service", value: \.service).width(min: 60, ideal: 100)
                    TableColumn("Address", value: \.address) { Text($0.address).foregroundStyle(.secondary) }
                        .width(min: 100, ideal: 200)
                    TableColumn("Reachable From", value: \.reach) { row in
                        Label(row.reach, systemImage: row.reach == "This Mac only" ? "lock" : "globe")
                            .foregroundStyle(row.reach == "This Mac only" ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                    }
                    .width(min: 110, ideal: 130)
                }
                .monospacedDigit()
                .contextMenu(forSelectionType: ListeningRow.ID.self) { ids in
                    if let row = rows.first(where: { $0.id == ids.first }) {
                        Button("Show Process") { store.reveal(row.pid) }
                    }
                } primaryAction: { ids in
                    if let row = rows.first(where: { $0.id == ids.first }) { store.reveal(row.pid) }
                }
                .overlay {
                    if rows.isEmpty {
                        EmptyState(title: query.isEmpty ? "Nothing Listening" : "No Matches", symbol: "ear",
                                   message: query.isEmpty ? "No process accepts incoming connections." : "No listener matches “\(query)”.")
                    }
                }
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: filterPrompt)
        .navigationSubtitle("\(rows.count) listening sockets")
        .onChange(of: store.snapshot?.timestamp, initial: true) { rebuild() }
        .onChange(of: query) { rebuild() }
        .onChange(of: sortOrder) { rebuild() }
    }

    private func rebuild() {
        guard let stats = store.snapshot?.connections, stats.mode == .all else { rows = []; return }
        let names = store.processNames()
        let filter = ConnectionFilter(query)
        rows = stats.flows.compactMap { flow -> ListeningRow? in
            guard flow.isListening, let port = flow.local.port else { return nil }
            let name = names[flow.pid] ?? flow.processName
            guard filter.isEmpty || filter.matches(flow, process: name) else { return nil }
            let reach = switch flow.scope {
            case .loopback: "This Mac only"
            case .any: "All networks"
            case .linkLocal, .privateNetwork: "Local network"
            default: "Network"
            }
            return ListeningRow(id: flow.id, pid: flow.pid, process: name,
                                proto: flow.proto.uppercased() + (flow.isIPv6 ? "6" : "4"),
                                address: flow.local.host == "*" ? "Any" : flow.local.host, port: Int(port),
                                service: flow.service ?? "", reach: reach)
        }
        .sorted(using: sortOrder)
    }
}

// MARK: Log

struct LogRow: Identifiable, Hashable {
    var id: UUID
    var date: Date
    var opened: Bool
    var pid: pid_t
    var process: String
    var proto: String
    var remote: String
    var service: String
    var scope: String
    var total: UInt64
}

private struct ConnectionLogPage: View {
    @Environment(SystemStore.self) private var store
    @AppStorage(SettingsKey.networkShowLoopback) private var showLoopback = false
    @State private var query = ""
    @State private var rows: [LogRow] = []
    @State private var sortOrder = [KeyPathComparator(\LogRow.date, order: .reverse)]

    var body: some View {
        @Bindable var store = store
        Table(rows, sortOrder: $sortOrder) {
            TableColumn("Time", value: \.date) { Text($0.date, format: .dateTime.hour().minute().second()) }
                .width(min: 70, ideal: 80)
            TableColumn("Event", value: \.opened.description) { row in
                Label(row.opened ? "Opened" : "Closed", systemImage: row.opened ? "plus.circle" : "minus.circle")
                    .foregroundStyle(row.opened ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
            }
            .width(min: 70, ideal: 80)
            TableColumn("Process", value: \.process) { ProcessCell(pid: $0.pid, name: $0.process, icon: store.apps[$0.pid]?.icon) }
                .width(min: 140, ideal: 180)
            TableColumn("Proto", value: \.proto).width(50)
            TableColumn("Remote", value: \.remote) { Text($0.remote).textSelection(.enabled) }
                .width(min: 140, ideal: 260)
            TableColumn("Service", value: \.service).width(min: 60, ideal: 80)
            TableColumn("Scope", value: \.scope).width(min: 60, ideal: 70)
            TableColumn("Transferred", value: \.total) { Text($0.opened ? "" : Fmt.bytes($0.total)) }
                .width(min: 70, ideal: 80).alignment(.trailing)
        }
        .monospacedDigit()
        .overlay {
            if rows.isEmpty {
                EmptyState(title: query.isEmpty ? "No Events Yet" : "No Matches", symbol: "list.bullet.clipboard",
                           message: query.isEmpty
                               ? "Connections that open or close while this page is open appear here. Short-lived ones between two updates are not seen."
                               : "No event matches “\(query)”.")
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: filterPrompt)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: $showLoopback) { Label("Loopback", systemImage: "arrow.triangle.2.circlepath") }
                    .help("Include connections within this Mac (127.0.0.1, ::1)")
                Toggle(isOn: $store.connectionLogPaused) {
                    Label("Pause", systemImage: store.connectionLogPaused ? "play.fill" : "pause.fill")
                }
                .help("Stop recording new events")
                Button { store.clearConnectionLog() } label: { Label("Clear", systemImage: "trash") }
                    .help("Clear the log")
            }
        }
        .navigationSubtitle("\(rows.count) events")
        .onChange(of: store.connectionLog, initial: true) { rebuild() }
        .onChange(of: query) { rebuild() }
        .onChange(of: showLoopback) { rebuild() }
        .onChange(of: sortOrder) { rebuild() }
    }

    private func rebuild() {
        let names = store.processNames()
        let filter = ConnectionFilter(query)
        rows = store.connectionLog.compactMap { event -> LogRow? in
            let flow = event.flow
            guard showLoopback || flow.scope != .loopback else { return nil }
            let name = names[flow.pid] ?? flow.processName
            guard filter.isEmpty || filter.matches(flow, process: name) else { return nil }
            return LogRow(id: event.id, date: event.date, opened: event.kind == .opened, pid: flow.pid, process: name,
                          proto: flow.proto.uppercased() + (flow.isIPv6 ? "6" : "4"), remote: flow.remote.description,
                          service: flow.service ?? "", scope: flow.scope.rawValue, total: flow.bytesIn + flow.bytesOut)
        }
        .sorted(using: sortOrder)
    }
}
