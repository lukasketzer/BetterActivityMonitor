import Darwin
import Foundation
import SystemConfiguration

final class NetworkSampler {
    private var previous: [String: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
    private var previousTime: Date?
    private var displayNames: [String: String] = [:]
    private var displayNamesLoaded: Date?
    private var cachedAddresses: [String: [String]] = [:]
    private var addressesLoaded: Date?
    private var indexNames: [UInt16: String] = [:]

    func sample() -> NetworkStats {
        let now = Date()
        let dt = previousTime.map { max(now.timeIntervalSince($0), 0.001) }
        refreshDisplayNamesIfNeeded(now)
        // Addresses rarely change and getnameinfo is comparatively slow.
        if addressesLoaded.map({ now.timeIntervalSince($0) > 10 }) ?? true {
            cachedAddresses = Self.addresses()
            addressesLoaded = now
        }
        let addresses = cachedAddresses

        var interfaces: [NetworkInterface] = []
        for raw in readCounters() {
            var iface = NetworkInterface(
                name: raw.name, displayName: displayNames[raw.name] ?? raw.name,
                isUp: raw.isUp, isLoopback: raw.isLoopback, addresses: addresses[raw.name] ?? [],
                bytesIn: raw.bytesIn, bytesOut: raw.bytesOut,
                packetsIn: raw.packetsIn, packetsOut: raw.packetsOut,
                errorsIn: raw.errorsIn, errorsOut: raw.errorsOut, rateIn: 0, rateOut: 0
            )
            if iface.isLoopback { iface.displayName = "Loopback" }
            if let dt, let prev = previous[raw.name] {
                if raw.bytesIn >= prev.bytesIn { iface.rateIn = Double(raw.bytesIn - prev.bytesIn) / dt }
                if raw.bytesOut >= prev.bytesOut { iface.rateOut = Double(raw.bytesOut - prev.bytesOut) / dt }
            }
            previous[raw.name] = (raw.bytesIn, raw.bytesOut)
            interfaces.append(iface)
        }
        previousTime = now

        let external = interfaces.filter { !$0.isLoopback }
        return NetworkStats(
            interfaces: interfaces.sorted { ($0.bytesIn + $0.bytesOut) > ($1.bytesIn + $1.bytesOut) },
            rateIn: external.reduce(0) { $0 + $1.rateIn },
            rateOut: external.reduce(0) { $0 + $1.rateOut },
            totalIn: external.reduce(0) { $0 + $1.bytesIn },
            totalOut: external.reduce(0) { $0 + $1.bytesOut }
        )
    }

    private func refreshDisplayNamesIfNeeded(_ now: Date) {
        if let loaded = displayNamesLoaded, now.timeIntervalSince(loaded) < 30 { return }
        displayNamesLoaded = now
        guard let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return }
        for iface in all {
            if let bsd = SCNetworkInterfaceGetBSDName(iface) as String?,
               let name = SCNetworkInterfaceGetLocalizedDisplayName(iface) as String? {
                displayNames[bsd] = name
            }
        }
    }

    private struct RawCounters {
        var name: String
        var isUp, isLoopback: Bool
        var bytesIn, bytesOut, packetsIn, packetsOut, errorsIn, errorsOut: UInt64
    }

    /// 64-bit counters via NET_RT_IFLIST2 (getifaddrs' if_data wraps at 4 GiB).
    private func readCounters() -> [RawCounters] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var size = 0
        guard sysctl(&mib, 6, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 6, &buffer, &size, nil, 0) == 0 else { return [] }

        var result: [RawCounters] = []
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= size {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= size {
                    let msg = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if let name = interfaceName(msg.ifm_index) {
                        let data = msg.ifm_data
                        let flags = Int32(msg.ifm_flags)
                        result.append(RawCounters(
                            name: name,
                            isUp: flags & IFF_UP != 0, isLoopback: flags & IFF_LOOPBACK != 0,
                            bytesIn: data.ifi_ibytes, bytesOut: data.ifi_obytes,
                            packetsIn: data.ifi_ipackets, packetsOut: data.ifi_opackets,
                            errorsIn: data.ifi_ierrors, errorsOut: data.ifi_oerrors
                        ))
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return result
    }

    /// if_indextoname is a syscall per interface; indexes are stable while the interface exists.
    private func interfaceName(_ index: UInt16) -> String? {
        if let name = indexNames[index] { return name }
        var buffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        guard if_indextoname(UInt32(index), &buffer) != nil else { return nil }
        let name = String(cString: buffer)
        indexNames[index] = name
        return name
    }

    private static func addresses() -> [String: [String]] {
        var result: [String: [String]] = [:]
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return result }
        defer { freeifaddrs(ifap) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let addr = ptr.pointee.ifa_addr else { continue }
            let family = Int32(addr.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let len = socklen_t(family == AF_INET ? MemoryLayout<sockaddr_in>.size : MemoryLayout<sockaddr_in6>.size)
            guard getnameinfo(addr, len, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let name = String(cString: ptr.pointee.ifa_name)
            result[name, default: []].append(String(cString: host))
        }
        return result
    }
}
