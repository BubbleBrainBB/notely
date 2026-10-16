import AppKit

// Regenerate the app icon (e.g. after the product is named — change "N"):
//
//     swiftc Tools/make_app_icon.swift -o /tmp/make_app_icon
//     /tmp/make_app_icon Notely/Resources/Assets.xcassets/AppIcon.appiconset
//
// App icon, design board ㉖ option E: an italic Didot "N" on paper, with a
// vermilion bookmark ribbon hanging from the top edge. Drawn as vectors at
// every size on the macOS icon grid (824pt body on a 1024 canvas).

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render(px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    let k = CGFloat(px) / 1024
    // Body on the macOS grid; y-up coordinates.
    let body = NSRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    let radius = 185 * k
    let shape = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    // Drop shadow under the body (skipped at the tiniest sizes, where it muddies).
    if px >= 64 {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -10 * k)
        shadow.shadowBlurRadius = 22 * k
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.26)
        shadow.set()
        color(0xF4F1EA).setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    // Paper.
    NSGradient(starting: color(0xF2EFE8), ending: color(0xFDFCF9))!.draw(in: body, angle: 90)

    // Glass: a soft highlight over the top of the paper, under the ink.
    let glossRect = NSRect(x: body.minX, y: body.maxY - body.height * 0.40, width: body.width, height: body.height * 0.40)
    NSGradient(starting: NSColor.white.withAlphaComponent(0), ending: NSColor.white.withAlphaComponent(0.5))!
        .draw(in: glossRect, angle: 90)

    // The N, centred on its outline (not its line box), a little left of the
    // middle to leave room for the ribbon and a little low, as in the design.
    let size = 0.68 * 824 * k
    let font = NSFont(name: "Didot-Italic", size: size) ?? NSFont.systemFont(ofSize: size)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "N", attributes: [
        .font: font, .foregroundColor: color(0x2B2A26),
    ]))
    let cg = ctx.cgContext
    let ink = CTLineGetImageBounds(line, cg)
    let center = CGPoint(x: body.midX - 0.05 * 824 * k, y: body.midY - 0.04 * 824 * k)
    cg.textPosition = CGPoint(x: center.x - ink.midX, y: center.y - ink.midY)
    CTLineDraw(line, cg)

    // Bookmark ribbon from the top edge, with a notched tail.
    let rw = 0.085 * 824 * k, rh = 0.25 * 824 * k
    let rx = body.minX + 0.66 * 824 * k, top = body.maxY
    let ribbon = NSBezierPath()
    ribbon.move(to: NSPoint(x: rx, y: top))
    ribbon.line(to: NSPoint(x: rx + rw, y: top))
    ribbon.line(to: NSPoint(x: rx + rw, y: top - rh))
    ribbon.line(to: NSPoint(x: rx + rw / 2, y: top - rh * 0.84))
    ribbon.line(to: NSPoint(x: rx, y: top - rh))
    ribbon.close()
    NSGraphicsContext.saveGraphicsState()
    let ribbonShadow = NSShadow()
    ribbonShadow.shadowOffset = NSSize(width: 0, height: -3 * k)
    ribbonShadow.shadowBlurRadius = 6 * k
    ribbonShadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    ribbonShadow.set()
    color(0xC24E39).setFill()
    ribbon.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    ribbon.addClip()
    NSGradient(starting: color(0xCB5A43), ending: color(0xAE3F2C))!.draw(in: ribbon.bounds, angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()

    // Hairline edge.
    let edge = NSBezierPath(roundedRect: body.insetBy(dx: 0.75 * k, dy: 0.75 * k), xRadius: radius, yRadius: radius)
    edge.lineWidth = max(0.5, 1.5 * k)
    NSColor.black.withAlphaComponent(0.07).setStroke()
    edge.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = CommandLine.arguments[1]
let files: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32), ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256), ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, px) in files {
    let data = render(px: px).representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: out).appendingPathComponent(name))
}
print("wrote \(files.count) files")
