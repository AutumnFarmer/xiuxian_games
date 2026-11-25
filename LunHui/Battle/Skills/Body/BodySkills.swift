import Foundation

/// 崩山拳（7.5）：扇形拳劲，击退。
/// 崩天裂地：每一拳都是重拳，360°。白虎：每一拳都打出一道拳影，无限穿透（12.5）。
final class BengShanSkill: SkillBase {
    private var punches = 0

    override func update(_ w: BattleWorld, dt: Double) {
        tickCooldown(w, dt: dt, ready: { meleeReady(w) }) { punch(w) }
    }

    private func punch(_ w: BattleWorld) {
        punches += 1
        let dir = aimDir(w, range: w.cfg.balance.meleeRange)
        let r = radius(w)
        let full = has("fullCircle") || v("angle", 120) >= 360
        let half = full ? Double.pi : v("angle", 120).degToRad / 2
        let heavyEvery = Int(v("heavyEvery"))
        let heavy = has("allHeavy") || (heavyEvery > 0 && punches % heavyEvery == 0)
        let m = mult * (heavy ? v("heavyMult", 3) : 1)
        w.events.append(.slash(pos: w.player.pos, dir: dir, radius: r, angle: half * 2, element: element))
        if heavy { w.events.append(.shake(1)) }
        strike(w, .cone(r, half, dir), at: w.player.pos, hit: makeHit(w, mult: m, knockback: v("knockback", 60)))
        if w.hasLegendary("L_baihu") {
            shoot(w, from: w.player.pos, dir: dir, speed: w.lp("L_baihu", "speed", 700), radius: 30 * w.stats.area,
                  range: w.lp("L_baihu", "range", 500), pierce: -1, visual: .slash,
                  hit: makeHit(w, mult: m * w.lp("L_baihu", "mult", 0.8)), halfWidth: 30 * w.stats.area)
        }
    }
}

/// 铁布衫（7.5）：常驻护体罡气，减伤。
/// 金刚不坏：罡气 ×1.5，减伤再 +15%，反震 ×3。金刚：半径 ×2，减伤 +10%，不造成伤害，反震 ×5（12.5）。
final class TieBuSkill: SkillBase {
    private var zoneId = -1

    override func update(_ w: BattleWorld, dt: Double) {
        let jingang = w.hasLegendary("L_jingang")
        var r = radius(w)
        if jingang { r *= w.lp("L_jingang", "radiusMul", 2) }
        if let z = zoneIndex(w, id: zoneId) {
            w.zones[z].shape = .circle(r)
            w.zones[z].hit = jingang ? Hit(mult: 0, element: element, school: def.school, statusChance: -1) : makeHit(w)
        } else {
            zoneId = zone(w, .circle(r), at: w.player.pos, delay: 0.01, duration: .infinity, visual: .aura, follow: true)
        }
    }

    override func statMods(_ w: BattleWorld) -> [StatMod] {
        var reduce = v("dmgReduce", 0.05) + v("extraReduce")
        if w.hasLegendary("L_jingang") { reduce += w.lp("L_jingang", "reduce", 0.1) }
        return [StatMod(.dmgReduce, reduce)]
    }

    override func playerHurt(_ w: BattleWorld, amount: Double) {
        guard has("reflect") else { return }
        var m = v("reflectMult", 2) * (has("reflectMul") ? v("reflectMul") : 1)
        if w.hasLegendary("L_jingang") { m *= w.lp("L_jingang", "reflectMul", 5) }
        var r = radius(w)
        if w.hasLegendary("L_jingang") { r *= w.lp("L_jingang", "radiusMul", 2) }
        w.events.append(.nova(pos: w.player.pos, radius: r, element: element))
        strike(w, .circle(r), at: w.player.pos, hit: makeHit(w, mult: m))
    }

    override func stageStarted(_ w: BattleWorld) {
        super.stageStarted(w)
        zoneId = -1
    }
}

/// 震地踏（7.5）：跺脚产生冲击波，带余震。
/// 地裂天崩：余震 3 次，每次大 20%。天震：全屏，倍率 ×0.5，必定施加状态（12.5）。
final class ZhenTaSkill: SkillBase {
    private var shocks: [(time: Double, radius: Double, mult: Double)] = []

    override func update(_ w: BattleWorld, dt: Double) {
        for k in shocks.indices { shocks[k].time -= dt }
        while let s = shocks.first, s.time <= 0 {
            shocks.removeFirst()
            stomp(w, radius: s.radius, mult: s.mult)
        }
        let quake = w.hasLegendary("L_tianzhen")
        tickCooldown(w, dt: dt, ready: { quake ? targetReady(w) : meleeReady(w) }) {
            var r = radius(w)
            var m = mult
            if quake {
                r = max(w.viewSize.x, w.viewSize.y) * 0.75
                m *= w.lp("L_tianzhen", "multMul", 0.5)
            }
            stomp(w, radius: r, mult: m)
            let delay = v("aftershockDelay", 0.4)
            let am = v("aftershockMult", 0.5)
            if has("fixedAftershocks") {
                let g = 1 + v("aftershockGrow", 0.2)
                for k in 1...Int(v("fixedAftershocks")) {
                    shocks.append((delay * Double(k), r * pow(g, Double(k)), m * am))
                }
            } else if has("aftershock") {
                shocks.append((delay, r, m * am))
            }
        }
    }

    private func stomp(_ w: BattleWorld, radius r: Double, mult m: Double) {
        w.events.append(.nova(pos: w.player.pos, radius: r, element: element))
        w.events.append(.shake(1))
        var h = makeHit(w, mult: m)
        if w.hasLegendary("L_tianzhen") { h.statusChance = 10 }
        strike(w, .circle(r), at: w.player.pos, hit: h)
    }

    override func stageStarted(_ w: BattleWorld) {
        super.stageStarted(w)
        shocks.removeAll()
    }
}

/// 蛮牛冲（7.5）：冲刺，期间无敌，撞到的敌人受伤并击退。
/// 蛮荒冲撞：连冲 4 次，路径留下裂地。奔雷：留下雷光，冷却 −50%（12.5）。
final class ChongZhuangSkill: SkillBase {
    private var dashLeft = 0
    private var dashTimer = 0.0
    private var dashDir = Vec2.up
    private var hitIds: Set<Int> = []
    private var trailTimer = 0.0

    override func cooldown(_ w: BattleWorld) -> Double {
        super.cooldown(w) * (w.hasLegendary("L_benlei") ? w.lp("L_benlei", "cooldownMul", 0.5) : 1)
    }

    override func update(_ w: BattleWorld, dt: Double) {
        if dashTimer > 0 {
            dashTimer -= dt
            let r = v("radius", 40) * w.stats.area
            for i in w.enemiesIn(.circle(r), at: w.player.pos) where !hitIds.contains(w.enemies[i].id) {
                hitIds.insert(w.enemies[i].id)
                w.damageEnemy(i, makeHit(w, knockback: v("knockback", 100)), from: w.player.pos)
            }
            trailTimer -= dt
            if trailTimer <= 0 {
                trailTimer = 0.06
                if has("trail") {
                    zone(w, .circle(36 * w.stats.area), at: w.player.pos, delay: 0.01, duration: 2 * w.stats.duration,
                         visual: .residue, hit: makeHit(w, mult: v("trailMult", 0.5)))
                }
                if w.hasLegendary("L_benlei") {
                    zone(w, .circle(36 * w.stats.area), at: w.player.pos, delay: 0.01,
                         duration: w.lp("L_benlei", "duration", 3) * w.stats.duration, visual: .residue,
                         hit: Hit(mult: mult * w.lp("L_benlei", "mult", 0.8), element: .thunder, school: def.school,
                                  statusChance: def.statusChance, source: .skill(slot)))
                }
            }
            if dashTimer <= 0 { endDash(w) }
            return
        }
        tickCooldown(w, dt: dt, ready: { meleeReady(w) || w.hasEnemy(within: 320) }) {
            dashLeft = has("fixedDashes") ? Int(v("fixedDashes")) : Int(v("dashes", 1))
            startDash(w)
        }
    }

    private func startDash(_ w: BattleWorld) {
        dashLeft -= 1
        dashDir = aimDir(w, range: 400)
        let t = v("dashTime", 0.25)
        let dist = v("dashDistance", 250) * (1 + v("dashDistancePct"))
        dashTimer = t
        hitIds.removeAll()
        w.player.dashTime = t
        w.player.dashVel = dashDir * (dist / t)
        w.player.skillInvuln = max(w.player.skillInvuln, t + 0.05)
        w.player.facing = dashDir
    }

    private func endDash(_ w: BattleWorld) {
        if has("endWave") {
            let r = v("endWaveRadius", 120) * w.stats.area
            w.events.append(.nova(pos: w.player.pos, radius: r, element: element))
            strike(w, .circle(r), at: w.player.pos, hit: makeHit(w, mult: mult * v("endWaveMult", 1.5)))
        }
        if dashLeft > 0 { startDash(w) }
    }

    override func stageStarted(_ w: BattleWorld) {
        super.stageStarted(w)
        dashTimer = 0
        dashLeft = 0
    }
}
