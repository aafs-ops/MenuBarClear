// BarView.swift
// MenuBarClear — https://github.com/aafs-ops/MenuBarClear
// Copyright © 2026 aafs-ops. MIT License.
//
// Draws one cleared menu bar:
//   wallpaper strip → [recoloured status icons] → app menus → click ripples

import AppKit
import QuartzCore

final class BarView: NSView {
    var wallpaper: CGImage? { didSet { needsDisplay = true } }
    var icons: CGImage? { didSet { needsDisplay = true } }
    var items: [MenuItem] = [] { didSet { if items != oldValue { needsDisplay = true } } }
    var darkText = false { didSet { if darkText != oldValue { needsDisplay = true } } }
    /// Top-left of the bar in CoreGraphics global coordinates.
    var origin: CGPoint = .zero

    override var isFlipped: Bool { true }
    private var textColor: NSColor { darkText ? .black : .white }

    private let rippleHost = CALayer()
    private var liveRipples = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        rippleHost.masksToBounds = true
        rippleHost.zPosition = 10
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        if rippleHost.superlayer == nil { layer?.addSublayer(rippleHost) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rippleHost.frame = bounds
        CATransaction.commit()
    }

    // MARK: Drawing

    private func drawImage(_ image: CGImage, in ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: bounds)
        ctx.restoreGState()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        if let wallpaper { drawImage(wallpaper, in: ctx) }
        if let icons { drawImage(icons, in: ctx) }

        let fontSize = NSFont.menuBarFont(ofSize: 0).pointSize
        for item in items {
            let r = CGRect(x: item.frame.minX - origin.x, y: item.frame.minY - origin.y,
                           width: item.frame.width, height: item.frame.height)

            if item.index == 0 {
                drawAppleMenu(in: r)
                continue
            }
            guard !item.title.isEmpty else { continue }
            let font: NSFont = item.index == 1 ? .boldSystemFont(ofSize: fontSize) : .menuBarFont(ofSize: fontSize)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
            let title = item.title as NSString
            let size = title.size(withAttributes: attributes)
            title.draw(at: CGPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2),
                       withAttributes: attributes)
        }
    }

    private func drawAppleMenu(in r: CGRect) {
        let config = NSImage.SymbolConfiguration(pointSize: round(bounds.height * 0.46), weight: .medium)
            .applying(.init(paletteColors: [textColor]))
        guard let logo = NSImage(systemSymbolName: "apple.logo", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let size = logo.size
        logo.draw(in: CGRect(x: r.midX - size.width / 2, y: r.midY - size.height / 2 - 0.5,
                             width: size.width, height: size.height))
    }

    // MARK: Liquid-glass ripple (Core Animation only; composited on the GPU)

    /// `point` in this view's flipped coordinates.
    func ripple(at point: CGPoint) {
        guard liveRipples < 6 else { return }
        if rippleHost.superlayer == nil {
            layer?.addSublayer(rippleHost)
            rippleHost.frame = bounds
        }
        liveRipples += 1

        let diameter = bounds.height * 2.2
        let scale = window?.backingScaleFactor ?? 2
        let box = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        let circle = CGPath(ellipseIn: box.insetBy(dx: 0.75, dy: 0.75), transform: nil)
        let white = { (alpha: CGFloat) in NSColor.white.withAlphaComponent(alpha).cgColor }

        let lens = CALayer()
        lens.frame = CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2, width: diameter, height: diameter)
        lens.contentsScale = scale
        lens.opacity = 0

        // Glass body: clear centre, frosted towards the edge.
        let body = CAGradientLayer()
        body.type = .radial
        body.frame = box
        body.startPoint = CGPoint(x: 0.5, y: 0.5)
        body.endPoint = CGPoint(x: 1, y: 1)
        body.colors = [white(0.02), white(darkText ? 0.10 : 0.07), white(darkText ? 0.38 : 0.26)]
        body.locations = [0, 0.62, 1]
        let bodyMask = CAShapeLayer()
        bodyMask.path = circle
        body.mask = bodyMask

        // Faint dark outline so the lens reads on bright wallpapers.
        let edge = CAShapeLayer()
        edge.path = CGPath(ellipseIn: box.insetBy(dx: 0.2, dy: 0.2), transform: nil)
        edge.fillColor = nil
        edge.strokeColor = NSColor.black.withAlphaComponent(darkText ? 0.16 : 0.08).cgColor
        edge.lineWidth = 1.2
        edge.contentsScale = scale

        // Bright rim.
        let rim = CAShapeLayer()
        rim.path = circle
        rim.fillColor = nil
        rim.strokeColor = white(0.55)
        rim.lineWidth = 1.1
        rim.contentsScale = scale

        // Specular glints along the rim.
        let glint = CAGradientLayer()
        glint.type = .conic
        glint.frame = box
        glint.startPoint = CGPoint(x: 0.5, y: 0.5)
        glint.endPoint = CGPoint(x: 0.5, y: 0)
        glint.colors    = [white(0), white(0.4), white(0), white(0), white(0.2), white(0.95), white(0.2), white(0)]
        glint.locations = [0, 0.06, 0.12, 0.45, 0.55, 0.63, 0.71, 1]
        let ring = CAShapeLayer()
        ring.path = circle
        ring.fillColor = nil
        ring.strokeColor = NSColor.white.cgColor
        ring.lineWidth = 2.2
        glint.mask = ring

        [body, edge, rim, glint].forEach(lens.addSublayer)

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            lens.removeFromSuperlayer()
            self?.liveRipples -= 1
        }
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.12
        grow.toValue = 1.0
        grow.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 0.85, 0]
        fade.keyTimes = [0, 0.12, 0.55, 1]

        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = -0.35
        spin.toValue = 0.15

        let group = CAAnimationGroup()
        group.animations = [grow, fade, spin]
        group.duration = 0.55
        group.isRemovedOnCompletion = true
        group.fillMode = .forwards
        lens.add(group, forKey: "ripple")
        rippleHost.addSublayer(lens)
        CATransaction.commit()
    }
}
