import CoreGraphics
import Foundation

@inline(__always) func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
@inline(__always) func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }
func smoothstep(_ t: CGFloat) -> CGFloat { let x = clamp(t, 0, 1); return x * x * (3 - 2 * x) }
func rnd(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a < b ? CGFloat.random(in: a...b) : a }
func rndD(_ a: Double, _ b: Double) -> Double { a < b ? Double.random(in: a...b) : a }
func chance(_ p: Double) -> Bool { Double.random(in: 0..<1) < p }
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

extension CGPoint {
    init(_ x: CGFloat, _ y: CGFloat) { self.init(x: x, y: y) }
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, k: CGFloat) -> CGPoint { CGPoint(x: a.x * k, y: a.y * k) }
    static func += (a: inout CGPoint, b: CGPoint) { a = a + b }
    var length: CGFloat { hypot(x, y) }
    func distance(to p: CGPoint) -> CGFloat { hypot(x - p.x, y - p.y) }
    var normalized: CGPoint {
        let l = length
        return l > 0.0001 ? CGPoint(x: x / l, y: y / l) : .zero
    }
    func mix(_ b: CGPoint, _ t: CGFloat) -> CGPoint { CGPoint(x: x + (b.x - x) * t, y: y + (b.y - y) * t) }
}

extension CGColor {
    func alpha(_ a: CGFloat) -> CGColor { copy(alpha: a) ?? self }
}
