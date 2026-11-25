import Foundation

/// 心魔影子（8.8）。
/// 自定：影子复制的功法统一用"按标签的镜像招式"实现（SkillBase.shadowPattern），
/// 投射物类朝玩家射出同样数量的弹，范围类在玩家脚下或影子周围预警后结算。
/// 这样每个功法都自动支持影子施放，不需要为 24 个功法各写一份影子版本。
final class ShadowController: ShadowControlling {
    struct Copy {
        var pattern: ShadowPattern
        var cooldown: Double
        var timer: Double
        var mult: Double
    }

    private var copies: [Copy] = []
    private var ultTimer: Double
    private var ultInterval: Double
    private var orbitAngle = 0.0
    private let skillDamageBase: Double

    init(_ w: BattleWorld, run: RunState) {
        let hd = w.cfg.heartDemon
        let strength = hd.shadowStrength(run.heartDemon)
        skillDamageBase = w.cfg.enemies.realms[4].atk * w.cfg.balance.enemyScale(tier: run.tier) * hd.shadowSkillDmg * strength * w.setup.enemyAtkMult
        ultInterval = hd.shadowUltInterval
        ultTimer = hd.shadowUltInterval
        for s in w.skills {
            guard let b = s as? SkillBase, b.copyableByShadow else { continue }
            copies.append(Copy(pattern: b.shadowPattern(w), cooldown: max(0.5, b.cooldown(w)),
                               timer: Double(copies.count) * 0.4 + 1, mult: b.mult))
        }
    }

    /// 生成影子（8.8）。
    static func spawn(_ w: BattleWorld, run: RunState) {
        let hd = w.cfg.heartDemon
        let strength = hd.shadowStrength(run.heartDemon)
        let skipped = w.skills.filter { !$0.copyableByShadow }.count
        let hp = w.cfg.enemies.realms[4].bossHp * w.cfg.balance.enemyScale(tier: run.tier) * hd.shadowHpMult * strength
            * (1 + hd.shadowSummonPenalty * Double(skipped)) * w.setup.enemyHpMult
        let e = Enemy(id: w.makeId(), role: .shadow, typeIndex: 0, pos: w.player.pos + Vec2(0, hd.shadowOrbit),
                      radius: 20, speed: w.stats.moveSpeed * hd.shadowSpeedFactor, hp: hp, maxHp: hp,
                      atk: w.cfg.enemies.realms[4].atk * w.cfg.balance.enemyScale(tier: run.tier), element: nil)
        w.enemies.append(e)
        w.aliveEnemies += 1
        w.shadowController = ShadowController(w, run: run)
        w.director.bossSpawned = true
        w.director.bossName = "心魔"
        w.director.introTime = w.cfg.balance.stage.bossIntro
        w.events.append(.bossIntro(name: "心魔"))
    }

    func act(_ w: BattleWorld, _ i: Int, _ rate: Double) {
        let dt = w.dt * rate
        let hd = w.cfg.heartDemon
        // 和玩家保持约 250pt 绕圈移动（8.8）
        orbitAngle += (w.enemies[i].speed / hd.shadowOrbit) * dt
        let goal = w.player.pos + Vec2.fromAngle(orbitAngle, hd.shadowOrbit)
        let d = goal - w.enemies[i].pos
        let step = w.enemies[i].speed * dt
        w.enemies[i].pos += d.length <= step ? d : d.normalized() * step
        let src = w.enemies[i].pos
        let tele = hd.shadowTelegraph
        for k in copies.indices {
            copies[k].timer -= dt
            guard copies[k].timer <= 0 else { continue }
            copies[k].timer = copies[k].cooldown
            let dmg = skillDamageBase * copies[k].mult
            perform(w, copies[k].pattern, from: src, damage: dmg, telegraph: tele, ownerId: w.enemies[i].id)
        }
        ultTimer -= dt
        if ultTimer <= 0 {
            ultTimer = ultInterval
            w.events.append(.banner(text: "心魔·绝学", duration: 0.8))
            for _ in 0..<12 {
                let p = w.player.pos + Vec2.fromAngle(w.rng.range(0, 2 * .pi), w.rng.range(0, 260))
                w.zones.append(w.enemyZone(.circle(90), at: p, telegraph: max(0.6, tele + 0.4), damage: skillDamageBase * 3,
                                           ownerId: w.enemies[i].id))
            }
        }
    }

    private func perform(_ w: BattleWorld, _ p: ShadowPattern, from src: Vec2, damage: Double, telegraph: Double, ownerId: Int) {
        let toP = (w.player.pos - src).normalized(or: .up)
        switch p {
        case .projectiles(let n, let speed, let radius):
            for k in 0..<n {
                let a = (Double(k) - Double(n - 1) / 2) * 10.0.degToRad
                w.shootEnemyProjectile(from: src, dir: toP.rotated(a), speed: speed * 0.6, radius: radius,
                                       damage: damage, visual: .orb, element: nil)
            }
        case .circleAtPlayer(let n, let radius):
            for k in 0..<n {
                let off = k == 0 ? Vec2.zero : Vec2.fromAngle(w.rng.range(0, 2 * .pi), w.rng.range(40, 160))
                w.zones.append(w.enemyZone(.circle(radius), at: w.player.pos + off, telegraph: telegraph, damage: damage, ownerId: ownerId))
            }
        case .circleAtSelf(let radius):
            w.zones.append(w.enemyZone(.circle(radius), at: src, telegraph: telegraph, damage: damage, ownerId: ownerId))
        case .line(let width, let length):
            w.zones.append(w.enemyZone(.rect(width / 2, length, toP), at: src, telegraph: telegraph, damage: damage, ownerId: ownerId))
        }
    }
}

/// 影子施放功法时的镜像招式。
enum ShadowPattern {
    case projectiles(count: Int, speed: Double, radius: Double)
    case circleAtPlayer(count: Int, radius: Double)
    case circleAtSelf(radius: Double)
    case line(width: Double, length: Double)
}

extension SkillBase {
    /// 影子施放这个功法时的招式（8.8）。按标签和参数推出来。
    func shadowPattern(_ w: BattleWorld) -> ShadowPattern {
        if def.has(.projectile) {
            let n = min(8, max(1, count(w)))
            return .projectiles(count: n, speed: max(300, v("speed", 500)), radius: 12)
        }
        if def.has(.target) {
            let n = min(6, max(1, Int(v("count", v("targets", 1)))))
            return .circleAtPlayer(count: n, radius: max(50, min(160, v("radius", 80))))
        }
        if def.has(.area) || def.has(.melee) {
            if v("width") > 0 { return .line(width: min(200, v("width") * 1.2), length: max(300, v("range", 400))) }
            return .circleAtSelf(radius: max(120, min(260, v("radius", 150) * w.stats.area)))
        }
        return .circleAtPlayer(count: 1, radius: 100)
    }
}
