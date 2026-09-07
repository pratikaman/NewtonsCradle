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
        NSGraphicsContext.current?.shouldAntialias = true
        NSGraphicsContext.current?.imageInterpolation = .high
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
        NSGraphicsContext.current?.shouldAntialias = true
        drawRoomAndDesk(in: bounds)
        drawFrame()
        NSGraphicsContext.restoreGraphicsState()
        let img = NSImage(size: bounds.size)
        img.addRepresentation(rep)
        bg = img
    }

    // MARK: - Scene

    private func drawRoomAndDesk(in rect: NSRect) {
        NSColor(calibratedRed: 0.035, green: 0.028, blue: 0.022, alpha: 1).setFill()
        rect.fill()

        // Warm key from a high window, left of center.
        let roomLight = NSGradient(colors: [
            NSColor(calibratedRed: 0.22, green: 0.14, blue: 0.08, alpha: 0.55),
            NSColor(calibratedRed: 0.06, green: 0.04, blue: 0.03, alpha: 0.0)
        ])
        let lightPath = NSBezierPath(rect: rect)
        roomLight?.draw(in: lightPath, relativeCenterPosition: NSPoint(x: -0.28, y: 0.55))

        guard let first = sim.balls.first else { return }
        let r = CGFloat(first.radius)
        let deskTop = CGFloat(first.pivotY - first.length) - r * 2.35
        let desk = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(8, deskTop - rect.minY))

        NSColor(calibratedRed: 0.09, green: 0.055, blue: 0.032, alpha: 1).setFill()
        desk.fill()

        let deskWash = NSGradient(colors: [
            NSColor(calibratedRed: 0.16, green: 0.10, blue: 0.055, alpha: 1),
            NSColor(calibratedRed: 0.08, green: 0.048, blue: 0.028, alpha: 1),
            NSColor(calibratedRed: 0.04, green: 0.025, blue: 0.016, alpha: 1)
        ])
        deskWash?.draw(in: desk, angle: 90)

        // Horizontal grain — a desk, not a wall.
        var y = desk.minY
        var i = 0
        let step = max(0.7, desk.height / 220)
        while y < desk.maxY {
            let n = noise(i &+ 17)
            let a = 0.028 + n * 0.07
            NSColor(calibratedRed: 0.38, green: 0.22, blue: 0.10, alpha: a).setFill()
            NSRect(x: desk.minX, y: y, width: desk.width, height: step * (0.45 + n * 0.8)).fill()
            y += step * (1.15 + n * 1.8)
            i += 1
        }

        // Pool of window light on the desk under the cradle.
        let pool = NSBezierPath(ovalIn: NSRect(
            x: rect.midX - r * 9,
            y: deskTop - r * 3.4,
            width: r * 18,
            height: r * 4.2
        ))
        NSGradient(colors: [
            NSColor(calibratedRed: 0.42, green: 0.28, blue: 0.14, alpha: 0.28),
            NSColor(calibratedRed: 0.18, green: 0.10, blue: 0.05, alpha: 0)
        ])?.draw(in: pool, relativeCenterPosition: .zero)

        // Horizon catch on the desk edge.
        NSColor(calibratedRed: 0.55, green: 0.38, blue: 0.18, alpha: 0.18).setFill()
        NSRect(x: desk.minX, y: desk.maxY - 1.2, width: desk.width, height: 1.2).fill()

        // Falloff into the room.
        let vignette = NSGradient(
            starting: NSColor.clear,
            ending: NSColor(calibratedRed: 0.01, green: 0.008, blue: 0.005, alpha: 0.72)
        )
        vignette?.draw(in: NSBezierPath(rect: rect), relativeCenterPosition: NSPoint(x: 0, y: -0.15))
    }

    private func noise(_ i: Int) -> CGFloat {
        var x = (i &* 1103515245) &+ 12345
        x = (x ^ (x >> 16)) &* 0x7feb352d
        return CGFloat(x & 0xffff) / 65535.0
    }

    // MARK: - Frame (dual rail, four posts, felted plinth)

    private struct FrameGeom {
        var r: CGFloat
        var leftX: CGFloat
        var rightX: CGFloat
        var frontY: CGFloat
        var backY: CGFloat
        var postBottom: CGFloat
        var postW: CGFloat
        var deskTop: CGFloat
    }

    private func frameGeom() -> FrameGeom? {
        guard sim.balls.count >= 2, let first = sim.balls.first, let last = sim.balls.last else { return nil }
        let r = CGFloat(first.radius)
        let frontY = CGFloat(first.pivotY)
        return FrameGeom(
            r: r,
            leftX: CGFloat(first.pivotX) - r * 2.15,
            rightX: CGFloat(last.pivotX) + r * 2.15,
            frontY: frontY,
            backY: frontY + r * 0.42,
            postBottom: CGFloat(first.pivotY) - CGFloat(first.length) - r * 2.15,
            postW: r * 0.42,
            deskTop: CGFloat(first.pivotY - first.length) - r * 2.35
        )
    }

    private func drawFrame() {
        guard let g = frameGeom() else { return }
        let brassLite = NSColor(calibratedRed: 0.86, green: 0.70, blue: 0.42, alpha: 1)
        let brass = NSColor(calibratedRed: 0.62, green: 0.46, blue: 0.24, alpha: 1)
        let brassDark = NSColor(calibratedRed: 0.28, green: 0.18, blue: 0.08, alpha: 1)
        let steelLite = NSColor(calibratedRed: 0.62, green: 0.60, blue: 0.56, alpha: 1)
        let steel = NSColor(calibratedRed: 0.32, green: 0.30, blue: 0.28, alpha: 1)
        let steelDark = NSColor(calibratedRed: 0.10, green: 0.09, blue: 0.08, alpha: 1)

        func metalPost(x: CGFloat, y0: CGFloat, y1: CGFloat, width: CGFloat, back: Bool) {
            let inset: CGFloat = back ? width * 0.12 : 0
            let p = NSRect(x: x - width / 2 + inset, y: y0, width: width - inset * 2, height: y1 - y0)
            let path = NSBezierPath(roundedRect: p, xRadius: width * 0.45, yRadius: width * 0.12)
            let colors = back
                ? [steel, steelDark, steelDark]
                : [steelLite, steel, steelDark]
            NSGradient(colors: colors)?.draw(in: path, angle: 0)
            if !back {
                NSColor(calibratedWhite: 1, alpha: 0.18).setFill()
                NSRect(x: p.minX + p.width * 0.18, y: p.minY, width: 1.2, height: p.height).fill()
            }
        }

        func rail(y: CGFloat, back: Bool) {
            let h = g.r * (back ? 0.28 : 0.34)
            let bar = NSRect(x: g.leftX - g.postW * 0.15, y: y - h * 0.35, width: g.rightX - g.leftX + g.postW * 0.3, height: h)
            let path = NSBezierPath(roundedRect: bar, xRadius: h * 0.4, yRadius: h * 0.4)
            let colors = back
                ? [brass, brassDark]
                : [brassLite, brass, brassDark, brass]
            NSGradient(colors: colors)?.draw(in: path, angle: back ? 0 : 90)
            if !back {
                NSColor(calibratedRed: 1, green: 0.92, blue: 0.7, alpha: 0.35).setFill()
                NSRect(x: bar.minX + 4, y: bar.maxY - 1.4, width: bar.width - 8, height: 1.1).fill()
            }
        }

        // Back structure first.
        metalPost(x: g.leftX, y0: g.postBottom, y1: g.backY + g.r * 0.25, width: g.postW, back: true)
        metalPost(x: g.rightX, y0: g.postBottom, y1: g.backY + g.r * 0.25, width: g.postW, back: true)
        rail(y: g.backY, back: true)

        // Plinth
        let base = NSRect(
            x: g.leftX - g.r * 1.8,
            y: g.postBottom - g.r * 0.22,
            width: (g.rightX - g.leftX) + g.r * 3.6,
            height: g.r * 1.05
        )
        let basePath = NSBezierPath(roundedRect: base, xRadius: g.r * 0.10, yRadius: g.r * 0.10)
        NSGradient(colors: [
            NSColor(calibratedRed: 0.28, green: 0.16, blue: 0.08, alpha: 1),
            NSColor(calibratedRed: 0.12, green: 0.07, blue: 0.035, alpha: 1),
            NSColor(calibratedRed: 0.06, green: 0.035, blue: 0.018, alpha: 1)
        ])?.draw(in: basePath, angle: 90)

        let felt = NSRect(x: base.minX + g.r * 0.35, y: base.maxY - g.r * 0.28, width: base.width - g.r * 0.7, height: g.r * 0.22)
        let feltPath = NSBezierPath(roundedRect: felt, xRadius: g.r * 0.04, yRadius: g.r * 0.04)
        NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.06, alpha: 1).setFill()
        feltPath.fill()
        NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.10, alpha: 0.55).setFill()
        NSRect(x: felt.minX, y: felt.maxY - 1, width: felt.width, height: 1).fill()

        // Front posts + rail
        metalPost(x: g.leftX, y0: g.postBottom, y1: g.frontY + g.r * 0.38, width: g.postW, back: false)
        metalPost(x: g.rightX, y0: g.postBottom, y1: g.frontY + g.r * 0.38, width: g.postW, back: false)
        rail(y: g.frontY, back: false)

        // Pivot beads on the front rail
        for b in sim.balls {
            let capR = g.r * 0.13
            let cap = NSRect(x: CGFloat(b.pivotX) - capR, y: g.frontY - capR * 0.3, width: capR * 2, height: capR * 2)
            NSBezierPath(ovalIn: cap).fill(with: brassDark)
            NSColor(calibratedRed: 0.95, green: 0.82, blue: 0.52, alpha: 0.85).setFill()
            NSBezierPath(ovalIn: cap.insetBy(dx: capR * 0.35, dy: capR * 0.4)).fill()
        }
    }

    // MARK: - Moving parts

    private func drawStringsAndBalls() {
        guard let g = frameGeom() else { return }
        let attach = g.r * 0.20

        for b in sim.balls {
            let p = b.position
            let top = CGPoint(
                x: p.x,
                y: p.y + CGFloat(b.radius) * 0.88
            )
            func wire(_ from: CGPoint, alpha: CGFloat, width: CGFloat) {
                let path = NSBezierPath()
                path.move(to: from)
                path.line(to: top)
                path.lineWidth = width
                path.lineCapStyle = .round
                NSColor(calibratedRed: 0.72, green: 0.68, blue: 0.60, alpha: alpha).setStroke()
                path.stroke()
            }
            // Back string, then front pair — the classic two-string hang.
            wire(CGPoint(x: CGFloat(b.pivotX), y: g.backY), alpha: 0.38, width: max(0.6, g.r * 0.028))
            wire(CGPoint(x: CGFloat(b.pivotX) - attach, y: g.frontY), alpha: 0.78, width: max(0.8, g.r * 0.034))
            wire(CGPoint(x: CGFloat(b.pivotX) + attach, y: g.frontY), alpha: 0.78, width: max(0.8, g.r * 0.034))
        }

        for (i, b) in sim.balls.enumerated() {
            drawBall(b, index: i)
        }
    }

    private func drawBall(_ b: Ball, index: Int) {
        let p = b.position
        let r = CGFloat(b.radius)
        let lift = CGFloat((1 - cos(b.theta)) * b.length)

        // Contact shadow on the felt — tighter and darker when hanging, softer when raised.
        let shadowScale = 1 + lift / (r * 14)
        let shadowAlpha = 0.38 / Double(1 + lift / (r * 8))
        let squash = NSRect(
            x: p.x - r * 0.95 * shadowScale,
            y: CGFloat(b.pivotY - b.length) - r * 1.85,
            width: r * 1.9 * shadowScale,
            height: r * 0.32 * shadowScale
        )
        NSColor(calibratedWhite: 0, alpha: CGFloat(shadowAlpha)).setFill()
        NSBezierPath(ovalIn: squash).fill()

        let rect = NSRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        let ball = NSBezierPath(ovalIn: rect)

        // Cool chrome body.
        NSGradient(
            colors: [
                NSColor(calibratedRed: 0.92, green: 0.93, blue: 0.95, alpha: 1),
                NSColor(calibratedRed: 0.48, green: 0.50, blue: 0.54, alpha: 1),
                NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.18, alpha: 1),
                NSColor(calibratedRed: 0.04, green: 0.04, blue: 0.045, alpha: 1)
            ],
            atLocations: [0.0, 0.32, 0.68, 1.0],
            colorSpace: .genericRGB
        )?.draw(in: ball, relativeCenterPosition: NSPoint(x: -0.36, y: 0.44))

        // Warm wood bounce from below.
        let bounce = NSBezierPath(ovalIn: NSRect(
            x: p.x - r * 0.72,
            y: p.y - r * 0.92,
            width: r * 1.44,
            height: r * 0.70
        ))
        NSGradient(colors: [
            NSColor(calibratedRed: 0.45, green: 0.26, blue: 0.10, alpha: 0.32),
            NSColor(calibratedRed: 0.45, green: 0.26, blue: 0.10, alpha: 0)
        ])?.draw(in: bounce, angle: 90)

        // Horizon band — a thin environment reflection.
        let band = NSBezierPath(ovalIn: NSRect(
            x: p.x - r * 0.78,
            y: p.y - r * 0.08,
            width: r * 1.56,
            height: r * 0.22
        ))
        NSColor(calibratedWhite: 1, alpha: 0.10).setFill()
        band.fill()

        // Neighbor occlusion: darken the side facing a close ball.
        if index > 0 {
            let left = sim.balls[index - 1]
            let gap = CGFloat(b.position.x - left.position.x) - r - CGFloat(left.radius)
            let closeness = max(0, 1 - gap / (r * 0.55))
            if closeness > 0.05 {
                NSColor(calibratedWhite: 0, alpha: 0.22 * closeness).setFill()
                NSBezierPath(ovalIn: NSRect(x: p.x - r * 0.95, y: p.y - r * 0.55, width: r * 0.55, height: r * 1.1)).fill()
            }
        }
        if index + 1 < sim.balls.count {
            let right = sim.balls[index + 1]
            let gap = CGFloat(right.position.x - b.position.x) - r - CGFloat(right.radius)
            let closeness = max(0, 1 - gap / (r * 0.55))
            if closeness > 0.05 {
                NSColor(calibratedWhite: 0, alpha: 0.22 * closeness).setFill()
                NSBezierPath(ovalIn: NSRect(x: p.x + r * 0.40, y: p.y - r * 0.55, width: r * 0.55, height: r * 1.1)).fill()
            }
        }

        // Window specular.
        let spec = NSBezierPath(ovalIn: NSRect(
            x: p.x - r * 0.50,
            y: p.y + r * 0.22,
            width: r * 0.52,
            height: r * 0.34
        ))
        NSGradient(colors: [
            NSColor(calibratedWhite: 1, alpha: 0.92),
            NSColor(calibratedWhite: 1, alpha: 0)
        ])?.draw(in: spec, angle: -90)

        // Secondary glint.
        NSColor(calibratedWhite: 1, alpha: 0.28).setFill()
        NSBezierPath(ovalIn: NSRect(
            x: p.x + r * 0.28,
            y: p.y - r * 0.12,
            width: r * 0.16,
            height: r * 0.12
        )).fill()

        // Rim
        let rim = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
        rim.lineWidth = max(0.8, r * 0.028)
        NSColor(calibratedWhite: 0, alpha: 0.35).setStroke()
        rim.stroke()
        NSColor(calibratedWhite: 1, alpha: 0.12).setStroke()
        NSBezierPath(ovalIn: rect.insetBy(dx: r * 0.04, dy: r * 0.04)).stroke()
    }
}

private extension NSBezierPath {
    func fill(with color: NSColor) {
        color.setFill()
        fill()
    }
}
