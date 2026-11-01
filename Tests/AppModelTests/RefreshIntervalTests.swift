import Foundation
import SwiftUI
import XCTest
@testable import BetterActivityMonitor

final class RefreshIntervalTests: XCTestCase {
    func testStepsMoveThroughThePresets() {
        XCTAssertEqual(RefreshInterval.step(1000, faster: true), 500)
        XCTAssertEqual(RefreshInterval.step(1000, faster: false), 2000)
        XCTAssertEqual(RefreshInterval.step(500, faster: true), 500, "clamped")
        XCTAssertEqual(RefreshInterval.step(60_000, faster: false), 60_000)
        XCTAssertEqual(RefreshInterval.step(3000, faster: false), 5000, "old values snap to a preset first")
    }

    func testLabels() {
        XCTAssertEqual(RefreshInterval.label(500), "500 ms")
        XCTAssertEqual(RefreshInterval.label(30_000), "30 s")
        XCTAssertEqual(RefreshInterval.label(60_000), "1 min")
    }

    func testSettingStoresSeconds() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "RefreshIntervalTests"))
        defer { defaults.removePersistentDomain(forName: "RefreshIntervalTests") }
        RefreshInterval.set(2000, defaults)
        XCTAssertEqual(defaults.double(forKey: SettingsKey.refreshInterval), 2.0)
        RefreshInterval.set(20, defaults)
        XCTAssertEqual(defaults.double(forKey: SettingsKey.refreshInterval), 0.5)
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
