import AppKit
import SwiftUI

/// Developer aid: `BAM_MENUBAR_SNAPSHOT_DIR=/some/dir` renders the menu bar item in every style, coloring and
/// appearance at 0, 50 and 100 % into `menubar-<style>-<scheme>.png`, checks that each image is
/// `MenuBarGlyph.height` tall and keeps its width as values change, writes the findings to `menubar-report.txt`
/// (one line per issue; "#" lines are summaries) and quits. Used by scripts/check-menubar.sh.
@MainActor
enum MenuBarSnapshot {
    static func runIfRequested() {
        guard let dir = ProcessInfo.processInfo.environment["BAM_MENUBAR_SNAPSHOT_DIR"] else { return }
        let url = URL(fileURLWithPath: dir)
        var report: [String] = []
        let levels = [0.0, 0.5, 1.0]
        let metricSets = (1...MenuBarMetric.allCases.count).map { Array(MenuBarMetric.allCases.prefix($0)) }

        for style in MenuBarStyle.allCases {
            for scheme in [ColorScheme.light, .dark] {
                var rows: [SheetRow] = []
                for colored in [false, true] {
                    for symbols in [true, false] {
                        for metrics in metricSets {
                            var images: [NSImage] = []
                            for level in levels {
                                let glyph = MenuBarGlyph(readings: readings(metrics, level: level), style: style,
                                                         colored: colored, symbols: symbols, theme: .system)
                                guard let image = MenuBarRenderer.render(glyph, scale: 2, colorScheme: scheme) else {
                                    report.append("\(style) \(metrics.count) metrics: render failed")
                                    continue
                                }
                                images.append(image)
                            }
                            let name = "\(style.rawValue) colored=\(colored) symbols=\(symbols) metrics=\(metrics.count)"
                            if scheme == .light {
                                if let bad = images.first(where: { $0.size.height != MenuBarGlyph.height }) {
                                    report.append("\(name): height \(bad.size.height), expected \(MenuBarGlyph.height)")
                                }
                                let widths = Set(images.map(\.size.width))
                                if widths.count > 1 { report.append("\(name): width changes with value \(widths.sorted())") }
                                report.append("# \(name): \(images.first.map { "\(Int($0.size.width))x\(Int($0.size.height))" } ?? "-")")
                            }
                            rows.append(SheetRow(title: "\(colored ? "color" : "mono") \(symbols ? "sym" : "plain") \(metrics.count)",
                                                 images: images))
                        }
                    }
                }
                let sheet = Sheet(rows: rows, scheme: scheme).environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: sheet)
                renderer.scale = 2
                if let cg = renderer.cgImage,
                   let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
                    try? png.write(to: url.appendingPathComponent("menubar-\(style.rawValue)-\(scheme == .dark ? "dark" : "light").png"))
                }
            }
        }
        // The item renders at most once per sample, so this is its per-tick main-thread cost.
        let glyph = MenuBarGlyph(readings: readings([.cpu, .memory, .gpu, .network], level: 0.5), style: .rings,
                                 colored: false, symbols: true, theme: .system)
        let clock = ContinuousClock()
        let runs = 200
        let elapsed = clock.measure { for _ in 0..<runs { _ = MenuBarRenderer.render(glyph, scale: 2, colorScheme: .light) } }
        report.append("# render: \(String(format: "%.2f", elapsed / .milliseconds(1) / Double(runs))) ms per image (4 metrics)")
        try? (report.joined(separator: "\n") + "\n").write(to: url.appendingPathComponent("menubar-report.txt"),
                                                            atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }

    private static func readings(_ metrics: [MenuBarMetric], level: Double) -> [MenuBarReading] {
        let inputs = MenuBarInputs(cpu: level, memory: level, gpu: level, disk: level, battery: level,
                                   temperature: level * 100, netIn: level * 9.5 * 1024 * 1024, netOut: level * 999 * 1024,
                                   load: level * 88, memoryUsed: level * 64 * 1_073_741_824, diskUsed: level * 994 * 1_073_741_824,
                                   gpuMemory: level * 9.9 * 1_073_741_824, batteryMinutes: Int(level * 600))
        return metrics.compactMap { inputs.reading($0, fahrenheit: false) }
    }

    private struct SheetRow: Identifiable {
        var title: String
        var images: [NSImage]
        var id: String { title }
    }

    /// Images on menu-bar-like strips; templates tinted the way the system tints them.
    private struct Sheet: View {
        var rows: [SheetRow]
        var scheme: ColorScheme

        var body: some View {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                ForEach(rows) { row in
                    GridRow {
                        Text(row.title).font(.system(size: 10).monospaced())
                        ForEach(Array(row.images.enumerated()), id: \.offset) { _, image in
                            Image(nsImage: image)
                                .renderingMode(image.isTemplate ? .template : .original)
                                .foregroundStyle(scheme == .dark ? Color.white : Color.black.opacity(0.85))
                        }
                    }
                }
            }
            .padding(10)
            .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.93))
            .foregroundStyle(scheme == .dark ? Color.white : Color.black)
        }
    }
}
