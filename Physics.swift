import Foundation
import CoreGraphics

enum CradleSide {
    case left, right
}

struct Ball {
    var theta: Double
    var omega: Double
    var pivotX: Double
    var pivotY: Double
    var length: Double
    var radius: Double

    var position: CGPoint {
        CGPoint(
            x: pivotX + length * sin(theta),
            y: pivotY - length * cos(theta)
        )
    }

    var velocity: (dx: Double, dy: Double) {
        (
            length * cos(theta) * omega,
            length * sin(theta) * omega
        )
    }

    mutating func setCartesianVelocity(dx: Double, dy: Double) {
        let tangential = dx * cos(theta) + dy * sin(theta)
        omega = tangential / max(length, 1e-6)
    }
}

final class Simulation {
    var balls: [Ball] = []
    private var lastPullSeq: UInt64 = 0
    private var quietTime: Double = 0
    private var demoCooldown: Double = 2.5

    func layout(in rect: CGRect) {
        let count = 5
        let R = Double(min(rect.width, rect.height)) * 0.042
        let L = R * 7.35
        let spacing = 2 * R
        let total = spacing * Double(count - 1)
        let startX = Double(rect.midX) - total / 2
        let pivotY = Double(rect.midY) + L * 0.18

        if balls.count != count {
            balls = (0..<count).map { i in
                Ball(
                    theta: 0, omega: 0,
                    pivotX: startX + Double(i) * spacing,
                    pivotY: pivotY,
                    length: L,
                    radius: R
                )
            }
        } else {
            for i in 0..<count {
                balls[i].pivotX = startX + Double(i) * spacing
                balls[i].pivotY = pivotY
                balls[i].length = L
                balls[i].radius = R
            }
        }
    }

    func pull(_ side: CradleSide, count: Int, angle: Double = 0.92) {
        guard !balls.isEmpty else { return }
        let n = max(1, min(count, balls.count - 1))
        switch side {
        case .left:
            for i in 0..<n {
                balls[i].theta = -angle
                balls[i].omega = 0
            }
        case .right:
            for i in (balls.count - n)..<balls.count {
                balls[i].theta = angle
                balls[i].omega = 0
            }
        }
        quietTime = 0
        demoCooldown = 6
    }

    var energy: Double {
        balls.reduce(0) { $0 + $1.omega * $1.omega * 8 + $1.theta * $1.theta }
    }

    func step(dt: Double, hub: MotionHub) {
        guard balls.count >= 2 else { return }

        if hub.pullSeq != lastPullSeq {
            lastPullSeq = hub.pullSeq
            if let payload = hub.pullPayload {
                pull(payload.side, count: payload.count)
            }
        }

        if abs(hub.jerkImpulse) > 0.002 {
            let j = hub.jerkImpulse
            if j < 0 {
                balls[0].omega += j * 2.4
            } else {
                balls[balls.count - 1].omega += j * 2.4
            }
            quietTime = 0
        }

        let gScale: Double = 1650
        let gx = hub.gravityX * gScale
        let gy = hub.gravityY * gScale
        let damping = 0.085

        let sub = 10
        let h = min(dt, 0.05) / Double(sub)
        for _ in 0..<sub {
            integrate(dt: h, gx: gx, gy: gy, damping: damping)
            for _ in 0..<5 {
                collideNeighbors()
            }
        }

        if hub.autoDemo && !hub.paused {
            demoCooldown = max(0, demoCooldown - dt)
            if energy < 0.045 {
                quietTime += dt
            } else {
                quietTime = 0
            }
            if quietTime > 7.5 && demoCooldown == 0 {
                let n = Bool.random() ? 1 : 2
                pull(Bool.random() ? .left : .right, count: n, angle: Double.random(in: 0.72...1.05))
            }
        }
    }

    private func integrate(dt: Double, gx: Double, gy: Double, damping: Double) {
        for i in 0..<balls.count {
            let th = balls[i].theta
            let L = balls[i].length
            let alpha = (sin(th) * gy + cos(th) * gx) / L
            balls[i].omega += alpha * dt
            balls[i].omega *= max(0, 1 - damping * dt)
            balls[i].theta += balls[i].omega * dt
            if balls[i].theta > 2.55 { balls[i].theta = 2.55; balls[i].omega = min(0, balls[i].omega) }
            if balls[i].theta < -2.55 { balls[i].theta = -2.55; balls[i].omega = max(0, balls[i].omega) }
        }
    }

    private func collideNeighbors() {
        let e = 0.985
        for i in 0..<(balls.count - 1) {
            collide(i, i + 1, restitution: e)
        }
    }

    private func collide(_ i: Int, _ j: Int, restitution e: Double) {
        let a = balls[i]
        let b = balls[j]
        let pa = a.position
        let pb = b.position
        var dx = Double(pb.x - pa.x)
        var dy = Double(pb.y - pa.y)
        var dist = hypot(dx, dy)
        let minD = a.radius + b.radius + 0.35
        if dist < 1e-9 {
            dx = minD
            dy = 0
            dist = minD
        }
        if dist >= minD { return }

        let nx = dx / dist
        let ny = dy / dist
        var va = a.velocity
        var vb = b.velocity
        let vn = (vb.dx - va.dx) * nx + (vb.dy - va.dy) * ny

        if vn < 0 {
            let impulse = -(1 + e) * vn / 2
            va.dx -= impulse * nx
            va.dy -= impulse * ny
            vb.dx += impulse * nx
            vb.dy += impulse * ny
            balls[i].setCartesianVelocity(dx: va.dx, dy: va.dy)
            balls[j].setCartesianVelocity(dx: vb.dx, dy: vb.dy)
        }

        let overlap = minD - dist
        let corr = overlap * 0.52
        let thi = balls[i].theta
        let thj = balls[j].theta
        balls[i].theta += ((-nx) * cos(thi) + (-ny) * sin(thi)) * corr / a.length
        balls[j].theta += (( nx) * cos(thj) + ( ny) * sin(thj)) * corr / b.length
    }
}
