#if os(iOS)
import SpriteKit
import UIKit

/// 战斗场景（3.1、3.3）：固定步长推进 BattleWorld，把模拟结果画出来，处理摇杆。
/// 逻辑全部在 BattleWorld 里，这里只负责表现（3.4）。
final class BattleScene: SKScene {
    let flow: BattleFlow
    private var world: BattleWorld { flow.world }
    private let tex = TextureCache.shared
    private let settings: Settings

    private let cam = SKCameraNode()
    /// 平铺背景：一组 256pt 的地砖，跟着玩家按格子挪动（8.5：地图没有边界）。
    private var groundTiles: [SKSpriteNode] = []
    private var groundCols = 0
    private var groundRows = 0
    private var groundColor = UIColor.darkGray
    private let worldLayer = SKNode()
    private let zoneLayer = SKNode()
    private let dropLayer = SKNode()
    private let enemyLayer = SKNode()
    private let projLayer = SKNode()
    private let summonLayer = SKNode()
    private let playerNode = SKNode()
    private let playerBody = SKSpriteNode()
    private let playerRing = SKSpriteNode()
    private let shieldNode = SKSpriteNode()
    private let benmingNode = SKSpriteNode()
    private let joyBase = SKSpriteNode()
    private let joyKnob = SKSpriteNode()
    private var fx: FXLayer!

    private var enemyNodes: [Int: SKSpriteNode] = [:]
    private var enemyPool: [SKSpriteNode] = []
    private var projNodes: [Int: SKSpriteNode] = [:]
    private var projPool: [SKSpriteNode] = []
    private var zoneNodes: [Int: SKSpriteNode] = [:]
    private var zonePool: [SKSpriteNode] = []
    private var dropNodes: [Int: SKSpriteNode] = [:]
    private var dropPool: [SKSpriteNode] = []
    private var summonNodes: [Int: SKSpriteNode] = [:]
    private var summonPool: [SKSpriteNode] = []
    private var seen = Set<Int>()

    private var lastTime: TimeInterval = 0
    private var accumulator = 0.0
    private var clock = 0.0
    private var hitStop = 0.0
    private var slowMoLeft = 0.0
    private var slowMoScale = 1.0
    private var shakeLeft = 0.0
    private var shakeAmp = 0.0
    private var touch: UITouch?
    private var touchStart = CGPoint.zero
    private var deathsThisFrame = 0
    private var benmingColorLevel = -1

    init(flow: BattleFlow, size: CGSize, settings: Settings) {
        self.flow = flow
        self.settings = settings
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backgroundColor = Palette.bg
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = false
        view.ignoresSiblingOrder = true
        fx = FXLayer(cfg: flow.cfg.fx)
        fx.damageMode = settings.damageText
        Haptics.shared.enabled = settings.haptics
        Audio.shared.enabled = settings.sound
        Audio.shared.playMusic(.battle)
        flow.onStageStart = { kind in
            Audio.shared.playMusic(kind == .normal ? .battle : .boss)
        }
        flow.onUltimate = { Audio.shared.play("ultimate") }
        flow.onDeath = {
            Audio.shared.stopMusic()
            Audio.shared.play("death")
        }
        camera = cam
        addChild(cam)
        addChild(worldLayer)
        buildGround()
        for (l, z) in [(zoneLayer, -10.0), (dropLayer, -5.0), (enemyLayer, 0.0), (summonLayer, 5.0), (projLayer, 10.0)] {
            l.zPosition = CGFloat(z)
            worldLayer.addChild(l)
        }
        worldLayer.addChild(fx.root)
        playerBody.texture = tex.circle
        playerBody.size = CGSize(width: 34, height: 34)
        playerBody.color = .white
        playerBody.colorBlendFactor = 1
        playerRing.texture = tex.ring
        playerRing.size = CGSize(width: 46, height: 46)
        playerRing.colorBlendFactor = 1
        playerRing.color = Palette.element(world.lingGen.elements.first)
        shieldNode.texture = tex.softCircle
        shieldNode.size = CGSize(width: 80, height: 80)
        shieldNode.colorBlendFactor = 1
        shieldNode.color = UIColor(hex: "#80DEEA")
        shieldNode.alpha = 0
        shieldNode.blendMode = .add
        benmingNode.texture = tex.diamond
        benmingNode.size = CGSize(width: 16, height: 16)
        benmingNode.colorBlendFactor = 1
        benmingNode.color = Palette.gold
        playerNode.addChild(shieldNode)
        playerNode.addChild(playerRing)
        playerNode.addChild(playerBody)
        playerNode.zPosition = 8
        worldLayer.addChild(playerNode)
        benmingNode.zPosition = 9
        worldLayer.addChild(benmingNode)
        joyBase.texture = tex.ring
        joyBase.size = CGSize(width: 100, height: 100)
        joyBase.alpha = 0
        joyBase.zPosition = 200
        joyKnob.texture = tex.circle
        joyKnob.size = CGSize(width: 44, height: 44)
        joyKnob.alpha = 0
        joyKnob.zPosition = 201
        cam.addChild(joyBase)
        cam.addChild(joyKnob)
        applyTheme()
        world.viewSize = Vec2(Double(size.width), Double(size.height))
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        if size.width > 0 {
            world.viewSize = Vec2(Double(size.width), Double(size.height))
            if !groundTiles.isEmpty { buildGround() }
        }
    }

    private let tile: CGFloat = 256

    private func buildGround() {
        let cols = Int((size.width / tile).rounded(.up)) + 2
        let rows = Int((size.height / tile).rounded(.up)) + 2
        guard cols != groundCols || rows != groundRows || groundTiles.isEmpty else { return }
        for t in groundTiles { t.removeFromParent() }
        groundTiles = []
        groundCols = cols
        groundRows = rows
        for _ in 0..<(cols * rows) {
            let t = SKSpriteNode(texture: tex.ground, size: CGSize(width: tile, height: tile))
            t.colorBlendFactor = 1
            t.color = groundColor
            t.zPosition = -100
            worldLayer.addChild(t)
            groundTiles.append(t)
        }
    }

    private var themeId = ""

    private func applyTheme() {
        let realm = min(4, flow.rc.run.stageIndex / 3)
        let id = flow.rc.run.themeOrder[safe: realm] ?? "forest"
        guard id != themeId else { return }
        themeId = id
        let t = flow.cfg.themes.def(id)
        backgroundColor = UIColor(hex: t.bg)
        groundColor = UIColor(hex: t.deco)
        for g in groundTiles { g.color = groundColor }
    }

    // MARK: 主循环（3.3）

    override func update(_ currentTime: TimeInterval) {
        let real = lastTime == 0 ? 1.0 / 60 : min(0.25, currentTime - lastTime)
        lastTime = currentTime
        clock += real
        fx.update(now: clock)
        flow.tickHUD(real)
        deathsThisFrame = 0
        if flow.isLogicRunning {
            if hitStop > 0 {
                hitStop -= real
            } else {
                var scaled = real
                if slowMoLeft > 0 {
                    slowMoLeft -= real
                    scaled *= slowMoScale
                }
                accumulator += scaled
                var steps = 0
                while accumulator >= world.dt, steps < 3 {
                    accumulator -= world.dt
                    world.step()
                    steps += 1
                    consumeEvents()
                    if world.phase == .cleared || world.phase == .dead { break }
                }
                if steps == 3 { accumulator = 0 }
                flow.afterSteps(steps)
            }
        } else {
            accumulator = 0
            releaseJoystick()
        }
        applyTheme()
        render(real)
    }

    // MARK: 事件 → 表现（第 16 章）

    private func consumeEvents() {
        let evs = world.events
        world.events.removeAll(keepingCapacity: true)
        for e in evs { handle(e) }
    }

    private func handle(_ e: BattleEvent) {
        switch e {
        case .damage(let p, let amount, let crit, let el, let dot, let tid):
            fx.damage(at: p.cg, amount: amount, crit: crit, element: el, dot: dot, targetId: tid)
            if !dot { Audio.shared.play(crit ? "crit" : "hit") }
        case .enemyDied(_, let p, let el, let role, let r):
            deathsThisFrame += 1
            Audio.shared.play(role == .boss || role == .shadow ? "boom" : "kill")
            let pieces = flow.cfg.fx.deathPieces
            if deathsThisFrame > pieces.maxFullPerFrame, role == .minion { return }
            switch role {
            case .minion, .spirit: fx.shatter(at: p.cg, color: Palette.element(el), pieces: pieces.minion, spread: CGFloat(r) * 2.5)
            case .elite: fx.shatter(at: p.cg, color: Palette.element(el), pieces: pieces.elite, spread: 90)
            case .boss, .shadow:
                fx.shatter(at: p.cg, color: Palette.element(el), pieces: pieces.boss, spread: 260)
                flow.hud.flashScreen(.white, duration: 0.25)
            }
        case .playerHurt:
            playerBody.removeAction(forKey: "hurt")
            playerBody.run(.sequence([.colorize(with: Palette.danger, colorBlendFactor: 1, duration: 0.05),
                                      .colorize(with: .white, colorBlendFactor: 1, duration: 0.15)]), withKey: "hurt")
        case .playerHealed:
            break
        case .levelUp(let lv):
            flow.hud.pushBanner("突破！Lv.\(lv)", style: .levelUp, duration: flow.cfg.fx.levelBanner)
            Audio.shared.play("levelup")
            haptic(1)
        case .nova(let p, let r, let el):
            fx.nova(at: p.cg, radius: CGFloat(r), color: el.map { Palette.element($0) } ?? Palette.gold)
        case .slash(let p, let d, let r, _, let el):
            fx.slash(at: p.cg, dir: CGVector(dx: d.x, dy: d.y), radius: CGFloat(r), color: Palette.element(el))
        case .lightning(let a, let b):
            fx.lightning(from: a.cg, to: b.cg)
        case .skyBolt(let p, let el):
            fx.skyBolt(at: p.cg, color: Palette.element(el))
            Audio.shared.play(el == .thunder ? "thunder" : "sword")
        case .explosion(let p, let r, let el):
            Audio.shared.play(r >= 120 ? "boom" : "spell")
            fx.explosion(at: p.cg, radius: CGFloat(r), color: el.map { Palette.element($0) } ?? UIColor(hex: "#FF7043"))
        case .shatter(let p):
            fx.shatter(at: p.cg, color: Palette.element(.ice), pieces: 8, spread: 80)
        case .itemDropped(let q, let p):
            let d = flow.cfg.fx.drops[safe: q]
            if let d, d.pillar > 0 { fx.pillar(at: p.cg, color: Palette.quality(q), duration: d.pillar) }
            if let d, d.hitStop > 0 { hitStop = max(hitStop, d.hitStop) }
            if q >= 4 {
                flow.hud.flashScreen(q >= 5 ? .red : .gold, duration: q >= 5 ? 0.6 : 0.4)
                shake(q >= 5 ? 3 : 2)
                if q >= 5 { cam.run(.sequence([.scale(to: 0.85, duration: 0.12), .scale(to: 1, duration: 0.35)])) }
            }
        case .itemPicked(let q, let name):
            Audio.shared.play(q >= 5 ? "drop_hundun" : q >= 4 ? "drop_shen" : q >= 3 ? "drop_xian" : "drop_low")
            let d = flow.cfg.fx.drops[safe: q]
            if let d, d.haptic > 0 { haptic(d.haptic) }
            switch q {
            case 3: flow.hud.pushToast("获得仙品·\(name)", style: .xian)
            case 4: flow.hud.pushBanner("神品出世！", sub: name, style: .shen, duration: 1.5)
            case 5: flow.hud.pushBanner("混沌至宝！", sub: name, style: .hundun, duration: 2)
            default: break
            }
        case .bossIntro(let name):
            flow.hud.showBossIntro(name, duration: flow.cfg.balance.stage.bossIntro)
            Audio.shared.play("boss")
            Audio.shared.playMusic(.boss)
        case .banner(let text, let dur):
            let style: BannerStyle = text.contains("渡劫成功") || text.contains("心魔已斩") || text.contains("伏诛") ? .victory : .normal
            flow.hud.pushBanner(text, style: style, duration: dur)
            if style == .victory { Audio.shared.play("victory") }
        case .shake(let lv):
            shake(lv)
        case .haptic(let lv):
            haptic(lv)
        case .hitStop(let t):
            hitStop = max(hitStop, t)
        case .slowMo(let d, let s):
            slowMoLeft = d
            slowMoScale = s
        case .revive:
            Audio.shared.play("ultimate")
            flow.hud.flashScreen(.gold, duration: 0.4)
            flow.hud.pushBanner("涅槃重生", style: .victory, duration: 1.2)
        case .shieldBreak(let p):
            fx.shatter(at: p.cg, color: UIColor(hex: "#80DEEA"), pieces: 10, spread: 70)
        }
    }

    private func shake(_ lv: Int) {
        guard settings.screenShake, lv > 0 else { return }
        let s = flow.cfg.fx.shake[safe: min(lv, 3)] ?? flow.cfg.fx.shake[1]
        if s.amp >= shakeAmp || shakeLeft <= 0 {
            shakeAmp = s.amp
            shakeLeft = s.time
        }
    }

    private func haptic(_ lv: Int) {
        Haptics.shared.play(lv, minInterval: flow.cfg.fx.haptic.minInterval)
    }

    // MARK: 绘制

    private func render(_ real: Double) {
        let w = world
        // 镜头跟随玩家，加震屏（16.4）
        var camPos = w.player.pos.cg
        if shakeLeft > 0 {
            shakeLeft -= real
            camPos.x += CGFloat.random(in: -1...1) * CGFloat(shakeAmp)
            camPos.y += CGFloat.random(in: -1...1) * CGFloat(shakeAmp)
            if shakeLeft <= 0 { shakeAmp = 0 }
        }
        cam.position = camPos
        // 平铺背景：以玩家所在的格子为中心铺满屏幕
        let bx = floor(camPos.x / tile) * tile, by = floor(camPos.y / tile) * tile
        for (k, g) in groundTiles.enumerated() {
            let i = k % groundCols - groundCols / 2, j = k / groundCols - groundRows / 2
            g.position = CGPoint(x: bx + CGFloat(i) * tile + tile / 2, y: by + CGFloat(j) * tile + tile / 2)
        }
        // 玩家
        playerNode.position = w.player.pos.cg
        let invuln = w.player.invuln > 0 || w.player.skillInvuln > 0
        playerBody.alpha = invuln && Int(clock * 20) % 2 == 0 ? 0.45 : 1
        playerNode.setScale(w.bodyForm ? 2 : 1)
        playerRing.zRotation += CGFloat(real * 2)
        shieldNode.alpha = w.player.shield > 0 ? 0.35 : 0
        if let bh = w.hooks.first(where: { $0 is BenmingStrikeHook }) as? BenmingStrikeHook {
            let p = bh.strikePos ?? (w.player.pos + Vec2.fromAngle(bh.orbitAngle, 40))
            benmingNode.position = p.cg
            benmingNode.setScale(bh.strikePos == nil ? 1 : 1.8)
            benmingNode.zRotation += CGFloat(real * 6)
            if benmingColorLevel != flow.rc.save.benming.level {
                benmingColorLevel = flow.rc.save.benming.level
                benmingNode.color = UIColor(hex: flow.cfg.benming.color(level: benmingColorLevel))
            }
        }
        renderEnemies()
        renderProjectiles()
        renderZones()
        renderDrops()
        renderSummons()
        updateLootArrows()
    }

    private func take(_ pool: inout [SKSpriteNode], parent: SKNode) -> SKSpriteNode {
        let n = pool.popLast() ?? SKSpriteNode()
        n.colorBlendFactor = 1
        n.alpha = 1
        n.isHidden = false
        n.zRotation = 0
        n.setScale(1)
        n.removeAllActions()
        n.blendMode = .alpha
        if n.parent == nil { parent.addChild(n) }
        return n
    }

    private func recycle(_ dict: inout [Int: SKSpriteNode], pool: inout [SKSpriteNode]) {
        for (id, n) in dict where !seen.contains(id) {
            n.isHidden = true
            pool.append(n)
            dict[id] = nil
        }
    }

    private func renderEnemies() {
        seen.removeAll(keepingCapacity: true)
        for e in world.enemies where !e.dead {
            seen.insert(e.id)
            let n: SKSpriteNode
            if let x = enemyNodes[e.id] { n = x } else {
                n = take(&enemyPool, parent: enemyLayer)
                enemyNodes[e.id] = n
                n.texture = enemyTexture(e)
                let d = CGFloat(e.radius * 2)
                n.size = CGSize(width: d, height: d)
                n.removeAllChildren()
                if e.isEliteOrBoss {
                    let ring = SKSpriteNode(texture: tex.ring)
                    ring.name = "ring"
                    ring.size = CGSize(width: d * 1.35, height: d * 1.35)
                    ring.color = e.role == .elite ? Palette.gold : (e.role == .shadow ? UIColor(hex: "#7E57C2") : Palette.danger)
                    ring.colorBlendFactor = 1
                    n.addChild(ring)
                }
            }
            n.position = e.pos.cg
            n.alpha = e.clearAt >= 0 ? 0.6 : (e.role == .shadow ? 0.75 : 1)
            if e.freezeTime > 0 {
                n.color = Palette.element(.ice)
            } else if e.role == .shadow {
                n.color = UIColor(white: 0.12, alpha: 1)
            } else {
                n.color = Palette.element(e.element)
            }
            if e.role == .boss { n.childNode(withName: "ring")?.zRotation += 0.05 }
            if e.role == .minion, cfgType(e) == "bomber", e.phase == 1 { n.alpha = Int(clock * 12) % 2 == 0 ? 0.4 : 1 }
        }
        recycle(&enemyNodes, pool: &enemyPool)
    }

    private func cfgType(_ e: Enemy) -> String { flow.cfg.enemies.types[safe: e.typeIndex]?.id ?? "" }

    private func enemyTexture(_ e: Enemy) -> SKTexture {
        if e.role == .boss || e.role == .shadow { return tex.circle }
        switch flow.cfg.enemies.types[safe: e.typeIndex]?.shape ?? "" {
        case "triangle": return tex.triangle
        case "square": return tex.square
        case "diamond": return tex.diamond
        default: return tex.circle
        }
    }

    private func renderProjectiles() {
        seen.removeAll(keepingCapacity: true)
        for p in world.projectiles where !p.dead {
            seen.insert(p.id)
            let n: SKSpriteNode
            if let x = projNodes[p.id] { n = x } else {
                n = take(&projPool, parent: projLayer)
                projNodes[p.id] = n
                if p.team == .player, p.visual == .sword || p.visual == .wind { Audio.shared.play("sword") }
                let r = CGFloat(p.radius)
                switch p.visual {
                case .sword:
                    n.texture = tex.sword
                    n.size = CGSize(width: max(28, r * 3.6), height: max(8, r * 0.9))
                case .slash:
                    n.texture = tex.slash
                    n.size = CGSize(width: r * 1.4, height: CGFloat(p.halfWidth * 2))
                case .arrow:
                    n.texture = tex.arrow
                    n.size = CGSize(width: 22, height: 8)
                case .wind:
                    n.texture = tex.slash
                    n.size = CGSize(width: r * 1.2, height: r * 3)
                default:
                    n.texture = tex.softCircle
                    n.size = CGSize(width: r * 2.6, height: r * 2.6)
                    n.blendMode = .add
                }
                n.color = p.team == .enemy ? UIColor(hex: "#FF5252") : Palette.element(p.element)
            }
            n.position = p.pos.cg
            if p.motion == .orbit {
                n.zRotation = CGFloat(p.orbitAngle + .pi / 2)
            } else if p.vel.lengthSq > 0 {
                n.zRotation = CGFloat(p.vel.angle)
            }
        }
        recycle(&projNodes, pool: &projPool)
    }

    private func renderZones() {
        seen.removeAll(keepingCapacity: true)
        for z in world.zones where !z.dead {
            // 玩家阵营的一次性落点不画预警，只有持续区域和敌人预警需要画
            if z.team == .player, z.duration <= 0, z.visual != .telegraph { continue }
            seen.insert(z.id)
            let n: SKSpriteNode
            if let x = zoneNodes[z.id] { n = x } else {
                n = take(&zonePool, parent: zoneLayer)
                zoneNodes[z.id] = n
            }
            n.position = z.pos.cg
            let enemyTele = z.team == .enemy && !z.triggered
            switch z.shape {
            case .circle(let r):
                n.texture = z.visual == .aura || z.visual == .formation ? tex.ring : tex.softCircle
                n.size = CGSize(width: r * 2, height: r * 2)
                n.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                n.zRotation = z.visual == .formation ? CGFloat(clock) : 0
            case .ring(_, let o):
                n.texture = tex.ring
                n.size = CGSize(width: o * 2, height: o * 2)
                n.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            case .rect(let hw, let len, let dir):
                n.texture = tex.square
                n.anchorPoint = CGPoint(x: 0, y: 0.5)
                n.size = CGSize(width: len, height: hw * 2)
                n.zRotation = CGFloat(dir.angle)
            case .cone(let r, let half, let dir):
                n.texture = tex.softCircle
                n.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                n.size = CGSize(width: r * 2, height: r * 2 * max(0.35, sin(half)))
                n.position = (z.pos + dir.normalized() * (r * 0.5)).cg
                n.zRotation = CGFloat(dir.angle)
            }
            if enemyTele {
                let f = 1 - max(0, z.delay) / max(0.01, z.delayTotal)
                n.color = Palette.telegraph
                n.alpha = CGFloat(0.18 + 0.3 * f)
            } else if z.team == .enemy {
                n.color = z.visual == .web ? UIColor(white: 0.85, alpha: 1) : Palette.telegraph
                n.alpha = z.visual == .web ? 0.25 : 0.1
            } else {
                n.color = z.visual == .blood ? UIColor(hex: "#B71C1C") : Palette.element(z.element)
                switch z.visual {
                case .telegraph: n.alpha = 0.22
                case .aura, .formation: n.alpha = 0.55
                case .cloud: n.alpha = 0.35
                default: n.alpha = 0.3
                }
            }
        }
        recycle(&zoneNodes, pool: &zonePool)
    }

    private func renderDrops() {
        seen.removeAll(keepingCapacity: true)
        for d in world.drops where !d.dead {
            seen.insert(d.id)
            let n: SKSpriteNode
            if let x = dropNodes[d.id] { n = x } else {
                n = take(&dropPool, parent: dropLayer)
                dropNodes[d.id] = n
                n.removeAllChildren()
                switch d.kind {
                case .exp:
                    n.texture = tex.diamond
                    n.size = CGSize(width: 9, height: 9)
                    n.color = UIColor(hex: "#64FFDA")
                case .lingShi:
                    n.texture = tex.diamond
                    n.size = CGSize(width: 12, height: 12)
                    n.color = UIColor(hex: "#FFD54F")
                case .item:
                    n.texture = tex.square
                    n.size = CGSize(width: 18, height: 18)
                    n.color = Palette.quality(d.quality)
                    if d.quality >= 2 {
                        let glow = SKSpriteNode(texture: tex.softCircle)
                        glow.size = CGSize(width: 54, height: 54)
                        glow.color = Palette.quality(d.quality)
                        glow.colorBlendFactor = 1
                        glow.blendMode = .add
                        glow.zPosition = -1
                        n.addChild(glow)
                    }
                }
            }
            n.position = d.pos.cg
            if d.kind == .item { n.zRotation = CGFloat(clock * 1.5) }
        }
        for (id, n) in dropNodes where !seen.contains(id) { n.removeAllChildren() }
        recycle(&dropNodes, pool: &dropPool)
    }

    private func renderSummons() {
        seen.removeAll(keepingCapacity: true)
        for s in world.summons where !s.dead {
            seen.insert(s.id)
            let n: SKSpriteNode
            if let x = summonNodes[s.id] { n = x } else {
                n = take(&summonPool, parent: summonLayer)
                summonNodes[s.id] = n
                let el = s.skill >= 0 ? world.skills[safe: s.skill]?.element : world.ultElement
                n.color = Palette.element(el)
                switch s.kind {
                case .fox, .tempFox:
                    n.texture = tex.triangle
                    n.size = CGSize(width: 20, height: 20)
                case .bird:
                    n.texture = tex.diamond
                    n.size = CGSize(width: 14, height: 14)
                case .python:
                    n.texture = tex.ring
                    n.size = CGSize(width: 60, height: 60)
                case .turtle:
                    n.texture = tex.square
                    n.size = CGSize(width: 26, height: 26)
                }
            }
            n.position = s.pos.cg
            if s.kind == .python {
                let r = CGFloat((world.skills[safe: s.skill] as? SkillBase).map { $0.radius(world) } ?? 160)
                n.size = CGSize(width: r * 2, height: r * 2)
                n.zRotation = CGFloat(clock * 3)
                n.alpha = 0.5
            }
        }
        recycle(&summonNodes, pool: &summonPool)
    }

    private var arrowTimer = 0.0

    private func updateLootArrows() {
        arrowTimer += 1.0 / 60
        guard arrowTimer >= 0.1 else { return }
        arrowTimer = 0
        let hw = Double(size.width) / 2 - 20, hh = Double(size.height) / 2 - 40
        var arrows: [LootArrow] = []
        for d in world.drops where d.kind == .item && d.quality >= 3 && !d.dead {
            let off = d.pos - world.player.pos
            if abs(off.x) > hw || abs(off.y) > hh { arrows.append(LootArrow(id: d.id, angle: off.angle, quality: d.quality)) }
        }
        if arrows != flow.hud.lootArrows { flow.hud.lootArrows = arrows }
    }

    // MARK: 浮动摇杆（5.1）

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard touch == nil, flow.isLogicRunning, let t = touches.first else { return }
        touch = t
        touchStart = t.location(in: cam)
        joyBase.position = touchStart
        joyKnob.position = touchStart
        joyBase.alpha = 0.35
        joyKnob.alpha = 0.6
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touch, touches.contains(t) else { return }
        let p = t.location(in: cam)
        let d = CGVector(dx: p.x - touchStart.x, dy: p.y - touchStart.y)
        let len = hypot(d.dx, d.dy)
        let jc = flow.cfg.balance.joystick
        let r = CGFloat(jc.radius)
        let k = len > r ? r / len : 1
        joyKnob.position = CGPoint(x: touchStart.x + d.dx * k, y: touchStart.y + d.dy * k)
        if len >= CGFloat(jc.deadZone) {
            world.player.input = Vec2(Double(d.dx / len), Double(d.dy / len))
        } else {
            world.player.input = .zero
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touch, touches.contains(t) else { return }
        releaseJoystick()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseJoystick()
    }

    private func releaseJoystick() {
        touch = nil
        world.player.input = .zero
        joyBase.alpha = 0
        joyKnob.alpha = 0
    }
}
#endif
