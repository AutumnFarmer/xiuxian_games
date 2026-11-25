import Foundation

extension BattleWorld {
    // MARK: 伤害公式（5.4）

    /// 计算一次命中的伤害和是否暴击，不修改任何状态（除了消耗随机数）。
    func computeDamage(_ hit: Hit, on e: Enemy) -> (Double, Bool) {
        var inc = 1 + stats.dmgPct + demonDmgPct + tempDmgPct
        if let el = hit.element { inc += stats.elemPct[el.index] }
        if let s = hit.school { inc += stats.schoolPct[s.index] }
        if e.isEliteOrBoss { inc += stats.elitePct }

        var critRate = stats.critRate
        var critDmg = stats.critDmg
        if critRate > 1 {
            critDmg += (critRate - 1) * cfg.balance.critOverflowToCritDmg
            critRate = 1
        }
        let crit = rng.chance(critRate)
        var critF = crit ? critDmg : 1
        if crit { critF = extraCrit(critF) }

        var counterF = 1.0
        if let el = hit.element, let te = e.element, cfg.elements.counters(el, te) { counterF = counterMultValue }

        let st = cfg.elements.status
        var vuln = 1.0 + Double(e.flawStacks) * st.flaw.vulnPerStack * (1 + stats.statusPower)
        if e.vulnTime > 0 { vuln += e.vulnAmount }
        if let el = hit.element, hasGeneratingMark(e, hitBy: el) { vuln += generateBonusValue }

        let affixF = hit.element.map { affixElemMult[$0.index] } ?? 1
        let float = rng.range(cfg.balance.dmgFloatMin, cfg.balance.dmgFloatMax)
        let dmg = stats.atk * hit.mult * inc * critF * counterF * vuln * affixF * float * globalDmgMult
        return (dmg, crit)
    }

    /// 传说特效"天眼"（12.5）等额外暴击，M6 接入；默认不变。
    func extraCrit(_ critF: Double) -> Double {
        if let chance = legendaryParam("L_baoji", "chance"), rng.chance(chance) { return critF * critF }
        return critF
    }

    /// 6.3：目标带着元素 A 的状态，被 A 所生的元素命中。
    func hasGeneratingMark(_ e: Enemy, hitBy el: Element) -> Bool {
        for k in 0..<7 where e.marks[k] > 0 {
            if cfg.elements.generates(statusElement: Element.fromIndex(k), hit: el) { return true }
        }
        return false
    }

    // MARK: 造成伤害

    /// 对敌人 i 造成一次玩家阵营伤害（5.4）。src 是击退的来源位置。返回实际伤害。
    @discardableResult
    func damageEnemy(_ i: Int, _ hit: Hit, from src: Vec2? = nil) -> Double {
        guard i >= 0, i < enemies.count, !enemies[i].dead else { return 0 }
        let (dmg, crit) = computeDamage(hit, on: enemies[i])
        applyDamage(i, dmg)
        events.append(.damage(pos: enemies[i].pos, amount: dmg, crit: crit, element: hit.element, dot: false, targetId: enemies[i].id))
        if dmg > bestHit { bestHit = dmg }
        let ls = stats.lifesteal + hit.lifesteal
        if ls > 0 { lifestealHeal(dmg * ls) }
        if hit.knockback > 0, let src { knockEnemy(i, from: src, distance: hit.knockback) }
        let killed = enemies[i].hp <= 0
        if let el = hit.element, hit.statusChance >= 0 {
            let chance = hit.statusChance + stats.statusChance
            // 被打死的目标只保留感电的连锁闪电，其余状态没有意义。
            if rng.chance(chance), !killed || StatusKind.of(el) == .shock {
                applyStatus(i, el, hitDamage: dmg)
            }
        }
        for b in skills { b.didHit(self, enemy: i, damage: dmg, crit: crit, hit: hit) }
        if enemies[i].hp <= 0 { killEnemy(i) }
        return dmg
    }

    /// 固定伤害：灼烧、感电、碎裂等（6.4）。不暴击，不乘其他系数。
    func damageFixed(_ i: Int, _ amount: Double, element: Element?, dot: Bool = true) {
        guard i >= 0, i < enemies.count, !enemies[i].dead, amount > 0 else { return }
        applyDamage(i, amount)
        events.append(.damage(pos: enemies[i].pos, amount: amount, crit: false, element: element, dot: dot, targetId: enemies[i].id))
        if amount > bestHit { bestHit = amount }
        if enemies[i].hp <= 0 { killEnemy(i) }
    }

    private func applyDamage(_ i: Int, _ dmg: Double) {
        let before = enemies[i].hp
        enemies[i].hp -= dmg
        if enemies[i].isBossLike, enemies[i].maxHp > 0 {
            let lost = max(0, min(before, dmg)) / enemies[i].maxHp * 100
            addUltCharge(lost * cfg.balance.ult.perBossPct)
        }
    }

    func addUltCharge(_ v: Double) {
        guard !ultLocked else { return }
        ultCharge = min(cfg.balance.ult.max, ultCharge + v)
    }

    func lifestealHeal(_ amount: Double) {
        let cap = stats.hp * cfg.balance.lifestealCapPerSec
        let allowed = max(0, cap - player.lifestealBudget)
        let h = min(amount, allowed)
        guard h > 0 else { return }
        player.lifestealBudget += h
        heal(h, show: false)
    }

    func knockEnemy(_ i: Int, from src: Vec2, distance: Double) {
        guard !enemies[i].isBossLike else { return }
        var d = distance
        if enemies[i].role == .elite { d *= cfg.balance.eliteKnockbackFactor }
        let dir = (enemies[i].pos - src).normalized(or: player.facing)
        let t = cfg.balance.knockbackTime
        enemies[i].knock = dir * (2 * d / t)
        enemies[i].knockTime = t
    }

    // MARK: 范围伤害

    /// 圆形范围内每个敌人结算一次。返回命中数。
    @discardableResult
    func damageCircle(center: Vec2, radius: Double, hit: Hit, excluding: Int = -1) -> Int {
        var targets: [Int] = []
        forEachEnemy(inCircle: center, radius: radius) { i in
            if enemies[i].id != excluding { targets.append(i) }
            return true
        }
        for i in targets { damageEnemy(i, hit, from: center) }
        return targets.count
    }

    /// 某个形状内的敌人下标。
    func enemiesIn(_ shape: ZoneShape, at pos: Vec2) -> [Int] {
        var out: [Int] = []
        let reach: Double
        switch shape {
        case .circle(let r): reach = r
        case .ring(_, let o): reach = o
        case .rect(let hw, let l, _): reach = l + hw
        case .cone(let r, _, _): reach = r
        }
        forEachEnemy(inCircle: pos, radius: reach) { i in
            if shapeContains(shape, at: pos, point: enemies[i].pos, radius: enemies[i].radius) { out.append(i) }
            return true
        }
        return out
    }

    func shapeContains(_ shape: ZoneShape, at pos: Vec2, point p: Vec2, radius tr: Double) -> Bool {
        let d = p - pos
        switch shape {
        case .circle(let r):
            return d.lengthSq <= (r + tr) * (r + tr)
        case .ring(let inner, let outer):
            let l = d.length
            return l >= inner - tr && l <= outer + tr
        case .rect(let hw, let len, let dir):
            let along = d.dot(dir)
            let perp = abs(d.x * dir.y - d.y * dir.x)
            return along >= -tr && along <= len + tr && perp <= hw + tr
        case .cone(let r, let half, let dir):
            let l = d.length
            if l > r + tr { return false }
            if l <= tr { return true }
            return angleBetween(d, dir) <= half + asin(min(1, tr / l))
        }
    }

    // MARK: 元素状态（6.4）

    func applyStatus(_ i: Int, _ el: Element, hitDamage: Double) {
        let st = cfg.elements.status
        let power = 1 + stats.statusPower
        let role = enemies[i].role
        switch StatusKind.of(el) {
        case .flaw:
            enemies[i].flawStacks = min(st.flaw.maxStacks, enemies[i].flawStacks + 1)
            enemies[i].flawTime = st.flaw.duration
            mark(i, .metal, st.flaw.duration)
        case .entangle:
            if enemies[i].isBossLike {
                slowEnemy(i, st.entangle.bossSlow, st.entangle.bossSlowDuration)
                mark(i, .wood, st.entangle.bossSlowDuration)
            } else {
                let d = role == .elite ? st.entangle.eliteDuration : st.entangle.duration
                enemies[i].rootTime = max(enemies[i].rootTime, d)
                mark(i, .wood, d)
            }
        case .slow:
            slowEnemy(i, min(st.slow.maxAmount, st.slow.amount * power), st.slow.duration)
            mark(i, .water, st.slow.duration)
        case .burn:
            let per = hitDamage * st.burn.tickPct * power
            if enemies[i].burnTicks <= 0 || per > enemies[i].burnTick {
                enemies[i].burnTick = per
                enemies[i].burnTimer = st.burn.interval
            }
            enemies[i].burnTicks = st.burn.ticks
            mark(i, .fire, Double(st.burn.ticks) * st.burn.interval)
        case .stun:
            if enemies[i].isBossLike {
                enemies[i].vulnAmount = max(enemies[i].vulnAmount, st.stun.bossVuln)
                enemies[i].vulnTime = max(enemies[i].vulnTime, st.stun.bossVulnDuration)
                mark(i, .earth, st.stun.bossVulnDuration)
            } else {
                let d = role == .elite ? st.stun.eliteDuration : st.stun.duration
                enemies[i].stunTime = max(enemies[i].stunTime, d)
                mark(i, .earth, d)
            }
        case .shock:
            mark(i, .thunder, st.shock.markDuration)
            let dmg = hitDamage * st.shock.pct * power * shockMult
            let from = enemies[i].pos
            let near = nearestEnemies(to: from, within: st.shock.radius, count: st.shock.targets + 1)
            var n = 0
            for t in near where t != i && n < st.shock.targets {
                n += 1
                events.append(.lightning(from: from, to: enemies[t].pos))
                damageFixed(t, dmg, element: .thunder)
            }
        case .freeze:
            if enemies[i].isBossLike {
                slowEnemy(i, min(st.slow.maxAmount, st.slow.amount * power), st.slow.duration)
                mark(i, .ice, st.slow.duration)
            } else {
                let d = role == .elite ? st.freeze.eliteDuration : st.freeze.duration
                enemies[i].freezeTime = max(enemies[i].freezeTime, d)
                mark(i, .ice, d)
            }
        }
    }

    private func slowEnemy(_ i: Int, _ amount: Double, _ duration: Double) {
        if enemies[i].slowTime <= 0 { enemies[i].slowAmount = 0 }
        enemies[i].slowAmount = max(enemies[i].slowAmount, amount)
        enemies[i].slowTime = max(enemies[i].slowTime, duration)
    }

    private func mark(_ i: Int, _ el: Element, _ duration: Double) {
        enemies[i].marks[el.index] = max(enemies[i].marks[el.index], duration)
    }

    /// 冰封中被击杀时碎裂（6.4）。
    func shatter(at p: Vec2) {
        let st = cfg.elements.status.freeze
        let dmg = stats.atk * st.shatterMult * (1 + stats.statusPower) * shatterMult
        events.append(.shatter(pos: p))
        var targets: [Int] = []
        forEachEnemy(inCircle: p, radius: st.shatterRadius) { i in
            targets.append(i)
            return true
        }
        for t in targets { damageFixed(t, dmg, element: .ice) }
    }
}
