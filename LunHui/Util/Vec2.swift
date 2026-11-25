import Foundation

/// 逻辑层的二维向量。单位 pt，y 轴向上（和 SpriteKit 一致）。
struct Vec2: Codable, Equatable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    static let zero = Vec2(0, 0)
    static let up = Vec2(0, 1)

    static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    static func * (a: Vec2, s: Double) -> Vec2 { Vec2(a.x * s, a.y * s) }
    static func * (s: Double, a: Vec2) -> Vec2 { Vec2(a.x * s, a.y * s) }
    static func / (a: Vec2, s: Double) -> Vec2 { Vec2(a.x / s, a.y / s) }
    static prefix func - (a: Vec2) -> Vec2 { Vec2(-a.x, -a.y) }
    static func += (a: inout Vec2, b: Vec2) { a = a + b }
    static func -= (a: inout Vec2, b: Vec2) { a = a - b }

    var lengthSq: Double { x * x + y * y }
    var length: Double { lengthSq.squareRoot() }
    var angle: Double { atan2(y, x) }

    /// 长度为 0 时返回 fallback。
    func normalized(or fallback: Vec2 = .up) -> Vec2 {
        let l = length
        return l > 1e-9 ? self / l : fallback
    }

    func dot(_ o: Vec2) -> Double { x * o.x + y * o.y }

    func rotated(_ rad: Double) -> Vec2 {
        let c = cos(rad), s = sin(rad)
        return Vec2(x * c - y * s, x * s + y * c)
    }

    func distSq(_ o: Vec2) -> Double { (self - o).lengthSq }
    func dist(_ o: Vec2) -> Double { (self - o).length }

    static func fromAngle(_ rad: Double, _ len: Double = 1) -> Vec2 {
        Vec2(cos(rad) * len, sin(rad) * len)
    }
}

extension Double {
    var degToRad: Double { self * .pi / 180 }

    func clamped(_ lo: Double, _ hi: Double) -> Double { Swift.min(Swift.max(self, lo), hi) }
}

/// 两个方向的夹角（弧度，0 到 π）。
func angleBetween(_ a: Vec2, _ b: Vec2) -> Double {
    let d = a.normalized().dot(b.normalized()).clamped(-1, 1)
    return acos(d)
}
