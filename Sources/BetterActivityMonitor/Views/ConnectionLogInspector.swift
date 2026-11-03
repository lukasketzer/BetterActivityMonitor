import AppKit
import SwiftUI
import SystemKit

/// Details of one connection-log event: both endpoints, traffic, lifetime, the matching open/close event,
/// a reverse-DNS name for the remote host and shortcuts to filter the log or jump to the process.
struct ConnectionLogInspector: View {
    @Environment(SystemStore.self) private var store
    var eventID: ConnectionEvent.ID?
    /// Replaces the log's search text (used by the "Filter" buttons).
    var setQuery: (String) -> Void

    var body: some View {
        if let eventID, let event = store.connectionLog.first(where: { $0.id == eventID }) {
            LogEventDetails(event: event, setQuery: setQuery)
                .id(eventID)
        } else {
            EmptyState(title: "No Event Selected", symbol: "cursorarrow.click",
                       message: "Select an event in the log to see its details.")
        }
    }
}

private struct LogEventDetails: View {
    @Environment(SystemStore.self) private var store
    @Environment(\.theme) private var theme
    var event: ConnectionEvent
    var setQuery: (String) -> Void
    @State private var hostName: String?
    @State private var lookupDone = false

    private var flow: NetworkFlow { event.flow }
    /// The process in the latest sample, if it is still running.
    private var process: ProcessEntry? { store.snapshot?.processes.first { $0.pid == flow.pid } }
    private var processName: String { process.map(store.displayName) ?? flow.processName }
    /// The same flow in the latest sample, if it is still open.
    private var liveFlow: NetworkFlow? { store.snapshot?.connections?.flows.first { $0.id == flow.id } }
    /// The other half of this event's open/close pair, if the log still has it.
    private var partner: ConnectionEvent? {
        store.connectionLog.first { $0.flow.id == flow.id && $0.kind != event.kind }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                actions
                section("Connection") {
                    row("Protocol", flow.proto.uppercased() + (flow.isIPv6 ? " over IPv6" : " over IPv4"))
                    row("Remote", flow.remote.description)
                    row("Remote name", lookupDone ? (hostName ?? "No reverse DNS entry") : "Looking up…",
                        secondary: hostName == nil)
                    if let service = flow.service { row("Service", "\(service) (port \(flow.servicePort.map(String.init) ?? "—"))") }
                    row("Scope", flow.scope.rawValue)
                    row("Local", flow.local.description)
                    if !flow.interface.isEmpty { row("Interface", flow.interface) }
                    if !flow.state.isEmpty { row("TCP state", flow.state + (event.kind == .closed ? " (last seen)" : "")) }
                }
                section(event.kind == .closed ? "Traffic (when closed)" : liveFlow != nil ? "Traffic (now)" : "Traffic (when opened)") {
                    let f = liveFlow ?? flow
                    row("Received", Fmt.bytes(f.bytesIn), color: theme.netIn)
                    row("Sent", Fmt.bytes(f.bytesOut), color: theme.netOut)
                    if liveFlow != nil {
                        row("Rate", "↓ \(Fmt.rate(f.rateIn))  ↑ \(Fmt.rate(f.rateOut))")
                    }
                    if let rtt = f.rtt { row("Round trip", String(format: "%.0f ms", rtt)) }
                    if f.retransmits > 0 { row("Retransmitted", Fmt.bytes(f.retransmits)) }
                }
                section("Timing") {
                    row("First seen", flow.firstSeen.formatted(date: .omitted, time: .standard))
                    if let opened = openedDate { row("Opened", opened.formatted(date: .omitted, time: .standard)) }
                    if let closed = closedDate { row("Closed", closed.formatted(date: .omitted, time: .standard)) }
                    row("Lifetime", lifetime)
                }
                relatedSection
            }
            .padding()
        }
        .monospacedDigit()
        .task(id: flow.remote.host) {
            let host = flow.remote.host
            hostName = await Task.detached { ReverseDNS.name(for: host) }.value
            lookupDone = true
        }
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 12) {
            if let icon = store.apps[flow.pid]?.icon {
                Image(nsImage: icon).resizable().frame(width: 40, height: 40)
            } else {
                Image(systemName: "gearshape").font(.system(size: 28)).frame(width: 40, height: 40)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(processName).font(.title3.weight(.semibold)).lineLimit(1)
                Text("PID \(flow.pid)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Label(event.kind == .opened ? "Opened" : "Closed",
                  systemImage: event.kind == .opened ? "plus.circle.fill" : "minus.circle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(event.kind == .opened ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Menu("Filter") {
                Button("This process") { setQuery("pid:\(flow.pid)") }
                Button("This remote host") { setQuery("host:\(flow.remote.host)") }
                if let port = flow.remote.port { Button("This port") { setQuery("port:\(port)") } }
            }
            .fixedSize()
            Button("Copy") { copyDetails() }
                .help("Copy these details as text")
            if process != nil {
                Button("Show Process") { store.reveal(flow.pid) }
            }
        }
        .controlSize(.small)
    }

    @ViewBuilder private var relatedSection: some View {
        let sameHost = store.connectionLog.filter {
            $0.id != event.id && $0.flow.id != flow.id && $0.flow.remote.host == flow.remote.host
        }
        let sameProcess = store.connectionLog.filter { $0.flow.pid == flow.pid && $0.kind == .opened }
        section("In This Log") {
            row("Opens by this process", "\(sameProcess.count)")
            row("Other events with this host", "\(sameHost.count)")
            if let partner {
                row(partner.kind == .opened ? "Matching open" : "Matching close",
                    partner.date.formatted(date: .omitted, time: .standard))
            }
        }
    }

    // MARK: Values

    private var openedDate: Date? { event.kind == .opened ? event.date : partner?.date }
    private var closedDate: Date? { event.kind == .closed ? event.date : partner?.date }

    private var lifetime: String {
        if let closed = closedDate { return "≈ " + Fmt.duration(max(0, closed.timeIntervalSince(flow.firstSeen))) }
        if liveFlow != nil { return "Still open, " + Fmt.duration(Date().timeIntervalSince(flow.firstSeen)) + " so far" }
        return "Unknown (closed while not recording)"
    }

    private func copyDetails() {
        let f = liveFlow ?? flow
        var lines = [
            "\(event.kind == .opened ? "Opened" : "Closed") \(event.date.formatted(date: .abbreviated, time: .standard))",
            "Process: \(processName) (PID \(flow.pid))",
            "Protocol: \(flow.proto.uppercased())\(flow.isIPv6 ? "6" : "4")",
            "Remote: \(flow.remote.description)" + (hostName.map { " (\($0))" } ?? ""),
            "Local: \(flow.local.description)",
            "Scope: \(flow.scope.rawValue)",
        ]
        if let service = flow.service { lines.append("Service: \(service)") }
        if !flow.interface.isEmpty { lines.append("Interface: \(flow.interface)") }
        if !flow.state.isEmpty { lines.append("TCP state: \(flow.state)") }
        lines.append("Received: \(Fmt.bytes(f.bytesIn)), sent: \(Fmt.bytes(f.bytesOut))")
        lines.append("Lifetime: \(lifetime)")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    // MARK: Layout helpers

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.headline).padding(.bottom, 6)
            content()
        }
    }

    private func row(_ key: String, _ value: String, color: Color? = nil, secondary: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(key).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(value)
                    .foregroundStyle(color.map(AnyShapeStyle.init) ?? (secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)))
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
            .font(.callout)
            .padding(.vertical, 5)
            Divider()
        }
    }
}

enum ReverseDNS {
    /// PTR lookup for a numeric address; blocking, so call it off the main thread. Nil when there is no name.
    static func name(for host: String) -> String? {
        guard host != "*" else { return nil }
        var hints = addrinfo(ai_flags: AI_NUMERICHOST, ai_family: AF_UNSPEC, ai_socktype: 0, ai_protocol: 0,
                             ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let info = result else { return nil }
        defer { freeaddrinfo(result) }
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(info.pointee.ai_addr, info.pointee.ai_addrlen, &buffer, socklen_t(buffer.count),
                          nil, 0, NI_NAMEREQD) == 0 else { return nil }
        let name = String(cString: buffer)
        return name == host ? nil : name
    }
}
