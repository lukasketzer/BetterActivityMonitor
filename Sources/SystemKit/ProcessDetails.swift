import Darwin
import Foundation

public struct ProcessDetails: Sendable {
    public struct Port: Sendable, Hashable {
        public var proto: String
        public var localPort: Int
        public var remote: String?
        public var state: String
    }

    public var pid: pid_t
    public var arguments: [String]
    public var environment: [String]
    public var executable: String
    public var workingDirectory: String?
    public var openFiles: Int?
    public var sockets: Int?
    public var ports: [Port]
    public var group: String?

    public var commandLine: String { arguments.joined(separator: " ") }

    public static func fetch(pid: pid_t, gid: gid_t? = nil) -> ProcessDetails {
        let (exec, args, env) = Self.arguments(pid: pid)
        var details = ProcessDetails(pid: pid, arguments: args, environment: env, executable: exec,
                                     workingDirectory: Self.cwd(pid: pid), openFiles: nil, sockets: nil,
                                     ports: [], group: nil)
        if let fds = Self.fileDescriptors(pid: pid) {
            details.openFiles = fds.filter { $0.proc_fdtype == PROX_FDTYPE_VNODE }.count
            let sockets = fds.filter { $0.proc_fdtype == PROX_FDTYPE_SOCKET }
            details.sockets = sockets.count
            details.ports = sockets.compactMap { Self.port(pid: pid, fd: $0.proc_fd) }
                .reduce(into: [Port]()) { if !$0.contains($1) { $0.append($1) } }
                .sorted { ($0.state == "LISTEN" ? 0 : 1, $0.localPort) < ($1.state == "LISTEN" ? 0 : 1, $1.localPort) }
        }
        if let gid, let group = getgrgid(gid) { details.group = String(cString: group.pointee.gr_name) }
        return details
    }

    /// Command line via KERN_PROCARGS2: argc, exec path, padding, argv..., envp...
    public static func arguments(pid: pid_t) -> (String, [String], [String]) {
        var argmax: Int32 = 0
        var size = MemoryLayout<Int32>.size
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&mib, 2, &argmax, &size, nil, 0) == 0 else { return ("", [], []) }

        var buffer = [UInt8](repeating: 0, count: Int(argmax))
        size = buffer.count
        mib = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return ("", [], []) }

        let argc = buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        func readString() -> String {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            let s = String(decoding: buffer[start..<index], as: UTF8.self)
            return s
        }
        let exec = readString()
        while index < size, buffer[index] == 0 { index += 1 }

        var args: [String] = []
        while args.count < argc, index < size {
            args.append(readString())
            index += 1
        }
        var env: [String] = []
        while index < size {
            let s = readString()
            index += 1
            if s.isEmpty { break }
            env.append(s)
        }
        return (exec, args, env)
    }

    static func cwd(pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = String(cTuple: info.pvi_cdir.vip_path)
        return path.isEmpty ? nil : path
    }

    static func fileDescriptors(pid: pid_t) -> [proc_fdinfo]? {
        let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bytes > 0 else { return nil }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(bytes) / stride + 16)
        let used = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, Int32(fds.count * stride))
        guard used > 0 else { return nil }
        return Array(fds.prefix(Int(used) / stride))
    }

    static func port(pid: pid_t, fd: Int32) -> Port? {
        var info = socket_fdinfo()
        let size = Int32(MemoryLayout<socket_fdinfo>.size)
        guard proc_pidfdinfo(pid, fd, PROC_PIDFDSOCKETINFO, &info, size) == size else { return nil }
        let soi = info.psi
        let family = soi.soi_family
        guard family == AF_INET || family == AF_INET6 else { return nil }

        switch Int(soi.soi_kind) {
        case Int(SOCKINFO_TCP):
            let tcp = soi.soi_proto.pri_tcp
            let local = Int(UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport).byteSwapped)
            let remotePort = Int(UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_fport).byteSwapped)
            let state = tcpState(Int(tcp.tcpsi_state))
            let remote = remotePort == 0 ? nil : "\(address(tcp.tcpsi_ini, family: family)):\(remotePort)"
            return Port(proto: family == AF_INET6 ? "TCP6" : "TCP", localPort: local, remote: remote, state: state)
        case Int(SOCKINFO_IN):
            let ini = soi.soi_proto.pri_in
            let local = Int(UInt16(truncatingIfNeeded: ini.insi_lport).byteSwapped)
            guard local != 0 else { return nil }
            return Port(proto: family == AF_INET6 ? "UDP6" : "UDP", localPort: local, remote: nil, state: "")
        default:
            return nil
        }
    }

    private static func address(_ ini: in_sockinfo, family: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        var ini = ini
        if family == AF_INET {
            var addr = ini.insi_faddr.ina_46.i46a_addr4
            inet_ntop(AF_INET, &addr, &buffer, socklen_t(buffer.count))
        } else {
            inet_ntop(AF_INET6, &ini.insi_faddr.ina_6, &buffer, socklen_t(buffer.count))
        }
        return String(cString: buffer)
    }

    private static func tcpState(_ state: Int) -> String {
        ["CLOSED", "LISTEN", "SYN_SENT", "SYN_RECEIVED", "ESTABLISHED", "CLOSE_WAIT", "FIN_WAIT_1",
         "CLOSING", "LAST_ACK", "FIN_WAIT_2", "TIME_WAIT"][safe: state] ?? "?"
    }
}

public extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
