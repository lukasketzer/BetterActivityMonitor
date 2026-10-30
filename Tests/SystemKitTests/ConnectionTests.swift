import Darwin
import Foundation
import XCTest
@testable import SystemKit

final class NettopParserTests: XCTestCase {
    // Shapes copied from real `nettop -L 1 -n -x` output; addresses replaced with documentation ranges.
    let fixture = """
    time,,interface,state,bytes_in,bytes_out,rx_dupe,rx_ooo,re-tx,rtt_avg,rcvsize,tx_win,tc_class,tc_mgt,cc_algo,P,C,R,W,arch,
    22:25:26.125042,apsd.383,,,92842,234834,82,0,43748,,,,,,,,,,,,
    22:25:26.124535,tcp4 192.168.0.57:64051<->17.242.218.132:5223,en0,Established,92842,234834,82,0,43748,57.53 ms,131072,123008,RD,-,cubic,-,-,-,-,ch,
    22:25:26.125055,mDNSResponder.501,,,295219138,41587659,0,0,0,,,,,,,,,,,,
    22:25:26.124503,udp6 *.5353<->*.*,en0,,129403142,16919388,,,,,786896,,CTL,,,,,,,so,
    22:25:26.124489,udp4 *:5353<->*:*,en0,,165813500,24663915,,,,,786896,,CTL,,,,,,,so,
    22:25:26.125070,Google Chrome H.912,,,12379,5112,0,0,0,,,,,,,,,,,,
    22:25:26.124445,quic6 2001:db8::c1d1.62230<->2001:db8:a41::d.443,en0,,2496,4356,,,,54.06 ms,0,,BE,,,,,,,ch,
    22:25:26.124970,tcp6 fe80::cc9:b137%en0.51757<->fe80::1cc0:c614%en0.49362,en0,Established,30780,36580,0,0,0,38.97 ms,131072,131072,BE,-,cubic,-,-,-,-,so,
    22:21:50.299032,tcp6 ::1.8021<->*.*,lo0,Listen,,,,,,,,,,-,cubic,-,-,-,-,so,
    """

    func testProcessLinesCarryNameAndPid() {
        let parsed = NettopParser.parse(fixture)
        XCTAssertEqual(parsed.processes.map(\.pid), [383, 501, 912])
        XCTAssertEqual(parsed.processes.last?.name, "Google Chrome H", "names may contain spaces and dots before the pid")
        XCTAssertEqual(parsed.processes.first?.bytesOut, 234834)
    }

    func testFlowsBelongToThePrecedingProcess() {
        let flows = NettopParser.parse(fixture).flows
        XCTAssertEqual(flows.count, 6)
        XCTAssertEqual(flows.filter { $0.pid == 501 }.count, 2)
        XCTAssertEqual(flows.filter { $0.pid == 912 }.map(\.processName), ["Google Chrome H", "Google Chrome H", "Google Chrome H"])
    }

    func testIPv4Flow() throws {
        let flow = try XCTUnwrap(NettopParser.parse(fixture).flows.first)
        XCTAssertEqual(flow.proto, "tcp")
        XCTAssertFalse(flow.isIPv6)
        XCTAssertEqual(flow.local, Endpoint(host: "192.168.0.57", port: 64051))
        XCTAssertEqual(flow.remote, Endpoint(host: "17.242.218.132", port: 5223))
        XCTAssertEqual(flow.interface, "en0")
        XCTAssertEqual(flow.state, "Established")
        XCTAssertEqual(flow.bytesIn, 92842)
        XCTAssertEqual(flow.retransmits, 43748)
        XCTAssertEqual(flow.rtt, 57.53)
    }

    func testIPv6QuicAndZones() throws {
        let flows = NettopParser.parse(fixture).flows
        let quic = try XCTUnwrap(flows.first { $0.proto == "quic" })
        XCTAssertTrue(quic.isIPv6)
        XCTAssertEqual(quic.remote, Endpoint(host: "2001:db8:a41::d", port: 443))
        XCTAssertEqual(quic.state, "")

        let linkLocal = try XCTUnwrap(flows.first { $0.local.zone != nil })
        XCTAssertEqual(linkLocal.local, Endpoint(host: "fe80::cc9:b137", zone: "en0", port: 51757))
    }

    func testWildcardsAndListeners() throws {
        let flows = NettopParser.parse(fixture).flows
        let mdns = try XCTUnwrap(flows.first { $0.proto == "udp" && !$0.isIPv6 })
        XCTAssertEqual(mdns.local, Endpoint(host: "*", port: 5353))
        XCTAssertTrue(mdns.remote.isWildcard)

        let listener = try XCTUnwrap(flows.first { $0.state == "Listen" })
        XCTAssertEqual(listener.local, Endpoint(host: "::1", port: 8021))
        XCTAssertNil(listener.rtt)
        XCTAssertEqual(listener.bytesIn, 0, "listening sockets have empty byte columns")
    }

    func testGarbageIsIgnored() {
        let parsed = NettopParser.parse("not,csv\n\n,,,\ntime,,interface\nx,tcp4 nonsense<->,en0,,,,,,,,,")
        XCTAssertTrue(parsed.processes.isEmpty)
        XCTAssertTrue(parsed.flows.isEmpty)
    }
}

final class AddressEnrichmentTests: XCTestCase {
    func testScopes() {
        let cases: [(String, AddressScope)] = [
            ("*", .any), ("0.0.0.0", .any), ("::", .any),
            ("127.0.0.1", .loopback), ("::1", .loopback),
            ("169.254.1.2", .linkLocal), ("fe80::1", .linkLocal),
            ("10.1.2.3", .privateNetwork), ("172.16.0.1", .privateNetwork), ("172.32.0.1", .internet),
            ("192.168.0.57", .privateNetwork), ("100.64.0.1", .privateNetwork), ("fd00::1", .privateNetwork),
            ("224.0.0.251", .multicast), ("ff02::fb", .multicast),
            ("17.242.218.132", .internet), ("2001:db8::1", .internet),
            ("::ffff:192.168.1.1", .privateNetwork),
        ]
        for (host, scope) in cases { XCTAssertEqual(AddressScope(host), scope, host) }
    }

    func testServiceNamesAreLocal() {
        XCTAssertEqual(PortNames.name(for: 443, proto: "tcp"), "HTTPS")
        XCTAssertEqual(PortNames.name(for: 5353, proto: "udp"), "mDNS")
        // From /etc/services, not the built-in table.
        XCTAssertNotNil(PortNames.name(for: 179, proto: "tcp"))
        XCTAssertNil(PortNames.name(for: 61234, proto: "tcp"))
        XCTAssertNil(PortNames.name(for: 8021, proto: "tcp"), "registered high ports are not trusted")
    }

    func testListenerServiceUsesLocalPort() {
        let flow = NetworkFlow(id: "x", pid: 1, processName: "sshd", proto: "tcp", isIPv6: false,
                               local: Endpoint(host: "*", port: 22), remote: Endpoint(host: "*", port: nil),
                               interface: "", state: "Listen", bytesIn: 0, bytesOut: 0, rateIn: 0, rateOut: 0,
                               retransmits: 0, rtt: nil, firstSeen: Date())
        XCTAssertTrue(flow.isListening)
        XCTAssertEqual(flow.service, "SSH")
        XCTAssertEqual(flow.scope, .any)
    }
}

final class ConnectionSamplerTests: XCTestCase {
    func testFastRefreshReusesTheLastNettopRun() throws {
        let sampler = ConnectionSampler()
        sampler.mode = .external
        let start = Date()
        let first = try XCTUnwrap(sampler.sample(now: start))
        let reused = try XCTUnwrap(sampler.sample(now: start.addingTimeInterval(0.25)))
        XCTAssertEqual(first.flows.map(\.id), reused.flows.map(\.id))
        XCTAssertEqual(first.flows.map(\.firstSeen), reused.flows.map(\.firstSeen))

        sampler.mode = .off
        XCTAssertNil(sampler.sample(now: start.addingTimeInterval(0.5)), "off never returns cached data")
    }

    /// End to end against the real nettop: a local listener and a connection to it must show up with our pid.
    func testOwnLoopbackConnectionIsReported() async throws {
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(listener, 0)
        defer { close(listener) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(listener, $0, length) } }
        XCTAssertEqual(listen(listener, 1), 0)
        var bound = sockaddr_in()
        var boundLength = length
        _ = withUnsafeMutablePointer(to: &bound) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listener, $0, &boundLength) } }
        let port = UInt16(bigEndian: bound.sin_port)

        let client = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(client) }
        _ = withUnsafePointer(to: &bound) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(client, $0, length) } }

        let monitor = SystemMonitor()
        await monitor.setConnectionMode(.all)
        let snapshot = await monitor.sample()
        let stats = try XCTUnwrap(snapshot.connections)
        let mine = stats.flows.filter { $0.pid == getpid() }
        XCTAssertTrue(mine.contains { $0.isListening && $0.local.port == port }, "listener on \(port) missing")
        XCTAssertTrue(mine.contains { $0.remote.port == port && $0.state == "Established" }, "connection to \(port) missing")
        XCTAssertTrue(stats.flows.contains { $0.pid != getpid() }, "other processes' flows should be visible without root")

        await monitor.setConnectionMode(.off)
        let off = await monitor.sample()
        XCTAssertNil(off.connections)
    }
}
