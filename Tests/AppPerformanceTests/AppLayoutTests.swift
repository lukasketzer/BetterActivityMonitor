import Foundation
import XCTest

/// Renders every screen of the real app at several window sizes and fails on layout bugs found by the
/// app's LayoutAudit (overlapping cards, content spilling out of a card, horizontal clipping).
/// Opt-in because it opens the GUI app for about a minute:
///   scripts/bundle.sh && BAM_APP_LAYOUT=1 swift test -c release --filter AppLayoutTests
final class AppLayoutTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func testNoLayoutIssuesAtCommonSizes() throws {
        guard ProcessInfo.processInfo.environment["BAM_APP_LAYOUT"] != nil else {
            throw XCTSkip("set BAM_APP_LAYOUT=1 to run app layout tests")
        }
        let out = Self.root.appendingPathComponent("build/layout")
        let p = Process()
        p.executableURL = Self.root.appendingPathComponent("scripts/check-layout.sh")
        p.arguments = [out.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        try p.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        print(output)
        XCTAssertEqual(p.terminationStatus, 0, "layout issues (screenshots in \(out.path)):\n\(output)")
    }
}
