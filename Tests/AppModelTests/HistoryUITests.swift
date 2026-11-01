import Foundation
import XCTest
@testable import BetterActivityMonitor
@testable import SystemKit

final class TimelineTests: XCTestCase {
    private func v(_ minute: Int, _ value: Double = 1) -> HistoryValue {
        HistoryValue(date: Date(timeIntervalSince1970: TimeInterval(minute * 60)), value: value)
    }

    func testGapsBreakTheLine() {
        let segments = TimelineSegments.split([v(0), v(1), v(2), v(10), v(11)], maxGap: 150)
        XCTAssertEqual(segments.map(\.count), [3, 2])
        XCTAssertTrue(TimelineSegments.split([], maxGap: 60).isEmpty)
    }

    func testValueLookupStaysInsideTheGap() {
        let values = [v(0, 1), v(1, 2), v(5, 3)]
        XCTAssertEqual(TimelineSegments.value(in: values, at: Date(timeIntervalSince1970: 90), maxGap: 60), 2)
        XCTAssertNil(TimelineSegments.value(in: values, at: Date(timeIntervalSince1970: 200), maxGap: 60), "in the gap")
        XCTAssertNil(TimelineSegments.value(in: values, at: Date(timeIntervalSince1970: -1), maxGap: 60))
    }

    func testRangesUseAboutThreeHundredSixtyMinuteBuckets() {
        XCTAssertEqual(HistoryRange.allCases.first, .live)
        XCTAssertEqual(HistoryRange.hour.bucket, 60)
        XCTAssertEqual(HistoryRange.day.bucket, 240)
        XCTAssertEqual(HistoryRange.month.bucket, 7200)
    }

    func testHistoryIsOffUntilTheUserTurnsItOn() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "HistoryUITests"))
        defer { defaults.removePersistentDomain(forName: "HistoryUITests") }
        XCTAssertFalse(defaults.bool(forKey: SettingsKey.historyEnabled))
        XCTAssertEqual(HistorySettings.retentionDays(defaults), 7)
        defaults.set(30, forKey: SettingsKey.historyRetentionDays)
        XCTAssertEqual(HistorySettings.retentionDays(defaults), 30)
        defaults.set(3, forKey: SettingsKey.historyRetentionDays)
        XCTAssertEqual(HistorySettings.retentionDays(defaults), 7, "only 1, 7 or 30")
    }
}
