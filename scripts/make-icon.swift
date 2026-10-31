// Generates the BetterActivityMonitor app icon.
//
// Usage: swift scripts/make-icon.swift <output-dir>
//   Writes <output-dir>/AppIcon.iconset/*.png and <output-dir>/AppIcon-1024.png (legacy .icns art with
//   margin and shadow), plus <output-dir>/AppIcon-fullbleed-1024.png: the same art filling the whole
//   canvas, unmasked, for the macOS 26+ asset-catalog icon (the system applies mask, shadow and glass).
//   scripts/make-icon.sh wraps this and runs iconutil to produce Resources/AppIcon.icns.
//
// Design ("Silicon package"): a graphite squircle holding an Apple-silicon-style chip package (dark
// substrate with a ring of contact pads, metal lid). The lid's screen shows Activity Monitor's CPU Load
// graph (red = system, blue = user) with a live dot on the newest sample.
// Every size is drawn from vectors; sizes of 32 px and below drop fine detail and use heavier strokes.
//
// Drawing uses SVG-style design coordinates: a 1024 grid, y pointing down, icon body at 100...924.

import AppKit
import CoreGraphics

let canvas: CGFloat = 1024

// MARK: - Helpers

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map { $0.1 } as CFArray,
               locations: stops.map { $0.0 })!
}

/// Continuous-corner rounded rect (squircle-like), approximating Apple's icon shape.
func squircle(_ r: CGRect, radius: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let rad = min(radius, min(r.width, r.height) / 2)
    let e = rad * 1.528665 // corner extent factor used by iOS-style continuous corners
    func corner(_ cx: CGFloat, _ cy: CGFloat, _ dx1: CGFloat, _ dy1: CGFloat, _ dx2: CGFloat, _ dy2: CGFloat) {
        let s = CGPoint(x: cx + dx1 * e, y: cy + dy1 * e)
        let t = CGPoint(x: cx + dx2 * e, y: cy + dy2 * e)
        let c1 = CGPoint(x: cx + dx1 * e * 0.37, y: cy + dy1 * e * 0.37)
        let c2 = CGPoint(x: cx + dx2 * e * 0.37, y: cy + dy2 * e * 0.37)
        p.addLine(to: s)
        p.addCurve(to: t, control1: c1, control2: c2)
    }
    p.move(to: CGPoint(x: r.minX + e, y: r.maxY))
    corner(r.maxX, r.maxY, -1, 0, 0, -1)
    corner(r.maxX, r.minY, 0, 1, -1, 0)
    corner(r.minX, r.minY, 1, 0, 0, 1)
    corner(r.minX, r.maxY, 0, -1, 1, 0)
    p.closeSubpath()
    return p
}

func rounded(_ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: y, width: size, height: size), cornerWidth: r, cornerHeight: r, transform: nil)
}

/// Vertical gradient (top → bottom in design space) filling `path`.
func fill(_ ctx: CGContext, _ path: CGPath, _ stops: [(CGFloat, CGColor)], top: CGFloat, bottom: CGFloat) {
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    ctx.drawLinearGradient(gradient(stops), start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

/// Gradient stroke: the light top edge of the metal parts.
func edge(_ ctx: CGContext, _ path: CGPath, width: CGFloat, top: CGFloat, bottom: CGFloat) {
    ctx.saveGState()
    ctx.addPath(path); ctx.setLineWidth(width); ctx.replacePathWithStrokedPath(); ctx.clip()
    ctx.drawLinearGradient(gradient([(0, rgb(0xFFFFFF, 0.45)), (0.25, rgb(0xFFFFFF, 0.05)), (1, rgb(0xFFFFFF, 0))]),
                           start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom), options: [])
    ctx.restoreGState()
}

/// Blurred shadow of `path` without drawing the path itself: the shape is drawn far off to the side
/// and only its shadow is offset back into place. `device` converts design units to device pixels
/// (shadows are specified in device space and ignore the CTM).
func softShadow(_ ctx: CGContext, _ path: CGPath, sigma: CGFloat, color: CGColor, device: CGFloat) {
    let away: CGFloat = 4000
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: -away * device, height: 0), blur: sigma * 2 * device, color: color)
    var t = CGAffineTransform(translationX: away, y: 0)
    ctx.addPath(path.copy(using: &t)!)
    ctx.setFillColor(rgb(0x000000)); ctx.fillPath()
    ctx.restoreGState()
}

/// Smooth Catmull-Rom curve through the points.
func smooth(_ p: [CGPoint]) -> CGMutablePath {
    let path = CGMutablePath()
    path.move(to: p[0])
    for i in 0..<(p.count - 1) {
        let p0 = i > 0 ? p[i - 1] : p[i], p1 = p[i], p2 = p[i + 1], p3 = i + 2 < p.count ? p[i + 2] : p2
        path.addCurve(to: p2,
                      control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                      control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
    }
    return path
}

// MARK: - CPU Load graph

/// Load samples as fractions of the screen height, oldest first: user (blue) and system (red).
let userLoad: [CGFloat] = [0.17, 0.21, 0.19, 0.27, 0.35, 0.30, 0.41, 0.50, 0.40, 0.46, 0.56, 0.49, 0.54]
let systemLoad: [CGFloat] = [0.08, 0.09, 0.08, 0.12, 0.16, 0.13, 0.18, 0.22, 0.17, 0.20, 0.25, 0.21, 0.23]

/// Draws the stacked load graph into the screen rect `r` and returns the live (newest) sample point.
/// The curve continues past the live dot to the screen edge, like a scrolling graph.
func drawGraph(_ ctx: CGContext, in r: CGRect, lineScale: CGFloat) -> CGPoint {
    let n = userLoad.count
    let step = (r.width - 46) / CGFloat(n - 1)
    func points(_ v: [CGFloat]) -> [CGPoint] {
        v.enumerated().map { CGPoint(x: r.minX + CGFloat($0.offset) * step, y: r.minY + r.height * (1 - $0.element)) }
            + [CGPoint(x: r.maxX + 40, y: r.minY + r.height * (1 - v[n - 1] - 0.03))]
    }
    let total = points(zip(userLoad, systemLoad).map { $0 + $1 }), system = points(systemLoad)
    func area(_ p: [CGPoint]) -> CGPath {
        let a = smooth(p)
        a.addLine(to: CGPoint(x: r.maxX + 40, y: r.maxY + 10))
        a.addLine(to: CGPoint(x: r.minX, y: r.maxY + 10))
        a.closeSubpath()
        return a
    }
    let top = total.map(\.y).min()!, sysTop = system.map(\.y).min()!
    fill(ctx, area(total), [(0, rgb(0x5A97FF)), (1, rgb(0x1E3A8A))], top: top, bottom: r.maxY + 10)
    fill(ctx, area(system), [(0, rgb(0xF25555)), (1, rgb(0x7F1D1D))], top: sysTop, bottom: r.maxY + 10)
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.addPath(smooth(total)); ctx.setStrokeColor(rgb(0xA9CBFF)); ctx.setLineWidth(10 * lineScale); ctx.strokePath()
    ctx.addPath(smooth(system)); ctx.setStrokeColor(rgb(0xFFB0B0)); ctx.setLineWidth(7 * lineScale); ctx.strokePath()
    return total[n - 1]
}

// MARK: - Drawing

func draw(_ ctx: CGContext, pixels: Int, fullBleed: Bool = false) {
    let s = CGFloat(pixels) / canvas
    let small = pixels <= 32
    let tiny = pixels <= 16

    // Flip to design space (y down).
    ctx.translateBy(x: 0, y: CGFloat(pixels)); ctx.scaleBy(x: s, y: -s)
    var device = s
    if fullBleed {
        // The body (100...924) fills the canvas; the system applies mask and shadow.
        let k = canvas / 824
        ctx.scaleBy(x: k, y: k); ctx.translateBy(x: -100, y: -100)
        device *= k
    } else {
        // macOS grid: body raised slightly so the drop shadow has room below.
        ctx.translateBy(x: 0, y: -12)
    }

    let bodyRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let body = fullBleed ? CGPath(rect: bodyRect.insetBy(dx: -2, dy: -2), transform: nil)
                         : squircle(bodyRect, radius: 824 * 0.2245)

    if !fullBleed {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12 * s), blur: 28 * s, color: rgb(0x000000, 0.45))
        ctx.addPath(body); ctx.setFillColor(rgb(0x2A2E35)); ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(body); ctx.clip()

    // Graphite background with a faint blue halo behind the chip.
    fill(ctx, body, [(0, rgb(0x5C626E)), (1, rgb(0x141619))], top: 100, bottom: 924)
    let haloCenter = CGPoint(x: 512, y: 100 + 824 * 0.47)
    ctx.drawRadialGradient(gradient([(0, rgb(0x4F8FF7, 0.28)), (1, rgb(0x4F8FF7, 0))]),
                           startCenter: haloCenter, startRadius: 0, endCenter: haloCenter, endRadius: 412, options: [])

    // Chip shadow.
    softShadow(ctx, CGPath(roundedRect: CGRect(x: 266, y: 322, width: 492, height: 462), cornerWidth: 70, cornerHeight: 70, transform: nil),
               sigma: 22, color: rgb(0x000000, 0.55), device: device)

    // Substrate with a ring of contact pads.
    let substrate = rounded(222, 222, 580, 92)
    fill(ctx, substrate, [(0, rgb(0x3A3F48)), (1, rgb(0x1A1C21))], top: 222, bottom: 802)
    if !tiny { edge(ctx, rounded(224, 224, 576, 90), width: 4, top: 224, bottom: 800) }
    if !small {
        let padGradient = gradient([(0, rgb(0xF3F4F6)), (1, rgb(0x7D8490))])
        for i in 0..<10 {
            let c = 314 + (710 - 314) * CGFloat(i) / 9
            for p in [CGPoint(x: c, y: 252), CGPoint(x: c, y: 772), CGPoint(x: 252, y: c), CGPoint(x: 772, y: c)] {
                ctx.saveGState()
                ctx.addEllipse(in: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18)); ctx.clip()
                let hl = CGPoint(x: p.x - 3, y: p.y - 4)
                ctx.drawRadialGradient(padGradient, startCenter: hl, startRadius: 0, endCenter: hl, endRadius: 14,
                                       options: [.drawsAfterEndLocation])
                ctx.restoreGState()
            }
        }
    }

    // Metal lid: bevelled rim, dark face, inset screen.
    fill(ctx, rounded(286, 286, 452, 70),
         [(0, rgb(0xA7AEB9)), (0.18, rgb(0x5D636D)), (0.7, rgb(0x2A2E35)), (1, rgb(0x17191D))], top: 286, bottom: 738)
    if !tiny { edge(ctx, rounded(287.5, 287.5, 449, 68.5), width: 3, top: 287.5, bottom: 736.5) }
    fill(ctx, rounded(308, 308, 408, 48), [(0, rgb(0x1D2026)), (1, rgb(0x0B0C0F))], top: 308, bottom: 716)

    let screenRect = CGRect(x: 328, y: 328, width: 368, height: 368)
    let screen = rounded(328, 328, 368, 34)
    ctx.saveGState()
    ctx.addPath(screen); ctx.clip()
    ctx.addPath(screen); ctx.setFillColor(rgb(0x04060A)); ctx.fillPath()
    if !small {
        ctx.setStrokeColor(rgb(0x9CA3AF, 0.13)); ctx.setLineWidth(3)
        for i in 1...3 {
            let v = 328 + 368 * CGFloat(i) / 4
            ctx.move(to: CGPoint(x: v, y: 328)); ctx.addLine(to: CGPoint(x: v, y: 696))
            ctx.move(to: CGPoint(x: 328, y: v)); ctx.addLine(to: CGPoint(x: 696, y: v))
        }
        ctx.strokePath()
    }
    let lineScale: CGFloat = tiny ? 2.6 : (small ? 1.8 : 1)
    let live = drawGraph(ctx, in: screenRect, lineScale: lineScale)
    if !small {
        ctx.saveGState()
        ctx.setLineDash(phase: 0, lengths: [10, 10])
        ctx.move(to: CGPoint(x: live.x, y: 328)); ctx.addLine(to: CGPoint(x: live.x, y: 696))
        ctx.setStrokeColor(rgb(0xFFFFFF, 0.18)); ctx.setLineWidth(3); ctx.strokePath()
        ctx.restoreGState()
    }
    // Live dot: soft glow and white core.
    let glowR: CGFloat = 40 * (small ? 1.3 : 1)
    ctx.drawRadialGradient(gradient([(0, rgb(0xA9CBFF, 0.9)), (0.45, rgb(0xA9CBFF, 0.45)), (1, rgb(0xA9CBFF, 0))]),
                           startCenter: live, startRadius: 0, endCenter: live, endRadius: glowR, options: [])
    let dotR: CGFloat = 15 * (tiny ? 1.9 : (small ? 1.5 : 1))
    ctx.setFillColor(rgb(0xFFFFFF))
    ctx.fillEllipse(in: CGRect(x: live.x - dotR, y: live.y - dotR, width: dotR * 2, height: dotR * 2))
    if !tiny {
        // Glass reflection on the top-left half.
        ctx.drawLinearGradient(gradient([(0, rgb(0xFFFFFF, 0.09)), (0.45, rgb(0xFFFFFF, 0.02)), (0.46, rgb(0xFFFFFF, 0))]),
                               start: CGPoint(x: 328, y: 328), end: CGPoint(x: 696, y: 696), options: [])
    }
    // Inner shadow: a frame around the screen casting its shadow inwards.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 16 * device, color: rgb(0x000000, 0.8))
    let frame = CGMutablePath()
    frame.addRect(screenRect.insetBy(dx: -60, dy: -60)); frame.addPath(screen)
    ctx.addPath(frame); ctx.setFillColor(rgb(0x000000)); ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()
    ctx.restoreGState() // screen clip

    if !tiny {
        ctx.addPath(rounded(326.5, 326.5, 371, 35.5)); ctx.setStrokeColor(rgb(0xFFFFFF, 0.1)); ctx.setLineWidth(3); ctx.strokePath()
    }

    // Top highlight across the whole body.
    ctx.drawLinearGradient(gradient([(0, rgb(0xFFFFFF, 0.16)), (1, rgb(0xFFFFFF, 0))]),
                           start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 100 + 824 * 0.45), options: [])
    ctx.restoreGState() // body clip

    if !fullBleed {
        ctx.addPath(body); ctx.setStrokeColor(rgb(0xFFFFFF, 0.14)); ctx.setLineWidth(4); ctx.strokePath()
    }
}

func render(pixels: Int, to url: URL, fullBleed: Bool = false) {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    draw(ctx, pixels: pixels, fullBleed: fullBleed)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

// MARK: - Main

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = outDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    render(pixels: base, to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    render(pixels: base * 2, to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
render(pixels: 1024, to: outDir.appendingPathComponent("AppIcon-1024.png"))
render(pixels: 256, to: outDir.appendingPathComponent("AppIcon-256.png"))
render(pixels: 1024, to: outDir.appendingPathComponent("AppIcon-fullbleed-1024.png"), fullBleed: true)
print("Wrote \(iconset.path)")
