import Foundation
import SwiftUI
import XCTest
@testable import BetterActivityMonitor

final class RefreshIntervalTests: XCTestCase {
    func testStepsUseAFinerGridBelowOneSecond() {
        XCTAssertEqual(RefreshInterval.step(1000, faster: true), 900)
        XCTAssertEqual(RefreshInterval.step(900, faster: false), 1000)
        XCTAssertEqual(RefreshInterval.step(1000, faster: false), 1500)
        XCTAssertEqual(RefreshInterval.step(1500, faster: true), 1000)
        XCTAssertEqual(RefreshInterval.step(1250, faster: true), 1000, "snaps onto the grid")
        XCTAssertEqual(RefreshInterval.step(1250, faster: false), 1500)
        XCTAssertEqual(RefreshInterval.step(950, faster: true), 900)
        XCTAssertEqual(RefreshInterval.step(100, faster: true), 100, "clamped")
        XCTAssertEqual(RefreshInterval.step(10_000, faster: false), 10_000)
    }

    func testParsingAcceptsUnitsAndClamps() {
        XCTAssertEqual(RefreshInterval.parse("250"), 250)
        XCTAssertEqual(RefreshInterval.parse(" 250 ms"), 250)
        XCTAssertEqual(RefreshInterval.parse("1.5s"), 1500)
        XCTAssertEqual(RefreshInterval.parse("2 s"), 2000)
        XCTAssertEqual(RefreshInterval.parse("5"), 100, "snaps to the lower limit")
        XCTAssertEqual(RefreshInterval.parse("99999"), 10_000)
        XCTAssertNil(RefreshInterval.parse("fast"))
    }

    func testSettingStoresSeconds() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "RefreshIntervalTests"))
        defer { defaults.removePersistentDomain(forName: "RefreshIntervalTests") }
        RefreshInterval.set(250, defaults)
        XCTAssertEqual(defaults.double(forKey: SettingsKey.refreshInterval), 0.25)
        RefreshInterval.set(20, defaults)
        XCTAssertEqual(defaults.double(forKey: SettingsKey.refreshInterval), 0.1)
    }
}

final class SectionShortcutTests: XCTestCase {
    func testSectionsGetCommandDigits() {
        XCTAssertEqual(AppSection.allCases.count, 9)
        XCTAssertEqual(AppSection.shortcut(index: 0), KeyEquivalent("1"))
        XCTAssertEqual(AppSection.shortcut(index: 8), KeyEquivalent("9"))
        XCTAssertEqual(AppSection.shortcut(index: 9), KeyEquivalent("0"), "a tenth section must not trap")
    }
}
