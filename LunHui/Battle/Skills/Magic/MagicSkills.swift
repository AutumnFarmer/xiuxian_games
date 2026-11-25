import Foundation

/// 灵弹术（7.5）：射出灵弹，命中后爆炸。
/// 灵弹风暴：冷却 0.3 秒，爆炸半径 ×1.5。回旋：改为回旋镖，折返，无限穿透，不爆炸（12.5）。
final class LingDanSkill: SkillBase {
    override func update(_ w: BattleWorld, dt: Double) {
        tickCooldown(w, dt: dt, ready: { w.hasEnemy(within: v("range", 650)) }) { fire(w) }
    }

    private func fire(_ w: BattleWorld) {
        let n = count(w)
        let range = v("range", 650)
        let targets = w.nearestEnemies(to: w.player.pos, within: range, count: n)
        guard !targets.isEmpty else { return }
        let isBoomerang = w.hasLegendary("L_huixuan")
        let dirs: [Vec2] = targets.count >= n
            ? targets.map { (w.enemies[$0].pos - w.player.pos).normalized() }
            : fan((w.enemies[targets[0]].pos - w.player.pos).normalized(), count: n)
        for d in dirs {
            if isBoomerang {
                shoot(w, from: w.player.pos, dir: d, speed: projSpeed(w), radius: 14 * w.stats.area,
                      range: w.lp("L_huixuan", "range", 400), pierce: -1, visual: .orb, tag: 10)
            } else {
                shoot(w, from: w.player.pos, dir: d, speed: projSpeed(w), radius: v("radius", 10), range: range, pierce: 0, visual: .orb)
            }
        }
    }

    override func projectileHit(_ w: BattleWorld, proj: Int, enemy: Int) {
        let pr = w.projectiles[proj]
        if pr.tag >= 10 {
            w.damageEnemy(enemy, pr.hit, from: pr.pos)
            return
        }
        let r = radius(w, "explodeRadius")
        w.events.append(.explosion(pos: pr.pos, radius: r, element: element))
        strike(w, .circle(r), at: pr.pos, hit: pr.hit)
    }

    override func projectileExpired(_ w: BattleWorld, proj: Int) {
        let pr = w.projectiles[proj]
        guard pr.tag == 10, pr.range <= 0 else { return }
        var back = pr
        back.id = w.makeId()
        back.dead = false
        back.tag = 11
        back.vel = -pr.vel
        back.range = w.lp("L_huixuan", "range", 400)
        back.hits = []
        back.hitTimes = []
        w.projectiles.append(back)
    }
}

/// 落星术（7.5）：在敌人脚下预警，然后落下星辰。
/// 陨星天降：每次 5 颗，半径 ×1.5，残留区倍率 ×2。天外：一颗巨星，半径 ×3，倍率 ×4，冷却 ×2（12.5）。
final class LuoXingSkill: SkillBase {
    override func cooldown(_ w: BattleWorld) -> Double {
        super.cooldown(w) * (w.hasLegendary("L_tianwai") ? w.lp("L_tianwai", "cooldownMul", 2) : 1)
    }

    override func update(_ w: BattleWorld, dt: Double) {
        tickCooldown(w, dt: dt, ready: { targetReady(w) }) { fire(w) }
    }

    private func fire(_ w: BattleWorld) {
        let giant = w.hasLegendary("L_tianwai")
        let n = giant ? (isEvolved ? 2 : 1) : count(w)
        var r = radius(w)
        var m = mult
        if giant {
            r *= w.lp("L_tianwai", "radiusMul", 3)
            m *= w.lp("L_tianwai", "multMul", 4)
        }
        let targets = w.randomEnemies(near: w.player.pos, within: w.cfg.balance.targetRange, count: n, allowRepeat: false)
        for t in targets {
            zone(w, .circle(r), at: w.enemies[t].pos, delay: v("delay", 0.6), duration: 0, visual: .telegraph,
                 hit: makeHit(w, mult: m), tag: giant ? 1 : 0)
        }
    }

    override func zoneTriggered(_ w: BattleWorld, zone zi: Int) {
        let z = w.zones[zi]
        guard z.tag < SkillBase.followUpTag else { return }
        w.events.append(.explosion(pos: z.pos, radius: z.radiusForDisplay, element: element))
        w.events.append(.shake(z.tag == 1 ? 2 : 1))
        guard has("residue") else { return }
        var rr = z.radiusForDisplay
        if z.tag == 1, isEvolved { rr *= 3 }
        let rm = v("residueMult", 0.4) * (has("residueMultMul") ? v("residueMultMul") : 1)
        zone(w, .circle(rr), at: z.pos, delay: 0.01, duration: v("residueDuration", 3) * w.stats.duration,
             visual: .residue, hit: makeHit(w, mult: rm), tag: SkillBase.followUpTag)
    }
}

/// 灵阵（7.5）：脚下生成跟随玩家的法阵。
/// 周天星斗阵：常驻，半径 ×1.5，阵内必定施加状态。移动法阵：每 0.5 秒留下一个小法阵（12.5）。
final class LingZhenSkill: SkillBase {
    private var zoneId = -1
    private var dropTimer = 0.0

    override func update(_ w: BattleWorld, dt: Double) {
        if w.hasLegendary("L_yidong") {
            if let z = zoneIndex(w, id: zoneId) { w.zones[z].dead = true }
            zoneId = -1
            dropTimer -= dt
            if dropTimer <= 0 {
                dropTimer = w.lp("L_yidong", "interval", 0.5)
                let r = w.lp("L_yidong", "radius", 60) * w.stats.area * (isEvolved ? 1.5 : 1)
                zone(w, .circle(r), at: w.player.pos, delay: 0.01, duration: w.lp("L_yidong", "duration", 3) * w.stats.duration,
                     visual: .formation)
            }
            return
        }
        let permanent = isPermanent(w)
        if let z = zoneIndex(w, id: zoneId) {
            w.zones[z].shape = .circle(radius(w))
            if permanent { w.zones[z].duration = .infinity }
            if !permanent { _ = tickCooldownOnly(w, dt: dt) }
            return
        }
        zoneId = -1
        tickCooldown(w, dt: dt, ready: { true }) {
            zoneId = zone(w, .circle(radius(w)), at: w.player.pos, delay: 0.01,
                          duration: permanent ? .infinity : duration(w), visual: .formation, follow: true)
        }
    }

    private func tickCooldownOnly(_ w: BattleWorld, dt: Double) -> Bool {
        if cooldownLeft > 0 { cooldownLeft -= dt }
        return cooldownLeft <= 0
    }

    override func stageStarted(_ w: BattleWorld) {
        super.stageStarted(w)
        zoneId = -1
        cooldownLeft = 0
    }
}

/// 灵爆（7.5）：以自身为中心爆发，击退。
/// 灵力潮汐：连爆 3 次，每次半径大 30%。连爆：被灵爆击杀的敌人原地再爆一次（12.5）。
final class LingBaoSkill: SkillBase {
    private var echoes: [(time: Double, radius: Double)] = []

    override func update(_ w: BattleWorld, dt: Double) {
        for k in echoes.indices { echoes[k].time -= dt }
        while let e = echoes.first, e.time <= 0 {
            echoes.removeFirst()
            burst(w, radius: e.radius)
        }
        tickCooldown(w, dt: dt, ready: { w.hasEnemy(within: radius(w) + 40) }) {
            let r = radius(w)
            burst(w, radius: r)
            let delay = v("echoDelay", 0.3)
            if has("fixedEcho") {
                let g = 1 + v("echoGrow", 0.3)
                for k in 1...Int(v("fixedEcho")) { echoes.append((delay * Double(k), r * pow(g, Double(k)))) }
            } else if has("echo") {
                echoes.append((delay, r))
            }
        }
    }

    private func burst(_ w: BattleWorld, radius r: Double) {
        w.events.append(.nova(pos: w.player.pos, radius: r, element: element))
        strike(w, .circle(r), at: w.player.pos, hit: makeHit(w, knockback: v("knockback", 80)))
    }

    override func killedEnemy(_ w: BattleWorld, _ e: Enemy, hit: Hit) {
        guard w.hasLegendary("L_lianbao"), hit.statusChance >= 0 else { return }
        let r = w.lp("L_lianbao", "radius", 80) * w.stats.area
        w.events.append(.explosion(pos: e.pos, radius: r, element: element))
        var h = makeHit(w, mult: mult * w.lp("L_lianbao", "mult", 0.5))
        h.statusChance = 0
        strike(w, .circle(r), at: e.pos, hit: h)
    }

    override func stageStarted(_ w: BattleWorld) {
        super.stageStarted(w)
        echoes.removeAll()
    }
}
