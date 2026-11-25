import Foundation

/// 剑阵（7.5）：剑绕身旋转。
/// 周天剑阵：常驻 8 把，半径 ×1.5，每转一圈向外射出 300pt 再收回。
/// 万刃：每转一圈射出全部剑，然后重新生成（12.5）。
final class JianZhenSkill: SkillBase {
    private var activeLeft = 0.0
    private var built = -1
    private var lapTimer = 0.0
    private var launchTimer = 0.0

    private var swordCount: Int { has("fixedCount") ? Int(v("fixedCount")) : Int(v("count", 3)) }

    override func update(_ w: BattleWorld, dt: Double) {
        let n = swordCount + w.stats.projCount
        let period = v("period", 1.5)
        let permanent = isPermanent(w)
        if permanent {
            activeLeft = .infinity
        } else {
            if activeLeft > 0 { activeLeft -= dt }
            if activeLeft <= 0 {
                if built >= 0 { clear(w) }
                tickCooldown(w, dt: dt, ready: { true }) { activeLeft = duration(w) }
                if activeLeft <= 0 { return }
            }
        }
        let orbitR = v("orbitRadius", 90) * (1 + v("orbitRadiusPct")) * (has("orbitRadiusMul") ? v("orbitRadiusMul") : 1) * w.stats.area
        if myOrbits(w).count != n || built != n {
            clear(w)
            for k in 0..<n {
                orbit(w, angle: Double(k) * 2 * .pi / Double(n), radius: orbitR, period: period,
                      size: v("radius", 14) * w.stats.area, life: .infinity, visual: .sword)
            }
            built = n
        }
        // 周天剑阵：每转一圈向外射出 300pt 再收回
        if has("launch") {
            lapTimer += dt
            if lapTimer >= period {
                lapTimer = 0
                launchTimer = 0.5
            }
            if launchTimer > 0 {
                launchTimer -= dt
                let f = sin((0.5 - launchTimer) / 0.5 * .pi)
                for i in myOrbits(w) { w.projectiles[i].orbitRadius = orbitR + v("launch") * f }
            }
        }
        // 万刃：每转一圈把全部剑射向最近的敌人
        if w.hasLegendary("L_wanren") {
            lapTimer += dt
            if lapTimer >= period, w.hasEnemy(within: 650) {
                lapTimer = 0
                for i in myOrbits(w) {
                    let pr = w.projectiles[i]
                    let d = w.nearestEnemy(to: pr.pos, within: 650).map { (w.enemies[$0].pos - pr.pos).normalized() } ?? (pr.pos - w.player.pos).normalized()
                    shoot(w, from: pr.pos, dir: d, speed: 800 * w.stats.projSpeed, radius: pr.radius, range: 650, pierce: 2, visual: .sword)
                    w.projectiles[i].dead = true
                }
                built = -1
            }
        }
    }

    private func clear(_ w: BattleWorld) {
        for i in myOrbits(w) { w.projectiles[i].dead = true }
        built = -1
    }

    override func onRefresh() { built = -1 }
    override func stageStarted(_ w: BattleWorld) {
        super.stageStarted(w)
        built = -1
        activeLeft = 0
    }
}

/// 剑气斩（7.5）：朝角色朝向斩出弧形剑气，无限穿透。
/// 开天剑气：8 个方向，宽度 ×2，暴击时追加一次。天河：横扫全屏的长剑光（12.5）。
final class JianQiSkill: SkillBase {
    override func update(_ w: BattleWorld, dt: Double) {
        tickCooldown(w, dt: dt, ready: { targetReady(w) }) { fire(w) }
    }

    private func fire(_ w: BattleWorld) {
        let facing = w.player.input.lengthSq > 0 ? w.player.facing : aimDir(w)
        var dirs: [Vec2] = [facing]
        if has("directions") {
            dirs = ring(facing, count: Int(v("directions")))
        } else {
            if has("back") { dirs.append(-facing) }
            if has("sides") { dirs.append(facing.rotated(.pi / 2)); dirs.append(facing.rotated(-.pi / 2)) }
        }
        var width = v("width", 160) * (1 + v("widthPct")) * (has("widthMul") ? v("widthMul") : 1) * w.stats.area
        var range = v("range", 400) * w.stats.area
        if w.hasLegendary("L_tianhe") {
            width *= w.lp("L_tianhe", "widthMul", 3)
            range *= w.lp("L_tianhe", "rangeMul", 2.5)
        }
        for d in dirs {
            shoot(w, from: w.player.pos + d * 20, dir: d, speed: projSpeed(w), radius: v("thickness", 26),
                  range: range, pierce: -1, visual: .slash, halfWidth: width / 2)
        }
    }

    override func didHit(_ w: BattleWorld, enemy: Int, result: HitResult, hit: Hit) {
        // 开天剑气：暴击时追加一次相同伤害
        guard has("critEcho"), result.crit, hit.source == .skill(slot), !result.killed else { return }
        w.damageFixed(enemy, result.damage, element: element, dot: false)
    }
}

/// 飞剑雨（7.5）：向随机敌人从天上落剑。
/// 天外飞仙：每次 15 把，落点留下剑气区。星落：落地后分裂成 4 把小剑（12.5）。
final class FeiJianYuSkill: SkillBase {
    override func update(_ w: BattleWorld, dt: Double) {
        tickCooldown(w, dt: dt, ready: { targetReady(w) }) { fire(w) }
    }

    private func fire(_ w: BattleWorld) {
        let n = count(w)
        let targets = w.randomEnemies(near: w.player.pos, within: w.cfg.balance.targetRange, count: n)
        let r = radius(w)
        for t in targets {
            let p = w.enemies[t].pos + Vec2(w.rng.range(-10, 10), w.rng.range(-10, 10))
            zone(w, .circle(r), at: p, delay: v("delay", 0.3), duration: 0, visual: .strikeMark)
        }
    }

    override func zoneTriggered(_ w: BattleWorld, zone zi: Int) {
        let z = w.zones[zi]
        guard z.tag < SkillBase.followUpTag else { return }
        w.events.append(.skyBolt(pos: z.pos, element: element))
        if has("residue") {
            self.zone(w, .circle(radius(w)), at: z.pos, delay: 0.01, duration: v("residueDuration", 2) * w.stats.duration,
                      visual: .residue, hit: makeHit(w, mult: v("residueMult", 0.3)), tag: SkillBase.followUpTag)
        }
        if w.hasLegendary("L_xingluo") {
            let k = Int(w.lp("L_xingluo", "count", 4))
            for d in ring(Vec2.fromAngle(w.rng.range(0, .pi)), count: k) {
                shoot(w, from: z.pos, dir: d, speed: 600, radius: 8, range: w.lp("L_xingluo", "range", 200),
                      pierce: 1, visual: .sword, hit: makeHit(w, mult: mult * w.lp("L_xingluo", "mult", 0.4)))
            }
        }
    }
}
