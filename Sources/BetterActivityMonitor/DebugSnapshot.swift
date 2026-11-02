import AppKit

/// Developer aid: `BAM_SNAPSHOT_DIR=/some/dir` renders every section of the main window to
/// `<section>-<w>x<h>.png` for each size in `BAM_SNAPSHOT_SIZES` (default "1280x820"), writes the
/// `LayoutAudit` findings to `layout-report.txt` (issue lines; "#" lines are per-screen summaries), restores the window frame and quits.
/// `BAM_SNAPSHOT_SECTIONS` (comma separated) limits the sections; `BAM_SNAPSHOT_SIDEBAR_CYCLE=1` collapses and
/// re-expands the sidebar before capturing. Used by scripts/check-layout.sh.
@MainActor
enum DebugSnapshot {
    static weak var store: SystemStore?

    static func runIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["BAM_SNAPSHOT_DIR"] else { return }
        let sizes = (env["BAM_SNAPSHOT_SIZES"] ?? "1280x820").split(separator: ",").compactMap { spec -> CGSize? in
            let parts = spec.lowercased().split(separator: "x").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            return parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : nil
        }
        let sections = env["BAM_SNAPSHOT_SECTIONS"].map { $0.split(separator: ",").compactMap { AppSection.resolve(String($0)) } }
            ?? AppSection.allCases
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard let window = mainWindow() else {
                write("no main window found\n", to: dir)
                NSApp.terminate(nil)
                return
            }
            let originalFrame = window.frame
            if env["BAM_SNAPSHOT_SIDEBAR_CYCLE"] != nil {
                // Collapse and re-expand the sidebar first: checks that showing it pushes the content aside.
                for _ in 0..<2 {
                    NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
                    try? await Task.sleep(for: .seconds(1.5))
                }
            }
            var report: [String] = []
            for size in sizes {
                window.setContentSize(size)
                for section in sections {
                    // No reset between screens: views that didn't change wouldn't report again.
                    // Cards remove themselves when they disappear.
                    store?.section = section
                    // Two refresh ticks so live data (and its layout) has settled.
                    try? await Task.sleep(for: .seconds(2.2))
                    let label = "\(Int(size.width))x\(Int(size.height))"
                    capture(window, to: URL(fileURLWithPath: dir).appendingPathComponent("\(section.rawValue)-\(label).png"))
                    let visible = window.contentView?.bounds ?? .zero
                    let issues = LayoutAudit.issues(visible: visible)
                    let cards = LayoutAudit.cardNames
                    report.append("# \(label) \(section.rawValue): \(issues.count) issues in \(cards.count) cards: \(cards.joined(separator: ", "))")
                    if cards.isEmpty && section != .processes {
                        report.append("\(label) \(section.rawValue): no cards reported, audit is blind")
                    }
                    report += issues.map { "\(label) \(section.rawValue): \($0)" }
                }
            }
            window.setFrame(originalFrame, display: false)
            // Lines starting with "#" are informational; any other line is a layout issue.
            write(report.joined(separator: "\n") + "\n", to: dir)
            NSApp.terminate(nil)
        }
    }

    private static func mainWindow() -> NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.contentView != nil && $0.frame.width > 500 }
    }

    private static func write(_ text: String, to dir: String) {
        try? text.write(to: URL(fileURLWithPath: dir).appendingPathComponent("layout-report.txt"), atomically: true, encoding: .utf8)
    }

    static func capture(_ window: NSWindow, to url: URL) {
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
