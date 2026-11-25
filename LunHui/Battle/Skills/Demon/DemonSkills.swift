import Foundation

/// 噬魂爪（7.5）：爪击，本功法吸血。
/// 天魔爪：360°，连抓 3 次，暴击时本次吸血 ×2。吞噬：每击杀 1 个敌人本关攻击 +0.2%，最多 +50%（12.5）。
final class ShiHunSkill: SkillBase {
    private var pending = 0
    private var gapTimer = 0.0
    private var devour = 0.0

    override func update(_ w: BattleWorld, dt: Double) {
        if pending > 0 {
            gapTimer -= dt
            if gapTimer <= 0 { claw(w) }
        }
        tickCooldown(w, dt: dt, ready: { meleeReady(w) }) {
            pending = has("fixedHits") ? Int(v("fixedHits")) : Int(v("hits", 1))
            claw(w)
        }
        w.tempAtkPct += devour
    }

    private func claw(_ w: BattleWorld) {
        pending -= 1
        gapTimer = 0.12
        let dir = aimDir(w, range: w.cfg.balance.meleeRange)
        let r = radius(w)
        let full = has("fullCircle") || v("angle", 90) >= 360
        let half = full ? Double.pi : v("angle", 90).degToRad / 2
        w.events.append(.slash(pos: w.player.pos, dir: dir, radius: r, angle: half * 2, element: element))
        let ls = v("lifesteal", 0.05)
        for i in w.enemiesIn(.cone(r, half, dir), at: w.player.pos) {
            let res = w.damageEnemy(i, makeHit(w, lifesteal: ls), from: w.player.pos)
            if res.crit, has("critLifesteal") { w.lifestealHeal(res.damage * ls * (v("critLifesteal") - 1)) }
        }
    }

    override func enemyKilled(_ w: BattleWorld, _ e: Enemy) {
        guard w.hasLegendary("L_tunshi") else { return }
        devour = min(w.lp("L_tunshi", "cap", 0.5), devour + w.lp("L_tunshi", "per", 0.002))
    }

    override func stageStarted(_ w: BattleWorld) {
        super.stageStarted(w)
        devour = 0
        pending = 0
    }
}

/// 血河（7.5）：身后留下血河。
/// 血海：宽度和持续 ×2，站上去回血 3%。血脉：变成跟随的血环，常驻（12.5）。
final class XueHeSkill: SkillBase {
    private var activeLeft = 0.0
    private var lastDrop = Vec2(1e9, 1e9)
    private var ringId = -1

    override func update(_ w: BattleWorld, dt: Double) {
        let width = v("width", 60) * (1 + v("widthPct")) * (has("widthMul") ? v("widthMul") : 1) * w.stats.area
        if w.hasLegendary("L_xuemai") {
            let r = w.lp("L_xuemai", "radius", 140) * w.stats.area * (isEvolved ? 1.5 : 1)
            if let z = zoneIndex(w, id: ringId) { w.zones[z].shape = .circle(r) } else {
                ringId = zone(w, .circle(r), at: w.player.pos, delay: 0.01, duration: .infinity, visual: .blood, follow: true)
            }
            standBonus(w, onRiver: true)
            return
        }
        let life = duration(w)
        if isPermanent(w) {
            activeLeft = .infinity
        } else {
            if activeLeft > 0 { activeLeft -= dt }
            if activeLeft <= 0 {
                tickCooldown(w, dt: dt, ready: { true }) { activeLeft = life }
                if activeLeft <= 0 {
                    standBonus(w, onRiver: onRiver(w))
                    return
                }
            }
        }
        // 沿着走过的路径每隔一段放一块血河
        if w.player.pos.dist(lastDrop) >= v("spacing", 24) {
            lastDrop = w.player.pos
            zone(w, .circle(width / 2), at: w.player.pos, delay: 0.01, duration: life, visual: .blood)
        }
        standBonus(w, onRiver: onRiver(w))
    }

    private func onRiver(_ w: BattleWorld) -> Bool {
        w.zones.contains { $0.skill == slot && !$0.dead && w.zoneContains($0, point: w.player.pos, radius: 0) }
    }

    private func standBonus(_ w: BattleWorld, onRiver: Bool) {
        guard onRiver else { return }
        w.tempDmgPct += v("standBonus")
        if has("standRegen") { w.heal(w.stats.hp * v("standRegen") * w.dt, show: false) }
    }

    override func stageStarted(_ w: BattleWorld) {
        super.stageStarted(w)
        ringId = -1
        activeLeft = 0
        lastDrop = Vec2(1e9, 1e9)
    }
}

/// 魔焰（7.5）：魔焰命中后分裂。
/// 九幽魔焰：分裂 3 代，每一代必定施加状态。魔种：命中留下魔种，敌人死亡时分裂成 5 团（12.5）。
final class MoHuoSkill: SkillBase {
    private var seeded: Set<Int> = []

    override func update(_ w: BattleWorld, dt: Double) {
        tickCooldown(w, dt: dt, ready: { w.hasEnemy(within: v("range", 650)) }) {
            let n = count(w)
            let targets = w.nearestEnemies(to: w.player.pos, within: v("range", 650), count: n)
            guard !targets.isEmpty else { return }
            let dirs: [Vec2] = targets.count >= n
                ? targets.map { (w.enemies[$0].pos - w.player.pos).normalized() }
                : fan((w.enemies[targets[0]].pos - w.player.pos).normalized(), count: n)
            for d in dirs {
                shoot(w, from: w.player.pos, dir: d, speed: projSpeed(w), radius: v("radius", 12), range: v("range", 650),
                      pierce: 0, visual: .flame, tag: 0)
            }
        }
    }

    private var maxGeneration: Int {
        if has("generations") { return Int(v("generations")) }
        return has("splitTwice") ? 2 : 1
    }

    override func projectileHit(_ w: BattleWorld, proj: Int, enemy: Int) {
        let pr = w.projectiles[proj]
        w.damageEnemy(enemy, pr.hit, from: pr.pos)
        if w.hasLegendary("L_mozhong"), enemy < w.enemies.count { seeded.insert(w.enemies[enemy].id) }
        guard pr.tag < maxGeneration else { return }
        split(w, at: pr.pos, generation: pr.tag + 1, count: Int(v("split", 3)), exclude: enemy < w.enemies.count ? w.enemies[enemy].id : -1)
    }

    private func split(_ w: BattleWorld, at p: Vec2, generation g: Int, count n: Int, exclude: Int) {
        let m = mult * pow(v("splitMult", 0.3), Double(g))
        let base = Vec2.fromAngle(w.rng.range(0, 2 * .pi))
        for d in ring(base, count: n) {
            if let k = shoot(w, from: p + d * 6, dir: d, speed: v("splitSpeed", 360) * w.stats.projSpeed, radius: v("radius", 12) * 0.7,
                             range: v("splitRange", 220), pierce: 0, visual: .flame, hit: makeHit(w, mult: m), tag: g) {
                w.projectiles[k].hits = [exclude]
                w.projectiles[k].hitTimes = [w.time]
            }
        }
    }

    override func enemyKilled(_ w: BattleWorld, _ e: Enemy) {
        guard seeded.remove(e.id) != nil, w.hasLegendary("L_mozhong") else { return }
        split(w, at: e.pos, generation: 1, count: Int(w.lp("L_mozhong", "count", 5)), exclude: e.id)
    }

    override func stageStarted(_ w: BattleWorld) {
        super.stageStarted(w)
        seeded.removeAll()
    }
}

/// 心魔斩（7.5）：360° 斩击，心魔越高越强。
/// 心魔噬天：半径 ×1.3，每次斩击心魔值 +1，每关最多 +10。斩魔：每 10 点心魔值倍率 +25%（12.5）。
final class XinMoZhanSkill: SkillBase {
    private var second = 0.0

    override func update(_ w: BattleWorld, dt: Double) {
        if second > 0 {
            second -= dt
            if second <= 0 { slash(w) }
        }
        tickCooldown(w, dt: dt, ready: { w.hasEnemy(within: radius(w) + 30) }) {
            slash(w)
            if v("doubleAt") > 0, w.heartDemon >= Int(v("doubleAt")) { second = 0.25 }
        }
    }

    private func slash(_ w: BattleWorld) {
        let per10 = w.hasLegendary("L_zhanmo") ? w.lp("L_zhanmo", "per10", 0.25) : v("demonPer10", 0.1)
        let m = mult * (1 + per10 * Double(w.heartDemon / 10))
        let r = radius(w)
        w.events.append(.nova(pos: w.player.pos, radius: r, element: element))
        strike(w, .circle(r), at: w.player.pos, hit: makeHit(w, mult: m))
        if has("demonPerSlash"), w.stageDemonGained < Int(v("demonCapPerStage", 10)) {
            w.stageDemonGained += 1
            w.addHeartDemon(Int(v("demonPerSlash")))
        }
    }
}
