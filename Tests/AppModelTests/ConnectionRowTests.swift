import Foundation
import XCTest
@testable import BetterActivityMonitor
@testable import SystemKit

final class ConnectionRowTests: XCTestCase {
    let now = Date(timeIntervalSinceReferenceDate: 1000)

    // Addresses from documentation ranges (RFC 5737 / RFC 3849).
    func flow(pid: pid_t = 100, proto: String = "tcp", v6: Bool = false, local: Endpoint, remote: Endpoint,
              state: String = "Established", bytesIn: UInt64 = 0, bytesOut: UInt64 = 0, rateIn: Double = 0,
              rateOut: Double = 0, rtt: Double? = nil, age: TimeInterval = 0) -> NetworkFlow {
        NetworkFlow(
            id: "\(pid) \(local) \(remote)", pid: pid, processName: "proc", proto: proto, isIPv6: v6,
            local: local, remote: remote, interface: "en0", state: state, bytesIn: bytesIn, bytesOut: bytesOut,
            rateIn: rateIn, rateOut: rateOut, retransmits: 0, rtt: rtt, firstSeen: now - age
        )
    }

    lazy var https = flow(local: Endpoint(host: "192.168.0.10", port: 50000), remote: Endpoint(host: "203.0.113.7", port: 443),
                          bytesIn: 900, bytesOut: 100, rateIn: 10, rateOut: 2, rtt: 20, age: 30)
    lazy var listener = flow(pid: 200, local: Endpoint(host: "::1", port: 8021), remote: Endpoint(host: "*", port: nil),
                             state: "Listen")
    lazy var quic = flow(proto: "quic", v6: true, local: Endpoint(host: "2001:db8::1", port: 62230),
                         remote: Endpoint(host: "2001:db8:a41::d", port: 443), rateIn: 5, rateOut: 1, rtt: 50, age: 10)

    // MARK: rows

    func testFlowRowFormatsProtocolAddressesAndTotals() {
        let row = ConnectionRow.flow(https, process: "Safari", now: now)
        XCTAssertEqual(row.proto, "TCP4")
        XCTAssertEqual(row.local, "192.168.0.10:50000")
        XCTAssertEqual(row.remote, "203.0.113.7:443")
        XCTAssertEqual(row.total, 1000)
        XCTAssertEqual(row.rtt, 20)
        XCTAssertEqual(row.age, 30)
        XCTAssertEqual(row.process, "Safari")
    }

    func testIPv6AndWildcardRemote() {
        XCTAssertEqual(ConnectionRow.flow(quic, process: "p", now: now).proto, "QUIC6")
        XCTAssertEqual(ConnectionRow.flow(quic, process: "p", now: now).remote, "[2001:db8:a41::d]:443")
        XCTAssertEqual(ConnectionRow.flow(listener, process: "p", now: now).remote, "—")
    }

    func testUnknownRTTSortsLowest() {
        XCTAssertEqual(ConnectionRow.flow(listener, process: "p", now: now).rtt, -1)
    }

    func testGroupSumsChildren() {
        let children = [https, quic].map { ConnectionRow.flow($0, process: "Safari", now: now) }
        let group = ConnectionRow.group(pid: 100, process: "Safari", children: children)
        XCTAssertEqual(group.id, "pid 100")
        XCTAssertEqual(group.remote, "2 connections")
        XCTAssertEqual(group.rateIn, 15)
        XCTAssertEqual(group.rateOut, 3)
        XCTAssertEqual(group.rtt, 50)
        XCTAssertEqual(group.age, 30)
        XCTAssertEqual(group.children?.count, 2)

        let single = ConnectionRow.group(pid: 100, process: "Safari", children: [children[0]])
        XCTAssertEqual(single.remote, "1 connection")
    }

    // MARK: filter

    func testEmptyFilter() {
        XCTAssertTrue(ConnectionFilter("").isEmpty)
        XCTAssertTrue(ConnectionFilter("   ").matches(https, process: "Safari"))
    }

    func testFreeTextMatchesProcessAddressesAndService() {
        XCTAssertTrue(ConnectionFilter("safari").matches(https, process: "Safari"))
        XCTAssertTrue(ConnectionFilter("203.0.113").matches(https, process: "x"))
        XCTAssertTrue(ConnectionFilter("https").matches(https, process: "x"))
        XCTAssertFalse(ConnectionFilter("chrome").matches(https, process: "Safari"))
    }

    func testKeyedTokens() {
        XCTAssertTrue(ConnectionFilter("proc:saf").matches(https, process: "Safari"))
        XCTAssertTrue(ConnectionFilter("pid:100").matches(https, process: "x"))
        XCTAssertFalse(ConnectionFilter("pid:10").matches(https, process: "x"), "pid matches exactly")
        XCTAssertTrue(ConnectionFilter("port:443").matches(https, process: "x"))
        XCTAssertTrue(ConnectionFilter("port:50000").matches(https, process: "x"), "local port counts too")
        XCTAssertTrue(ConnectionFilter("host:203.0").matches(https, process: "x"))
        XCTAssertTrue(ConnectionFilter("state:est").matches(https, process: "x"))
        XCTAssertTrue(ConnectionFilter("proto:quic").matches(quic, process: "x"))
        XCTAssertFalse(ConnectionFilter("proto:udp").matches(quic, process: "x"))
        XCTAssertTrue(ConnectionFilter("scope:loop").matches(listener, process: "x"))
    }

    func testAllTokensMustMatchAndKeysAreCaseInsensitive() {
        XCTAssertTrue(ConnectionFilter("PROC:Safari port:443").matches(https, process: "Safari"))
        XCTAssertFalse(ConnectionFilter("proc:safari port:80").matches(https, process: "Safari"))
    }

    func testUnknownKeyIsFreeText() {
        XCTAssertFalse(ConnectionFilter("foo:bar").matches(https, process: "Safari"))
        XCTAssertTrue(ConnectionFilter("foo:bar").matches(https, process: "foo:bar daemon"))
    }
}
