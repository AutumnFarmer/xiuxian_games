import Foundation

/// 御剑术（7.5）：向最近敌人射出飞剑。
/// 神通万剑诀：数量 ×2，无限穿透，飞到最远处后折返再打一次。
/// 传说青萍：飞剑改为绕身旋转，数量 ×2，常驻（12.5）。
final class YuJianSkill: SkillBase {
    private var orbitCount = -1

    override func update(_ w: BattleWorld, dt: Double) {
        if w.hasLegendary("L_qingping") {
            updateOrbit(w, dt: dt)
            return
        }
        clearOrbits(w)
        tickCooldown(w, dt: dt, ready: { w.hasEnemy(within: v("range", 650)) }) { fire(w) }
    }

    private func fire(_ w: BattleWorld) {
        let range = v("range", 650)
        let n = count(w)
        let targets = w.nearestEnemies(to: w.player.pos, within: range, count: n)
        guard !targets.isEmpty else { return }
        let speed = projSpeed(w)
        let r = v("radius", 10) * w.stats.area
        // 目标够多时每把剑打不同的敌人，不够时朝最近的敌人扇形散开（7.4）。
        let dirs: [Vec2]
        if targets.count >= n {
            dirs = targets.map { (w.enemies[$0].pos - w.player.pos).normalized(or: w.player.facing) }
        } else {
            dirs = fan((w.enemies[targets[0]].pos - w.player.pos).normalized(or: w.player.facing), count: n)
        }
        for d in dirs {
            shoot(w, from: w.player.pos, dir: d, speed: speed, radius: r, range: range, pierce: pierce(), visual: .sword)
        }
    }

    override func projectileExpired(_ w: BattleWorld, proj: Int) {
        // 万剑诀：飞到最远处后折返（tag 0 → 1）。
        guard has("returns") else { return }
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
        let n = max(2, count(w) * 2)
        let alive = myOrbits(w)
        guard alive.count != n || orbitCount != n else { return }
        for i in alive { w.projectiles[i].dead = true }
        let radius = w.lp("L_qingping", "radius", 120) * w.stats.area
        for k in 0..<n {
            orbit(w, angle: Double(k) * 2 * .pi / Double(n), radius: radius, period: 1.2,
                  size: v("radius", 10) * w.stats.area * 1.4, life: .infinity, visual: .sword)
        }
        orbitCount = n
    }

    private func clearOrbits(_ w: BattleWorld) {
        guard orbitCount >= 0 else { return }
        for i in myOrbits(w) { w.projectiles[i].dead = true }
        orbitCount = -1
    }

    override func stageStarted(_ w: BattleWorld) {
        super.stageStarted(w)
        orbitCount = -1
    }
}
