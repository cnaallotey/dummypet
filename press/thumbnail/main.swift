// Renders the animated Product Hunt thumbnail (240x240 looping GIF) with the app's own dog renderer.
// Built and run by press/render-thumbnail.sh together with Sources/*.swift (minus Sources/main.swift).
import AppKit
import ImageIO
import UniformTypeIdentifiers

let size = 240
let frames = 24
let delay = 0.06
let loop = Double(frames) * delay
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "thumbnail.gif"

guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.gif.identifier as CFString, frames, nil) else {
    fatalError("cannot create \(out)")
}
CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)

for i in 0..<frames {
    let t = Double(i) * delay
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let g = NSGraphicsContext(bitmapImageRep: rep) else { continue }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = g
    let ctx = g.cgContext
    let S = CGFloat(size)

    // Sky and grass, matching the app icon.
    let colors = [rgb(0.62, 0.84, 1.0), rgb(0.88, 0.95, 1.0)] as CFArray
    if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])
    }
    let ground = S * 0.22
    ctx.setFillColor(rgb(0.47, 0.80, 0.42)); ctx.fill(CGRect(x: 0, y: 0, width: S, height: ground))
    ctx.setFillColor(rgb(0.40, 0.72, 0.36)); ctx.fill(CGRect(x: 0, y: ground - 2, width: S, height: 2))

    let dog = Dog()
    dog.pose = .sit
    dog.pose.tongue = 1
    dog.pose.mouth = 0.35
    dog.pose.tailWag = 0.5
    dog.pose.earLift = 0.08 * CGFloat(sin(2 * .pi * t / loop * 2))
    dog.pose.happyEyes = (i >= 8 && i < 14) ? 1 : 0          // a happy squint mid-loop
    dog.blinking = (i == 19 || i == 20) ? 1 : 0               // and a blink near the end
    dog.tailSpeed = CGFloat(2 * .pi * 3 / loop)               // exactly three wags per loop
    dog.facing = 1
    dog.facingSmooth = 1
    let s = S * 0.5 / 76
    dog.x = S * 0.52
    drawDog(ctx, dog: dog, coat: Coat.all[0], scale: s, groundY: ground - 2, time: t, look: CGPoint(0.4, 0.15), dirt: 0)
    drawBall(ctx, at: CGPoint(S * 0.84, ground + S * 0.045), r: S * 0.045, spin: 0.5)

    // A heart floats up and fades across the loop.
    let u = CGFloat(t / loop)
    drawHeart(ctx, at: CGPoint(S * 0.2 + 6 * sin(u * 2 * .pi), S * (0.62 + 0.22 * u)), size: S * 0.045,
              color: rgb(0.96, 0.33, 0.45, 1 - u))

    NSGraphicsContext.restoreGraphicsState()
    if let img = rep.cgImage {
        CGImageDestinationAddImage(dest, img, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
    }
}
if !CGImageDestinationFinalize(dest) { fatalError("could not write \(out)") }
print("  \(out)")
