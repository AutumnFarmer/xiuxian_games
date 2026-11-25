import Foundation

/// 御剑术（7.5）：向最近敌人射出飞剑。
/// 神通万剑诀：数量 ×2，无限穿透，飞到最远处后折返再打一次。
/// 传说青萍：飞剑改为绕身旋转，数量 ×2，常驻（12.5）。
final class YuJianSkill: SkillBase {
    private var orbitBuiltFor = -1

    override func update(_ w: BattleWorld, dt: Double) {
        if w.hasLegendary("L_qingping") {
            updateOrbit(w, dt: dt)
            return
        }
        let range = v("range", 650)
        tickCooldown(w, dt: dt, ready: { w.hasEnemy(within: range) }) {
            fire(w)
        }
    }

    private var swordCount: Int {
        Int(v("count", 1).rounded()) * (isEvolved ? Int(v("countMul", 2)) : 1)
    }

    private func fire(_ w: BattleWorld) {
        let range = v("range", 650)
        var n = swordCount + w.stats.projCount
        n = max(1, n)
        let targets = w.nearestEnemies(to: w.player.pos, within: range, count: n)
        guard !targets.isEmpty else { return }
        let pierce = isEvolved ? -1 : Int(v("pierce", 1))
        let speed = projSpeed(w)
        let r = v("radius", 10) * w.stats.area
        // 目标够多时每把剑打不同的敌人，不够时朝最近的敌人扇形散开（7.4）。
        if targets.count >= n {
            for t in targets {
                let dir = (w.enemies[t].pos - w.player.pos).normalized(or: w.player.facing)
                shoot(w, from: w.player.pos, dir: dir, speed: speed, radius: r, range: range, pierce: pierce, visual: .sword)
            }
        } else {
            let dir = (w.enemies[targets[0]].pos - w.player.pos).normalized(or: w.player.facing)
            for d in fan(dir, count: n) {
                shoot(w, from: w.player.pos, dir: d, speed: speed, radius: r, range: range, pierce: pierce, visual: .sword)
            }
        }
    }

    override func projectileExpired(_ w: BattleWorld, proj: Int) {
        // 万剑诀：飞到最远处后折返（tag 0 → 1）。
        guard isEvolved, v("returns") > 0 else { return }
        let pr = w.projectiles[proj]
        guard pr.tag == 0, pr.motion == .straight, pr.range <= 0 else { return }
        var back = pr
        back.id = w.makeId()
        back.dead = false
        back.tag = 1
        back.vel = -pr.vel
        back.range = v("range", 650)
        back.hits = []
        back.hitTimes = []
        w.projectiles.append(back)
    }

    // MARK: 青萍

    private func updateOrbit(_ w: BattleWorld, dt: Double) {
        let n = max(1, (swordCount + w.stats.projCount) * 2)
        let alive = w.projectiles.indices.filter { w.projectiles[$0].skill == slot && w.projectiles[$0].motion == .orbit && !w.projectiles[$0].dead }
        if alive.count != n || orbitBuiltFor != n {
            for i in alive { w.projectiles[i].dead = true }
            let radius = (w.legendaryParam("L_qingping", "radius") ?? 120) * w.stats.area
            for k in 0..<n {
                var pr = Projectile(id: w.makeId(), team: .player, motion: .orbit, visual: .sword, pos: w.player.pos,
                                    vel: .zero, radius: v("radius", 10) * w.stats.area * 1.4, range: .infinity,
                                    life: .infinity, pierce: -1, hit: makeHit(), element: element)
                pr.skill = slot
                pr.orbitRadius = radius
                pr.orbitAngle = Double(k) * 2 * .pi / Double(n)
                pr.orbitSpeed = 2 * .pi / 1.2
                w.projectiles.append(pr)
            }
            orbitBuiltFor = n
        }
    }

    override func stageStarted(_ w: BattleWorld) {
        super.stageStarted(w)
        orbitBuiltFor = -1
    }
}
