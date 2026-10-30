import AppKit

/// Developer aid: `BAM_RESIZE_BENCH=<report file>` resizes the main window through a sweep of sizes on
/// each screen (`BAM_SNAPSHOT_SECTIONS` limits them), timing every frame's synchronous layout + display,
/// writes median / p95 / max frame times to the report, restores the window and quits.
/// Used by scripts/resize-bench.sh and AppResizeTests. 60 fps leaves 16.7 ms per frame.
@MainActor
enum ResizeBench {
    static func runIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let reportPath = env["BAM_RESIZE_BENCH"] else { return }
        let sections = env["BAM_SNAPSHOT_SECTIONS"].map { $0.split(separator: ",").compactMap { AppSection(rawValue: String($0)) } }
            ?? AppSection.allCases
        let frames = Int(env["BAM_RESIZE_FRAMES"] ?? "") ?? 150
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 500 }) else {
                try? "no main window\n".write(toFile: reportPath, atomically: true, encoding: .utf8)
                NSApp.terminate(nil)
                return
            }
            let original = window.frame
            var lines = ["# screen frames median_ms p95_ms max_ms over_16.7ms"]
            for section in sections {
                DebugSnapshot.store?.section = section
                window.setFrame(original, display: true)
                try? await Task.sleep(for: .seconds(2.2))
                // Same state a real drag produces, so the benchmark measures what users get.
                DebugSnapshot.store?.simulatedLiveResize = true
                var times: [Double] = []
                for i in 0..<frames {
                    // Triangle wave between the minimum size and +600 × +400 pt, like a drag back and forth.
                    let phase = Double(i % 60) / 60
                    let t = phase < 0.5 ? phase * 2 : (1 - phase) * 2
                    var frame = original
                    frame.size = CGSize(width: 900 + 600 * t, height: 600 + 400 * t)
                    let start = CACurrentMediaTime()
                    window.setFrame(frame, display: true)
                    times.append((CACurrentMediaTime() - start) * 1000)
                    // Let the run loop breathe like it would between drag events.
                    try? await Task.sleep(for: .milliseconds(4))
                }
                DebugSnapshot.store?.simulatedLiveResize = false
                let sorted = times.sorted()
                let median = sorted[sorted.count / 2]
                let p95 = sorted[Int(Double(sorted.count - 1) * 0.95)]
                let over = times.filter { $0 > 16.7 }.count
                lines.append(String(format: "%@ %d %.1f %.1f %.1f %d", section.rawValue, frames, median, p95, sorted.last ?? 0, over))
            }
            window.setFrame(original, display: true)
            try? (lines.joined(separator: "\n") + "\n").write(toFile: reportPath, atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
    }
}
