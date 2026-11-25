import Foundation

/// 玩家在战斗中的实时状态。
struct PlayerState {
    var pos = Vec2.zero
    var facing = Vec2.up
    /// 摇杆输入，长度 0 或 1。
    var input = Vec2.zero
    var radius = 16.0
    var hp = 1000.0
    /// 受击无敌（5.6）和复活无敌（4.4）。
    var invuln = 0.0
    /// 技能带来的无敌（蛮牛冲、绝学）。
    var skillInvuln = 0.0
    var shield = 0.0
    var shieldMax = 0.0
    var knock = Vec2.zero
    var knockTime = 0.0
    /// 吸血预算：每秒最多回复最大生命的 10%（5.2）。
    var lifestealBudget = 0.0
    var lifestealTimer = 0.0
    /// 被蛛网减速（8.6），每步重新计算。
    var webSlow = 0.0
    /// 冲刺：剩余时间和速度。
    var dashTime = 0.0
    var dashVel = Vec2.zero
}

/// 一关的战斗模拟。纯 Swift，不依赖 SpriteKit，可以在命令行测试。
/// 表现层（BattleScene）每帧读这里的数组画出来，并消费 events。
final class BattleWorld {
    let cfg: GameConfig
    let dt = 1.0 / 60.0

    private(set) var setup: StageSetup
    /// 可见区域大小（pt），由表现层设置，用于屏幕外刷怪。
    var viewSize = Vec2(430, 932)

    // MARK: 实体
    var player = PlayerState()
    private(set) var stats = PlayerStats()
    var enemies: [Enemy] = []
    var projectiles: [Projectile] = []
    var zones: [Zone] = []
    var summons: [Summon] = []
    var drops: [Drop] = []
    var events: [BattleEvent] = []
    var skills: [SkillBehavior] = []
    /// 功法以外的钩子：绝学、本命一击、全局传说特效。
    var hooks: [WorldHook] = []
    let grid = SpatialGrid(cell: 64)
    var gridScratch: [Int32] = []
    private var nextId = 1

    // MARK: 本世上下文
    var lingGen: LingGen
    var school: School
    var tier: Int { setup.tier }
    var realm: Int { setup.realm }
    var rng: SeededRandom
    var lootRng: SeededRandom
    /// 不含等级系数的属性来源合计（5.3）。由 RunController 设置。
    var baseBlock = StatBlock() { didSet { recomputeStats() } }
    var benmingMult = 1.0 { didSet { recomputeStats() } }
    var counterMultValue = 1.3
    var generateBonusValue = 0.3
    /// 秘境词缀的元素伤害系数（9.3），默认 1。
    var affixElemMult = [Double](repeating: 1, count: 7)
    var shockMult = 1.0
    var shatterMult = 1.0
    /// 心魔值（第 10 章）。
    var heartDemon = 0
    var heartDemonGain = 1.0
    /// 魔修：每 10 点心魔值的全伤害加成。
    var dmgPctPer10Demon = 0.0
    /// 其他临时全伤害加成（血河站立等），每步由技能重新设置。
    var tempDmgPct = 0.0
    /// 天魔解体等全局伤害倍数。
    var globalDmgMult = 1.0

    // MARK: 进度
    var level = 1
    var exp = 0.0
    var pendingLevelUps = 0
    var revivesLeft = 1
    var ultCharge = 0.0
    var kills = 0
    var bestHit = 0.0
    var stageLingShi = 0.0
    /// 本关拾取的法宝（M4 接入），表现层只读。
    var stageItemCount = 0
    /// 掉落钩子：(品质下限, 来源) -> (品质序号, 名称)。M4 之前为空。
    var rollItem: ((inout SeededRandom, ItemDropSource, Int) -> ItemDropInfo?)?
    var onItemPicked: ((Int) -> Void)?
    /// 修为加成：秘境词缀和心魔区间（9.3、10.2），加在 expPct 上。
    var expBonus = 0.0
    /// 法宝掉落数量加成（12.3）。
    var dropBonus = 0.0
    /// 福星高照：法宝掉率再 ×1.5（9.3）。
    var dropFactor = 1.0
    /// 灵石加成：挑战类词缀收益和心魔区间（12.3），加在 lingShiPct 上。
    var lingShiBonus = 0.0
    /// 已装备的传说特效：id → 参数（12.5）。
    var legendaries: [String: [String: Double]] = [:]
    /// 持续型绝学生效期间，真元不增长（7.3）。
    var ultLocked = false
    /// 天魔解体：冷却和攻击间隔减半（7.3）。
    var fastCast = false
    /// 心魔影子的行为（8.8）。
    var shadowController: ShadowControlling?
    /// 御兽：召唤物攻击间隔变化和数量加成（7.1）。
    var summonIntervalPct = 0.0
    var summonCountBonus = 0
    /// 临时攻击%加成（吞噬），每步由技能重新设置。
    var tempAtkPct = 0.0
    /// 法天象地：体修功法倍率 ×3、范围 ×1.5（7.3）。
    var bodyForm = false
    /// 百兽朝宗：召唤物伤害 ×2（7.3）。
    var summonDmgMult = 1.0
    /// 五行轮转：所有功法改为这个元素（12.5）。
    var elementOverride: Element?
    /// 绝学和本命一击的元素（6.5），由 RunController 设置。
    var ultElement: Element = .fire
    /// 防止连锁伤害无限递归（连爆、魔种等）。
    var hitDepth = 0
    /// 每关已经给过的心魔值（心魔噬天每关最多 +10）。
    var stageDemonGained = 0
    /// 心魔值变化回调（RunController 用来重算心魔区间）。
    var onHeartDemonChanged: (() -> Void)?
    /// 挑战类秘境词缀的收益（9.3）。
    var challengeReward = 0.0
    var challengeExp = 0.0
    /// 心魔区间和劫数带来的寻宝加成（10.2、11.4）。
    var magicFindBonus = 0.0
    /// 全局传说特效带来的全伤害加成和伤害倍数（五行轮转、杀戮、不死）。
    var hookDmgPct = 0.0
    var hookDmgMult = 1.0
    /// 场上活着的敌人数量（3.3 的上限用）。
    var aliveEnemies = 0

    // MARK: 关卡
    private(set) var time = 0.0
    var phase: StagePhase = .fighting
    var director = StageDirector()

    init(cfg: GameConfig, setup: StageSetup, lingGen: LingGen, school: School, seed: UInt64) {
        self.cfg = cfg
        self.setup = setup
        self.lingGen = lingGen
        self.school = school
        var r = SeededRandom(seed: seed)
        self.rng = r.split()
        self.lootRng = r.split()
        counterMultValue = lingGen.counterMult(cfg)
        generateBonusValue = lingGen.generateBonus(cfg)
        recomputeStats()
        player.hp = stats.hp
    }

    func makeId() -> Int {
        nextId += 1
        return nextId
    }

    // MARK: 属性

    func recomputeStats() {
        let old = stats.hp
        stats = PlayerStats.finalize(baseBlock, cfg: cfg.stats,
                                     levelFactor: cfg.balance.levelFactor(level: level),
                                     benmingMult: benmingMult)
        // 最大生命变高时，当前生命同步加上差值。
        if stats.hp > old, old > 0 { player.hp += stats.hp - old }
        player.hp = min(player.hp, stats.hp)
    }

    var demonDmgPct: Double { dmgPctPer10Demon * Double(heartDemon / 10) }

    // MARK: 开始一关

    /// 开始新的一关：清空场上，保留玩家、功法、召唤物。
    func startStage(_ s: StageSetup) {
        setup = s
        time = 0
        phase = .fighting
        enemies.removeAll(keepingCapacity: true)
        projectiles.removeAll(keepingCapacity: true)
        zones.removeAll(keepingCapacity: true)
        drops.removeAll(keepingCapacity: true)
        stageLingShi = 0
        stageItemCount = 0
        director = StageDirector()
        player.pos = .zero
        player.knockTime = 0
        player.dashTime = 0
        for i in summons.indices { summons[i].pos = player.pos + Vec2.fromAngle(Double(i), 40) }
        // 4.3：普通关回 50%，劫关和最终关回满。
        switch s.kind {
        case .normal:
            player.hp = min(stats.hp, player.hp + stats.hp * cfg.balance.stage.normalHeal)
        case .boss, .tribulation, .shadow:
            player.hp = stats.hp
            ultCharge = cfg.balance.ult.max
        }
        stageDemonGained = 0
        for sk in skills { sk.stageStarted(self) }
        for h in hooks { h.stageStarted(self) }
    }

    // MARK: 主循环

    /// 固定步长推进一步（1/60 秒）。
    func step() {
        time += dt
        tempDmgPct = 0
        tempAtkPct = 0
        updatePlayer()
        if phase == .fighting { updateDirector() }
        rebuildGrid()
        if phase == .fighting || phase == .clearing {
            for sk in skills { sk.update(self, dt: dt) }
            for h in hooks { h.update(self, dt: dt) }
        }
        updateSummons()
        updateProjectiles()
        updateZones()
        updateEnemies()
        updateDrops()
        updatePhase()
        cleanup()
    }

    private func rebuildGrid() {
        grid.clear()
        for i in enemies.indices where !enemies[i].dead {
            grid.insert(i, at: enemies[i].pos)
        }
    }

    private func cleanup() {
        if enemies.contains(where: { $0.dead }) { enemies.removeAll { $0.dead } }
        if projectiles.contains(where: { $0.dead }) { projectiles.removeAll { $0.dead } }
        if zones.contains(where: { $0.dead }) { zones.removeAll { $0.dead } }
        if summons.contains(where: { $0.dead }) { summons.removeAll { $0.dead } }
        if drops.contains(where: { $0.dead }) { drops.removeAll { $0.dead } }
    }

    // MARK: 玩家

    var playerInvulnerable: Bool {
        player.invuln > 0 || player.skillInvuln > 0 || phase != .fighting || director.introTime > 0
    }

    private func updatePlayer() {
        let p = player
        if player.invuln > 0 { player.invuln -= dt }
        if player.skillInvuln > 0 { player.skillInvuln -= dt }
        player.lifestealTimer += dt
        if player.lifestealTimer >= 1 {
            player.lifestealTimer -= 1
            player.lifestealBudget = 0
        }
        if stats.regen > 0, phase == .fighting {
            heal(stats.hp * stats.regen * dt, show: false)
        }
        // 蛛网减速
        var web = 0.0
        for z in zones where z.team == .enemy && z.slowPlayer > 0 && z.triggered && !z.dead {
            if zoneContains(z, point: p.pos, radius: p.radius) { web = max(web, z.slowPlayer) }
        }
        player.webSlow = web
        if player.dashTime > 0 {
            player.dashTime -= dt
            player.pos += player.dashVel * dt
        } else if player.knockTime > 0 {
            let f = player.knockTime / cfg.balance.knockbackTime
            player.pos += player.knock * f * dt
            player.knockTime -= dt
        } else if p.input.lengthSq > 0 {
            let speed = stats.moveSpeed * (1 - web)
            player.pos += p.input * speed * dt
            player.facing = p.input.normalized(or: p.facing)
        }
    }

    func heal(_ amount: Double, show: Bool = true) {
        guard amount > 0, player.hp > 0 else { return }
        let before = player.hp
        player.hp = min(stats.hp, player.hp + amount)
        if show, player.hp - before >= 1 { events.append(.playerHealed(amount: player.hp - before)) }
    }

    func knockPlayer(from src: Vec2, distance: Double) {
        let dir = (player.pos - src).normalized(or: -player.facing)
        player.knock = dir * (2 * distance / cfg.balance.knockbackTime)
        player.knockTime = cfg.balance.knockbackTime
    }

    /// 敌人阵营对玩家造成伤害（5.6）。
    func hurtPlayer(_ raw: Double) {
        guard raw > 0, !playerInvulnerable, player.hp > 0 else { return }
        var d = raw * (1 - stats.dmgReduce)
        for sk in skills { d = sk.modifyIncomingDamage(self, d) }
        for h in hooks { d = h.modifyIncomingDamage(self, d) }
        if player.shield > 0 {
            let absorbed = min(player.shield, d)
            player.shield -= absorbed
            d -= absorbed
            if player.shield <= 0 {
                player.shield = 0
                for sk in skills { sk.shieldBroken(self) }
                for h in hooks { h.shieldBroken(self) }
            }
        }
        player.invuln = cfg.balance.hitInvuln
        guard d > 0 else { return }
        player.hp -= d
        events.append(.playerHurt(amount: d))
        for sk in skills { sk.playerHurt(self, amount: d) }
        for h in hooks { h.playerHurt(self, amount: d) }
        if player.hp <= 0 { playerDied() }
    }

    private func playerDied() {
        if revivesLeft > 0 {
            revivesLeft -= 1
            player.hp = stats.hp
            player.invuln = cfg.balance.revive.invuln
            director.revivedThisWave = true
            let r2 = cfg.balance.revive.radius * cfg.balance.revive.radius
            for i in enemies.indices where !enemies[i].dead && enemies[i].role == .minion {
                if enemies[i].pos.distSq(player.pos) <= r2 { killEnemy(i) }
            }
            events.append(.revive)
            for sk in skills { sk.revived(self) }
            for h in hooks { h.revived(self) }
            events.append(.nova(pos: player.pos, radius: cfg.balance.revive.radius, element: nil))
            events.append(.shake(2))
            events.append(.haptic(2))
        } else {
            player.hp = 0
            phase = .dead
        }
    }

    // MARK: 修为

    func gainExp(_ amount: Double) {
        exp += amount * (1 + stats.expPct + expBonus)
        var need = cfg.balance.expNeed(level: level)
        while exp >= need {
            exp -= need
            level += 1
            pendingLevelUps += 1
            recomputeStats()
            levelWave()
            events.append(.levelUp(level: level))
            need = cfg.balance.expNeed(level: level)
        }
    }

    private func levelWave() {
        let w = cfg.balance.levelWave
        let hit = Hit(mult: w.mult, element: nil, school: nil, statusChance: 0, knockback: w.knockback, source: .levelWave)
        damageCircle(center: player.pos, radius: w.radius, hit: hit)
        events.append(.nova(pos: player.pos, radius: w.radius, element: nil))
    }

    // MARK: 查询

    func nearestEnemy(to p: Vec2, within r: Double, excluding: Int = -1) -> Int? {
        var best = -1
        var bestD = r * r
        for i in enemies.indices where !enemies[i].dead && enemies[i].id != excluding {
            let d = enemies[i].pos.distSq(p)
            if d <= bestD {
                bestD = d
                best = i
            }
        }
        return best >= 0 ? best : nil
    }

    /// 最近的若干个不同敌人（下标），按距离排序。
    func nearestEnemies(to p: Vec2, within r: Double, count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let r2 = r * r
        var cand: [(Double, Int)] = []
        cand.reserveCapacity(64)
        for i in enemies.indices where !enemies[i].dead {
            let d = enemies[i].pos.distSq(p)
            if d <= r2 { cand.append((d, i)) }
        }
        cand.sort { $0.0 < $1.0 }
        return cand.prefix(count).map { $0.1 }
    }

    /// 范围内随机的若干个不同敌人；不够时可以重复。
    func randomEnemies(near p: Vec2, within r: Double, count: Int, allowRepeat: Bool = true) -> [Int] {
        guard count > 0 else { return [] }
        let r2 = r * r
        var pool: [Int] = []
        for i in enemies.indices where !enemies[i].dead && enemies[i].pos.distSq(p) <= r2 { pool.append(i) }
        guard !pool.isEmpty else { return [] }
        rng.shuffle(&pool)
        var out = Array(pool.prefix(count))
        if allowRepeat {
            while out.count < count { out.append(pool[rng.int(pool.count)]) }
        }
        return out
    }

    func hasEnemy(within r: Double) -> Bool { nearestEnemy(to: player.pos, within: r) != nil }

    /// 遍历圆内的敌人（候选来自网格）。body 返回 false 时停止。
    func forEachEnemy(inCircle c: Vec2, radius r: Double, _ body: (Int) -> Bool) {
        let maxR = 70.0
        if r > 600 {
            for i in enemies.indices where !enemies[i].dead {
                let rr = r + enemies[i].radius
                if enemies[i].pos.distSq(c) <= rr * rr, !body(i) { return }
            }
            return
        }
        grid.query(c, r + maxR, into: &gridScratch)
        let list = gridScratch
        for k in list {
            let i = Int(k)
            guard i < enemies.count, !enemies[i].dead else { continue }
            let rr = r + enemies[i].radius
            if enemies[i].pos.distSq(c) <= rr * rr, !body(i) { return }
        }
    }

    // MARK: 屏幕外位置

    /// 可见区域外 margin 一圈上的随机点（8.5）。
    func offscreenPoint(margin: Double? = nil) -> Vec2 {
        let m = margin ?? cfg.spawn.offscreenMargin
        let hw = viewSize.x / 2 + m, hh = viewSize.y / 2 + m
        let per = 4 * (hw + hh)
        var t = rng.nextDouble() * per
        let off: Vec2
        if t < 2 * hw { off = Vec2(-hw + t, hh) } else {
            t -= 2 * hw
            if t < 2 * hh { off = Vec2(hw, hh - t) } else {
                t -= 2 * hh
                if t < 2 * hw { off = Vec2(hw - t, -hh) } else {
                    t -= 2 * hw
                    off = Vec2(-hw, -hh + t)
                }
            }
        }
        return player.pos + off
    }

    /// 玩家前进方向的屏幕外一点（8.1 的瞬移重刷）。
    func offscreenPointAhead() -> Vec2 {
        let dir = (player.input.lengthSq > 0 ? player.input : player.facing).rotated(rng.range(-0.8, 0.8))
        let hw = viewSize.x / 2 + cfg.spawn.offscreenMargin
        let hh = viewSize.y / 2 + cfg.spawn.offscreenMargin
        let tx = abs(dir.x) > 1e-6 ? hw / abs(dir.x) : .infinity
        let ty = abs(dir.y) > 1e-6 ? hh / abs(dir.y) : .infinity
        return player.pos + dir * min(tx, ty)
    }

    /// 以 c 为中心、可见区域内的随机点。
    func randomPointInView(around c: Vec2, shrink: Double = 40) -> Vec2 {
        let hw = max(10, viewSize.x / 2 - shrink), hh = max(10, viewSize.y / 2 - shrink)
        return c + Vec2(rng.range(-hw, hw), rng.range(-hh, hh))
    }
}

/// 掉落来源（12.3）。
enum ItemDropSource {
    case minion, elite, boss, final
}

/// 生成好的一件掉落法宝：在 RunState.stageLoot 里的下标、品质序号、名称。
struct ItemDropInfo {
    var index: Int
    var quality: Int
    var name: String
}

extension BattleWorld {
    func hasLegendary(_ id: String) -> Bool { legendaries[id] != nil }
    func legendaryParam(_ id: String, _ key: String) -> Double? { legendaries[id]?[key] }
    func lp(_ id: String, _ key: String, _ d: Double) -> Double { legendaries[id]?[key] ?? d }

    /// 法天象地：体修功法范围 ×1.5（7.3）。
    func areaFactor(_ def: SkillDef) -> Double { bodyForm && def.school == .body ? 1.5 : 1 }

    /// 随绝学变化的功法倍率：法天象地体修 ×3，百兽朝宗召唤 ×2（7.3）。
    func skillFactor(_ hit: Hit) -> Double {
        guard case .skill(let s) = hit.source, s >= 0, s < skills.count else { return 1 }
        let d = skills[s].def
        var f = 1.0
        if bodyForm, d.school == .body { f *= 3 }
        if d.has(.summon) { f *= summonDmgMult }
        return f
    }

    /// 增加心魔值（10.1）：乘获取系数，向下取整，最高 100。
    func addHeartDemon(_ amount: Int) {
        let mx = cfg.heartDemon.max
        if amount > 0 {
            heartDemon = min(mx, heartDemon + Int((Double(amount) * heartDemonGain).rounded(.down)))
        } else {
            heartDemon = max(0, heartDemon + amount)
        }
        onHeartDemonChanged?()
    }
}
