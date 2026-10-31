import XCTest
@testable import BetterActivityMonitor

final class MenuBarMetricTests: XCTestCase {
    func testItemsRoundTripThroughRawValue() {
        var items = MenuBarItems.default
        items.entries.swapAt(0, 3)
        items.entries[1].enabled.toggle()
        XCTAssertEqual(MenuBarItems(rawValue: items.rawValue), items)
        XCTAssertEqual(MenuBarItems.default.rawValue, "cpu,memory,-gpu,-disk,-battery,-temperature,-network")
    }

    func testParsingDropsDuplicatesAndAppendsMissingMetricsHidden() {
        let items = MenuBarItems(rawValue: "network,cpu,network,bogus")!
        XCTAssertEqual(items.enabled, [.network, .cpu])
        XCTAssertEqual(items.entries.map(\.metric).count, MenuBarMetric.allCases.count)
        XCTAssertEqual(items.entries[2...].filter(\.enabled), [])
    }

    func testMigrationCarriesOverOldToggles() {
        XCTAssertEqual(MenuBarItems.migrated(cpu: false, memory: true, network: true).enabled, [.memory, .network])
    }

    func testMigrationFromDefaultsRunsOnceAndRemovesOldKeys() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "MenuBarMetricTests"))
        defaults.removePersistentDomain(forName: "MenuBarMetricTests")
        defaults.set(false, forKey: "menuBarShowsCPU")
        defaults.set(true, forKey: "menuBarShowsNetwork")
        Defaults.migrateMenuBarToggles(defaults)
        XCTAssertEqual(MenuBarItems(rawValue: defaults.string(forKey: SettingsKey.menuBarItems) ?? "")?.enabled, [.memory, .network])
        XCTAssertNil(defaults.object(forKey: "menuBarShowsCPU"))
        defaults.removePersistentDomain(forName: "MenuBarMetricTests")
    }

    func testUnavailableMetricsHaveNoReading() {
        let inputs = MenuBarInputs(cpu: 0.5, memory: 0.5)
        for metric in [MenuBarMetric.gpu, .disk, .battery, .temperature] {
            XCTAssertNil(inputs.reading(metric, fahrenheit: false), "\(metric)")
        }
        XCTAssertEqual(inputs.reading(.cpu, fahrenheit: false)?.lines, ["50%"])
        XCTAssertNil(inputs.reading(.network, fahrenheit: false)?.fraction)
    }

    func testReadingsClampAndConvertTemperature() {
        let inputs = MenuBarInputs(cpu: 1.4, memory: -0.1, temperature: 50)
        XCTAssertEqual(inputs.reading(.cpu, fahrenheit: false)?.lines, ["100%"])
        XCTAssertEqual(inputs.reading(.memory, fahrenheit: false)?.fraction, 0)
        XCTAssertEqual(inputs.reading(.temperature, fahrenheit: true)?.lines, ["122°"])
        XCTAssertEqual(inputs.reading(.temperature, fahrenheit: true)?.fraction, 0.5)
    }

    func testRateStaysShort() {
        XCTAssertEqual(MenuBarBytes.format(0), "0B")
        XCTAssertEqual(MenuBarBytes.format(999), "999B")
        XCTAssertEqual(MenuBarBytes.format(1023.9), "1.0K")
        XCTAssertEqual(MenuBarBytes.format(48 * 1024), "48K")
        XCTAssertEqual(MenuBarBytes.format(9.96 * 1024 * 1024), "10M")
        XCTAssertEqual(MenuBarBytes.format(3.4 * 1024 * 1024), "3.4M")
        var value = 1.0
        while value < 1e15 {
            XCTAssertLessThanOrEqual(MenuBarBytes.format(value).count, 4, "\(value)")
            value *= 1.37
        }
    }

    /// The reserved width must fit every value, or the item would grow and shift its neighbours.
    @MainActor func testReservedWidthFitsEveryValue() {
        let font = NSFont.monospacedDigitSystemFont(ofSize: MenuBarGlyph.fontSize, weight: .regular)
        func width(_ s: String) -> CGFloat { (s as NSString).size(withAttributes: [.font: font]).width }
        let percentWidth = TextWidth.max(MenuBarMetric.cpu.widestTexts(.percent), size: MenuBarGlyph.fontSize)
        for p in 0...100 { XCTAssertLessThanOrEqual(width("\(p)%"), percentWidth) }
        let tempWidth = TextWidth.max(MenuBarMetric.temperature.widestTexts(.percent), size: MenuBarGlyph.fontSize)
        for t in 0...250 { XCTAssertLessThanOrEqual(width("\(t)°"), tempWidth) }

        let small = NSFont.monospacedDigitSystemFont(ofSize: MenuBarGlyph.smallFontSize, weight: .medium)
        let rateWidth = TextWidth.max(MenuBarMetric.network.widestTexts(.percent), size: MenuBarGlyph.smallFontSize, weight: .medium)
        var value = 1.0
        while value < 1e13 {
            for arrow in ["↓", "↑"] {
                let s = arrow + MenuBarBytes.format(value)
                XCTAssertLessThanOrEqual((s as NSString).size(withAttributes: [.font: small]).width, rateWidth, s)
            }
            value *= 1.21
        }
    }

    func testAbsoluteValuesFallBackToPercentages() {
        let full = MenuBarInputs(cpu: 0.5, memory: 0.5, gpu: 0.2, disk: 0.5, battery: 0.8, load: 3.456,
                                 memoryUsed: 12.4 * 1_073_741_824, diskUsed: 412 * 1_073_741_824,
                                 gpuMemory: 1.5 * 1_073_741_824, batteryMinutes: 192)
        XCTAssertEqual(full.reading(.cpu, fahrenheit: false)?.absolute, ["3.5"])
        XCTAssertEqual(full.reading(.memory, fahrenheit: false)?.absolute, ["12G"])
        XCTAssertEqual(full.reading(.disk, fahrenheit: false)?.absolute, ["412G"])
        XCTAssertEqual(full.reading(.gpu, fahrenheit: false)?.absolute, ["1.5G"])
        XCTAssertEqual(full.reading(.battery, fahrenheit: false)?.absolute, ["3:12"])
        let bare = MenuBarInputs(cpu: 0.5, memory: 0.5, gpu: 0.2, battery: 0.8)
        XCTAssertEqual(bare.reading(.gpu, fahrenheit: false)?.absolute, ["20%"])
        XCTAssertEqual(bare.reading(.battery, fahrenheit: false)?.absolute, ["80%"])
    }

    func testOldValuesStyleReadsAsPercentages() {
        XCTAssertEqual(MenuBarStyle(rawValue: "values"), .percent)
    }

    @MainActor func testAbsoluteReservedWidthFitsEveryValue() {
        let size = MenuBarGlyph.fontSize
        let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
        func width(_ s: String) -> CGFloat { (s as NSString).size(withAttributes: [.font: font]).width }
        var load = 0.0
        while load < 500 {
            XCTAssertLessThanOrEqual(width(MenuBarBytes.load(load)), TextWidth.max(MenuBarMetric.cpu.widestTexts(.absolute), size: size))
            load += 0.37
        }
        var bytes = 1.0
        while bytes < 1e15 {
            XCTAssertLessThanOrEqual(width(MenuBarBytes.format(bytes)), TextWidth.max(MenuBarMetric.memory.widestTexts(.absolute), size: size))
            bytes *= 1.21
        }
        for minutes in stride(from: 0, to: 6000, by: 7) {
            XCTAssertLessThanOrEqual(width(String(format: "%d:%02d", minutes / 60, minutes % 60)),
                                     TextWidth.max(MenuBarMetric.battery.widestTexts(.absolute), size: size))
        }
    }
}
