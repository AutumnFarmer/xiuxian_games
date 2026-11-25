import Foundation

/// 召唤类功法的公共部分：按数量维护召唤物，追最近敌人。
class SummonSkill: SkillBase {
    var kind: SummonKind { .fox }

    /// 召唤物数量：参数 + 御兽流派被动（7.1）。
    func summonCount(_ w: BattleWorld) -> Int {
        var n = Int(v("count", 1).rounded())
        if v("countMul") > 0 { n *= Int(v("countMul")) }
        if def.has(.projectile) { n += w.stats.projCount }
        return max(1, n + w.summonCountBonus)
    }

    /// 让召唤物数量等于 n。
    func ensure(_ w: BattleWorld, count n: Int) {
        let mine = mySummons(w)
        if mine.count > n { for i in mine.suffix(mine.count - n) { w.summons[i].dead = true } }
        if mine.count < n {
            for k in mine.count..<n {
                let a = Double(k) * 2 * .pi / Double(max(1, n))
                w.summons.append(Summon(id: w.makeId(), kind: kind, skill: slot, pos: w.player.pos + Vec2.fromAngle(a, 50), angle: a))
            }
        }
    }

    func clearSummons(_ w: BattleWorld) { for i in mySummons(w) { w.summons[i].dead = true } }

    /// 朝目标移动，返回到目标的距离。
    @discardableResult
    func move(_ w: BattleWorld, _ i: Int, to p: Vec2, speed: Double, dt: Double, stop: Double = 0) -> Double {
        let d = p - w.summons[i].pos
        let l = d.length
        if l > stop { w.summons[i].pos += d / l * min(l - stop, speed * dt) }
        return l
    }

    override func stageStarted(_ w: BattleWorld) {
        super.stageStarted(w)
        for i in mySummons(w) { w.summons[i].pos = w.player.pos + Vec2.fromAngle(w.summons[i].angle, 50) }
    }
}

/// 唤灵（7.5）：常驻灵狐，追敌撕咬。
/// 九尾天狐：合成 1 只，体型 ×2，每 0.5 秒撕咬，范围 120pt，倍率再乘合成前的狐数。九尾：固定 9 只，倍率 ×0.5（12.5）。
final class HuanLingSkill: SummonSkill {
    override var kind: SummonKind { .fox }

    override func update(_ w: BattleWorld, dt: Double) {
        let base = summonCount(w)
        let jiuwei = w.hasLegendary("L_jiuwei")
        var n = jiuwei ? Int(w.lp("L_jiuwei", "count", 9)) : base
        var m = mult
        if jiuwei { m *= w.lp("L_jiuwei", "multMul", 0.5) }
        if has("merge") {
            // 九尾 + 九尾天狐：倍率 ×4.5，不再乘狐数（12.5 合并规则）
            m = jiuwei ? mult * 4.5 : mult * Double(base)
            n = 1
        }
        ensure(w, count: n)
        let interval = summonInterval(w, v("interval", 0.8))
        let biteR = v("biteRadius") > 0 ? v("biteRadius") * w.stats.area : 0
        let reach = v("reach", 30) * (has("merge") ? 2 : 1)
        for i in mySummons(w) {
            w.summons[i].timer -= dt
            guard let t = w.nearestEnemy(to: w.summons[i].pos, within: 450) else {
                move(w, i, to: w.player.pos + Vec2.fromAngle(w.summons[i].angle, 60), speed: v("moveSpeed", 250), dt: dt, stop: 4)
                continue
            }
            let d = move(w, i, to: w.enemies[t].pos, speed: v("moveSpeed", 250), dt: dt, stop: reach * 0.6)
            if w.summons[i].timer <= 0, d <= reach + w.enemies[t].radius {
                w.summons[i].timer = interval
                if biteR > 0 {
                    strike(w, .circle(biteR), at: w.enemies[t].pos, hit: makeHit(w, mult: m))
                } else {
                    w.damageEnemy(t, makeHit(w, mult: m), from: w.summons[i].pos)
                }
            }
        }
    }
}

/// 灵雀（7.5）：常驻灵雀盘旋，吐灵弹。
/// 朱雀离火：灵雀 ×2，火羽无限穿透。凤凰：每 10 秒俯冲自爆再重生，回复 2% 生命（12.5）。
final class LingQueSkill: SummonSkill {
    override var kind: SummonKind { .bird }

    override func update(_ w: BattleWorld, dt: Double) {
        let n = summonCount(w)
        ensure(w, count: n)
        let interval = summonInterval(w, v("interval", 1.2))
        let orbitR = v("orbitRadius", 120)
        let phoenix = w.hasLegendary("L_fenghuang")
        for (k, i) in mySummons(w).enumerated() {
            w.summons[i].angle += dt * 1.6
            let home = w.player.pos + Vec2.fromAngle(w.summons[i].angle + Double(k) * 2 * .pi / Double(n), orbitR)
            move(w, i, to: home, speed: 600, dt: dt)
            w.summons[i].timer -= dt
            if w.summons[i].timer <= 0 {
                let targets = w.randomEnemies(near: w.summons[i].pos, within: v("range", 400), count: 1)
                if let t = targets.first {
                    w.summons[i].timer = interval
                    let d = (w.enemies[t].pos - w.summons[i].pos).normalized()
                    shoot(w, from: w.summons[i].pos, dir: d, speed: projSpeed(w), radius: v("radius", 8),
                          range: v("range", 400) + 60, pierce: pierce(), visual: isEvolved ? .feather : .orb)
                }
            }
            if phoenix {
                w.summons[i].life = w.summons[i].life < 0 ? w.lp("L_fenghuang", "interval", 10) + Double(k) : w.summons[i].life
                if w.summons[i].life <= 0.05 {
                    let r = w.lp("L_fenghuang", "radius", 120) * w.stats.area
                    let p = w.nearestEnemy(to: w.summons[i].pos, within: 400).map { w.enemies[$0].pos } ?? w.summons[i].pos
                    w.events.append(.explosion(pos: p, radius: r, element: element))
                    strike(w, .circle(r), at: p, hit: makeHit(w, mult: mult * w.lp("L_fenghuang", "mult", 3)))
                    w.heal(w.stats.hp * w.lp("L_fenghuang", "heal", 0.02))
                    w.summons[i].life = w.lp("L_fenghuang", "interval", 10)
                }
            }
        }
    }
}

/// 碧蟒（7.5）：召唤巨蟒原地扫尾。
/// 青蛟：常驻跟随，半径 ×1.5，每 3 秒吐息。烛龙：跟随玩家并环绕，常驻（12.5）。
final class BiMangSkill: SummonSkill {
    override var kind: SummonKind { .python }
    private var activeLeft = 0.0
    private var tickTimer = 0.0
    private var breathTimer = 3.0

    override func update(_ w: BattleWorld, dt: Double) {
        let zhuolong = w.hasLegendary("L_zhuolong")
        let permanent = isPermanent(w) || zhuolong || has("follow")
        if permanent {
            activeLeft = .infinity
        } else {
            if activeLeft > 0 { activeLeft -= dt }
            if activeLeft <= 0 {
                clearSummons(w)
                tickCooldown(w, dt: dt, ready: { targetReady(w) }) { activeLeft = duration(w) }
                if activeLeft <= 0 { return }
            }
        }
        if mySummons(w).isEmpty {
            let p = permanent ? w.player.pos : (w.nearestEnemy(to: w.player.pos, within: 400).map { w.enemies[$0].pos } ?? w.player.pos)
            w.summons.append(Summon(id: w.makeId(), kind: kind, skill: slot, pos: p))
        }
        guard let i = mySummons(w).first else { return }
        if zhuolong || has("follow") { w.summons[i].pos = w.player.pos }
        var r = radius(w)
        if zhuolong { r = max(r, w.lp("L_zhuolong", "radius", 150) * w.stats.area) }
        tickTimer -= dt
        if tickTimer <= 0 {
            tickTimer = w.cfg.balance.areaTick
            w.summons[i].angle += 1
            strike(w, .circle(r), at: w.summons[i].pos)
        }
        if has("breath") {
            breathTimer -= dt
            if breathTimer <= 0, let t = w.nearestEnemy(to: w.summons[i].pos, within: 450) {
                breathTimer = 3
                let d = (w.enemies[t].pos - w.summons[i].pos).normalized()
                w.events.append(.slash(pos: w.summons[i].pos, dir: d, radius: 400, angle: 0.2, element: element))
                strike(w, .rect(30 * w.stats.area, 400, d), at: w.summons[i].pos, hit: makeHit(w, mult: 2))
            }
        }
    }

    override func stageStarted(_ w: BattleWorld) {
        super.stageStarted(w)
        activeLeft = 0
        clearSummons(w)
    }
}

/// 玄龟（7.5）：常驻玄龟跟在身后砸地，在场时减伤。
/// 玄武：合成 1 只，砸地半径 ×2，减伤 20%，每次砸地回复 1% 生命。镇岳：砸地震晕 1 秒（12.5）。
final class XuanGuiSkill: SummonSkill {
    override var kind: SummonKind { .turtle }

    override func update(_ w: BattleWorld, dt: Double) {
        let n = has("merge") ? 1 : summonCount(w)
        ensure(w, count: n)
        let interval = summonInterval(w, max(0.5, v("interval", 2)))
        let r = radius(w)
        for (k, i) in mySummons(w).enumerated() {
            let behind = w.player.pos - w.player.facing * 50 + Vec2.fromAngle(Double(k) * 2.4, 20)
            move(w, i, to: behind, speed: 400, dt: dt, stop: 2)
            w.summons[i].timer -= dt
            guard w.summons[i].timer <= 0, let t = w.nearestEnemy(to: w.summons[i].pos, within: v("range", 260)) else { continue }
            w.summons[i].timer = interval
            let p = w.enemies[t].pos
            w.events.append(.nova(pos: p, radius: r, element: element))
            for e in w.enemiesIn(.circle(r), at: p) {
                let res = w.damageEnemy(e, makeHit(w), from: p)
                if w.hasLegendary("L_zhenyue"), !res.killed, e < w.enemies.count, !w.enemies[e].dead {
                    if w.enemies[e].isBossLike {
                        w.enemies[e].vulnAmount = max(w.enemies[e].vulnAmount, w.lp("L_zhenyue", "bossVuln", 0.2))
                        w.enemies[e].vulnTime = max(w.enemies[e].vulnTime, 1)
                    } else {
                        w.enemies[e].stunTime = max(w.enemies[e].stunTime, w.lp("L_zhenyue", "stun", 1))
                    }
                }
            }
            if has("healPct") { w.heal(w.stats.hp * v("healPct")) }
        }
    }

    override func statMods(_ w: BattleWorld) -> [StatMod] {
        [StatMod(.dmgReduce, has("fixedReduce") ? v("fixedReduce") : v("dmgReduce", 0.05))]
    }
}
