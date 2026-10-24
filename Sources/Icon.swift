import AppKit

/// Renders the app icon from the same drawing code as the pet (used by build.sh).
enum IconRenderer {
    static func render(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let sizes: [(Int, String)] = [
            (16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
            (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"), (512, "icon_256x256@2x"),
            (512, "icon_512x512"), (1024, "icon_512x512@2x"),
        ]
        for (px, name) in sizes {
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let gctx = NSGraphicsContext(bitmapImageRep: rep) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = gctx
            draw(gctx.cgContext, size: CGFloat(px))
            NSGraphicsContext.restoreGraphicsState()
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
            }
        }
    }

    /// The DMG window backdrop (660×400 points): "drag the app to Applications" art.
    /// Icon centres in make-dmg.sh are (165, 190) and (495, 190) from the top-left.
    static func renderInstallerBackground(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for (factor, name) in [(1, "background.png"), (2, "background@2x.png")] {
            let w = 660 * factor, h = 400 * factor
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let gctx = NSGraphicsContext(bitmapImageRep: rep) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = gctx
            let ctx = gctx.cgContext
            ctx.scaleBy(x: CGFloat(factor), y: CGFloat(factor))
            drawInstaller(ctx)
            NSGraphicsContext.restoreGraphicsState()
            rep.size = NSSize(width: 660, height: 400)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
            }
        }
    }

    private static func drawInstaller(_ ctx: CGContext) {
        let W: CGFloat = 660, H: CGFloat = 400
        let colors = [rgb(0.80, 0.91, 1.0), rgb(0.96, 0.98, 1.0)] as CFArray
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])
        }
        let ground: CGFloat = 54
        ctx.setFillColor(rgb(0.52, 0.82, 0.46))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: ground))
        ctx.setFillColor(rgb(0.44, 0.74, 0.39))
        ctx.fill(CGRect(x: 0, y: ground - 3, width: W, height: 3))

        // Dashed arrow between the two icon slots (icons sit at y = 400 - 190 = 210).
        let y: CGFloat = 214
        let arrow = CGMutablePath()
        arrow.move(to: CGPoint(x: 248, y: y))
        arrow.addQuadCurve(to: CGPoint(x: 404, y: y), control: CGPoint(x: 326, y: y + 46))
        ctx.saveGState()
        ctx.addPath(arrow)
        ctx.setStrokeColor(rgb(0.16, 0.20, 0.30, 0.55))
        ctx.setLineWidth(4)
        ctx.setLineCap(.round)
        ctx.setLineDash(phase: 0, lengths: [2, 11])
        ctx.strokePath()
        ctx.restoreGState()
        let head = CGMutablePath()
        head.move(to: CGPoint(x: 392, y: y + 15))
        head.addLine(to: CGPoint(x: 410, y: y - 2))
        head.addLine(to: CGPoint(x: 388, y: y - 6))
        ctx.addPath(head)
        ctx.setStrokeColor(rgb(0.16, 0.20, 0.30, 0.55))
        ctx.setLineWidth(4)
        ctx.setLineJoin(.round)
        ctx.strokePath()

        drawText("Drag DummyPet into Applications", center: CGPoint(x: W / 2, y: H - 52), size: 20,
                 color: NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.20, alpha: 1), weight: .bold)
        drawText("Then open it from Launchpad or your Applications folder.", center: CGPoint(x: W / 2, y: H - 80), size: 13,
                 color: NSColor(calibratedRed: 0.25, green: 0.30, blue: 0.40, alpha: 1), weight: .regular)

        let dog = Dog()
        dog.pose = .sit
        dog.pose.tongue = 1
        dog.pose.mouth = 0.35
        dog.pose.tailWag = 0
        dog.facing = 1
        dog.facingSmooth = 1
        dog.x = 300
        drawDog(ctx, dog: dog, coat: Coat.all[0], scale: 0.85, groundY: ground - 4, time: 0.3,
                look: CGPoint(0.6, 0.2), dirt: 0)
        drawBall(ctx, at: CGPoint(368, ground + 4), r: 8, spin: 0.4)
    }

    private static func draw(_ ctx: CGContext, size: CGFloat) {
        let inset = size * 0.09
        let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
        let radius = rect.width * 0.225
        let shape = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.01), blur: size * 0.03, color: rgb(0, 0, 0, 0.3))
        ctx.addPath(shape); ctx.setFillColor(rgb(0.55, 0.80, 0.98)); ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(shape); ctx.clip()
        let colors = [rgb(0.62, 0.84, 1.0), rgb(0.85, 0.94, 1.0)] as CFArray
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])
        }
        let grassTop = rect.minY + rect.height * 0.26
        ctx.setFillColor(rgb(0.47, 0.80, 0.42))
        ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: grassTop - rect.minY))
        ctx.setFillColor(rgb(0.40, 0.72, 0.36))
        ctx.fill(CGRect(x: rect.minX, y: grassTop - size * 0.012, width: rect.width, height: size * 0.012))

        let dog = Dog()
        dog.pose = .sit
        dog.pose.tongue = 1
        dog.pose.mouth = 0.35
        dog.pose.tailWag = 0
        dog.pose.tailAngle = 0.9
        dog.blinking = 0
        let s = rect.height * 0.62 / 76
        dog.x = rect.midX + 2 * s
        dog.y = 0
        dog.facing = 1
        dog.facingSmooth = 1
        drawDog(ctx, dog: dog, coat: Coat.all[0], scale: s, groundY: grassTop - size * 0.02, time: 0.3,
                look: CGPoint(0.4, 0.1), dirt: 0)
        drawBall(ctx, at: CGPoint(rect.maxX - rect.width * 0.17, grassTop + rect.width * 0.05), r: rect.width * 0.065, spin: 0.5)
        drawHeart(ctx, at: CGPoint(rect.minX + rect.width * 0.2, rect.maxY - rect.height * 0.2), size: rect.width * 0.06,
                  color: rgb(0.96, 0.33, 0.45))
        ctx.restoreGState()
    }
}
