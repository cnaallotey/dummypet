import AppKit

// MARK: - Dog skeleton transforms

/// Coordinate frames for one dog: head → body → dog-local → screen.
/// Dog-local space has its origin between the feet, +x pointing toward the snout.
struct DogFrames {
    let world: CGAffineTransform
    let body: CGAffineTransform
    let head: CGAffineTransform

    init(dog d: Dog, scale s: CGFloat, groundY gy: CGFloat) {
        let p = d.pose
        let bob = abs(sin(d.phase)) * 2.2 * min(p.walk, 1.2)
        let pivot = CGPoint(-18, -6)
        body = CGAffineTransform(translationX: -pivot.x, y: -pivot.y)
            .concatenating(CGAffineTransform(rotationAngle: p.bodyAngle))
            .concatenating(CGAffineTransform(translationX: pivot.x, y: pivot.y + p.bodyY + bob))
        head = CGAffineTransform(rotationAngle: p.headAngle)
            .concatenating(CGAffineTransform(translationX: p.headX, y: p.headY))
        var f = d.facingSmooth
        if abs(f) < 0.08 { f = f < 0 ? -0.08 : 0.08 }
        let cy = p.bodyY
        world = CGAffineTransform(translationX: 0, y: -cy)
            .concatenating(CGAffineTransform(rotationAngle: d.roll + d.wobble))
            .concatenating(CGAffineTransform(translationX: 0, y: cy))
            .concatenating(CGAffineTransform(scaleX: s * f, y: s))
            .concatenating(CGAffineTransform(translationX: d.x, y: gy + d.y))
    }

    func fromLocal(_ p: CGPoint) -> CGPoint { p.applying(world) }
    func fromBody(_ p: CGPoint) -> CGPoint { p.applying(body).applying(world) }
    func fromHead(_ p: CGPoint) -> CGPoint { p.applying(head).applying(body).applying(world) }
}

/// Neck base and the point where the collar sits, in body space.
func neckGeometry(_ p: Pose) -> (base: CGPoint, collar: CGPoint, dir: CGPoint) {
    let base = CGPoint(18, 6)
    let top = CGPoint(p.headX - 4, p.headY - 5)
    let dir = (top - base).normalized
    return (base, base.mix(top, 0.5), dir)
}

// MARK: - Small drawing helpers

private func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2), transform: nil)
}

private func fillStroke(_ ctx: CGContext, _ path: CGPath, _ fill: CGColor, _ stroke: CGColor?, _ width: CGFloat = 1.8) {
    ctx.addPath(path)
    ctx.setFillColor(fill)
    ctx.fillPath()
    if let stroke = stroke {
        ctx.addPath(path)
        ctx.setStrokeColor(stroke)
        ctx.setLineWidth(width)
        ctx.setLineJoin(.round)
        ctx.strokePath()
    }
}

private func strokeLine(_ ctx: CGContext, _ a: CGPoint, _ b: CGPoint, _ color: CGColor, _ width: CGFloat) {
    ctx.move(to: a)
    ctx.addLine(to: b)
    ctx.setStrokeColor(color)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.strokePath()
}

func drawText(_ s: String, center: CGPoint, size: CGFloat, color: NSColor = .white,
              weight: NSFont.Weight = .bold) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
    ]
    let str = NSAttributedString(string: s, attributes: attrs)
    let sz = str.size()
    str.draw(at: CGPoint(x: center.x - sz.width / 2, y: center.y - sz.height / 2))
}

private func floppyEar() -> CGPath {
    let e = CGMutablePath()
    e.move(to: CGPoint(-6, 2))
    e.addQuadCurve(to: CGPoint(-5, -20), control: CGPoint(-12, -8))
    e.addQuadCurve(to: CGPoint(5, -17), control: CGPoint(0, -27))
    e.addQuadCurve(to: CGPoint(6, 2), control: CGPoint(8, -6))
    e.closeSubpath()
    return e
}

private func triangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGPath {
    let p = CGMutablePath()
    p.move(to: a); p.addLine(to: b); p.addLine(to: c); p.closeSubpath()
    return p
}

// MARK: - The dog

func drawDog(_ ctx: CGContext, dog d: Dog, coat c: Coat, scale s: CGFloat, groundY gy: CGFloat,
             time: Double, look: CGPoint, dirt: CGFloat) {
    let p = d.pose
    let t = CGFloat(time)
    let fr = DogFrames(dog: d, scale: s, groundY: gy)
    let ol = c.outline

    // Ground shadow
    let lift = min(d.y / 300, 0.6)
    let sw = 80 * s * (1 - lift * 0.6)
    ctx.setFillColor(rgb(0, 0, 0, 0.17 * (1 - lift)))
    ctx.fillEllipse(in: CGRect(x: d.x - sw / 2, y: gy - 3 * s, width: sw, height: 9 * s))

    ctx.saveGState()
    ctx.concatenate(fr.world)

    // Leg end points, in dog-local space
    let w = p.walk
    let ph = d.phase
    func stepOff(_ o: CGFloat) -> CGPoint { CGPoint(sin(ph + o) * 9 * w, max(0, cos(ph + o)) * 6 * w) }
    func wig(_ i: CGFloat) -> CGPoint {
        CGPoint(sin(t * 15 + i * 1.7) * 4 * p.legWiggle, cos(t * 13 + i * 2.3) * 4 * p.legWiggle)
    }
    func scr(_ o: CGFloat) -> CGPoint { CGPoint(sin(t * 26 + o) * 8 * p.scratch, abs(cos(t * 26 + o)) * 6 * p.scratch) }
    let shoulderN = CGPoint(20, -8).applying(fr.body)
    let shoulderF = CGPoint(16, -8).applying(fr.body)
    let hipN = CGPoint(-19, -6).applying(fr.body)
    let hipF = CGPoint(-23, -6).applying(fr.body)
    let footFN = p.frontFoot + stepOff(0) + p.pawRaise + wig(0) + scr(0)
    let footFF = p.frontFoot + CGPoint(-5, 0) + stepOff(.pi) + wig(1) + scr(.pi)
    let footBN = p.backFoot + stepOff(.pi) + wig(2)
    let footBF = p.backFoot + CGPoint(-5, 0) + stepOff(0) + wig(3)

    func leg(_ a: CGPoint, _ b: CGPoint, _ color: CGColor) {
        strokeLine(ctx, a, b, ol, 11)
        strokeLine(ctx, a, b, color, 7.6)
        fillStroke(ctx, ellipse(b.x + 1.5, b.y + 2.5, 5.6, 4.2), color, ol, 1.6)
    }

    // Far side legs
    leg(shoulderF, footFF, c.shade)
    leg(hipF, footBF, c.shade)

    // Tail + body
    ctx.saveGState()
    ctx.concatenate(fr.body)
    let ta = p.tailAngle + sin(t * d.tailSpeed) * p.tailWag
    let tdir = CGPoint(-cos(ta), sin(ta))
    let tbase = CGPoint(-28, 5)
    let ttip = tbase + tdir * 24
    let tctrl = tbase + tdir * 14 + CGPoint(-tdir.y, tdir.x) * -5
    let tail = CGMutablePath()
    tail.move(to: tbase)
    tail.addQuadCurve(to: ttip, control: tctrl)
    ctx.addPath(tail); ctx.setStrokeColor(ol); ctx.setLineWidth(9.5); ctx.setLineCap(.round); ctx.strokePath()
    ctx.addPath(tail); ctx.setStrokeColor(c.base); ctx.setLineWidth(6.2); ctx.strokePath()
    if c.pattern == .husky || c.pointy {
        ctx.setFillColor(c.belly)
        ctx.fillEllipse(in: CGRect(x: ttip.x - 3, y: ttip.y - 3, width: 6, height: 6))
    }

    let bodyPath = ellipse(0, 0, 31, 16)
    ctx.addPath(bodyPath); ctx.setFillColor(c.base); ctx.fillPath()
    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.clip()
    ctx.addPath(ellipse(3, -12, 24, 8)); ctx.setFillColor(c.belly); ctx.fillPath()
    switch c.pattern {
    case .spots:
        ctx.setFillColor(c.dark)
        let spots: [(CGFloat, CGFloat, CGFloat)] = [(-14, 6, 5), (4, -3, 4), (14, 8, 3.5), (-22, -5, 3), (-3, 11, 3), (21, -2, 3)]
        for sp in spots { ctx.addPath(ellipse(sp.0, sp.1, sp.2, sp.2 * 0.85)) }
        ctx.fillPath()
    case .husky:
        ctx.addPath(ellipse(-6, 13, 27, 12)); ctx.setFillColor(c.dark); ctx.fillPath()
    case .shiba, .plain:
        break
    }
    if dirt > 0.01 {
        ctx.setFillColor(rgb(0.42, 0.30, 0.18, 0.75 * dirt))
        let blots: [(CGFloat, CGFloat, CGFloat)] = [(-10, 2, 4), (8, 6, 3), (18, -6, 3.5), (-20, -8, 3), (0, -10, 2.5)]
        for b in blots { ctx.addPath(ellipse(b.0, b.1, b.2, b.2 * 0.8)) }
        ctx.fillPath()
    }
    ctx.restoreGState()
    ctx.addPath(bodyPath); ctx.setStrokeColor(ol); ctx.setLineWidth(1.8); ctx.strokePath()
    ctx.restoreGState()

    // Near side legs
    leg(hipN, footBN, c.base)
    leg(shoulderN, footFN, c.base)

    // Haunch, neck, collar, head (body space)
    ctx.saveGState()
    ctx.concatenate(fr.body)
    fillStroke(ctx, ellipse(-17, -1, 13, 14), c.base, ol)
    if c.pattern == .spots {
        ctx.setFillColor(c.dark); ctx.fillEllipse(in: CGRect(x: -21, y: 2, width: 6, height: 5))
    }

    let neck = neckGeometry(p)
    strokeLine(ctx, neck.base, CGPoint(p.headX - 4, p.headY - 5), c.base, 17)
    let perp = CGPoint(-neck.dir.y, neck.dir.x)
    strokeLine(ctx, neck.collar + perp * 8.5, neck.collar - perp * 8.5, rgb(0.55, 0.08, 0.14), 6.2)
    strokeLine(ctx, neck.collar + perp * 8.5, neck.collar - perp * 8.5, rgb(0.88, 0.22, 0.28), 4.2)
    let tag = neck.collar - perp * 10.5
    fillStroke(ctx, ellipse(tag.x, tag.y, 2.9, 2.9), rgb(0.99, 0.80, 0.25), rgb(0.6, 0.45, 0.1), 1)

    ctx.saveGState()
    ctx.concatenate(fr.head)
    let earBounce = sin(ph * 2) * 0.12 * w + sin(t * 3) * 0.03

    // Far ear
    if c.pointy {
        fillStroke(ctx, triangle(CGPoint(-1, 10), CGPoint(5, 29 + p.earLift * 4), CGPoint(10, 11)), c.shade, ol)
    } else {
        ctx.saveGState()
        ctx.translateBy(x: 1, y: 13)
        ctx.rotate(by: 0.35 - p.earLift * 1.3 + earBounce)
        fillStroke(ctx, floppyEar(), c.shade == c.base ? c.dark : c.dark.alpha(0.9), ol)
        ctx.restoreGState()
    }

    // Skull
    let headPath = ellipse(0, 0, 17, 16.5)
    ctx.addPath(headPath); ctx.setFillColor(c.base); ctx.fillPath()
    ctx.saveGState()
    ctx.addPath(headPath); ctx.clip()
    switch c.pattern {
    case .husky:
        ctx.addPath(ellipse(9, -8, 15, 10)); ctx.setFillColor(c.belly); ctx.fillPath()
        ctx.addPath(ellipse(-8, 12, 12, 9)); ctx.setFillColor(c.dark); ctx.fillPath()
        ctx.setFillColor(c.belly); ctx.fillEllipse(in: CGRect(x: 5, y: 8.5, width: 4.5, height: 3.5))
    case .shiba:
        ctx.addPath(ellipse(9, -8, 15, 9.5)); ctx.setFillColor(c.belly); ctx.fillPath()
    case .spots:
        ctx.setFillColor(c.dark); ctx.fillEllipse(in: CGRect(x: -11, y: 2, width: 8, height: 7))
    case .plain:
        break
    }
    ctx.restoreGState()
    ctx.addPath(headPath); ctx.setStrokeColor(ol); ctx.setLineWidth(1.8); ctx.strokePath()

    // Snout + mouth
    fillStroke(ctx, ellipse(14, -5, 11.5, 7.5), c.muzzle, ol)
    if p.mouth > 0.05 {
        ctx.addPath(ellipse(13, -11.5 - p.mouth * 2.5, 7.5, 1.5 + p.mouth * 4))
        ctx.setFillColor(rgb(0.45, 0.08, 0.12)); ctx.fillPath()
    }
    if p.tongue > 0.05 {
        let bob = sin(t * 12) * 1.2 * p.tongue
        let ty = -12 - p.mouth * 4 - p.tongue * 4 + bob
        fillStroke(ctx, ellipse(15.5, ty, 3.9, 2.5 + 4.5 * p.tongue), rgb(0.96, 0.46, 0.56), rgb(0.75, 0.25, 0.35), 1.1)
        strokeLine(ctx, CGPoint(15.5, ty + 2), CGPoint(15.5, ty - 2.5 * p.tongue), rgb(0.8, 0.3, 0.4), 0.9)
    }
    if p.mouth > 0.05 {
        fillStroke(ctx, ellipse(12.5, -12 - p.mouth * 6, 7, 3), c.muzzle, ol, 1.4)
    }
    let smile = CGMutablePath()
    smile.move(to: CGPoint(23.5, -8))
    smile.addQuadCurve(to: CGPoint(12, -9), control: CGPoint(18, -12.5 - p.happyEyes * 1.5))
    ctx.addPath(smile); ctx.setStrokeColor(ol); ctx.setLineWidth(1.4); ctx.strokePath()

    // Nose
    fillStroke(ctx, ellipse(25, -1.5, 4.4, 3.4), rgb(0.1, 0.08, 0.08), nil)
    ctx.setFillColor(rgb(1, 1, 1, 0.55))
    ctx.fillEllipse(in: CGRect(x: 25, y: -0.5, width: 2.2, height: 1.4))

    // Eye
    let open = d.blinking > 0 ? 0 : p.eyeOpen
    let eyeInk = rgb(0.07, 0.06, 0.06)
    if d.xEyes {
        strokeLine(ctx, CGPoint(3.5, 2.5), CGPoint(8.5, 7.5), eyeInk, 1.8)
        strokeLine(ctx, CGPoint(3.5, 7.5), CGPoint(8.5, 2.5), eyeInk, 1.8)
    } else if open < 0.25 {
        let e = CGMutablePath()
        e.move(to: CGPoint(2.5, 5)); e.addQuadCurve(to: CGPoint(9.5, 5), control: CGPoint(6, 2))
        ctx.addPath(e); ctx.setStrokeColor(eyeInk); ctx.setLineWidth(1.8); ctx.strokePath()
    } else if p.happyEyes > 0.5 {
        let e = CGMutablePath()
        e.move(to: CGPoint(2.5, 3.5)); e.addQuadCurve(to: CGPoint(9.5, 3.5), control: CGPoint(6, 9.5))
        ctx.addPath(e); ctx.setStrokeColor(eyeInk); ctx.setLineWidth(2); ctx.strokePath()
    } else {
        let ex = 6 + look.x * 1.3
        let ey = 5 + look.y * 1.1
        ctx.addPath(ellipse(ex, ey, 3.3, 3.6 * open)); ctx.setFillColor(eyeInk); ctx.fillPath()
        ctx.setFillColor(rgb(1, 1, 1, 0.95))
        ctx.fillEllipse(in: CGRect(x: ex + 0.1, y: ey + 0.4 * open, width: 2.1, height: 2.1 * open))
    }
    if p.happyEyes > 0.2 {
        ctx.setFillColor(rgb(1, 0.45, 0.55, 0.45 * p.happyEyes))
        ctx.fillEllipse(in: CGRect(x: 0, y: -4.5, width: 7, height: 4))
    }

    // Near ear
    if c.pointy {
        ctx.saveGState()
        ctx.translateBy(x: -4, y: 12)
        ctx.rotate(by: -p.earLift * 0.6)
        ctx.translateBy(x: 4, y: -12)
        fillStroke(ctx, triangle(CGPoint(-12, 8), CGPoint(-6, 31 + p.earLift * 3), CGPoint(4, 13)), c.base, ol)
        fillStroke(ctx, triangle(CGPoint(-8.5, 11), CGPoint(-6, 25), CGPoint(0, 14)), rgb(0.96, 0.7, 0.72), nil)
        ctx.restoreGState()
    } else {
        ctx.saveGState()
        ctx.translateBy(x: -6, y: 12)
        ctx.rotate(by: 0.2 - p.earLift * 1.3 + earBounce)
        fillStroke(ctx, floppyEar(), c.dark, ol)
        ctx.restoreGState()
    }

    if d.foam > 0.01 {
        ctx.setFillColor(rgb(1, 1, 1, 0.92 * d.foam))
        for f in [(-2.0, 15.0, 7.0), (7.0, 14.0, 5.0), (-10.0, 10.0, 5.0)] as [(CGFloat, CGFloat, CGFloat)] {
            ctx.addPath(ellipse(f.0, f.1, f.2 * d.foam, f.2 * d.foam))
        }
        ctx.fillPath()
    }
    ctx.restoreGState() // head

    if d.foam > 0.01 {
        ctx.setFillColor(rgb(1, 1, 1, 0.92 * d.foam))
        let blobs: [(CGFloat, CGFloat, CGFloat)] = [(-18, 14, 7), (-6, 17, 8), (8, 15, 7), (20, 11, 6), (-27, 5, 5), (-14, -2, 5)]
        for b in blobs { ctx.addPath(ellipse(b.0, b.1, b.2 * d.foam, b.2 * d.foam)) }
        ctx.fillPath()
    }
    ctx.restoreGState() // body
    ctx.restoreGState() // world
}

// MARK: - Props

func drawBall(_ ctx: CGContext, at c: CGPoint, r: CGFloat, spin: CGFloat) {
    let path = ellipse(c.x, c.y, r, r)
    fillStroke(ctx, path, rgb(0.84, 0.93, 0.26), rgb(0.42, 0.52, 0.08), 1.5)
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.rotate(by: spin)
    ctx.setStrokeColor(rgb(1, 1, 1, 0.95))
    ctx.setLineWidth(max(1.2, r * 0.18))
    ctx.addArc(center: CGPoint(-r * 1.25, 0), radius: r * 0.95, startAngle: -0.9, endAngle: 0.9, clockwise: false)
    ctx.strokePath()
    ctx.addArc(center: CGPoint(r * 1.25, 0), radius: r * 0.95, startAngle: .pi - 0.9, endAngle: .pi + 0.9, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()
    ctx.setFillColor(rgb(1, 1, 1, 0.35))
    ctx.fillEllipse(in: CGRect(x: c.x - r * 0.55, y: c.y + r * 0.2, width: r * 0.6, height: r * 0.45))
}

func drawBone(_ ctx: CGContext, at c: CGPoint, r: CGFloat, spin: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.rotate(by: spin)
    let p = CGMutablePath()
    p.addRoundedRect(in: CGRect(x: -r * 0.75, y: -r * 0.24, width: r * 1.5, height: r * 0.48), cornerWidth: r * 0.2, cornerHeight: r * 0.2)
    for sx in [-1.0, 1.0] as [CGFloat] {
        for sy in [-1.0, 1.0] as [CGFloat] {
            p.addEllipse(in: CGRect(x: sx * r * 0.78 - r * 0.32, y: sy * r * 0.24 - r * 0.32, width: r * 0.64, height: r * 0.64))
        }
    }
    ctx.addPath(p); ctx.setStrokeColor(rgb(0.55, 0.38, 0.22)); ctx.setLineWidth(2.6); ctx.strokePath()
    ctx.addPath(p); ctx.setFillColor(rgb(0.95, 0.86, 0.68)); ctx.fillPath()
    ctx.restoreGState()
}

func drawPoop(_ ctx: CGContext, at c: CGPoint, r: CGFloat, time: Double) {
    let brown = rgb(0.47, 0.30, 0.15)
    let edge = rgb(0.28, 0.17, 0.08)
    let base = c.y - r * 0.5
    fillStroke(ctx, ellipse(c.x, base + r * 0.32, r, r * 0.38), brown, edge, 1.4)
    fillStroke(ctx, ellipse(c.x + r * 0.05, base + r * 0.75, r * 0.72, r * 0.32), brown, edge, 1.4)
    fillStroke(ctx, ellipse(c.x + r * 0.1, base + r * 1.12, r * 0.42, r * 0.27), brown, edge, 1.4)
    ctx.setFillColor(rgb(1, 1, 1, 0.3))
    ctx.fillEllipse(in: CGRect(x: c.x - r * 0.5, y: base + r * 0.4, width: r * 0.35, height: r * 0.15))
    // stink lines
    let t = CGFloat(time)
    ctx.setStrokeColor(rgb(0.45, 0.6, 0.25, 0.55))
    ctx.setLineWidth(1.4)
    for i in 0..<2 {
        let x0 = c.x + CGFloat(i == 0 ? -r * 0.4 : r * 0.45)
        let y0 = base + r * 1.5
        let path = CGMutablePath()
        path.move(to: CGPoint(x0, y0))
        for k in 1...6 {
            let yy = y0 + CGFloat(k) * r * 0.22
            path.addLine(to: CGPoint(x0 + sin(t * 4 + CGFloat(k) + CGFloat(i) * 2) * r * 0.18, yy))
        }
        ctx.addPath(path); ctx.strokePath()
    }
    // flies
    for i in 0..<2 {
        let a = t * (3.2 + CGFloat(i)) + CGFloat(i) * 3
        let fp = CGPoint(c.x + cos(a) * r * 1.4, base + r * 1.6 + sin(a * 1.7) * r * 0.6)
        ctx.setFillColor(rgb(1, 1, 1, 0.7))
        let flap = abs(sin(t * 40 + CGFloat(i))) * 2.2
        ctx.fillEllipse(in: CGRect(x: fp.x - 2.5, y: fp.y, width: 2.5, height: 1 + flap))
        ctx.fillEllipse(in: CGRect(x: fp.x + 0.2, y: fp.y, width: 2.5, height: 1 + flap))
        ctx.setFillColor(rgb(0.08, 0.08, 0.08))
        ctx.fillEllipse(in: CGRect(x: fp.x - 1.5, y: fp.y - 1.5, width: 3, height: 3))
    }
}

func drawBowl(_ ctx: CGContext, _ b: Bowl, groundY gy: CGFloat, scale s: CGFloat) {
    ctx.saveGState()
    ctx.setAlpha(b.alpha)
    let w: CGFloat = 26 * s, h: CGFloat = 15 * s, x = b.x
    ctx.setFillColor(rgb(0, 0, 0, 0.15))
    ctx.fillEllipse(in: CGRect(x: x - w * 1.05, y: gy - 3 * s, width: w * 2.1, height: 7 * s))
    if b.food > 0.01 {
        let mound = 2 * s + b.food * 8 * s
        fillStroke(ctx, ellipse(x, gy + h, w * 0.85, mound), rgb(0.62, 0.38, 0.18), rgb(0.4, 0.22, 0.1), 1.2)
        ctx.setFillColor(rgb(0.48, 0.27, 0.12))
        for i in 0..<9 {
            let fx = x + (CGFloat(i) - 4) * w * 0.17
            let fy = gy + h + mound * (0.2 + 0.5 * abs(sin(CGFloat(i) * 1.9)))
            ctx.fillEllipse(in: CGRect(x: fx - 2.2 * s, y: fy - 1.6 * s, width: 4.4 * s, height: 3.2 * s))
        }
    }
    let body = CGMutablePath()
    body.move(to: CGPoint(x - w, gy + h))
    body.addLine(to: CGPoint(x + w, gy + h))
    body.addLine(to: CGPoint(x + w * 0.76, gy))
    body.addLine(to: CGPoint(x - w * 0.76, gy))
    body.closeSubpath()
    fillStroke(ctx, body, rgb(0.86, 0.27, 0.32), rgb(0.5, 0.1, 0.15), 1.6)
    fillStroke(ctx, ellipse(x, gy + h, w, 3.5 * s), rgb(0.95, 0.42, 0.46), rgb(0.5, 0.1, 0.15), 1.4)
    // paw print decal
    ctx.setFillColor(rgb(1, 1, 1, 0.85))
    let pc = CGPoint(x, gy + h * 0.42)
    ctx.fillEllipse(in: CGRect(x: pc.x - 3 * s, y: pc.y - 2.6 * s, width: 6 * s, height: 4.8 * s))
    for k in 0..<3 {
        let kx = pc.x + (CGFloat(k) - 1) * 3.4 * s
        let ky = pc.y + 3.2 * s + (k == 1 ? 1 * s : 0)
        ctx.fillEllipse(in: CGRect(x: kx - 1.3 * s, y: ky - 1.3 * s, width: 2.6 * s, height: 2.6 * s))
    }
    ctx.restoreGState()
}

func drawHeart(_ ctx: CGContext, at c: CGPoint, size s: CGFloat, color: CGColor) {
    ctx.setFillColor(color)
    ctx.fillEllipse(in: CGRect(x: c.x - s, y: c.y - s * 0.35, width: s * 1.1, height: s * 1.1))
    ctx.fillEllipse(in: CGRect(x: c.x - s * 0.1, y: c.y - s * 0.35, width: s * 1.1, height: s * 1.1))
    let tri = triangle(CGPoint(c.x - s * 0.97, c.y + s * 0.05), CGPoint(c.x + s * 0.97, c.y + s * 0.05), CGPoint(c.x, c.y - s * 1.05))
    ctx.addPath(tri); ctx.fillPath()
}

func drawSparkle(_ ctx: CGContext, at c: CGPoint, size s: CGFloat, rot: CGFloat, color: CGColor) {
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.rotate(by: rot)
    let p = CGMutablePath()
    for i in 0..<8 {
        let a = CGFloat(i) * .pi / 4
        let r = i % 2 == 0 ? s : s * 0.3
        let pt = CGPoint(cos(a) * r, sin(a) * r)
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    ctx.addPath(p); ctx.setFillColor(color); ctx.fillPath()
    ctx.restoreGState()
}

func drawButterfly(_ ctx: CGContext, _ b: Butterfly, time: Double) {
    let flap = 0.25 + 0.75 * abs(sin(CGFloat(time) * 15 + b.phase))
    ctx.saveGState()
    ctx.translateBy(x: b.pos.x, y: b.pos.y)
    ctx.scaleBy(x: b.vx >= 0 ? 1 : -1, y: 1)
    ctx.rotate(by: 0.2)
    ctx.setFillColor(b.color)
    ctx.addPath(ellipse(-4 * flap, 4, 7 * flap, 6.5))
    ctx.addPath(ellipse(-3 * flap, -3, 5 * flap, 4.5))
    ctx.fillPath()
    ctx.setFillColor(rgb(1, 1, 1, 0.5))
    ctx.fillEllipse(in: CGRect(x: -6 * flap, y: 4, width: 3 * flap, height: 3))
    ctx.setFillColor(rgb(0.15, 0.1, 0.1))
    ctx.fillEllipse(in: CGRect(x: -1.5, y: -6, width: 3, height: 13))
    strokeLine(ctx, CGPoint(0, 6), CGPoint(3, 11), rgb(0.15, 0.1, 0.1), 0.8)
    ctx.restoreGState()
}

func drawFlower(_ ctx: CGContext, _ f: Flower, groundY gy: CGFloat, scale s: CGFloat, time: Double) {
    let sway = sin(CGFloat(time) * 1.6 + f.phase) * 2.5
    let h = f.height * s
    let green = rgb(0.36, 0.66, 0.30)
    switch f.kind {
    case 0:
        for i in -1...1 {
            let dx = CGFloat(i) * 3 * s
            let p = CGMutablePath()
            p.move(to: CGPoint(f.x + dx, gy))
            p.addQuadCurve(to: CGPoint(f.x + dx * 2 + sway, gy + h * (i == 0 ? 1 : 0.7)), control: CGPoint(f.x + dx, gy + h * 0.5))
            ctx.addPath(p); ctx.setStrokeColor(green); ctx.setLineWidth(1.6); ctx.strokePath()
        }
    default:
        let top = CGPoint(f.x + sway, gy + h * 1.3)
        let stem = CGMutablePath()
        stem.move(to: CGPoint(f.x, gy))
        stem.addQuadCurve(to: top, control: CGPoint(f.x, gy + h * 0.7))
        ctx.addPath(stem); ctx.setStrokeColor(green); ctx.setLineWidth(1.6); ctx.strokePath()
        if f.kind == 1 {
            ctx.setFillColor(f.color)
            for i in 0..<6 {
                let a = CGFloat(i) * .pi / 3 + f.phase
                ctx.fillEllipse(in: CGRect(x: top.x + cos(a) * 3.2 * s - 2.4 * s, y: top.y + sin(a) * 3.2 * s - 2.4 * s, width: 4.8 * s, height: 4.8 * s))
            }
            ctx.setFillColor(rgb(0.99, 0.80, 0.2))
            ctx.fillEllipse(in: CGRect(x: top.x - 2.2 * s, y: top.y - 2.2 * s, width: 4.4 * s, height: 4.4 * s))
        } else {
            let cup = CGMutablePath()
            cup.move(to: CGPoint(top.x - 4 * s, top.y + 5 * s))
            cup.addLine(to: CGPoint(top.x - 2 * s, top.y + 2.5 * s))
            cup.addLine(to: CGPoint(top.x, top.y + 5 * s))
            cup.addLine(to: CGPoint(top.x + 2 * s, top.y + 2.5 * s))
            cup.addLine(to: CGPoint(top.x + 4 * s, top.y + 5 * s))
            cup.addQuadCurve(to: CGPoint(top.x - 4 * s, top.y + 5 * s), control: CGPoint(top.x, top.y - 4 * s))
            ctx.addPath(cup); ctx.setFillColor(f.color); ctx.fillPath()
        }
    }
}

func drawLeash(_ ctx: CGContext, from a: CGPoint, to b: CGPoint) {
    let dist = a.distance(to: b)
    let sag = max(6, 90 - dist * 0.22)
    let mid = a.mix(b, 0.5) - CGPoint(0, sag)
    let p = CGMutablePath()
    p.move(to: a)
    p.addQuadCurve(to: b, control: mid)
    ctx.addPath(p); ctx.setStrokeColor(rgb(0.45, 0.06, 0.12)); ctx.setLineWidth(5.2); ctx.setLineCap(.round); ctx.strokePath()
    ctx.addPath(p); ctx.setStrokeColor(rgb(0.90, 0.25, 0.32)); ctx.setLineWidth(3.2); ctx.strokePath()
    ctx.addPath(ellipse(b.x, b.y - 6, 5.5, 8)); ctx.setStrokeColor(rgb(0.45, 0.06, 0.12)); ctx.setLineWidth(4.5); ctx.strokePath()
    ctx.addPath(ellipse(b.x, b.y - 6, 5.5, 8)); ctx.setStrokeColor(rgb(0.90, 0.25, 0.32)); ctx.setLineWidth(2.6); ctx.strokePath()
}

func drawLaser(_ ctx: CGContext, at c: CGPoint, time: Double) {
    let j = CGPoint(sin(CGFloat(time) * 37) * 0.8, cos(CGFloat(time) * 29) * 0.8)
    let p = c + j
    ctx.setFillColor(rgb(1, 0.1, 0.1, 0.12)); ctx.fillEllipse(in: CGRect(x: p.x - 14, y: p.y - 14, width: 28, height: 28))
    ctx.setFillColor(rgb(1, 0.1, 0.1, 0.35)); ctx.fillEllipse(in: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14))
    ctx.setFillColor(rgb(1, 0.25, 0.2, 1)); ctx.fillEllipse(in: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7))
    ctx.setFillColor(rgb(1, 0.9, 0.9, 1)); ctx.fillEllipse(in: CGRect(x: p.x - 1.3, y: p.y - 1.3, width: 2.6, height: 2.6))
}

func drawParticle(_ ctx: CGContext, _ p: Particle) {
    let a = p.fade
    switch p.kind {
    case .heart:
        drawHeart(ctx, at: p.pos, size: p.size * (0.7 + 0.3 * a), color: p.color.alpha(a))
    case .sparkle:
        drawSparkle(ctx, at: p.pos, size: p.size * (0.4 + 0.6 * a), rot: p.rot, color: p.color.alpha(a))
    case .crumb, .dust:
        ctx.setFillColor(p.color.alpha(a * (p.kind == .dust ? 0.5 : 1)))
        let s = p.kind == .dust ? p.size * (1.6 - a * 0.6) : p.size
        ctx.fillEllipse(in: CGRect(x: p.pos.x - s, y: p.pos.y - s, width: s * 2, height: s * 2))
    case .droplet:
        ctx.setFillColor(rgb(0.45, 0.7, 1, 0.85 * a))
        ctx.fillEllipse(in: CGRect(x: p.pos.x - p.size * 0.7, y: p.pos.y - p.size, width: p.size * 1.4, height: p.size * 2))
    case .bubble:
        let r = p.size
        ctx.setFillColor(rgb(0.85, 0.93, 1, 0.25 * a))
        ctx.fillEllipse(in: CGRect(x: p.pos.x - r, y: p.pos.y - r, width: r * 2, height: r * 2))
        ctx.setStrokeColor(rgb(0.6, 0.8, 1, 0.8 * a)); ctx.setLineWidth(1.1)
        ctx.strokeEllipse(in: CGRect(x: p.pos.x - r, y: p.pos.y - r, width: r * 2, height: r * 2))
        ctx.setFillColor(rgb(1, 1, 1, 0.8 * a))
        ctx.fillEllipse(in: CGRect(x: p.pos.x - r * 0.5, y: p.pos.y + r * 0.2, width: r * 0.45, height: r * 0.35))
    case .confetti:
        ctx.saveGState()
        ctx.translateBy(x: p.pos.x, y: p.pos.y)
        ctx.rotate(by: p.rot)
        ctx.setFillColor(p.color.alpha(a))
        ctx.fill(CGRect(x: -p.size / 2, y: -p.size / 4 * abs(cos(p.rot * 2)), width: p.size, height: p.size / 2 * abs(cos(p.rot * 2)) + 0.5))
        ctx.restoreGState()
    case .zzz, .text:
        ctx.saveGState()
        ctx.setAlpha(a)
        ctx.translateBy(x: p.pos.x, y: p.pos.y)
        ctx.rotate(by: p.rot)
        let color = p.kind == .zzz ? NSColor(calibratedRed: 0.45, green: 0.55, blue: 0.85, alpha: 1) : NSColor.white
        drawText(p.text, center: .zero, size: p.size, color: color, weight: .heavy)
        ctx.restoreGState()
    }
}
