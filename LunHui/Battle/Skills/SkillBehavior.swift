import Foundation

/// 一次命中的结果。
struct HitResult {
    var damage = 0.0
    var crit = false
    var killed = false
}

/// 战斗里的钩子：功法、绝学、本命一击、全局传说特效都实现它。
protocol WorldHook: AnyObject {
    func stageStarted(_ w: BattleWorld)
    func update(_ w: BattleWorld, dt: Double)
    /// 任何玩家阵营命中之后。
    func didHit(_ w: BattleWorld, enemy: Int, result: HitResult, hit: Hit)
    func enemyKilled(_ w: BattleWorld, _ e: Enemy)
    func playerHurt(_ w: BattleWorld, amount: Double)
    func modifyIncomingDamage(_ w: BattleWorld, _ d: Double) -> Double
    func shieldBroken(_ w: BattleWorld)
    func revived(_ w: BattleWorld)
    func ultimateCast(_ w: BattleWorld)
}

/// 钩子的空实现。子类只覆盖需要的方法。
class HookBase: WorldHook {
    func stageStarted(_ w: BattleWorld) {}
    func update(_ w: BattleWorld, dt: Double) {}
    func didHit(_ w: BattleWorld, enemy: Int, result: HitResult, hit: Hit) {}
    func enemyKilled(_ w: BattleWorld, _ e: Enemy) {}
    func playerHurt(_ w: BattleWorld, amount: Double) {}
    func modifyIncomingDamage(_ w: BattleWorld, _ d: Double) -> Double { d }
    func shieldBroken(_ w: BattleWorld) {}
    func revived(_ w: BattleWorld) {}
    func ultimateCast(_ w: BattleWorld) {}
}

/// 功法行为（7.4）。每个功法一个文件，继承 SkillBase。
protocol SkillBehavior: WorldHook {
    var slot: Int { get set }
    var def: SkillDef { get }
    var level: Int { get set }
    var element: Element { get set }
    /// 已合成的神通（7.8）。
    var evolution: EvolutionDef? { get set }
    var displayName: String { get }
    /// 本功法的投射物命中敌人。
    func projectileHit(_ w: BattleWorld, proj: Int, enemy: Int)
    /// 本功法的投射物飞完、到时或穿透用完。
    func projectileExpired(_ w: BattleWorld, proj: Int)
    /// 本功法的区域第一次结算之后。
    func zoneTriggered(_ w: BattleWorld, zone: Int)
    /// 本功法的命中打死了敌人。
    func killedEnemy(_ w: BattleWorld, _ e: Enemy, hit: Hit)
    /// 功法自带的属性（比如铁布衫的减伤），并入玩家属性。
    func statMods(_ w: BattleWorld) -> [StatMod]
    /// 心魔影子是否复制（8.8：召唤和光环不复制）。
    var copyableByShadow: Bool { get }
    func cooldownProgress(_ w: BattleWorld) -> Double
}

/// 功法的公共实现：参数、冷却、常驻判断、Hit 构造。
class SkillBase: HookBase, SkillBehavior {
    var slot: Int
    let def: SkillDef
    var level: Int { didSet { refresh() } }
    var element: Element
    var evolution: EvolutionDef? { didSet { refresh() } }
    /// 当前等级的参数（含神通参数）。
    private(set) var p: [String: Double] = [:]
    var cooldownLeft = 0.0
    unowned let cfg: GameConfig

    required init(def: SkillDef, slot: Int, level: Int, element: Element, cfg: GameConfig) {
        self.def = def
        self.slot = slot
        self.level = level
        self.element = element
        self.cfg = cfg
        super.init()
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

    /// 参数变化后的回调（比如重建常驻物）。
    func onRefresh() {}

    func v(_ k: String, _ d: Double = 0) -> Double { p[k] ?? d }
    func has(_ k: String) -> Bool { (p[k] ?? 0) > 0 }

    var isEvolved: Bool { evolution != nil }
    var displayName: String { evolution?.name ?? def.name }

    // MARK: 常用数值（7.4）

    /// 倍率：等级成长；神通 = 5 级倍率 × 1.5（7.8）。
    var mult: Double {
        if isEvolved { return cfg.skills.mult(def, level: cfg.skills.maxLevel) * cfg.evolutions.multFactor }
        return cfg.skills.mult(def, level: level)
    }

    /// 基础冷却（含等级的冷却变化），没有乘冷却缩减。
    var baseCooldown: Double {
        if v("fixedCooldown") > 0 { return v("fixedCooldown") }
        return max(0.05, def.cooldown + v("cooldownDelta"))
    }

    func cooldown(_ w: BattleWorld) -> Double {
        var c = baseCooldown * (1 - w.stats.cdr)
        if w.fastCast { c *= 0.5 }
        return max(0.05, c)
    }

    /// 半径类参数：基础值 × (1 + 对应 Pct 参数) × Mul 参数 × area。
    func radius(_ w: BattleWorld, _ key: String = "radius") -> Double {
        let mul = p[key + "Mul"].map { $0 > 0 ? $0 : 1 } ?? 1
        return v(key) * (1 + v(key + "Pct")) * mul * w.stats.area * w.areaFactor(def)
    }

    /// 持续时间：(基础 + Delta) × Mul × duration 属性。
    func duration(_ w: BattleWorld, _ key: String = "duration") -> Double {
        let mul = p[key + "Mul"].map { $0 > 0 ? $0 : 1 } ?? 1
        return (v(key) + v(key + "Delta")) * mul * w.stats.duration
    }

    /// 数量：参数（或神通固定值）+ 额外投射物（只对投射物标签生效）。
    func count(_ w: BattleWorld, _ key: String = "count", fixedKey: String = "fixedCount") -> Int {
        if v(fixedKey) > 0 { return Int(v(fixedKey)) + (def.has(.projectile) ? w.stats.projCount : 0) }
        var n = Int(v(key).rounded())
        if v("countMul") > 0 { n *= Int(v("countMul")) }
        if def.has(.projectile) { n += w.stats.projCount }
        return max(1, n)
    }

    func projSpeed(_ w: BattleWorld, _ key: String = "speed") -> Double { v(key) * w.stats.projSpeed }

    /// 穿透：神通可以给无限穿透（−1）。
    func pierce(_ key: String = "pierce") -> Int { has("infinitePierce") ? -1 : Int(v(key)) }

    /// 持续时间不小于冷却时变成常驻（7.4）。
    func isPermanent(_ w: BattleWorld, durationKey: String = "duration") -> Bool {
        if def.cooldown <= 0 || has("permanent") { return true }
        return duration(w, durationKey) >= cooldown(w)
    }

    /// 召唤物攻击间隔（7.4、7.1）。
    func summonInterval(_ w: BattleWorld, _ base: Double) -> Double {
        var t = base * (1 - w.stats.cdr) * (1 + w.summonIntervalPct)
        if w.fastCast { t *= 0.5 }
        return max(0.1, t)
    }

    var statusChance: Double { has("forceStatus") ? 10 : def.statusChance }

    func makeHit(_ w: BattleWorld, mult m: Double? = nil, knockback: Double = 0, lifesteal: Double = 0) -> Hit {
        Hit(mult: m ?? mult, element: element, school: def.school, statusChance: statusChance,
            knockback: knockback, lifesteal: lifesteal, source: .skill(slot))
    }

    /// 冷却走完、条件满足时释放（7.4）。
    @discardableResult
    func tickCooldown(_ w: BattleWorld, dt: Double, ready: () -> Bool, cast: () -> Void) -> Bool {
        if cooldownLeft > 0 { cooldownLeft -= dt }
        guard cooldownLeft <= 0, ready() else { return false }
        cast()
        cooldownLeft = cooldown(w)
        return true
    }

    /// 索敌（600pt）。
    func targetReady(_ w: BattleWorld) -> Bool { w.hasEnemy(within: w.cfg.balance.targetRange) }
    /// 近战（200pt）。
    func meleeReady(_ w: BattleWorld) -> Bool { w.hasEnemy(within: w.cfg.balance.meleeRange) }

    func cooldownProgress(_ w: BattleWorld) -> Double {
        guard def.cooldown > 0 else { return 1 }
        let c = cooldown(w)
        return c > 0 ? 1 - max(0, cooldownLeft) / c : 1
    }

    // MARK: 默认实现

    override func stageStarted(_ w: BattleWorld) { cooldownLeft = min(cooldownLeft, 0.3) }

    func projectileHit(_ w: BattleWorld, proj: Int, enemy: Int) {
        w.damageEnemy(enemy, w.projectiles[proj].hit, from: w.projectiles[proj].pos)
    }
    func projectileExpired(_ w: BattleWorld, proj: Int) {}
    func zoneTriggered(_ w: BattleWorld, zone: Int) {}
    func killedEnemy(_ w: BattleWorld, _ e: Enemy, hit: Hit) {}
    func statMods(_ w: BattleWorld) -> [StatMod] { [] }
    var copyableByShadow: Bool { !(def.has(.summon) || def.has(.aura)) }

    // MARK: 常用动作

    /// 发射一枚直线投射物。返回它在数组里的下标。
    @discardableResult
    func shoot(_ w: BattleWorld, from p0: Vec2, dir: Vec2, speed: Double, radius r: Double, range: Double,
               pierce: Int, visual: ProjVisual, hit: Hit? = nil, tag: Int = 0, halfWidth: Double = 0) -> Int? {
        guard w.projectiles.count < w.cfg.balance.caps.projectiles else { return nil }
        var pr = Projectile(id: w.makeId(), team: .player, motion: .straight, visual: visual, pos: p0,
                            vel: dir.normalized() * speed, radius: r, range: range, pierce: pierce,
                            hit: hit ?? makeHit(w), element: element)
        pr.skill = slot
        pr.tag = tag
        pr.halfWidth = halfWidth
        w.projectiles.append(pr)
        return w.projectiles.count - 1
    }

    /// 生成一个绕玩家旋转的投射物。
    @discardableResult
    func orbit(_ w: BattleWorld, angle: Double, radius orbitR: Double, period: Double, size: Double,
               life: Double, visual: ProjVisual, hit: Hit? = nil, tag: Int = 0) -> Int? {
        guard w.projectiles.count < w.cfg.balance.caps.projectiles else { return nil }
        var pr = Projectile(id: w.makeId(), team: .player, motion: .orbit, visual: visual,
                            pos: w.player.pos + Vec2.fromAngle(angle, orbitR), vel: .zero, radius: size,
                            range: .infinity, life: life, pierce: -1, hit: hit ?? makeHit(w), element: element)
        pr.skill = slot
        pr.tag = tag
        pr.orbitAngle = angle
        pr.orbitRadius = orbitR
        pr.orbitSpeed = 2 * .pi / max(0.1, period)
        w.projectiles.append(pr)
        return w.projectiles.count - 1
    }

    /// 生成一个玩家阵营区域，返回它的 id。
    @discardableResult
    func zone(_ w: BattleWorld, _ shape: ZoneShape, at p0: Vec2, delay: Double, duration d: Double,
              visual: ZoneVisual, hit: Hit? = nil, follow: Bool = false, tag: Int = 0, tick: Double? = nil) -> Int {
        guard w.zones.count < w.cfg.balance.caps.zones else { return -1 }
        var z = Zone(id: w.makeId(), team: .player, shape: shape, pos: p0, visual: visual, element: element,
                     followPlayer: follow, delay: delay, delayTotal: delay, duration: d, hit: hit ?? makeHit(w))
        z.tick = tick ?? w.cfg.balance.areaTick
        z.skill = slot
        z.tag = tag
        w.zones.append(z)
        return z.id
    }

    /// 立即对一个形状内的敌人结算一次，并通知表现层。
    @discardableResult
    func strike(_ w: BattleWorld, _ shape: ZoneShape, at p0: Vec2, hit: Hit? = nil) -> [HitResult] {
        let h = hit ?? makeHit(w)
        return w.enemiesIn(shape, at: p0).map { w.damageEnemy($0, h, from: p0) }
    }

    /// 指向最近敌人的方向，没有敌人时用角色朝向。
    func aimDir(_ w: BattleWorld, range: Double? = nil) -> Vec2 {
        if let t = w.nearestEnemy(to: w.player.pos, within: range ?? w.cfg.balance.targetRange) {
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

    /// 均匀分布在一圈上的方向。
    func ring(_ dir: Vec2, count n: Int) -> [Vec2] {
        (0..<max(1, n)).map { dir.rotated(Double($0) * 2 * .pi / Double(max(1, n))) }
    }

    /// 本功法当前的召唤物下标。
    func mySummons(_ w: BattleWorld) -> [Int] {
        w.summons.indices.filter { w.summons[$0].skill == slot && !w.summons[$0].dead }
    }

    /// 本功法的常驻投射物下标。
    func myOrbits(_ w: BattleWorld) -> [Int] {
        w.projectiles.indices.filter { w.projectiles[$0].skill == slot && w.projectiles[$0].motion == .orbit && !w.projectiles[$0].dead }
    }

    /// 由区域派生出来的区域（残留区等）带这个 tag，不会再回调 zoneTriggered，防止无限生成。
    static let followUpTag = 100

    func zoneIndex(_ w: BattleWorld, id: Int) -> Int? {
        w.zones.firstIndex { $0.id == id && !$0.dead }
    }
}
