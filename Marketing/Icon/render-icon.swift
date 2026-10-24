// Renders the Grid Fleet icon layers. Run: swiftc -O -o /tmp/icon render-icon.swift && /tmp/icon <out dir>
// Copy layer-*.png into GridFleet/AppIcon.icon/Assets. icon-light.png is a flat copy for marketing.

import AppKit
import CoreGraphics

// Renders the Grid Fleet icon: an open folding pegboard, enemy plate standing above, your fleet below.
let S: CGFloat = 1024
let out = CommandLine.arguments[1]

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render(_ name: String, _ draw: (CGContext) -> Void) {
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Top-left origin.
    ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1)
    draw(ctx)
    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}

func linear(_ ctx: CGContext, _ rect: CGRect, _ top: CGColor, _ bottom: CGColor, path: CGPath? = nil) {
    ctx.saveGState()
    ctx.addPath(path ?? CGPath(rect: rect, transform: nil)); ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
    ctx.restoreGState()
}

struct Palette {
    var bgTop: UInt32, bgBottom: UInt32
    var lidTop: UInt32, lidBottom: UInt32
    var trayTop: UInt32, trayBottom: UInt32
    var hole: UInt32
    var red: UInt32, redDark: UInt32
    var white: UInt32, whiteDark: UInt32
    var hullLight: UInt32, hullDark: UInt32
}

let light = Palette(bgTop: 0x123456, bgBottom: 0x081A2C, lidTop: 0x3B74AE, lidBottom: 0x2A5A8E, trayTop: 0x24507F, trayBottom: 0x1A3D63, hole: 0x0B1E33, red: 0xF0503C, redDark: 0x8E1A12, white: 0xFFFFFF, whiteDark: 0xA9B6C4, hullLight: 0xDCE4EC, hullDark: 0x6F8296)
let dark = Palette(bgTop: 0x0B1420, bgBottom: 0x03070C, lidTop: 0x2C5786, lidBottom: 0x1F4369, trayTop: 0x1B3A5C, trayBottom: 0x132B45, hole: 0x060F1A, red: 0xFF5A45, redDark: 0x8E1A12, white: 0xF2F5F8, whiteDark: 0x8E9BAA, hullLight: 0xC9D3DE, hullDark: 0x56687C)

// Geometry
let plateX: CGFloat = 132, plateW: CGFloat = 760
let lid = CGRect(x: plateX, y: 120, width: plateW, height: 372)
let tray = CGRect(x: plateX, y: 532, width: plateW, height: 372)
let cols = 5, rows = 3
func cell(_ plate: CGRect, _ c: Int, _ r: Int) -> CGPoint {
    let cw = plate.width / CGFloat(cols), rh = plate.height / CGFloat(rows)
    return CGPoint(x: plate.minX + cw * (CGFloat(c) + 0.5), y: plate.minY + rh * (CGFloat(r) + 0.5))
}

func background(_ ctx: CGContext, _ p: Palette) {
    linear(ctx, CGRect(x: 0, y: 0, width: S, height: S), color(p.bgTop), color(p.bgBottom))
}

func plate(_ ctx: CGContext, _ rect: CGRect, _ top: UInt32, _ bottom: UInt32, _ p: Palette, shadow: Bool) {
    let path = CGPath(roundedRect: rect, cornerWidth: 56, cornerHeight: 56, transform: nil)
    if shadow {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 40, color: color(0x000000, 0.45))
        ctx.addPath(path); ctx.setFillColor(color(bottom)); ctx.fillPath()
        ctx.restoreGState()
    }
    linear(ctx, rect, color(top), color(bottom), path: path)
    // Rim light along the top edge.
    ctx.saveGState()
    ctx.addPath(path); ctx.setStrokeColor(color(0xFFFFFF, 0.18)); ctx.setLineWidth(4); ctx.strokePath()
    ctx.restoreGState()
    for r in 0..<rows { for c in 0..<cols {
        let pt = cell(rect, c, r)
        ctx.setFillColor(color(p.hole)); ctx.fillEllipse(in: CGRect(x: pt.x - 17, y: pt.y - 17, width: 34, height: 34))
        ctx.setFillColor(color(0xFFFFFF, 0.10)); ctx.fillEllipse(in: CGRect(x: pt.x - 17, y: pt.y - 13, width: 34, height: 34))
        ctx.setFillColor(color(p.hole)); ctx.fillEllipse(in: CGRect(x: pt.x - 15, y: pt.y - 16, width: 30, height: 30))
    }}
}

func peg(_ ctx: CGContext, at pt: CGPoint, _ main: UInt32, _ shade: UInt32, radius: CGFloat = 50) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 18, color: color(0x000000, 0.5))
    ctx.setFillColor(color(shade)); ctx.fillEllipse(in: CGRect(x: pt.x - radius, y: pt.y - radius, width: radius * 2, height: radius * 2))
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: pt.x - radius, y: pt.y - radius, width: radius * 2, height: radius * 2)); ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(main), color(main), color(shade)] as CFArray, locations: [0, 0.35, 1])!
    ctx.drawRadialGradient(g, startCenter: CGPoint(x: pt.x - radius * 0.35, y: pt.y - radius * 0.4), startRadius: 0, endCenter: pt, endRadius: radius * 1.05, options: [.drawsAfterEndLocation])
    ctx.restoreGState()
    ctx.setFillColor(color(0xFFFFFF, 0.75)); ctx.fillEllipse(in: CGRect(x: pt.x - radius * 0.5, y: pt.y - radius * 0.6, width: radius * 0.42, height: radius * 0.3))
}

func ship(_ ctx: CGContext, _ p: Palette) {
    let a = cell(tray, 1, 1), b = cell(tray, 4, 1)
    let h: CGFloat = 112
    let rect = CGRect(x: a.x - 66, y: a.y - h / 2, width: b.x - a.x + 132, height: h)
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.minX + h / 2, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - 110, y: rect.minY))
    path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY), control: CGPoint(x: rect.maxX - 20, y: rect.minY))
    path.addQuadCurve(to: CGPoint(x: rect.maxX - 110, y: rect.maxY), control: CGPoint(x: rect.maxX - 20, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX + h / 2, y: rect.maxY))
    path.addArc(center: CGPoint(x: rect.minX + h / 2, y: rect.midY), radius: h / 2, startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: false)
    path.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 22, color: color(0x000000, 0.5))
    ctx.addPath(path); ctx.setFillColor(color(p.hullDark)); ctx.fillPath()
    ctx.restoreGState()
    linear(ctx, rect, color(p.hullLight), color(p.hullDark), path: path)
    // Peg holes along the hull.
    for c in 1...4 {
        let pt = cell(tray, c, 1)
        ctx.setFillColor(color(0x1B2633)); ctx.fillEllipse(in: CGRect(x: pt.x - 15, y: pt.y - 15, width: 30, height: 30))
    }
}

func hinge(_ ctx: CGContext) {
    linear(ctx, CGRect(x: 96, y: 503, width: S - 192, height: 18), color(0x000000, 0.0), color(0x000000, 0.0))
    ctx.setFillColor(color(0x000000, 0.35)); ctx.fill(CGRect(x: 110, y: 508, width: S - 220, height: 8))
}

func art(_ ctx: CGContext, _ p: Palette, layers: Set<String> = ["lid", "tray", "ship", "pegs"]) {
    if layers.contains("tray") { plate(ctx, tray, p.trayTop, p.trayBottom, p, shadow: true) }
    if layers.contains("ship") { ship(ctx, p) }
    if layers.contains("lid") { plate(ctx, lid, p.lidTop, p.lidBottom, p, shadow: true) }
    if layers.contains("pegs") {
        peg(ctx, at: cell(lid, 3, 1), p.red, p.redDark)
        peg(ctx, at: cell(lid, 1, 0), p.white, p.whiteDark, radius: 42)
        peg(ctx, at: cell(lid, 0, 2), p.white, p.whiteDark, radius: 42)
        peg(ctx, at: cell(tray, 2, 1), p.red, p.redDark, radius: 42)
        peg(ctx, at: cell(tray, 3, 2), p.white, p.whiteDark, radius: 36)
    }
}

// Flat icons for the asset catalog.
render("icon-light") { ctx in background(ctx, light); art(ctx, light) }
render("icon-dark") { ctx in background(ctx, dark); art(ctx, dark) }
render("icon-tinted-color") { ctx in ctx.setFillColor(color(0x000000)); ctx.fill(CGRect(x: 0, y: 0, width: S, height: S)); art(ctx, light) }
// Layers for Icon Composer, on transparent backgrounds.
render("layer-tray") { ctx in art(ctx, light, layers: ["tray"]) }
render("layer-ship") { ctx in art(ctx, light, layers: ["ship"]) }
render("layer-lid") { ctx in art(ctx, light, layers: ["lid"]) }
render("layer-pegs") { ctx in art(ctx, light, layers: ["pegs"]) }
