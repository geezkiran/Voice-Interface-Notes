import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// The brand mark redrawn as vector geometry, measured off Logo.png (144x129).
// Coordinates below are in that source space, y down, and get scaled into the
// 1024 icon canvas — so the icon is crisp instead of a 7x bitmap upscale.
let markW: CGFloat = 144, markH: CGFloat = 129

func markPaths() -> (outline: CGPath, nose: CGPath, smile: CGPath, eyes: CGPath) {
    // Folder outline, stroked at width 8 on its centerline.
    let o = CGMutablePath()
    o.move(to: CGPoint(x: 20, y: 5))
    o.addLine(to: CGPoint(x: 46, y: 5))
    o.addQuadCurve(to: CGPoint(x: 62, y: 20), control: CGPoint(x: 56, y: 6))
    o.addLine(to: CGPoint(x: 123, y: 20))
    o.addArc(tangent1End: CGPoint(x: 138, y: 20), tangent2End: CGPoint(x: 138, y: 35), radius: 15)
    o.addLine(to: CGPoint(x: 138, y: 108))
    o.addArc(tangent1End: CGPoint(x: 138, y: 123), tangent2End: CGPoint(x: 123, y: 123), radius: 15)
    o.addLine(to: CGPoint(x: 20, y: 123))
    o.addArc(tangent1End: CGPoint(x: 5, y: 123), tangent2End: CGPoint(x: 5, y: 108), radius: 15)
    o.addLine(to: CGPoint(x: 5, y: 20))
    o.addArc(tangent1End: CGPoint(x: 5, y: 5), tangent2End: CGPoint(x: 20, y: 5), radius: 15)
    o.closeSubpath()

    // The J-shaped nose.
    let n = CGMutablePath()
    n.move(to: CGPoint(x: 74.5, y: 49))
    n.addLine(to: CGPoint(x: 74.5, y: 73.5))
    n.addLine(to: CGPoint(x: 65, y: 73.5))

    // The smile.
    let s = CGMutablePath()
    s.move(to: CGPoint(x: 56, y: 86.5))
    s.addCurve(to: CGPoint(x: 88, y: 86.5),
               control1: CGPoint(x: 60, y: 98), control2: CGPoint(x: 84, y: 98))

    // The two eyes.
    let e = CGMutablePath()
    for x in [CGFloat(41), CGFloat(94)] {
        e.addRoundedRect(in: CGRect(x: x, y: 45, width: 9, height: 18),
                         cornerWidth: 2, cornerHeight: 2)
    }
    return (o.copy()!, n.copy()!, s.copy()!, e.copy()!)
}

func render(to url: URL, size: CGFloat, background: CGColor?, ink: CGColor, markFraction: CGFloat) {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    if let background {
        ctx.setFillColor(background)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    }

    // Flip to y-down, then scale/centre the mark inside the canvas.
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)
    let scale = (size * markFraction) / markW
    let drawn = CGSize(width: markW * scale, height: markH * scale)
    ctx.translateBy(x: (size - drawn.width) / 2, y: (size - drawn.height) / 2)
    ctx.scaleBy(x: scale, y: scale)

    let p = markPaths()
    ctx.setStrokeColor(ink)
    ctx.setFillColor(ink)
    ctx.setLineJoin(.round)

    ctx.setLineWidth(8)
    ctx.setLineCap(.butt)
    ctx.addPath(p.outline); ctx.strokePath()
    ctx.addPath(p.nose); ctx.strokePath()

    ctx.setLineCap(.round)
    ctx.addPath(p.smile); ctx.strokePath()

    ctx.addPath(p.eyes); ctx.fillPath()

    let image = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r, g, b, a])!
}

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
// Light: the app's own background behind near-black ink.
render(to: outDir.appendingPathComponent("AppIcon-Light.png"), size: 1024,
       background: rgb(0.949, 0.949, 0.969), ink: rgb(0.07, 0.07, 0.07), markFraction: 0.60)
// Dark and tinted variants ship with a transparent background; iOS supplies its own.
render(to: outDir.appendingPathComponent("AppIcon-Dark.png"), size: 1024,
       background: nil, ink: rgb(1, 1, 1), markFraction: 0.60)
render(to: outDir.appendingPathComponent("AppIcon-Tinted.png"), size: 1024,
       background: nil, ink: rgb(1, 1, 1), markFraction: 0.60)
// A same-size proof of the original next to the redraw, for eyeballing fidelity.
render(to: outDir.appendingPathComponent("proof.png"), size: 144,
       background: rgb(1, 1, 1), ink: rgb(0.07, 0.07, 0.07), markFraction: 0.986)
print("ok")
