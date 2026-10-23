// Draws the OwlEye app icon: a night-sky rounded square with a glowing amber eye.
// Usage: swift tools/make-icon.swift <out.png>   (1024×1024)
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// macOS icon grid: 824pt rounded square centred in 1024, corner radius ~185.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
ctx.addPath(tilePath)
ctx.setFillColor(NSColor.black.cgColor)
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let sky = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(red: 0.20, green: 0.16, blue: 0.45, alpha: 1).cgColor,
        NSColor(red: 0.04, green: 0.05, blue: 0.16, alpha: 1).cgColor,
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(sky, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

// A few stars.
for (x, y, r) in [(250.0, 780.0, 7.0), (330, 700, 4), (760, 800, 6), (820, 660, 4), (690, 730, 3), (210, 620, 3)] {
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.8).cgColor)
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}

// Soft amber glow behind the eye.
let glow = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(red: 1.0, green: 0.72, blue: 0.25, alpha: 0.55).cgColor,
        NSColor(red: 1.0, green: 0.72, blue: 0.25, alpha: 0).cgColor,
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 470), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 470), endRadius: 360, options: [])
ctx.restoreGState()

// The eye, from SF Symbols.
let config = NSImage.SymbolConfiguration(pointSize: 420, weight: .semibold)
    .applying(.init(paletteColors: [NSColor(red: 1.0, green: 0.80, blue: 0.35, alpha: 1)]))
if let eye = NSImage(systemSymbolName: "eye.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let s = eye.size
    eye.draw(in: CGRect(x: 512 - s.width / 2, y: 470 - s.height / 2, width: s.width, height: s.height))
}

image.unlockFocus()

let rep = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
rep.size = NSSize(width: size, height: size)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
