// Renders every desktop widget to a PNG (2x, transparent corners) for the README and the website:
//   swift run widgetshots [output-dir]      (default: docs/screenshots/widgets)
// Besides one PNG per widget it writes grid.png: the widgets tiled on the desktop's widget grid, as the README shows them.
// It compiles the real widget views from Sources/BAMWidgets and feeds them the widgets' placeholder data, so the
// numbers are the same on every run. The desktop's widget frame (background, margins, corner radius) is drawn here.
import AppKit
import SwiftUI
import WidgetKit

/// Widget sizes and content margins on the macOS desktop, in points.
enum Family: String {
    case small, medium, large, extraLarge

    var size: CGSize {
        switch self {
        case .small: CGSize(width: 164, height: 164)
        case .medium: CGSize(width: 344, height: 164)
        case .large: CGSize(width: 344, height: 344)
        case .extraLarge: CGSize(width: 704, height: 344)
        }
    }

    var widgetFamily: WidgetFamily {
        switch self {
        case .small: .systemSmall
        case .medium: .systemMedium
        case .large: .systemLarge
        case .extraLarge: .systemExtraLarge
        }
    }
}

/// The desktop's widget frame around a widget view.
struct Frame<Content: View>: View {
    var family: Family
    @ViewBuilder var content: Content

    var body: some View {
        content
            .environment(\.widgetFamilyOverride, family.widgetFamily)
            .padding(16)
            .frame(width: family.size.width, height: family.size.height)
            .background(Color(white: 0.155))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
            )
            .environment(\.colorScheme, .dark)
    }
}

/// The README/website mosaic: a 6 × 5 grid of small-widget cells (164 pt, 16 pt apart), like the desktop's.
/// Each entry is a shot name and its top-left cell (column, row).
let gridLayout: [(name: String, column: Int, row: Int)] = [
    ("overview-extralarge", 0, 0), ("stats-large", 4, 0),
    ("overview-large", 0, 2), ("rings-medium", 2, 2), ("battery-medium", 4, 2),
    ("memory-medium", 2, 3), ("storage-medium", 4, 3),
    ("stats-medium", 0, 4), ("uptime-small", 2, 4), ("rings-small", 3, 4), ("battery-small", 4, 4), ("storage-small", 5, 4),
]
let cell: CGFloat = 164, gap: CGFloat = 16

let system = SystemEntry.placeholder
let all = WidgetMetric.allCases

@MainActor
let shots: [(String, Family, AnyView)] = [
    ("overview-extralarge", .extraLarge, AnyView(OverviewView(entry: system))),
    ("overview-large", .large, AnyView(OverviewView(entry: system))),
    ("stats-large", .large, AnyView(ActivityStatsView(entry: MetricsEntry(system: system, metrics: all)))),
    ("stats-medium", .medium, AnyView(ActivityStatsView(entry: MetricsEntry(system: system, metrics: all)))),
    ("rings-medium", .medium, AnyView(SystemRingsView(entry: RingsEntry(system: system, metrics: WidgetMetric.defaults)))),
    ("rings-small", .small, AnyView(SystemRingsView(entry: RingsEntry(system: system, metrics: WidgetMetric.defaults)))),
    ("memory-medium", .medium, AnyView(MemoryWidgetView(entry: system))),
    ("memory-small", .small, AnyView(MemoryWidgetView(entry: system))),
    ("storage-medium", .medium, AnyView(StorageWidgetView(entry: system))),
    ("storage-small", .small, AnyView(StorageWidgetView(entry: system))),
    ("battery-medium", .medium, AnyView(BatteryWidgetView(entry: system))),
    ("battery-small", .small, AnyView(BatteryWidgetView(entry: system))),
    ("uptime-small", .small, AnyView(UptimeWidgetView(entry: system))),
]

@MainActor
func render() throws {
    let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "docs/screenshots/widgets")
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for (name, family, view) in shots {
        try save(Frame(family: family) { view }, to: out.appendingPathComponent("\(name).png"))
    }

    let byName = Dictionary(uniqueKeysWithValues: shots.map { ($0.0, ($0.1, $0.2)) })
    let grid = ZStack(alignment: .topLeading) {
        ForEach(gridLayout, id: \.name) { item in
            if let (family, view) = byName[item.name] {
                Frame(family: family) { view }
                    .offset(x: CGFloat(item.column) * (cell + gap), y: CGFloat(item.row) * (cell + gap))
            }
        }
    }
    .frame(width: 6 * cell + 5 * gap, height: 5 * cell + 4 * gap, alignment: .topLeading)
    try save(grid, to: out.appendingPathComponent("grid.png"))
}

@MainActor
func save(_ view: some View, to file: URL) throws {
    let renderer = ImageRenderer(content: view.environment(\.locale, Locale(identifier: "en_US")))
    renderer.scale = 2
    guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
    let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    try png?.write(to: file)
    print("\(file.path)  \(image.width)×\(image.height)")
}

@main
struct WidgetShots {
    @MainActor static func main() throws {
        // English number formats (16.0 GB, not 16,0 GB) whatever this Mac's region, for the English README and site.
        UserDefaults.standard.setVolatileDomain(["AppleLocale": "en_US", "AppleLanguages": ["en"]], forName: UserDefaults.argumentDomain)
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        try render()
    }
}
