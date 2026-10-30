import XCTest
@testable import BetterActivityMonitor

final class FormatTests: XCTestCase {
    func testBytesPicksUnitAndPrecision() {
        XCTAssertEqual(Fmt.bytes(UInt64(0)), "0 B")
        XCTAssertEqual(Fmt.bytes(UInt64(1023)), "1023 B")
        XCTAssertEqual(Fmt.bytes(UInt64(1024)), "1.00 KB")
        XCTAssertEqual(Fmt.bytes(UInt64(15 * 1024)), "15.0 KB")
        XCTAssertEqual(Fmt.bytes(UInt64(150 * 1024 * 1024)), "150 MB")
        XCTAssertEqual(Fmt.bytes(UInt64(48) << 30), "48.0 GB")
    }

    func testBytesClampsNegativesAndCapsAtPetabytes() {
        XCTAssertEqual(Fmt.bytes(-5.0), "0 B")
        XCTAssertEqual(Fmt.bytes(Double(UInt64(2048)) * pow(1024, 5)), "2048 PB")
    }

    func testRateAppendsPerSecond() {
        XCTAssertEqual(Fmt.rate(2048), "2.00 KB/s")
    }

    func testPercentAndNumber() {
        XCTAssertEqual(Fmt.percent(0.123), "12.3%")
        XCTAssertEqual(Fmt.percent(1, digits: 0), "100%")
        XCTAssertEqual(Fmt.number(3.14159, digits: 2), "3.14")
    }

    func testCompact() {
        XCTAssertEqual(Fmt.compact(999), "999")
        XCTAssertEqual(Fmt.compact(1500), "1.5K")
        XCTAssertEqual(Fmt.compact(25_000), "25K")
        XCTAssertEqual(Fmt.compact(3_200_000), "3.2M")
    }

    func testDuration() {
        XCTAssertEqual(Fmt.duration(0), "0:00")
        XCTAssertEqual(Fmt.duration(-10), "0:00")
        XCTAssertEqual(Fmt.duration(75), "1:15")
        XCTAssertEqual(Fmt.duration(3 * 3600 + 5 * 60 + 9), "3:05:09")
        XCTAssertEqual(Fmt.duration(7 * 86400 + 13 * 3600 + 14 * 60), "7d 13h 14m")
    }

    func testCPUTimeKeepsHundredths() {
        XCTAssertEqual(Fmt.cpuTime(0), "0:00.00")
        XCTAssertEqual(Fmt.cpuTime(65.5), "1:05.50")
        XCTAssertEqual(Fmt.cpuTime(3600 + 62.25), "1:01:02.25")
    }

    func testTemperature() {
        XCTAssertEqual(Fmt.temperature(95, fahrenheit: false), "95°C")
        XCTAssertEqual(Fmt.temperature(100, fahrenheit: true), "212°F")
    }

    func testMinutes() {
        XCTAssertEqual(Fmt.minutes(45), "45m")
        XCTAssertEqual(Fmt.minutes(60), "1h 0m")
        XCTAssertEqual(Fmt.minutes(135), "2h 15m")
    }
}

final class HistoryTests: XCTestCase {
    let start = Date(timeIntervalSinceReferenceDate: 0)

    func testDropsOldestBeyondCapacity() {
        var history = History(capacity: 3)
        for i in 0..<5 { history.append(Double(i), at: start + Double(i)) }
        XCTAssertEqual(history.values, [2, 3, 4])
        XCTAssertEqual(history.last, 4)
        XCTAssertEqual(history.maxValue, 4)
    }

    func testIDsStayUniqueAfterTrimming() {
        var history = History(capacity: 2)
        for i in 0..<4 { history.append(Double(i), at: start + Double(i)) }
        XCTAssertEqual(Set(history.points.map(\.id)).count, 2)
        XCTAssertEqual(history.points.map(\.id), [2, 3])
    }

    func testNonFiniteValuesBecomeZero() {
        var history = History(capacity: 4)
        history.append(.nan, at: start)
        history.append(.infinity, at: start + 1)
        XCTAssertEqual(history.values, [0, 0])
    }

    func testValueNearPicksClosestPoint() {
        var history = History(capacity: 10)
        XCTAssertNil(history.value(near: start))
        for i in 0..<5 { history.append(Double(i * 10), at: start + Double(i)) }
        XCTAssertEqual(history.value(near: start + 2.4), 20)
        XCTAssertEqual(history.value(near: start + 2.6), 30)
        XCTAssertEqual(history.value(near: start + 100), 40)
    }

    func testEmptyHistory() {
        let history = History(capacity: 5)
        XCTAssertNil(history.last)
        XCTAssertEqual(history.maxValue, 0)
    }
}
