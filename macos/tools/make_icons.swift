// Generates AppIcon.icns and menu-bar template icons. Run: swift tools/make_icons.swift <outdir>
import Cocoa

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/icons")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func png(_ size: Int, _ draw: (CGFloat) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func glyph(_ s: String, font: NSFont, color: NSColor, center: CGPoint) {
    let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let sz = s.size(withAttributes: a)
    s.draw(at: CGPoint(x: center.x - sz.width / 2, y: center.y - sz.height / 2), withAttributes: a)
}

func appIcon(_ s: CGFloat) {
    let inset = s * 0.098, r = s - inset * 2
    let rect = CGRect(x: inset, y: inset, width: r, height: r)
    let path = NSBezierPath(roundedRect: rect, xRadius: r * 0.225, yRadius: r * 0.225)
    // drop shadow
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.35)
    sh.shadowBlurRadius = s * 0.02; sh.shadowOffset = NSSize(width: 0, height: -s * 0.012); sh.set()
    NSColor.black.setFill(); path.fill()
    NSGraphicsContext.restoreGraphicsState()
    // body gradient
    NSGraphicsContext.saveGraphicsState(); path.addClip()
    NSGradient(colors: [NSColor(red: 0.36, green: 0.74, blue: 1.0, alpha: 1), NSColor(red: 0.08, green: 0.36, blue: 0.86, alpha: 1)])!
        .draw(in: rect, angle: -90)
    // soft top gloss
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])!
        .draw(in: CGRect(x: rect.minX, y: rect.midY, width: r, height: r / 2), angle: -90)
    // diagonal swap divider
    let d = NSBezierPath(); d.move(to: CGPoint(x: rect.minX + r * 0.2, y: rect.minY + r * 0.2))
    d.line(to: CGPoint(x: rect.maxX - r * 0.2, y: rect.maxY - r * 0.2))
    NSColor.white.withAlphaComponent(0.22).setStroke(); d.lineWidth = s * 0.012
    d.setLineDash([s * 0.02, s * 0.025], count: 2, phase: 0); d.stroke()
    NSGraphicsContext.restoreGraphicsState()
    // glyphs with soft shadow
    NSGraphicsContext.saveGraphicsState()
    let gs = NSShadow(); gs.shadowColor = NSColor.black.withAlphaComponent(0.25)
    gs.shadowBlurRadius = s * 0.015; gs.shadowOffset = NSSize(width: 0, height: -s * 0.01); gs.set()
    glyph("A", font: .systemFont(ofSize: s * 0.40, weight: .bold), color: .white,
          center: CGPoint(x: rect.minX + r * 0.34, y: rect.minY + r * 0.64))
    glyph("ก", font: NSFont(name: "Thonburi-Bold", size: s * 0.40) ?? .systemFont(ofSize: s * 0.40, weight: .bold),
          color: .white, center: CGPoint(x: rect.minX + r * 0.68, y: rect.minY + r * 0.33))
    NSGraphicsContext.restoreGraphicsState()
}

func menuIcon(_ s: CGFloat) {  // black on transparent = template image
    glyph("A", font: .systemFont(ofSize: s * 0.78, weight: .bold), color: .black, center: CGPoint(x: s * 0.30, y: s * 0.54))
    glyph("ก", font: NSFont(name: "Thonburi-Bold", size: s * 0.78) ?? .systemFont(ofSize: s * 0.78, weight: .bold),
          color: .black, center: CGPoint(x: s * 0.72, y: s * 0.46))
}

let set = out.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(base, appIcon).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(base * 2, appIcon).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try png(18, menuIcon).write(to: out.appendingPathComponent("menuTemplate.png"))
try png(36, menuIcon).write(to: out.appendingPathComponent("menuTemplate@2x.png"))
try png(1024, appIcon).write(to: out.appendingPathComponent("preview.png"))
