#if os(iOS)
import SpriteKit
import UIKit

/// 占位美术（3.3）：启动时把圆、方块等画成白色贴图缓存，战斗中统一用 SKSpriteNode 染色显示。
final class TextureCache {
    static let shared = TextureCache()

    let circle: SKTexture
    let ring: SKTexture
    let softCircle: SKTexture
    let square: SKTexture
    let triangle: SKTexture
    let diamond: SKTexture
    let sword: SKTexture
    let slash: SKTexture
    let arrow: SKTexture
    let spark: SKTexture
    let ground: SKTexture

    private init() {
        circle = TextureCache.draw(64) { ctx, r in ctx.fillEllipse(in: r) }
        ring = TextureCache.draw(128) { ctx, r in
            ctx.setLineWidth(6)
            ctx.strokeEllipse(in: r.insetBy(dx: 4, dy: 4))
        }
        softCircle = TextureCache.drawGradient(128)
        square = TextureCache.draw(64) { ctx, r in ctx.fill(r.insetBy(dx: 4, dy: 4)) }
        triangle = TextureCache.draw(64) { ctx, r in
            ctx.move(to: CGPoint(x: r.midX, y: r.minY + 2))
            ctx.addLine(to: CGPoint(x: r.maxX - 2, y: r.maxY - 4))
            ctx.addLine(to: CGPoint(x: r.minX + 2, y: r.maxY - 4))
            ctx.closePath()
            ctx.fillPath()
        }
        diamond = TextureCache.draw(64) { ctx, r in
            ctx.move(to: CGPoint(x: r.midX, y: r.minY + 2))
            ctx.addLine(to: CGPoint(x: r.maxX - 2, y: r.midY))
            ctx.addLine(to: CGPoint(x: r.midX, y: r.maxY - 2))
            ctx.addLine(to: CGPoint(x: r.minX + 2, y: r.midY))
            ctx.closePath()
            ctx.fillPath()
        }
        // 剑：朝右的细长菱形
        sword = TextureCache.draw(CGSize(width: 64, height: 16)) { ctx, r in
            ctx.move(to: CGPoint(x: r.maxX, y: r.midY))
            ctx.addLine(to: CGPoint(x: r.minX + 14, y: r.minY + 2))
            ctx.addLine(to: CGPoint(x: r.minX, y: r.midY))
            ctx.addLine(to: CGPoint(x: r.minX + 14, y: r.maxY - 2))
            ctx.closePath()
            ctx.fillPath()
        }
        // 剑气：朝右的月牙
        slash = TextureCache.draw(CGSize(width: 48, height: 128)) { ctx, r in
            ctx.addEllipse(in: CGRect(x: r.minX, y: r.minY, width: r.width * 1.6, height: r.height))
            ctx.addEllipse(in: CGRect(x: r.minX - r.width * 0.5, y: r.minY + 6, width: r.width * 1.6, height: r.height - 12))
            ctx.fillPath(using: .evenOdd)
        }
        arrow = TextureCache.draw(CGSize(width: 32, height: 12)) { ctx, r in
            ctx.fill(CGRect(x: r.minX, y: r.midY - 2, width: r.width - 8, height: 4))
            ctx.move(to: CGPoint(x: r.maxX, y: r.midY))
            ctx.addLine(to: CGPoint(x: r.maxX - 10, y: r.minY))
            ctx.addLine(to: CGPoint(x: r.maxX - 10, y: r.maxY))
            ctx.closePath()
            ctx.fillPath()
        }
        spark = TextureCache.draw(16) { ctx, r in ctx.fill(r.insetBy(dx: 3, dy: 3)) }
        ground = TextureCache.drawGround()
    }

    private static func draw(_ size: Int, _ body: (CGContext, CGRect) -> Void) -> SKTexture {
        draw(CGSize(width: size, height: size), body)
    }

    private static func draw(_ size: CGSize, _ body: (CGContext, CGRect) -> Void) -> SKTexture {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 2
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { c in
            let ctx = c.cgContext
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.setStrokeColor(UIColor.white.cgColor)
            body(ctx, CGRect(origin: .zero, size: size))
        }
        return SKTexture(image: img)
    }

    private static func drawGradient(_ size: Int) -> SKTexture {
        let s = CGSize(width: size, height: size)
        let img = UIGraphicsImageRenderer(size: s).image { c in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            let ctr = CGPoint(x: s.width / 2, y: s.height / 2)
            c.cgContext.drawRadialGradient(g, startCenter: ctr, startRadius: 0, endCenter: ctr, endRadius: s.width / 2, options: [])
        }
        return SKTexture(image: img)
    }

    /// 地面装饰：一块 256pt 的平铺贴图，白色小点，按主题染色。
    private static func drawGround() -> SKTexture {
        let s = CGSize(width: 256, height: 256)
        var r = SeededRandom(seed: 99)
        let img = UIGraphicsImageRenderer(size: s).image { c in
            let ctx = c.cgContext
            ctx.setFillColor(UIColor.white.withAlphaComponent(0.55).cgColor)
            for _ in 0..<26 {
                let x = r.range(0, 256), y = r.range(0, 256), d = r.range(3, 9)
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: d, height: d))
            }
            ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.3).cgColor)
            ctx.setLineWidth(2)
            for _ in 0..<6 {
                let x = r.range(0, 256), y = r.range(0, 256)
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addLine(to: CGPoint(x: x + r.range(-30, 30), y: y + r.range(-30, 30)))
                ctx.strokePath()
            }
        }
        return SKTexture(image: img)
    }
}
#endif
