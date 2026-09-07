import Cocoa

final class CradleView: NSView {
    let sim = Simulation()
    private var bg: NSImage?
    private var lastSize: CGSize = .zero
    private var lastScale: CGFloat = 0

    override var isOpaque: Bool { true }
    override var wantsDefaultClipping: Bool { false }

    override func layout() {
        super.layout()
        sim.layout(in: bounds)
        let scale = window?.backingScaleFactor ?? 2
        if bounds.size != lastSize || scale != lastScale {
            lastSize = bounds.size
            lastScale = scale
            bg = nil
        }
    }

    func tick(dt: Double) {
        if bounds.width > 8 {
            sim.layout(in: bounds)
        }
        if !MotionHub.shared.paused {
            sim.step(dt: dt, hub: MotionHub.shared)
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if bg == nil { rebuildBackground() }
        bg?.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)

        guard !sim.balls.isEmpty else { return }
        drawStringsAndBalls()
    }

    private func rebuildBackground() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let w = max(1, Int(bounds.width * scale))
        let h = max(1, Int(bounds.height * scale))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
        rep.size = bounds.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        drawDesk(in: bounds)
        drawFrame(in: bounds)
        NSGraphicsContext.restoreGraphicsState()
        let img = NSImage(size: bounds.size)
        img.addRepresentation(rep)
        bg = img
    }

    private func drawDesk(in rect: NSRect) {
        NSColor(calibratedRed: 0.075, green: 0.045, blue: 0.028, alpha: 1).setFill()
        rect.fill()

        let grain = NSGradient(colors: [
            NSColor(calibratedRed: 0.11, green: 0.07, blue: 0.04, alpha: 1),
            NSColor(calibratedRed: 0.16, green: 0.10, blue: 0.06, alpha: 1),
            NSColor(calibratedRed: 0.09, green: 0.055, blue: 0.032, alpha: 1)
        ])
        grain?.draw(in: rect, angle: 92)

        let step = max(1.0, rect.width / 900)
        var x = rect.minX
        var i = 0
        while x < rect.maxX {
            let n = grainNoise(i)
            let alpha = 0.035 + n * 0.07
            NSColor(calibratedRed: 0.32, green: 0.20, blue: 0.11, alpha: alpha).setFill()
            NSRect(x: x, y: rect.minY, width: step * (0.6 + n), height: rect.height).fill()
            x += step * (1.4 + n * 2.2)
            i += 1
        }

        let vignette = NSGradient(
            starting: NSColor.clear,
            ending: NSColor(calibratedRed: 0.01, green: 0.005, blue: 0.0, alpha: 0.62)
        )
        let inset = rect.insetBy(dx: -rect.width * 0.08, dy: -rect.height * 0.08)
        vignette?.draw(in: NSBezierPath(rect: rect), relativeCenterPosition: .zero)
        NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.18).setFill()
        NSBezierPath(rect: rect).fill()
        _ = inset
    }

    private func grainNoise(_ i: Int) -> CGFloat {
        var x = (i &* 1103515245) &+ 12345
        x = (x ^ (x >> 16)) &* 0x7feb352d
        let u = CGFloat(x & 0xffff) / 65535.0
        return u
    }

    private func drawFrame(in rect: NSRect) {
        guard sim.balls.count >= 2 else { return }
        let first = sim.balls.first!
        let last = sim.balls.last!
        let r = CGFloat(first.radius)
        let barY = CGFloat(first.pivotY)
        let leftX = CGFloat(first.pivotX) - r * 2.4
        let rightX = CGFloat(last.pivotX) + r * 2.4
        let postW = r * 0.55
        let postTop = barY + r * 0.7
        let postBottom = CGFloat(first.pivotY) - CGFloat(first.length) - r * 2.8

        let brassDark = NSColor(calibratedRed: 0.42, green: 0.28, blue: 0.12, alpha: 1)
        let brass = NSColor(calibratedRed: 0.72, green: 0.54, blue: 0.28, alpha: 1)
        let brassLite = NSColor(calibratedRed: 0.90, green: 0.74, blue: 0.42, alpha: 1)

        func post(_ x: CGFloat) {
            let p = NSRect(x: x - postW / 2, y: postBottom, width: postW, height: postTop - postBottom)
            let path = NSBezierPath(roundedRect: p, xRadius: postW * 0.2, yRadius: postW * 0.2)
            NSGradient(colors: [brassLite, brass, brassDark])?.draw(in: path, angle: 0)
        }
        post(leftX)
        post(rightX)

        let barH = r * 0.48
        let bar = NSRect(x: leftX - postW * 0.2, y: barY - barH * 0.15, width: rightX - leftX + postW * 0.4, height: barH)
        let barPath = NSBezierPath(roundedRect: bar, xRadius: barH * 0.3, yRadius: barH * 0.3)
        NSGradient(colors: [brassLite, brass, brassDark, brass])?.draw(in: barPath, angle: 90)

        // Base plinth
        let base = NSRect(
            x: leftX - r * 1.6,
            y: postBottom - r * 0.35,
            width: (rightX - leftX) + r * 3.2,
            height: r * 0.85
        )
        let basePath = NSBezierPath(roundedRect: base, xRadius: r * 0.12, yRadius: r * 0.12)
        NSGradient(colors: [
            NSColor(calibratedRed: 0.22, green: 0.13, blue: 0.07, alpha: 1),
            NSColor(calibratedRed: 0.10, green: 0.06, blue: 0.03, alpha: 1)
        ])?.draw(in: basePath, angle: 90)

        // Pivot caps
        for b in sim.balls {
            let cap = NSRect(x: CGFloat(b.pivotX) - r * 0.18, y: barY - r * 0.12, width: r * 0.36, height: r * 0.36)
            NSBezierPath(ovalIn: cap).fill(with: brassDark)
            NSColor(calibratedRed: 0.95, green: 0.82, blue: 0.5, alpha: 0.7).setFill()
            NSBezierPath(ovalIn: cap.insetBy(dx: r * 0.1, dy: r * 0.12)).fill()
        }
    }

    private func drawStringsAndBalls() {
        let wire = NSColor(calibratedRed: 0.78, green: 0.74, blue: 0.68, alpha: 0.92)
        for b in sim.balls {
            let p = b.position
            let pivot = CGPoint(x: b.pivotX, y: b.pivotY)
            var dx = Double(p.x) - b.pivotX
            var dy = Double(p.y) - b.pivotY
            let mag = max(hypot(dx, dy), 1e-6)
            dx /= mag
            dy /= mag
            let end = CGPoint(
                x: Double(p.x) - dx * b.radius * 0.92,
                y: Double(p.y) - dy * b.radius * 0.92
            )
            let path = NSBezierPath()
            path.move(to: pivot)
            path.line(to: end)
            path.lineWidth = max(1.0, CGFloat(b.radius) * 0.045)
            wire.setStroke()
            path.stroke()
        }

        for b in sim.balls {
            drawBall(b)
        }
    }

    private func drawBall(_ b: Ball) {
        let p = b.position
        let r = CGFloat(b.radius)

        // Contact shadow on the plinth plane
        let shadowY = CGFloat(b.pivotY - b.length) - r * 1.55
        let squash = NSRect(x: p.x - r * 0.85, y: shadowY, width: r * 1.7, height: r * 0.38)
        NSColor(calibratedWhite: 0, alpha: 0.32).setFill()
        NSBezierPath(ovalIn: squash).fill()

        let rect = NSRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        let ball = NSBezierPath(ovalIn: rect)
        NSGradient(
            colors: [
                NSColor(calibratedWhite: 0.96, alpha: 1),
                NSColor(calibratedWhite: 0.62, alpha: 1),
                NSColor(calibratedWhite: 0.28, alpha: 1),
                NSColor(calibratedWhite: 0.07, alpha: 1)
            ],
            atLocations: [0.0, 0.28, 0.62, 1.0],
            colorSpace: .deviceGray
        )?.draw(in: ball, relativeCenterPosition: NSPoint(x: -0.38, y: 0.42))

        let rim = NSBezierPath(ovalIn: rect.insetBy(dx: 0.4, dy: 0.4))
        rim.lineWidth = max(1, r * 0.04)
        NSColor(calibratedWhite: 0.05, alpha: 0.5).setStroke()
        rim.stroke()

        let spec = NSBezierPath(ovalIn: NSRect(
            x: p.x - r * 0.48,
            y: p.y + r * 0.18,
            width: r * 0.58,
            height: r * 0.38
        ))
        NSGradient(colors: [
            NSColor(calibratedWhite: 1, alpha: 0.85),
            NSColor(calibratedWhite: 1, alpha: 0)
        ])?.draw(in: spec, angle: -90)

        let spec2 = NSBezierPath(ovalIn: NSRect(
            x: p.x + r * 0.22,
            y: p.y - r * 0.18,
            width: r * 0.22,
            height: r * 0.16
        ))
        NSColor(calibratedWhite: 1, alpha: 0.22).setFill()
        spec2.fill()
    }
}

private extension NSBezierPath {
    func fill(with color: NSColor) {
        color.setFill()
        fill()
    }
}
