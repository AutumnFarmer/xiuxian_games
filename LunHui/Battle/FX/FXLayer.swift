#if os(iOS)
import SpriteKit
import UIKit

/// 一次性特效：伤害数字、碎裂、爆炸圈、光柱（第 16 章）。全部用对象池。
final class FXLayer {
    let root = SKNode()
    private let tex = TextureCache.shared
    private var textPool: [SKLabelNode] = []
    private var activeTexts: [(node: SKLabelNode, until: Double, target: Int, amount: Double, crit: Bool)] = []
    private var spritePool: [SKSpriteNode] = []
    private var activeSprites: [(node: SKSpriteNode, until: Double)] = []
    private let cfg: FXConfig
    var damageMode: Settings.DamageText = .all
    var now = 0.0

    init(cfg: FXConfig) {
        self.cfg = cfg
        root.zPosition = 50
        for _ in 0..<cfg.damageText.max { textPool.append(makeLabel()) }
        for _ in 0..<200 { spritePool.append(SKSpriteNode(texture: tex.circle)) }
    }

    private func makeLabel() -> SKLabelNode {
        let l = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        l.horizontalAlignmentMode = .center
        l.verticalAlignmentMode = .center
        return l
    }

    // MARK: 伤害数字（16.1）

    func damage(at p: CGPoint, amount: Double, crit: Bool, element: Element?, dot: Bool, targetId: Int) {
        if damageMode == .off { return }
        if damageMode == .crit, !crit { return }
        let dt = cfg.damageText
        // 同一目标 0.2 秒内的多次命中合并（超过上限时）
        if activeTexts.count >= dt.max - 4, let k = activeTexts.lastIndex(where: { $0.target == targetId && now - ($0.until - dt.life) < dt.mergeWindow }) {
            activeTexts[k].amount += amount
            activeTexts[k].node.text = NumberText.format(activeTexts[k].amount) + (activeTexts[k].crit ? "!" : "")
            return
        }
        let node: SKLabelNode
        if let n = textPool.popLast() {
            node = n
        } else if let k = activeTexts.firstIndex(where: { !$0.crit }) ?? activeTexts.indices.first {
            node = activeTexts.remove(at: k).node
            node.removeAllActions()
        } else { return }
        node.text = NumberText.format(amount) + (crit ? "!" : "")
        node.fontSize = CGFloat(dot ? dt.dotSize : (crit ? dt.critSize : dt.normalSize))
        node.fontColor = dot ? Palette.element(element) : (crit ? Palette.gold : .white)
        node.position = CGPoint(x: p.x + CGFloat.random(in: -10...10), y: p.y + 14)
        node.alpha = 1
        node.setScale(1)
        node.zPosition = crit ? 2 : 1
        if node.parent == nil { root.addChild(node) }
        var actions: [SKAction] = []
        if crit {
            actions.append(.sequence([.scale(to: CGFloat(dt.critPop), duration: 0.06), .scale(to: 1, duration: 0.1)]))
        }
        actions.append(.moveBy(x: 0, y: CGFloat(dt.rise), duration: dt.life))
        actions.append(.sequence([.wait(forDuration: dt.life * 0.5), .fadeOut(withDuration: dt.life * 0.5)]))
        node.run(.group(actions))
        activeTexts.append((node, now + dt.life, targetId, amount, crit))
    }

    // MARK: 精灵特效

    private func sprite(_ t: SKTexture, at p: CGPoint, color: UIColor, size: CGFloat, life: Double, z: CGFloat = 0) -> SKSpriteNode {
        let s: SKSpriteNode
        if let n = spritePool.popLast() {
            s = n
        } else if !activeSprites.isEmpty {
            s = activeSprites.removeFirst().node
            s.removeAllActions()
        } else {
            s = SKSpriteNode(texture: t)
        }
        s.texture = t
        s.color = color
        s.colorBlendFactor = 1
        s.alpha = 1
        s.zRotation = 0
        s.position = p
        s.size = CGSize(width: size, height: size)
        s.setScale(1)
        s.zPosition = z
        s.blendMode = .alpha
        if s.parent == nil { root.addChild(s) }
        activeSprites.append((s, now + life))
        return s
    }

    /// 扩散的光圈（升级冲击波、灵爆、震地踏等）。
    func nova(at p: CGPoint, radius: CGFloat, color: UIColor) {
        let s = sprite(tex.ring, at: p, color: color, size: radius * 2, life: 0.35)
        s.setScale(0.3)
        s.run(.group([.scale(to: 1, duration: 0.25), .sequence([.wait(forDuration: 0.12), .fadeOut(withDuration: 0.22)])]))
    }

    /// 爆炸：实心圆闪一下。
    func explosion(at p: CGPoint, radius: CGFloat, color: UIColor) {
        let s = sprite(tex.softCircle, at: p, color: color, size: radius * 2.2, life: 0.3)
        s.blendMode = .add
        s.alpha = 0.9
        s.setScale(0.5)
        s.run(.group([.scale(to: 1, duration: 0.12), .fadeOut(withDuration: 0.28)]))
    }

    /// 扇形挥击：用拉长的月牙表示。
    func slash(at p: CGPoint, dir: CGVector, radius: CGFloat, color: UIColor) {
        let s = sprite(tex.slash, at: p, color: color, size: radius, life: 0.2, z: 3)
        s.size = CGSize(width: radius * 0.6, height: radius * 1.6)
        s.zRotation = atan2(dir.dy, dir.dx)
        s.position = CGPoint(x: p.x + dir.dx * radius * 0.5, y: p.y + dir.dy * radius * 0.5)
        s.blendMode = .add
        s.run(.group([.fadeOut(withDuration: 0.2), .scaleX(to: 1.3, duration: 0.2)]))
    }

    /// 天上落下的剑或雷：一道竖线。
    func skyBolt(at p: CGPoint, color: UIColor) {
        let s = sprite(tex.square, at: CGPoint(x: p.x, y: p.y + 60), color: color, size: 10, life: 0.25, z: 4)
        s.size = CGSize(width: 8, height: 140)
        s.blendMode = .add
        s.run(.group([.moveBy(x: 0, y: -60, duration: 0.08), .sequence([.wait(forDuration: 0.08), .fadeOut(withDuration: 0.17)])]))
        explosion(at: p, radius: 30, color: color)
    }

    func lightning(from a: CGPoint, to b: CGPoint) {
        let d = CGVector(dx: b.x - a.x, dy: b.y - a.y)
        let len = max(1, hypot(d.dx, d.dy))
        let s = sprite(tex.square, at: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), color: Palette.element(.thunder), size: 4, life: 0.15, z: 4)
        s.size = CGSize(width: len, height: 4)
        s.zRotation = atan2(d.dy, d.dx)
        s.blendMode = .add
        s.run(.fadeOut(withDuration: 0.15))
    }

    /// 敌人死亡碎片（16.2）。
    func shatter(at p: CGPoint, color: UIColor, pieces: Int, spread: CGFloat) {
        for _ in 0..<pieces {
            let s = sprite(tex.spark, at: p, color: color, size: CGFloat.random(in: 4...8), life: 0.35, z: 2)
            let a = CGFloat.random(in: 0...(2 * .pi))
            let d = CGFloat.random(in: spread * 0.4...spread)
            s.zRotation = a
            s.run(.group([.moveBy(x: cos(a) * d, y: sin(a) * d, duration: 0.3), .fadeOut(withDuration: 0.35),
                          .rotate(byAngle: .pi, duration: 0.35)]))
        }
    }

    /// 高品质掉落的光柱（16.3）。
    func pillar(at p: CGPoint, color: UIColor, duration: Double) {
        let s = sprite(tex.softCircle, at: CGPoint(x: p.x, y: p.y + 200), color: color, size: 40, life: duration, z: -1)
        s.size = CGSize(width: 46, height: 420)
        s.blendMode = .add
        s.alpha = 0
        s.run(.sequence([.fadeAlpha(to: 0.85, duration: 0.15), .wait(forDuration: max(0, duration - 0.6)), .fadeOut(withDuration: 0.45)]))
    }

    // MARK: 回收

    func update(now t: Double) {
        now = t
        if let f = activeTexts.first, f.until <= t {
            var keep: [(node: SKLabelNode, until: Double, target: Int, amount: Double, crit: Bool)] = []
            for e in activeTexts {
                if e.until <= t {
                    e.node.removeAllActions()
                    e.node.alpha = 0
                    textPool.append(e.node)
                } else { keep.append(e) }
            }
            activeTexts = keep
        }
        if activeSprites.contains(where: { $0.until <= t }) {
            var keep: [(node: SKSpriteNode, until: Double)] = []
            for e in activeSprites {
                if e.until <= t {
                    e.node.removeAllActions()
                    e.node.alpha = 0
                    spritePool.append(e.node)
                } else { keep.append(e) }
            }
            activeSprites = keep
        }
    }
}
#endif
