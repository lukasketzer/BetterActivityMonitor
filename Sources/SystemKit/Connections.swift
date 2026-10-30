import Darwin
import Foundation

// MARK: Model

/// Which flows `nettop` is asked for. Cost scales with the number of flows, so the cheap mode skips the
/// many loopback and unbound sockets (measured: ~10 ms vs ~35 ms CPU per run, see `sysbench nettop`).
public enum ConnectionMode: Sendable {
    case off
    /// Flows on Wi-Fi and wired interfaces only.
    case external
    /// Every socket, including loopback, VPN and listening sockets.
    case all
}

public struct Endpoint: Sendable, Hashable {
    /// Numeric address without zone, or `*` for any address.
    public var host: String
    /// Interface zone of a link-local IPv6 address (`en0` in `fe80::1%en0`).
    public var zone: String?
    /// Nil for a wildcard port.
    public var port: UInt16?

    public init(host: String, zone: String? = nil, port: UInt16?) {
        self.host = host
        self.zone = zone
        self.port = port
    }

    public var isWildcard: Bool { host == "*" && port == nil }

    public var description: String {
        let portText = port.map(String.init) ?? "*"
        return host.contains(":") ? "[\(host)]:\(portText)" : "\(host):\(portText)"
    }
}

public struct NetworkFlow: Sendable, Identifiable, Hashable {
    public var id: String
    public var pid: pid_t
    public var processName: String
    /// `tcp`, `udp` or `quic`.
    public var proto: String
    public var isIPv6: Bool
    public var local: Endpoint
    public var remote: Endpoint
    /// BSD interface name; empty for unbound sockets.
    public var interface: String
    /// TCP state as nettop prints it (`Established`, `Listen`, …); empty for UDP and QUIC.
    public var state: String
    public var bytesIn: UInt64
    public var bytesOut: UInt64
    public var rateIn: Double
    public var rateOut: Double
    public var retransmits: UInt64
    /// Average round-trip time in milliseconds.
    public var rtt: Double?
    public var firstSeen: Date

    public var isListening: Bool {
        state == "Listen" || (proto == "udp" && remote.isWildcard && local.port != nil)
    }

    /// Endpoint that names the service: the remote one for outgoing flows, the local one for listeners.
    public var servicePort: UInt16? { isListening ? local.port : remote.port }
    public var service: String? { servicePort.flatMap { PortNames.name(for: $0, proto: proto) } }
    public var scope: AddressScope { isListening ? AddressScope(local.host) : AddressScope(remote.host) }
}

/// Per-process totals as nettop reports them; counters include flows that have already closed.
public struct ProcessNetUsage: Sendable, Identifiable, Hashable {
    public var id: pid_t { pid }
    public var pid: pid_t
    public var name: String
    public var bytesIn: UInt64
    public var bytesOut: UInt64
    public var rateIn: Double
    public var rateOut: Double
}

public struct ConnectionStats: Sendable {
    public var mode: ConnectionMode
    public var flows: [NetworkFlow]
    public var processes: [ProcessNetUsage]
}

// MARK: Offline enrichment

public enum AddressScope: String, Sendable, CaseIterable {
    case any = "Any"
    case loopback = "Loopback"
    case linkLocal = "Link-local"
    case privateNetwork = "Private"
    case multicast = "Multicast"
    case internet = "Internet"

    /// Classifies a numeric address without any lookup.
    public init(_ host: String) {
        if host == "*" { self = .any; return }
        var v4 = in_addr()
        if inet_pton(AF_INET, host, &v4) == 1 {
            let a = UInt32(bigEndian: v4.s_addr)
            let b0 = a >> 24, b1 = (a >> 16) & 0xff
            switch true {
            case b0 == 0: self = .any
            case b0 == 127: self = .loopback
            case b0 == 169 && b1 == 254: self = .linkLocal
            case b0 == 10, b0 == 172 && (16...31).contains(b1), b0 == 192 && b1 == 168,
                 b0 == 100 && (64...127).contains(b1): self = .privateNetwork
            case (224...239).contains(b0): self = .multicast
            default: self = .internet
            }
            return
        }
        var v6 = in6_addr()
        guard inet_pton(AF_INET6, host, &v6) == 1 else { self = .internet; return }
        let bytes = withUnsafeBytes(of: v6) { Array($0) }
        if bytes.allSatisfy({ $0 == 0 }) { self = .any; return }
        if bytes.dropLast().allSatisfy({ $0 == 0 }) && bytes.last == 1 { self = .loopback; return }
        // IPv4-mapped (::ffff:a.b.c.d): classify the embedded IPv4 address.
        if bytes[0..<10].allSatisfy({ $0 == 0 }) && bytes[10] == 0xff && bytes[11] == 0xff {
            self.init(bytes[12...].map(String.init).joined(separator: "."))
            return
        }
        switch true {
        case bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80: self = .linkLocal
        case bytes[0] & 0xfe == 0xfc: self = .privateNetwork
        case bytes[0] == 0xff: self = .multicast
        default: self = .internet
        }
    }
}

/// Well-known service names. The built-in table covers what macOS shows most; other system ports come
/// from the local /etc/services via getservbyport, so no lookup ever leaves the machine.
public enum PortNames {
    private static let builtIn: [UInt16: String] = [
        20: "FTP data", 21: "FTP", 22: "SSH", 23: "Telnet", 25: "SMTP", 53: "DNS", 67: "DHCP", 68: "DHCP",
        80: "HTTP", 88: "Kerberos", 110: "POP3", 123: "NTP", 137: "NetBIOS", 138: "NetBIOS", 139: "SMB",
        143: "IMAP", 389: "LDAP", 443: "HTTPS", 445: "SMB", 465: "SMTPS", 548: "AFP", 587: "Submission",
        631: "IPP", 853: "DNS over TLS", 993: "IMAPS", 995: "POP3S", 1900: "SSDP", 3283: "Remote Desktop",
        3389: "RDP", 5000: "AirPlay", 5223: "Apple Push", 5353: "mDNS", 5900: "VNC", 7000: "AirPlay",
        8080: "HTTP alt", 8443: "HTTPS alt",
    ]
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: String?] = [:]

    public static func name(for port: UInt16, proto: String) -> String? {
        if let name = builtIn[port] { return name }
        // Registrations above 1023 rarely match what actually runs there (8021 is "intu-ec-client",
        // usually a local dev server), so /etc/services is only trusted for system ports.
        guard port < 1024 else { return nil }
        let key = "\(port)/\(proto)"
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        // getservbyport uses static storage, hence the lock.
        let entry = getservbyport(Int32(port.bigEndian), proto == "quic" ? "udp" : proto)
        let name = entry.flatMap { $0.pointee.s_name.map { String(cString: $0) } }
        cache[key] = name
        return name
    }
}

// MARK: Parsing

/// Parses `nettop -L 1 -n -x` CSV. Process lines (`name.pid`) are followed by that process's flows
/// (`tcp4 1.2.3.4:5<->6.7.8.9:443`); IPv4 endpoints use `:` before the port, IPv6 endpoints `.`.
public enum NettopParser {
    public struct Process: Equatable {
        public var pid: pid_t
        public var name: String
        public var bytesIn: UInt64
        public var bytesOut: UInt64
    }

    public struct Flow: Equatable {
        public var pid: pid_t
        public var processName: String
        public var proto: String
        public var isIPv6: Bool
        public var local: Endpoint
        public var remote: Endpoint
        public var interface: String
        public var state: String
        public var bytesIn: UInt64
        public var bytesOut: UInt64
        public var retransmits: UInt64
        public var rtt: Double?
    }

    public static func parse(_ text: String) -> (processes: [Process], flows: [Flow]) {
        var processes: [Process] = []
        var flows: [Flow] = []
        var current: Process?
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 10, fields[0] != "time" else { continue }
            let name = fields[1]
            let bytesIn = UInt64(fields[4]) ?? 0
            let bytesOut = UInt64(fields[5]) ?? 0
            if let arrow = name.range(of: "<->") {
                guard let process = current, let space = name.firstIndex(of: " ") else { continue }
                let kind = name[..<space]
                let isIPv6 = kind.hasSuffix("6")
                guard let local = endpoint(name[name.index(after: space)..<arrow.lowerBound], ipv6: isIPv6),
                      let remote = endpoint(name[arrow.upperBound...], ipv6: isIPv6) else { continue }
                flows.append(Flow(
                    pid: process.pid, processName: process.name,
                    proto: String(kind.dropLast()), isIPv6: isIPv6, local: local, remote: remote,
                    interface: String(fields[2]), state: String(fields[3]),
                    bytesIn: bytesIn, bytesOut: bytesOut,
                    retransmits: UInt64(fields[8]) ?? 0,
                    rtt: Double(fields[9].split(separator: " ").first ?? "")
                ))
            } else if let dot = name.lastIndex(of: "."), let pid = pid_t(name[name.index(after: dot)...]) {
                let process = Process(pid: pid, name: String(name[..<dot]), bytesIn: bytesIn, bytesOut: bytesOut)
                processes.append(process)
                current = process
            }
        }
        return (processes, flows)
    }

    static func endpoint(_ text: Substring, ipv6: Bool) -> Endpoint? {
        guard let separator = text.lastIndex(of: ipv6 ? "." : ":") else { return nil }
        let portText = text[text.index(after: separator)...]
        let port: UInt16?
        if portText == "*" { port = nil } else if let value = UInt16(portText) { port = value } else { return nil }
        var host = text[..<separator]
        var zone: String?
        if let percent = host.firstIndex(of: "%") {
            zone = String(host[host.index(after: percent)...])
            host = host[..<percent]
        }
        return Endpoint(host: String(host), zone: zone, port: port)
    }
}
