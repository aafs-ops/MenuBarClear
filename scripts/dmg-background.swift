// dmg-background.swift
// MenuBarClear — https://github.com/aafs-ops/MenuBarClear
// Copyright © 2026 aafs-ops. MIT License.
//
// Draws the DMG window background (640×400 pt) at 1x and 2x.
//   swiftc scripts/dmg-background.swift -o build/dmg-background
//   build/dmg-background <out-1x.png> <out-2x.png>
//
// Layout must match scripts/make-dmg.sh: app icon centred at (160, 205),
// Applications at (480, 205), window 640×400.

import AppKit
import ImageIO

let width: CGFloat = 640, height: CGFloat = 400

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render(scale: CGFloat, to path: String) {
    let pw = Int(width * scale), ph = Int(height * scale)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("context") }
    // Top-left origin, points.
    ctx.translateBy(x: 0, y: CGFloat(ph))
    ctx.scaleBy(x: scale, y: -scale)
    ctx.interpolationQuality = .high

    // Base gradient.
    let base = CGGradient(colorsSpace: space, colors: [color(0xFBFAFF), color(0xF1F0FB)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(base, start: .zero, end: CGPoint(x: 0, y: height), options: [])

    // Soft colour blobs (same palette as the app icon).
    func blob(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ hex: UInt32, _ a: CGFloat) {
        let g = CGGradient(colorsSpace: space, colors: [color(hex, a), color(hex, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0,
                               endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
    }
    blob(width * 0.12, height * 0.05, 330, 0x60A5FA, 0.28)
    blob(width * 0.92, height * 0.12, 300, 0xF472B6, 0.22)
    blob(width * 0.85, height * 1.05, 330, 0xFB923C, 0.18)
    blob(width * 0.10, height * 1.00, 300, 0x8B5CF6, 0.16)

    // White wells behind the two icons.
    blob(160, 205, 96, 0xFFFFFF, 0.9)
    blob(480, 205, 96, 0xFFFFFF, 0.9)

    // Text (flipped NSGraphicsContext so AppKit text draws upright).
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    func text(_ s: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight, hex: UInt32, rounded: Bool = false) {
        var font = NSFont.systemFont(ofSize: size, weight: weight)
        if rounded, let d = font.fontDescriptor.withDesign(.rounded) { font = NSFont(descriptor: d, size: size) ?? font }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor(cgColor: color(hex)) ?? .black, .kern: size > 20 ? -0.3 : 0,
        ]
        let str = s as NSString
        let sz = str.size(withAttributes: attrs)
        str.draw(at: CGPoint(x: (width - sz.width) / 2, y: y - sz.height / 2), withAttributes: attrs)
    }
    text("MenuBarClear", y: 56, size: 26, weight: .bold, hex: 0x1E1B4B)
    text("Drag the app into Applications to install", y: 86, size: 13, weight: .medium, hex: 0x6B7280)
    text("Created by aafs-ops · Free and open source (MIT)", y: 370, size: 11, weight: .medium, hex: 0x9CA3AF)
    NSGraphicsContext.restoreGraphicsState()

    // Dotted gradient arrow.
    let arc = CGMutablePath()
    arc.move(to: CGPoint(x: 250, y: 200))
    arc.addCurve(to: CGPoint(x: 386, y: 196), control1: CGPoint(x: 300, y: 168), control2: CGPoint(x: 340, y: 168))
    ctx.saveGState()
    ctx.addPath(arc)
    ctx.setLineWidth(4)
    ctx.setLineCap(.round)
    ctx.setLineDash(phase: 0, lengths: [0.01, 12])
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let arrowGradient = CGGradient(colorsSpace: space,
                                   colors: [color(0x3B82F6), color(0x8B5CF6), color(0xEC4899)] as CFArray,
                                   locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(arrowGradient, start: CGPoint(x: 250, y: 0), end: CGPoint(x: 392, y: 0), options: [])
    ctx.restoreGState()

    let head = CGMutablePath()
    head.move(to: CGPoint(x: 374, y: 182))
    head.addLine(to: CGPoint(x: 392, y: 200))
    head.addLine(to: CGPoint(x: 368, y: 206))
    ctx.addPath(head)
    ctx.setStrokeColor(color(0xEC4899))
    ctx.setLineWidth(4)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()

    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)
    else { fatalError("png") }
    CGImageDestinationAddImage(dest, image, [kCGImagePropertyDPIWidth: 72 * scale,
                                             kCGImagePropertyDPIHeight: 72 * scale] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { fatalError("write \(path)") }
}

let args = CommandLine.arguments
guard args.count == 3 else {
    print("usage: dmg-background <out-1x.png> <out-2x.png>")
    exit(1)
}
render(scale: 1, to: args[1])
render(scale: 2, to: args[2])
