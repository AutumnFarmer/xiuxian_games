import Foundation

/// 绝学（7.3）。右下角按钮触发 cast()。
final class UltimateHook: HookBase {
    let school: School
    /// 持续型绝学剩余时间（法天象地、天魔解体、百兽朝宗）。
    private(set) var activeLeft = 0.0
    /// 万剑归宗、星河倒悬：还没落下的数量和间隔。
    private var dropsLeft = 0
    private var dropTimer = 0.0
    private var dropInterval = 0.0

    init(school: School) { self.school = school }

    var isActive: Bool { activeLeft > 0 || dropsLeft > 0 }
    var ready: Bool { false }

    func canCast(_ w: BattleWorld) -> Bool {
        w.ultCharge >= w.cfg.balance.ult.max && !isActive && w.phase == .fighting && w.director.introTime <= 0
    }

    private func hit(_ w: BattleWorld, mult: Double) -> Hit {
        Hit(mult: mult, element: w.ultElement, school: school, statusChance: w.cfg.benming.strikeStatusChance, source: .ultimate)
    }

    func cast(_ w: BattleWorld) {
        guard canCast(w) else { return }
        w.ultCharge = 0
        w.events.append(.banner(text: w.cfg.schools.def(school).ultName, duration: 1.2))
        w.events.append(.shake(2))
        w.events.append(.haptic(3))
        switch school {
        case .sword:
            dropsLeft = 60
            dropInterval = 3.0 / 60
            dropTimer = 0
            w.player.skillInvuln = max(w.player.skillInvuln, 3)
        case .magic:
            dropsLeft = 40
            dropInterval = 4.0 / 40
            dropTimer = 0
            w.player.skillInvuln = max(w.player.skillInvuln, 4)
        case .body:
            activeLeft = 10
            w.bodyForm = true
            w.ultLocked = true
            w.player.skillInvuln = max(w.player.skillInvuln, 10)
        case .beast:
            activeLeft = 10
            w.summonDmgMult = 2
            w.player.skillInvuln = max(w.player.skillInvuln, 1)
            for k in 0..<20 {
                w.summons.append(Summon(id: w.makeId(), kind: .tempFox, skill: -2,
                                        pos: w.player.pos + Vec2.fromAngle(Double(k) * .pi / 10, 60),
                                        angle: Double(k) * .pi / 10, life: 10))
            }
        case .demon:
            activeLeft = 10
            w.globalDmgMult = 3
            w.fastCast = true
            w.ultLocked = true
            w.player.skillInvuln = max(w.player.skillInvuln, 10)
        }
        for s in w.skills { s.ultimateCast(w) }
        for h in w.hooks where h !== self { h.ultimateCast(w) }
    }

    override func update(_ w: BattleWorld, dt: Double) {
        if dropsLeft > 0 {
            dropTimer -= dt
            while dropTimer <= 0, dropsLeft > 0 {
                dropTimer += dropInterval
                dropsLeft -= 1
                dropOne(w)
            }
        }
        if activeLeft > 0 {
            activeLeft -= dt
            if school == .beast { updateFoxes(w, dt: dt) }
            if activeLeft <= 0 { end(w) }
        }
    }

    private func dropOne(_ w: BattleWorld) {
        switch school {
        case .sword:
            // 均匀覆盖全屏：按 6 × 10 的格子依次落下，加一点抖动
            let k = 60 - dropsLeft - 1
            let col = Double(k % 6), row = Double(k / 6)
            let p = w.player.pos + Vec2((col - 2.5) / 6 * w.viewSize.x, (row - 4.5) / 10 * w.viewSize.y)
                + Vec2(w.rng.range(-20, 20), w.rng.range(-20, 20))
            w.events.append(.skyBolt(pos: p, element: w.ultElement))
            w.damageCircle(center: p, radius: 120, hit: hit(w, mult: 4))
        case .magic:
            let p = w.randomPointInView(around: w.player.pos, shrink: 20)
            w.events.append(.explosion(pos: p, radius: 150, element: w.ultElement))
            w.damageCircle(center: p, radius: 150, hit: hit(w, mult: 5))
        default:
            break
        }
    }

    private func updateFoxes(_ w: BattleWorld, dt: Double) {
        for i in w.summons.indices where w.summons[i].skill == -2 && !w.summons[i].dead {
            w.summons[i].timer -= dt
            let target = w.nearestEnemy(to: w.summons[i].pos, within: 500)
            if let t = target {
                let d = w.enemies[t].pos - w.summons[i].pos
                if d.length > 30 { w.summons[i].pos += d.normalized() * 300 * dt }
                if w.summons[i].timer <= 0, d.length <= 40 {
                    w.summons[i].timer = 0.6
                    w.damageEnemy(t, hit(w, mult: 3), from: w.summons[i].pos)
                }
            } else {
                let home = w.player.pos + Vec2.fromAngle(w.summons[i].angle, 60)
                let d = home - w.summons[i].pos
                if d.length > 5 { w.summons[i].pos += d.normalized() * 300 * dt }
            }
        }
    }

    private func end(_ w: BattleWorld) {
        activeLeft = 0
        switch school {
        case .body:
            w.bodyForm = false
            w.ultLocked = false
        case .beast:
            w.summonDmgMult = 1
        case .demon:
            w.globalDmgMult = 1
            w.fastCast = false
            w.ultLocked = false
            w.addHeartDemon(10)
        default:
            break
        }
    }

    override func stageStarted(_ w: BattleWorld) {
        if activeLeft > 0 || dropsLeft > 0 {
            dropsLeft = 0
            end(w)
        }
        for i in w.summons.indices where w.summons[i].skill == -2 { w.summons[i].dead = true }
    }
}

/// 本命一击（13.5）。
final class BenmingStrikeHook: HookBase {
    private var level = 1
    private var cdr = 0.0
    private var dmgBonus = 0.0
    private var timer = 0.0
    /// 正在飞行的本命法宝位置，nil 表示在玩家身边环绕。
    private(set) var strikePos: Vec2?
    private var targetId = -1
    private var returning = false
    /// 环绕角度，给表现层。
    private(set) var orbitAngle = 0.0

    func configure(level: Int, bonus: (cdr: Double, dmg: Double)) {
        self.level = level
        cdr = bonus.cdr
        dmgBonus = bonus.dmg
    }

    private func interval(_ w: BattleWorld) -> Double {
        max(w.cfg.benming.strikeMinInterval, w.cfg.benming.strikeInterval - cdr)
    }

    override func update(_ w: BattleWorld, dt: Double) {
        orbitAngle += dt * 2.2
        let home = w.player.pos + Vec2.fromAngle(orbitAngle, 40)
        if var p = strikePos {
            let speed = 1100.0
            if returning {
                let d = home - p
                if d.length <= speed * dt { strikePos = nil; returning = false; return }
                p += d.normalized() * speed * dt
                strikePos = p
                return
            }
            guard let t = w.enemies.firstIndex(where: { $0.id == targetId && !$0.dead }) else {
                returning = true
                return
            }
            let d = w.enemies[t].pos - p
            if d.length <= speed * dt + w.enemies[t].radius {
                explode(w, at: w.enemies[t].pos)
                returning = true
                strikePos = w.enemies[t].pos
            } else {
                p += d.normalized() * speed * dt
                strikePos = p
            }
            return
        }
        timer -= dt
        guard timer <= 0 else { return }
        // 优先 Boss 和精英，其次生命最高的敌人
        let r2 = w.cfg.benming.strikeRange * w.cfg.benming.strikeRange
        var best = -1
        var bestScore = -1.0
        for i in w.enemies.indices where !w.enemies[i].dead && w.enemies[i].pos.distSq(w.player.pos) <= r2 {
            let score = w.enemies[i].hp + (w.enemies[i].isEliteOrBoss ? 1e300 : 0)
            if score > bestScore { bestScore = score; best = i }
        }
        guard best >= 0 else { return }
        timer = interval(w)
        targetId = w.enemies[best].id
        strikePos = home
    }

    private func explode(_ w: BattleWorld, at p: Vec2) {
        let bm = w.cfg.benming
        let m = bm.strikeMult(level: level) * (1 + dmgBonus)
        let hit = Hit(mult: m, element: w.ultElement, school: nil, statusChance: bm.strikeStatusChance, source: .benming)
        w.events.append(.explosion(pos: p, radius: bm.strikeRadius * w.stats.area, element: w.ultElement))
        w.damageCircle(center: p, radius: bm.strikeRadius * w.stats.area, hit: hit)
    }

    override func stageStarted(_ w: BattleWorld) {
        strikePos = nil
        returning = false
        timer = 2
    }
}

/// 全局传说特效（12.5）：五行轮转、杀戮、不死、还原。天眼在伤害公式里，福缘在掉落里。
final class GlobalLegendaryHook: HookBase {
    private var wuxingTimer = 0.0
    private var wuxingIndex = 0
    private var killCounter = 0
    private var shaluLeft = 0.0
    private var busiLeft = 0.0

    override func update(_ w: BattleWorld, dt: Double) {
        var pct = 0.0
        var mult = 1.0
        if w.hasLegendary("L_wuxing") {
            wuxingTimer -= dt
            if wuxingTimer <= 0 {
                wuxingTimer = w.lp("L_wuxing", "interval", 5)
                wuxingIndex = (wuxingIndex + 1) % 5
                w.elementOverride = Element.fiveElements[wuxingIndex]
            }
            pct += w.lp("L_wuxing", "dmg", 0.3)
        } else {
            w.elementOverride = nil
        }
        if shaluLeft > 0 {
            shaluLeft -= dt
            pct += w.lp("L_shalu", "dmg", 1)
        }
        if busiLeft > 0 {
            busiLeft -= dt
            mult *= w.lp("L_busi", "mult", 3)
        }
        w.hookDmgPct = pct
        w.hookDmgMult = mult
    }

    override func enemyKilled(_ w: BattleWorld, _ e: Enemy) {
        guard w.hasLegendary("L_shalu") else { return }
        killCounter += 1
        if killCounter >= Int(w.lp("L_shalu", "kills", 100)) {
            killCounter = 0
            shaluLeft = w.lp("L_shalu", "duration", 3)
            w.events.append(.banner(text: "杀戮", duration: 0.8))
        }
    }

    override func revived(_ w: BattleWorld) {
        if w.hasLegendary("L_busi") { busiLeft = w.lp("L_busi", "duration", 5) }
    }

    override func ultimateCast(_ w: BattleWorld) {
        guard w.hasLegendary("L_huanyuan") else { return }
        for s in w.skills { (s as? SkillBase)?.cooldownLeft = 0 }
    }
}
