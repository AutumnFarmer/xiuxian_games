import Foundation

/// 功法行为（7.4）。每个功法一个文件，继承 SkillBase 并覆盖需要的方法。
protocol SkillBehavior: AnyObject {
    var slot: Int { get set }
    var def: SkillDef { get }
    var level: Int { get set }
    var element: Element { get set }
    /// 已合成的神通（7.8）。
    var evolution: EvolutionDef? { get set }

    func stageStarted(_ w: BattleWorld)
    func update(_ w: BattleWorld, dt: Double)
    /// 本功法的投射物命中敌人。默认按投射物自带的 Hit 结算。
    func projectileHit(_ w: BattleWorld, proj: Int, enemy: Int)
    /// 本功法的投射物飞完或到时消失。
    func projectileExpired(_ w: BattleWorld, proj: Int)
    /// 本功法的区域第一次结算之后。
    func zoneTriggered(_ w: BattleWorld, zone: Int)
    /// 任何玩家阵营命中之后（所有功法都会收到）。
    func didHit(_ w: BattleWorld, enemy: Int, damage: Double, crit: Bool, hit: Hit)
    func enemyKilled(_ w: BattleWorld, _ e: Enemy)
    func playerHurt(_ w: BattleWorld, amount: Double)
    func modifyIncomingDamage(_ w: BattleWorld, _ d: Double) -> Double
    func shieldBroken(_ w: BattleWorld)
    /// 功法自带的属性（比如铁布衫的减伤），会并入玩家属性。
    func statMods(_ w: BattleWorld) -> [StatMod]
    /// 影子复制时是否跳过（召唤、光环，8.8）。
    var copyableByShadow: Bool { get }
}

/// 功法的公共实现：参数、冷却、常驻判断、Hit 构造。
class SkillBase: SkillBehavior {
    var slot: Int
    let def: SkillDef
    var level: Int { didSet { refresh() } }
    var element: Element
    var evolution: EvolutionDef? { didSet { refresh() } }
    /// 当前等级（含神通）的参数。
    private(set) var p: [String: Double] = [:]
    var cooldownLeft = 0.0
    unowned let cfg: GameConfig

    required init(def: SkillDef, slot: Int, level: Int, element: Element, cfg: GameConfig) {
        self.def = def
        self.slot = slot
        self.level = level
        self.element = element
        self.cfg = cfg
        refresh()
    }

    func refresh() {
        var q = def.params(level: level)
        if let ev = evolution {
            for (k, v) in ev.params { q[k, default: 0] += v }
        }
        p = q
        onRefresh()
    }

    /// 参数变化后的回调（比如重建常驻投射物）。
    func onRefresh() {}

    func v(_ k: String, _ d: Double = 0) -> Double { p[k] ?? d }

    var isEvolved: Bool { evolution != nil }

    // MARK: 常用数值（7.4）

    /// 倍率：等级成长；神通 = 5 级倍率 × 1.5（7.8）。
    var mult: Double {
        if isEvolved {
            let f = (try? cfg.evolutionsMultFactor()) ?? 1.5
            return cfg.skills.mult(def, level: cfg.skills.maxLevel) * f
        }
        return cfg.skills.mult(def, level: level)
    }

    func cooldown(_ w: BattleWorld) -> Double {
        let base = max(0.05, def.cooldown + v("cooldownDelta"))
        var c = base * (1 - w.stats.cdr)
        if w.fastCast { c *= 0.5 }
        return max(0.05, c)
    }

    /// 半径类参数：基础值 × (1 + 对应百分比参数) × area。
    func radius(_ w: BattleWorld, _ key: String = "radius") -> Double {
        v(key) * (1 + v(key + "Pct")) * w.stats.area
    }

    func duration(_ w: BattleWorld, _ key: String = "duration") -> Double {
        (v(key) + v(key + "Delta")) * w.stats.duration
    }

    /// 投射物数量：参数 + 玩家的额外投射物（只对投射物标签生效）。
    func count(_ w: BattleWorld, _ key: String = "count") -> Int {
        var n = Int(v(key).rounded())
        if def.has(.projectile) { n += w.stats.projCount }
        return max(1, n)
    }

    func projSpeed(_ w: BattleWorld, _ key: String = "speed") -> Double { v(key) * w.stats.projSpeed }

    /// 持续时间不小于冷却时变成常驻（7.4）。
    func isPermanent(_ w: BattleWorld, durationKey: String = "duration") -> Bool {
        if def.cooldown <= 0 { return true }
        return duration(w, durationKey) >= cooldown(w)
    }

    func makeHit(mult m: Double? = nil, knockback: Double = 0, lifesteal: Double = 0) -> Hit {
        Hit(mult: m ?? mult, element: element, school: def.school, statusChance: def.statusChance,
            knockback: knockback, lifesteal: lifesteal, source: .skill(slot))
    }

    /// 冷却走完、条件满足时释放。返回是否释放。
    @discardableResult
    func tickCooldown(_ w: BattleWorld, dt: Double, ready: () -> Bool, cast: () -> Void) -> Bool {
        if cooldownLeft > 0 { cooldownLeft -= dt }
        guard cooldownLeft <= 0 else { return false }
        guard ready() else { return false }
        cast()
        cooldownLeft = cooldown(w)
        return true
    }

    /// 冷却进度 0（刚放）到 1（就绪），给 HUD。
    func cooldownProgress(_ w: BattleWorld) -> Double {
        let c = cooldown(w)
        guard c > 0, def.cooldown > 0 else { return 1 }
        return 1 - max(0, cooldownLeft) / c
    }

    var displayName: String { evolution?.name ?? def.name }

    // MARK: 默认实现

    func stageStarted(_ w: BattleWorld) { cooldownLeft = min(cooldownLeft, 0.3) }
    func update(_ w: BattleWorld, dt: Double) {}
    func projectileHit(_ w: BattleWorld, proj: Int, enemy: Int) {
        w.damageEnemy(enemy, w.projectiles[proj].hit, from: w.projectiles[proj].pos)
    }
    func projectileExpired(_ w: BattleWorld, proj: Int) {}
    func zoneTriggered(_ w: BattleWorld, zone: Int) {}
    func didHit(_ w: BattleWorld, enemy: Int, damage: Double, crit: Bool, hit: Hit) {}
    func enemyKilled(_ w: BattleWorld, _ e: Enemy) {}
    func playerHurt(_ w: BattleWorld, amount: Double) {}
    func modifyIncomingDamage(_ w: BattleWorld, _ d: Double) -> Double { d }
    func shieldBroken(_ w: BattleWorld) {}
    func statMods(_ w: BattleWorld) -> [StatMod] { [] }
    var copyableByShadow: Bool { !(def.has(.summon) || def.has(.aura)) }

    // MARK: 常用动作

    /// 朝方向发射一枚直线投射物。
    func shoot(_ w: BattleWorld, from p0: Vec2, dir: Vec2, speed: Double, radius r: Double, range: Double,
               pierce: Int, visual: ProjVisual, hit: Hit? = nil, tag: Int = 0, halfWidth: Double = 0) {
        guard w.projectiles.count < w.cfg.balance.caps.projectiles else { return }
        var pr = Projectile(id: w.makeId(), team: .player, motion: .straight, visual: visual, pos: p0,
                            vel: dir.normalized() * speed, radius: r, range: range, pierce: pierce,
                            hit: hit ?? makeHit(), element: element)
        pr.skill = slot
        pr.tag = tag
        pr.halfWidth = halfWidth
        w.projectiles.append(pr)
    }

    /// 生成一个玩家阵营区域。
    @discardableResult
    func zone(_ w: BattleWorld, _ shape: ZoneShape, at p0: Vec2, delay: Double, duration: Double,
              visual: ZoneVisual, hit: Hit? = nil, follow: Bool = false, tag: Int = 0, tick: Double? = nil) -> Int {
        var z = Zone(id: w.makeId(), team: .player, shape: shape, pos: p0, visual: visual, element: element,
                     followPlayer: follow, delay: delay, delayTotal: delay, duration: duration,
                     hit: hit ?? makeHit())
        z.tick = tick ?? w.cfg.balance.areaTick
        z.skill = slot
        z.tag = tag
        w.zones.append(z)
        return w.zones.count - 1
    }

    /// 朝向：有目标时指向最近敌人，没有时用角色朝向。
    func aimDir(_ w: BattleWorld, range: Double) -> Vec2 {
        if let t = w.nearestEnemy(to: w.player.pos, within: range) {
            return (w.enemies[t].pos - w.player.pos).normalized(or: w.player.facing)
        }
        return w.player.facing
    }

    /// 扇形散开的方向（7.4：相邻夹角 10°）。
    func fan(_ dir: Vec2, count n: Int, spacingDeg: Double = 10) -> [Vec2] {
        guard n > 1 else { return [dir] }
        let step = spacingDeg.degToRad
        let start = -step * Double(n - 1) / 2
        return (0..<n).map { dir.rotated(start + step * Double($0)) }
    }
}
