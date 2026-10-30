import Foundation
import SystemKit

/// One line of the Connections table: a flow, or (when grouped) a process summing its flows.
struct ConnectionRow: Identifiable, Hashable {
    var id: String
    var pid: pid_t
    var process: String
    var proto: String
    var local: String
    var remote: String
    var service: String
    var scope: String
    var state: String
    var interface: String
    var rateIn: Double
    var rateOut: Double
    var total: UInt64
    /// Milliseconds; -1 when unknown so it sorts below every real value.
    var rtt: Double
    var retransmits: UInt64
    var age: TimeInterval
    var children: [ConnectionRow]?

    static func flow(_ flow: NetworkFlow, process: String, now: Date) -> ConnectionRow {
        ConnectionRow(
            id: flow.id, pid: flow.pid, process: process,
            proto: flow.proto.uppercased() + (flow.isIPv6 ? "6" : "4"),
            local: flow.local.description, remote: flow.remote.isWildcard ? "—" : flow.remote.description,
            service: flow.service ?? "", scope: flow.scope.rawValue, state: flow.state, interface: flow.interface,
            rateIn: flow.rateIn, rateOut: flow.rateOut, total: flow.bytesIn + flow.bytesOut,
            rtt: flow.rtt ?? -1, retransmits: flow.retransmits, age: now.timeIntervalSince(flow.firstSeen)
        )
    }

    static func group(pid: pid_t, process: String, children: [ConnectionRow]) -> ConnectionRow {
        ConnectionRow(
            id: "pid \(pid)", pid: pid, process: process,
            proto: "", local: "", remote: "\(children.count) connection\(children.count == 1 ? "" : "s")",
            service: "", scope: "", state: "", interface: "",
            rateIn: children.reduce(0) { $0 + $1.rateIn }, rateOut: children.reduce(0) { $0 + $1.rateOut },
            total: children.reduce(0) { $0 + $1.total },
            rtt: children.map(\.rtt).max() ?? -1, retransmits: children.reduce(0) { $0 + $1.retransmits },
            age: children.map(\.age).max() ?? 0, children: children
        )
    }
}

/// Filter syntax for the connection views: `proc:`, `pid:`, `port:`, `host:`, `state:`, `proto:` and `scope:`
/// tokens, plus free text matched against process, addresses and service. All tokens must match.
struct ConnectionFilter {
    private var terms: [(key: String?, value: String)] = []

    init(_ text: String) {
        for token in text.lowercased().split(whereSeparator: \.isWhitespace) {
            if let colon = token.firstIndex(of: ":"), colon != token.startIndex,
               ["proc", "pid", "port", "host", "state", "proto", "scope"].contains(String(token[..<colon])) {
                terms.append((String(token[..<colon]), String(token[token.index(after: colon)...])))
            } else {
                terms.append((nil, String(token)))
            }
        }
    }

    var isEmpty: Bool { terms.isEmpty }

    func matches(_ flow: NetworkFlow, process: String) -> Bool {
        terms.allSatisfy { term in
            let v = term.value
            switch term.key {
            case "proc": return process.lowercased().contains(v)
            case "pid": return String(flow.pid) == v
            case "port": return [flow.local.port, flow.remote.port].contains { $0.map(String.init) == v }
            case "host": return flow.remote.host.lowercased().contains(v) || flow.local.host.lowercased().contains(v)
            case "state": return flow.state.lowercased().hasPrefix(v)
            case "proto": return flow.proto.hasPrefix(v)
            case "scope": return flow.scope.rawValue.lowercased().hasPrefix(v)
            default:
                return process.lowercased().contains(v)
                    || flow.remote.description.lowercased().contains(v)
                    || flow.local.description.lowercased().contains(v)
                    || (flow.service?.lowercased().contains(v) ?? false)
            }
        }
    }
}
