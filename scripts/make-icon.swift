// Generates the ActivityManagerReloaded app icon.
//
// Usage: swift scripts/make-icon.swift <output-dir>
//   Writes <output-dir>/AppIcon.iconset/*.png and <output-dir>/AppIcon-1024.png (legacy .icns art with
//   margin and shadow), plus <output-dir>/AppIcon-fullbleed-1024.png: the same art filling the whole
//   canvas, unmasked, for the macOS 26+ asset-catalog icon (the system applies mask, shadow and glass).
//   scripts/make-icon.sh wraps this and runs iconutil to produce Resources/AppIcon.icns.
//
// Design: a plain blue squircle with a green live activity line ending in a white dot.
// Every size is drawn from vectors; small sizes use a heavier stroke.

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
    // Superellipse-ish corners built from cubic Béziers with extended handles (continuous curvature).
    let p = CGMutablePath()
    let rad = min(radius, min(r.width, r.height) / 2)
    let k: CGFloat = 1.528665 // corner extent factor used by iOS-style continuous corners
    let e = rad * k            // how far from the corner the curve starts
    let minX = r.minX, maxX = r.maxX, minY = r.minY, maxY = r.maxY
    // Control-point fractions (from the well-known continuous-corner reconstruction)
    func corner(_ cx: CGFloat, _ cy: CGFloat, _ dx1: CGFloat, _ dy1: CGFloat, _ dx2: CGFloat, _ dy2: CGFloat) {
        // start point on edge 1, end on edge 2; (cx,cy) is the sharp corner
        let s = CGPoint(x: cx + dx1 * e, y: cy + dy1 * e)
        let t = CGPoint(x: cx + dx2 * e, y: cy + dy2 * e)
        let c1 = CGPoint(x: cx + dx1 * e * 0.37, y: cy + dy1 * e * 0.37)
        let c2 = CGPoint(x: cx + dx2 * e * 0.37, y: cy + dy2 * e * 0.37)
        p.addLine(to: s)
        p.addCurve(to: t, control1: c1, control2: c2)
    }
    p.move(to: CGPoint(x: minX + e, y: maxY))
    corner(maxX, maxY, -1, 0, 0, -1)
    corner(maxX, minY, 0, 1, -1, 0)
    corner(minX, minY, 1, 0, 0, 1)
    corner(minX, maxY, 0, -1, 1, 0)
    p.closeSubpath()
    return p
}

// MARK: - Waveform

/// The activity trace in screen-normalised coordinates (x 0...1 left→right, y 0...1 bottom→top).
/// `sharp` points get zero tangent so the curve forms a crisp peak (ECG-style spike).
let tracePoints: [(CGPoint, Bool)] = [
    (CGPoint(x: -0.05, y: 0.42), false),
    (CGPoint(x: 0.09, y: 0.42), false),
    (CGPoint(x: 0.155, y: 0.37), false),
    (CGPoint(x: 0.235, y: 0.90), true),  // spike
    (CGPoint(x: 0.305, y: 0.12), true),  // dip
    (CGPoint(x: 0.375, y: 0.47), false),
    (CGPoint(x: 0.445, y: 0.40), false),
    (CGPoint(x: 0.545, y: 0.64), false),
    (CGPoint(x: 0.645, y: 0.33), false),
    (CGPoint(x: 0.725, y: 0.50), false),
    (CGPoint(x: 0.795, y: 0.40), false),
]

/// Smooth Catmull-Rom path through the points, mapped into `r`.
func tracePath(in r: CGRect) -> (CGPath, CGPoint) {
    let pts = tracePoints.map { CGPoint(x: r.minX + $0.0.x * r.width, y: r.minY + $0.0.y * r.height) }
    let sharp = tracePoints.map { $0.1 }
    let p = CGMutablePath()
    p.move(to: pts[0])
    for i in 0..<(pts.count - 1) {
        let p0 = i > 0 ? pts[i - 1] : pts[i]
        let p1 = pts[i], p2 = pts[i + 1]
        let p3 = i + 2 < pts.count ? pts[i + 2] : p2
        let t1: CGFloat = sharp[i] ? 0.02 : 0.20
        let t2: CGFloat = sharp[i + 1] ? 0.02 : 0.20
        let c1 = CGPoint(x: p1.x + (p2.x - p0.x) * t1, y: p1.y + (p2.y - p0.y) * t1)
        let c2 = CGPoint(x: p2.x - (p3.x - p1.x) * t2, y: p2.y - (p3.y - p1.y) * t2)
        p.addCurve(to: p2, control1: c1, control2: c2)
    }
    return (p, pts.last!)
}

// MARK: - Drawing

func draw(_ ctx: CGContext, pixels: Int, fullBleed: Bool = false) {
    let s = CGFloat(pixels) / canvas
    ctx.scaleBy(x: s, y: s)
    let small = pixels <= 32
    let tiny = pixels <= 16

    // macOS grid: 824 body centred in 1024 with a slight upward bias for the drop shadow.
    // Full bleed: the body is the whole canvas and the system applies mask and shadow.
    let body = fullBleed ? CGRect(x: 0, y: 0, width: canvas, height: canvas)
                         : CGRect(x: 100, y: 112, width: 824, height: 824)
    let bodyPath = squircle(body, radius: body.width * 0.2245)

    if !fullBleed {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.45))
        ctx.addPath(bodyPath); ctx.setFillColor(rgb(0x1A4FB8)); ctx.fillPath()
        ctx.restoreGState()
    }

    // Plain blue background
    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.clip()
    ctx.drawLinearGradient(gradient([(0, rgb(0x2B6EE6)), (1, rgb(0x1646A8))]),
                           start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])

    // Activity line: soft glow, solid stroke, light core, leading dot
    let traceRect = body.insetBy(dx: 0, dy: body.height * 0.18)
    let (trace, end) = tracePath(in: traceRect)
    let width = (tiny ? 76 : (small ? 58 : 38)) * body.width / 824
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: small ? 8 : 24, color: rgb(0x2DFF9B, 0.7))
    ctx.addPath(trace); ctx.setStrokeColor(rgb(0x3BF0A0)); ctx.setLineWidth(width); ctx.strokePath()
    ctx.restoreGState()
    if !tiny {
        ctx.addPath(trace); ctx.setStrokeColor(rgb(0xD9FFEC, 0.7)); ctx.setLineWidth(width * 0.3); ctx.strokePath()
    }
    let dotR = width * 0.95
    ctx.setFillColor(rgb(0xFFFFFF))
    ctx.fillEllipse(in: CGRect(x: end.x - dotR, y: end.y - dotR, width: dotR * 2, height: dotR * 2))
    ctx.restoreGState()
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
render(pixels: 1024, to: outDir.appendingPathComponent("AppIcon-fullbleed-1024.png"), fullBleed: true)
print("Wrote \(iconset.path)")
