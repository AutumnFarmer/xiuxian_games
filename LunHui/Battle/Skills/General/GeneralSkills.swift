import Foundation

/// 掌心雷（7.6）：对随机敌人降下天雷。
/// 九天神雷：每次 10 道，必定施加状态。天罚：每道天雷连锁弹射 3 次，每次 70%（12.5）。
final class LeiYinSkill: SkillBase {
    override func update(_ w: BattleWorld, dt: Double) {
        tickCooldown(w, dt: dt, ready: { targetReady(w) }) {
            let n = has("fixedTargets") ? Int(v("fixedTargets")) : Int(v("targets", 1))
            let r = radius(w)
            for t in w.randomEnemies(near: w.player.pos, within: w.cfg.balance.targetRange, count: n) {
                let p = w.enemies[t].pos
                w.events.append(.skyBolt(pos: p, element: element))
                strike(w, .circle(r), at: p)
                if w.hasLegendary("L_tianfa") { chain(w, from: p, exclude: w.enemies[safe: t]?.id ?? -1) }
            }
        }
    }

    private func chain(_ w: BattleWorld, from start: Vec2, exclude: Int) {
        var p = start
        var hitIds: Set<Int> = [exclude]
        var m = mult
        for _ in 0..<Int(w.lp("L_tianfa", "bounces", 3)) {
            m *= w.lp("L_tianfa", "mult", 0.7)
            let cands = w.nearestEnemies(to: p, within: w.lp("L_tianfa", "range", 220), count: 6)
            guard let next = cands.first(where: { !hitIds.contains(w.enemies[$0].id) }) else { return }
            hitIds.insert(w.enemies[next].id)
            w.events.append(.lightning(from: p, to: w.enemies[next].pos))
            let q = w.enemies[next].pos
            w.damageEnemy(next, makeHit(w, mult: m), from: p)
            p = q
        }
    }
}

/// 火云（7.6）：在敌人处生成火云。
/// 焚天云海：常驻 5 片云跟随玩家。焚身：火云跟随玩家，半径 ×1.5（12.5）。
final class HuoYunSkill: SkillBase {
    private var cloudIds: [Int] = []

    override func update(_ w: BattleWorld, dt: Double) {
        let follow = has("follow") || w.hasLegendary("L_fenshen")
        var r = radius(w)
        if w.hasLegendary("L_fenshen") { r *= w.lp("L_fenshen", "radiusMul", 1.5) }
        let n = count(w)
        if follow {
            // 跟随：云固定分布在玩家周围
            cloudIds = cloudIds.filter { zoneIndex(w, id: $0) != nil }
            let permanent = isPermanent(w)
            if cloudIds.isEmpty {
                let ok = permanent || { () -> Bool in
                    var cast = false
                    tickCooldown(w, dt: dt, ready: { true }) { cast = true }
                    return cast
                }()
                guard ok else { return }
                let life = permanent ? Double.infinity : duration(w)
                for _ in 0..<n {
                    cloudIds.append(zone(w, .circle(r), at: w.player.pos, delay: 0.01, duration: life, visual: .cloud))
                }
            }
            let spread = has("spread") ? v("spread") : r * 0.9
            for (k, id) in cloudIds.enumerated() {
                guard let z = zoneIndex(w, id: id) else { continue }
                let a = w.time * 0.6 + Double(k) * 2 * .pi / Double(max(1, cloudIds.count))
                w.zones[z].pos = w.player.pos + (cloudIds.count == 1 ? .zero : Vec2.fromAngle(a, spread))
                w.zones[z].shape = .circle(r)
            }
            return
        }
        tickCooldown(w, dt: dt, ready: { targetReady(w) }) {
            let targets = w.randomEnemies(near: w.player.pos, within: w.cfg.balance.targetRange, count: n, allowRepeat: false)
            for t in targets {
                zone(w, .circle(r), at: w.enemies[t].pos, delay: 0.01, duration: duration(w), visual: .cloud)
            }
        }
    }

    override func stageStarted(_ w: BattleWorld) {
        super.stageStarted(w)
        cloudIds.removeAll()
    }
}

/// 玄光盾（7.6）：护盾吸收伤害，破裂时爆开。护盾破裂后才开始计冷却。
/// 太虚玄光：护盾 50%，冷却 4 秒，破裂爆炸半径 ×2。无量：破裂后立即重生，护盾值减半（12.5）。
final class XuanGuangSkill: SkillBase {
    private var shieldUp = false

    override func update(_ w: BattleWorld, dt: Double) {
        if shieldUp, w.player.shield <= 0 { shieldUp = false }
        guard !shieldUp else { return }
        if cooldownLeft > 0 { cooldownLeft -= dt }
        guard cooldownLeft <= 0 else { return }
        raise(w)
    }

    private func raise(_ w: BattleWorld) {
        var pct = has("fixedShield") ? v("fixedShield") : v("shieldPct", 0.2)
        if w.hasLegendary("L_wuliang") { pct *= w.lp("L_wuliang", "shieldMul", 0.5) }
        w.player.shieldMax = w.stats.hp * pct
        w.player.shield = w.player.shieldMax
        shieldUp = true
    }

    override func shieldBroken(_ w: BattleWorld) {
        guard shieldUp else { return }
        shieldUp = false
        let r = radius(w)
        w.events.append(.shieldBreak(pos: w.player.pos))
        w.events.append(.nova(pos: w.player.pos, radius: r, element: element))
        strike(w, .circle(r), at: w.player.pos)
        if has("healOnBreak") { w.heal(w.stats.hp * v("healOnBreak")) }
        if w.hasLegendary("L_wuliang") {
            raise(w)
        } else {
            cooldownLeft = cooldown(w)
        }
    }

    override func cooldownProgress(_ w: BattleWorld) -> Double {
        shieldUp ? 1 : super.cooldownProgress(w)
    }

    override func stageStarted(_ w: BattleWorld) {
        super.stageStarted(w)
        cooldownLeft = 0
        shieldUp = false
        w.player.shield = 0
    }
}

/// 风刃（7.6）：朝前方射出风刃，穿透。
/// 天风刃：8 个方向齐射，无限穿透。旋风：风刃绕身一圈后射出（12.5）。
final class FengRenSkill: SkillBase {
    private var spinning: [(proj: Int, left: Double)] = []

    override func update(_ w: BattleWorld, dt: Double) {
        tickCooldown(w, dt: dt, ready: { targetReady(w) }) { fire(w) }
    }

    private func fire(_ w: BattleWorld) {
        let facing = w.player.input.lengthSq > 0 ? w.player.facing : aimDir(w)
        let n = count(w)
        let dirs = has("directions") ? ring(facing, count: Int(v("directions")) + max(0, n - 2)) : fan(facing, count: n, spacingDeg: 12)
        let range = v("range", 500) * (1 + v("rangePct"))
        if w.hasLegendary("L_xuanfeng") {
            // 先绕身一圈，0.6 秒后沿当时的方向射出
            for (k, _) in dirs.enumerated() {
                let a = Double(k) * 2 * .pi / Double(dirs.count)
                if let i = orbit(w, angle: a, radius: 70 * w.stats.area, period: w.lp("L_xuanfeng", "spin", 0.6),
                                 size: v("radius", 12) * 1.2, life: w.lp("L_xuanfeng", "spin", 0.6), visual: .wind, tag: 1) {
                    w.projectiles[i].pierce = -1
                }
            }
            return
        }
        for d in dirs {
            shoot(w, from: w.player.pos, dir: d, speed: projSpeed(w), radius: v("radius", 12), range: range,
                  pierce: pierce(), visual: .wind)
        }
    }

    override func projectileExpired(_ w: BattleWorld, proj: Int) {
        let pr = w.projectiles[proj]
        guard pr.motion == .orbit, pr.tag == 1 else { return }
        let d = (pr.pos - w.player.pos).normalized(or: w.player.facing)
        shoot(w, from: pr.pos, dir: d, speed: projSpeed(w), radius: v("radius", 12), range: v("range", 500) * (1 + v("rangePct")),
              pierce: -1, visual: .wind)
    }
}
