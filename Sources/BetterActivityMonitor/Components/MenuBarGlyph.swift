import AppKit
import SwiftUI

/// The menu bar item's content: one ring or value per metric, side by side. Rendered into an image for the
/// status item (a `MenuBarExtra` label only shows a plain image or text) and shown as-is in the settings preview.
/// Monochrome draws in `.primary`; rendered with a light color scheme that is black, which becomes the template mask.
struct MenuBarGlyph: View {
    var readings: [MenuBarReading]
    var style: MenuBarStyle
    var colored: Bool
    var symbols: Bool
    var theme: Theme

    static let height: CGFloat = 18
    static let ringSize: CGFloat = 16
    static let ringLine: CGFloat = 2.25
    /// Two stacked lines (network) at this size fit the 18 pt height.
    static let smallFontSize: CGFloat = 9
    static let labelFontSize: CGFloat = 10
    static var fontSize: CGFloat { NSFont.menuBarFont(ofSize: 0).pointSize }

    var body: some View {
        HStack(spacing: style == .rings ? (symbols ? 7 : 4) : 7) {
            ForEach(readings, id: \.metric) { reading in
                if reading.text(style).count > 1 {
                    stacked(reading)
                } else if style == .rings, let fraction = reading.fraction {
                    ring(reading, fraction: fraction)
                } else {
                    value(reading)
                }
            }
        }
        .frame(height: Self.height)
        .fixedSize()
    }

    private func tint(_ metric: MenuBarMetric) -> Color { colored ? metric.color(theme) : .primary }

    private func ring(_ reading: MenuBarReading, fraction: Double) -> some View {
        let color = tint(reading.metric)
        return HStack(spacing: 3) {
            // A short caption beside the ring: a symbol inside one is too small to read.
            if symbols {
                Text(reading.metric.shortLabel)
                    .font(.system(size: Self.labelFontSize, weight: .medium))
                    .foregroundStyle(.primary)
            }
            ringShape(color: color, fraction: fraction)
        }
    }

    private func ringShape(color: Color, fraction: Double) -> some View {
        ZStack {
            Circle().stroke(color.opacity(colored ? 0.28 : 0.3), lineWidth: Self.ringLine)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0.001), 1))
                .stroke(color, style: StrokeStyle(lineWidth: Self.ringLine, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(Self.ringLine / 2)
        .frame(width: Self.ringSize, height: Self.ringSize)
    }

    private func value(_ reading: MenuBarReading) -> some View {
        HStack(spacing: 3) {
            if symbols {
                Image(systemName: reading.metric.symbol)
                    .font(.system(size: Self.fontSize - 2, weight: .medium))
                    .foregroundStyle(tint(reading.metric))
            }
            Text(reading.text(style)[0])
                .font(.system(size: Self.fontSize).monospacedDigit())
                // Leading, so the value hugs its symbol; the reserved width keeps the item still.
                .frame(width: TextWidth.max(reading.metric.widestTexts(style), size: Self.fontSize), alignment: .leading)
        }
    }

    /// Network: down over up in small digits, so it is no wider than a percentage.
    private func stacked(_ reading: MenuBarReading) -> some View {
        let width = TextWidth.max(reading.metric.widestTexts(style), size: Self.smallFontSize, weight: .medium)
        return VStack(alignment: .trailing, spacing: -1) {
            ForEach(reading.text(style), id: \.self) { line in
                Text(line).frame(width: width, alignment: .trailing)
            }
        }
        .font(.system(size: Self.smallFontSize, weight: .medium).monospacedDigit())
        .foregroundStyle(colored ? reading.metric.color(theme) : .primary)
    }
}

extension MenuBarMetric {
    /// Caption shown beside a ring.
    var shortLabel: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "MEM"
        case .gpu: "GPU"
        case .disk: "SSD"
        case .battery: "BAT"
        case .temperature: "TMP"
        case .network: "NET"
        }
    }
}

/// Width of the widest string in monospaced-digit system font, cached: the menu bar asks every tick.
@MainActor
enum TextWidth {
    private static var cache: [String: CGFloat] = [:]

    static func max(_ strings: [String], size: CGFloat, weight: NSFont.Weight = .regular) -> CGFloat {
        let key = "\(strings)|\(size)|\(weight.rawValue)"
        if let width = cache[key] { return width }
        let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        let width = strings.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        cache[key] = ceil(width) + 1
        return cache[key]!
    }
}

/// Renders the glyph into the status item image, reusing the last image while nothing visible changed.
@MainActor
enum MenuBarRenderer {
    private static var lastKey = ""
    private static var lastImage: NSImage?

    static func image(_ glyph: MenuBarGlyph, scale: CGFloat, colorScheme: ColorScheme) -> NSImage? {
        guard !glyph.readings.isEmpty else { return nil }
        let values = glyph.readings.map { r in
            "\(r.metric.rawValue)=\(r.fraction.map { Int(($0 * 100).rounded()) } ?? -1):\(r.text(glyph.style).joined(separator: "/"))"
        }
        let key = [glyph.style.rawValue, "\(glyph.colored)", "\(glyph.symbols)", glyph.theme.id, "\(scale)",
                   glyph.colored ? "\(colorScheme)" : "", values.joined(separator: ",")].joined(separator: "|")
        if key == lastKey, let lastImage { return lastImage }
        let image = render(glyph, scale: scale, colorScheme: colorScheme)
        lastKey = key
        lastImage = image
        return image
    }

    static func render(_ glyph: MenuBarGlyph, scale: CGFloat, colorScheme: ColorScheme) -> NSImage? {
        // A template is a mask: draw it black and let the system tint it like its own icons.
        let renderer = ImageRenderer(content: glyph.environment(\.colorScheme, glyph.colored ? colorScheme : .light))
        renderer.scale = scale
        let image = renderer.nsImage
        image?.isTemplate = !glyph.colored
        return image
    }
}
