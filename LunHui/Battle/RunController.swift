import Foundation

/// 一世的流程（4.2 到 4.6、第 9、10 章）：创建 RunState、每关搭 BattleWorld、关间顿悟和机缘。
/// 纯逻辑，不依赖界面。界面层（BattleView）只调用这里的方法。
final class RunController {
    let cfg: GameConfig
    private(set) var save: SaveData
    var run: RunState
    let world: BattleWorld
    private var insightRng: SeededRandom
    private var eventRng: SeededRandom
    /// 本关拾取、还没写进 run.loot 的法宝（过关时才写入，4.5）。
    private(set) var stageLoot: [Item] = []
    /// 本关新拾取的法宝下标（stageLoot 里），给掉落面板。
    private(set) var pickedThisStage: [Int] = []

    // MARK: 创建

    /// 从出发准备创建新的一世。
    static func newRun(_ cfg: GameConfig, save: SaveData, tier: Int, school: School, lingGen: LingGen,
                       pills: [String], seed: UInt64) -> RunState {
        var r = SeededRandom(seed: seed)
        var states: [String: UInt64] = [:]
        for k in ["spawn", "loot", "insight", "event"] { states[k] = r.split().state }
        let pv = save.nextRunPreview
        var run = RunState(seed: seed, rngStates: states, tier: tier, school: school, lingGen: lingGen,
                           themeOrder: pv.themeOrder, dungeonAffixes: pv.dungeonAffixes, pills: pills,
                           equippedSnapshot: save.equippedItems)
        let start = cfg.schools.def(school).startSkill
        var er = SeededRandom(seed: states["insight"]!)
        let el = lingGen.rollSkillElement(&er)
        run.skillElements[start] = el
        run.skills = [SkillState(id: start, level: 1 + save.building("cj_skill"), element: el, evolved: false)]
        run.rerollsLeft = cfg.insight.freeRerolls + save.building("cj_reroll")
        run.pendingInsights = save.building("cj_start")
        for p in pills { run.heartDemon += cfg.cave.pill(p)?.demon ?? 0 }
        run.heartDemon = min(cfg.heartDemon.max, run.heartDemon)
        return run
    }

    init(cfg: GameConfig, save: SaveData, run: RunState) {
        self.cfg = cfg
        self.save = save
        self.run = run
        insightRng = SeededRandom(seed: run.rngStates["insight"] ?? run.seed &+ 3)
        eventRng = SeededRandom(seed: run.rngStates["event"] ?? run.seed &+ 4)
        let setup = RunController.stageSetup(cfg, run: run, index: run.stageIndex, heartDemon: run.heartDemon)
        world = BattleWorld(cfg: cfg, setup: setup, lingGen: run.lingGen, school: run.school,
                            seed: (run.rngStates["spawn"] ?? run.seed) ^ UInt64(run.stageIndex &* 7919))
        world.lootRng = SeededRandom(seed: (run.rngStates["loot"] ?? run.seed) ^ UInt64(run.stageIndex &* 104729))
        world.rollItem = { [weak self] rng, source, minQ in self?.rollDrop(&rng, source, minQ) }
        world.onItemPicked = { [weak self] i in
            guard let self else { return }
            self.pickedThisStage.append(i)
            if let it = self.stageLoot[safe: i] {
                self.world.events.append(.itemPicked(quality: it.qualityIndex(self.cfg), name: it.name))
            }
        }
        world.onHeartDemonChanged = { [weak self] in self?.heartDemonChanged() }
        world.level = run.level
        world.exp = run.exp
        world.revivesLeft = run.revivesLeft
        world.ultCharge = run.ultCharge
        world.heartDemon = run.heartDemon
        world.kills = run.stats.kills
        world.bestHit = run.stats.bestHit
        rebuildSkills()
        applyRunModifiers()
        if run.hp <= 0 {
            // 新的一世：满血，复活次数按属性（4.4、14.3）。
            world.player.hp = world.stats.hp
            self.run.revivesLeft = world.stats.revive
            world.revivesLeft = world.stats.revive
        } else {
            world.player.hp = min(run.hp, world.stats.hp)
        }
    }

    // MARK: 关卡

    static func stageKind(index i: Int, heartDemon: Int, cfg: GameConfig) -> StageKind {
        if i == 14 { return heartDemon >= cfg.heartDemon.shadowAt ? .shadow : .tribulation }
        if i == 13 { return .boss }
        if i >= 12 { return .normal }
        return i % 3 == 2 ? .boss : .normal
    }

    static func stageSetup(_ cfg: GameConfig, run: RunState, index i: Int, heartDemon: Int) -> StageSetup {
        let realm = min(4, i / 3)
        let theme = cfg.themes.def(run.themeOrder[safe: realm] ?? "forest")
        var s = StageSetup(tier: run.tier, realm: realm, stageIndex: i,
                           kind: stageKind(index: i, heartDemon: heartDemon, cfg: cfg), themeElement: theme.element)
        for id in StatAssembler.activeAffixes(cfg, run: run) {
            guard let a = cfg.dungeonAffixes.def(id) else { continue }
            s.enemyHpMult *= a.hpMult ?? 1
            s.enemyAtkMult *= a.atkMult ?? 1
            s.enemySpeedMult *= a.speedMult ?? 1
            s.spawnMult *= a.spawnMult ?? 1
            s.eliteMult *= a.eliteMult ?? 1
            if a.minionExplode == true { s.minionExplode = true }
        }
        return s
    }

    /// 关卡名，比如"金丹·第 2 关"。
    func stageTitle(_ i: Int? = nil) -> String {
        let idx = i ?? run.stageIndex
        let realm = cfg.enemies.realms[min(4, idx / 3)].name
        switch RunController.stageKind(index: idx, heartDemon: run.heartDemon, cfg: cfg) {
        case .tribulation: return "\(realm)·天劫"
        case .shadow: return "\(realm)·心魔"
        case .boss: return "\(realm)·劫关"
        case .normal: return "\(realm)·第 \(idx % 3 + 1) 关"
        }
    }

    var realmName: String { cfg.enemies.realms[run.realm].name }

    /// 开始 run.stageIndex 这一关。
    func startStage() {
        let setup = RunController.stageSetup(cfg, run: run, index: run.stageIndex, heartDemon: run.heartDemon)
        stageLoot = []
        pickedThisStage = []
        world.rng = SeededRandom(seed: (run.rngStates["spawn"] ?? run.seed) ^ UInt64(run.stageIndex &* 7919 &+ 1))
        world.lootRng = SeededRandom(seed: (run.rngStates["loot"] ?? run.seed) ^ UInt64(run.stageIndex &* 104729 &+ 1))
        applyRunModifiers()
        world.startStage(setup)
        if setup.kind == .shadow { ShadowController.spawn(world, run: run) }
    }

    /// 过关：把本关拾取写进 RunState，推进关卡序号，生成机缘（4.3）。
    func finishStage() {
        syncFromWorld()
        let picked = pickedThisStage.compactMap { stageLoot[safe: $0] }
        run.loot.append(contentsOf: picked)
        run.lingShiGained += world.stageLingShi
        if world.setup.kind == .shadow { run.shadowKilled = true }
        run.stageIndex += 1
        if run.stageIndex >= 15 {
            run.finished = true
            run.cleared = true
            run.pendingEventChoices = nil
        } else {
            run.pendingEventChoices = rollEvents()
        }
        saveRngStates()
    }

    /// 本关拾取的法宝（掉落面板，4.3）。
    var stageItems: [Item] { pickedThisStage.compactMap { stageLoot[safe: $0] } }

    /// 一世结束（死亡或放弃，4.4、4.5）。
    func endRun() {
        syncFromWorld()
        run.finished = true
    }

    func syncFromWorld() {
        run.level = world.level
        run.exp = world.exp
        run.hp = world.player.hp
        run.revivesLeft = world.revivesLeft
        if world.revivesLeft < world.stats.revive { run.usedRevive = true }
        run.ultCharge = world.ultCharge
        run.heartDemon = world.heartDemon
        run.stats.kills = world.kills
        run.stats.bestHit = world.bestHit
    }

    private func saveRngStates() {
        run.rngStates["insight"] = insightRng.state
        run.rngStates["event"] = eventRng.state
    }

    // MARK: 掉落（12.3）

    private func rollDrop(_ rng: inout SeededRandom, _ source: ItemDropSource, _ minQ: Int) -> ItemDropInfo? {
        let mf = world.stats.magicFind + world.magicFindBonus
        var q = ItemForge.rollQuality(cfg, tier: run.tier, magicFind: mf, minQuality: minQ, rng: &rng)
        // 击败心魔影子额外 1 件神品，第 30 劫起 10% 变混沌（10.3）。
        if source == .final, world.setup.kind == .shadow, minQ >= cfg.heartDemon.shadowExtraItemQuality {
            q = minQ
            if run.tier >= cfg.items.qualities[5].minTier, rng.chance(cfg.heartDemon.shadowHundunChance) { q = 5 }
        }
        let item = ItemForge.make(cfg, quality: q, tier: run.tier, school: run.school, rng: &rng)
        stageLoot.append(item)
        return ItemDropInfo(index: stageLoot.count - 1, quality: q, name: item.name)
    }

    // MARK: 属性

    /// 重算本世全部属性（5.3）：局外 + 丹药 + 灵根 + 流派 + 心法 + 机缘 + 词缀 + 功法自带。
    func applyRunModifiers() {
        var b = StatAssembler.runBlock(cfg, save: save, run: run)
        for sk in world.skills { b.add(sk.statMods(world)) }
        world.benmingMult = cfg.benming.mult(level: save.benming.level)
        world.baseBlock = b
        let sd = cfg.schools.def(run.school)
        world.heartDemonGain = sd.heartDemonGain ?? 1
        world.dmgPctPer10Demon = sd.dmgPctPer10Demon ?? 0
        world.summonIntervalPct = sd.summonIntervalPct ?? 0
        world.summonCountBonus = sd.summonCountBonus ?? 0
        world.counterMultValue = run.lingGen.counterMult(cfg)
        world.generateBonusValue = run.lingGen.generateBonus(cfg)
        // 秘境词缀（9.3）
        var elemMult = [Double](repeating: 1, count: 7)
        var shock = 1.0, shatter = 1.0, dropFactor = 1.0, reward = 0.0, rewardExp = 0.0
        for id in StatAssembler.activeAffixes(cfg, run: run) {
            guard let a = cfg.dungeonAffixes.def(id) else { continue }
            for (k, v) in a.elemMult ?? [:] { if let e = Element(rawValue: k) { elemMult[e.index] *= v } }
            shock *= a.shockMult ?? 1
            shatter *= a.shatterMult ?? 1
            dropFactor *= a.dropFactor ?? 1
            reward += a.reward ?? 0
            rewardExp += a.rewardExp ?? 0
        }
        world.affixElemMult = elemMult
        world.shockMult = shock
        world.shatterMult = shatter
        world.dropFactor = dropFactor
        world.challengeReward = reward
        world.challengeExp = rewardExp
        // 传说特效（12.5）
        var legs: [String: [String: Double]] = [:]
        for it in run.equippedSnapshot {
            if let l = it.legendary, let d = cfg.legendaries.def(l) { legs[l] = d.params }
        }
        world.legendaries = legs
        world.ultElement = ultimateElement()
        heartDemonChanged()
        installHooks()
    }

    /// 心魔区间（10.2）对修为、掉落、寻宝、灵石的加成。
    private func heartDemonChanged() {
        let band = cfg.heartDemon.band(world.heartDemon)
        world.expBonus = band.exp + world.challengeExp
        world.dropBonus = band.drop + world.challengeReward
        world.magicFindBonus = band.mf + 0.01 * Double(run.tier - 1)
        world.lingShiBonus = band.ls + world.challengeReward
    }

    /// 绝学和本命一击的元素（6.5）：已学功法里数量最多的元素；并列或没有时取灵根第一个元素。
    func ultimateElement() -> Element {
        var counts: [Element: Int] = [:]
        for s in run.skills { counts[s.element, default: 0] += 1 }
        let best = counts.max { $0.value < $1.value }
        if let best, counts.values.filter({ $0 == best.value }).count == 1 { return best.key }
        return run.lingGen.elements.first ?? .fire
    }

    /// 按 run.skills 重建功法行为，保留已有实例的冷却。
    func rebuildSkills() {
        var old: [String: SkillBehavior] = [:]
        for s in world.skills { old[s.def.id] = s }
        var list: [SkillBehavior] = []
        for (k, st) in run.skills.enumerated() {
            let b: SkillBehavior
            if let o = old[st.id] {
                b = o
                b.slot = k
                if b.level != st.level { b.level = st.level }
                b.element = st.element
            } else if let n = SkillFactory.make(id: st.id, slot: k, level: st.level, element: st.element, cfg: cfg) {
                b = n
            } else { continue }
            if st.evolved, b.evolution == nil { b.evolution = cfg.evolutions.forSkill(st.id) }
            list.append(b)
        }
        // 被移除的功法清理它的常驻物。
        let keep = Set(list.map { ObjectIdentifier($0) })
        for o in world.skills where !keep.contains(ObjectIdentifier(o)) {
            let slot = o.slot
            for i in world.projectiles.indices where world.projectiles[i].skill == slot { world.projectiles[i].dead = true }
            for i in world.summons.indices where world.summons[i].skill == slot { world.summons[i].dead = true }
        }
        world.skills = list
    }

    private func installHooks() {
        var hooks: [WorldHook] = []
        if let u = world.hooks.first(where: { $0 is UltimateHook }) { hooks.append(u) } else { hooks.append(UltimateHook(school: run.school)) }
        let bonus = StatAssembler.strikeBonus(cfg, save.benming)
        if let b = world.hooks.first(where: { $0 is BenmingStrikeHook }) as? BenmingStrikeHook {
            b.configure(level: save.benming.level, bonus: bonus)
            hooks.append(b)
        } else {
            let b = BenmingStrikeHook()
            b.configure(level: save.benming.level, bonus: bonus)
            hooks.append(b)
        }
        if let g = world.hooks.first(where: { $0 is GlobalLegendaryHook }) { hooks.append(g) } else { hooks.append(GlobalLegendaryHook()) }
        world.hooks = hooks
    }

    var ultimate: UltimateHook? { world.hooks.first { $0 is UltimateHook } as? UltimateHook }

    // MARK: 顿悟（7.2）

    var cardCount: Int { cfg.insight.cards + save.building("cj_cards") }

    func rollInsight() -> [InsightCard] {
        syncFromWorld()
        return InsightGen.cards(cfg, run: run, cardCount: cardCount, rng: &insightRng)
    }

    func chooseInsight(_ card: InsightCard) {
        syncFromWorld()
        let r = InsightGen.apply(card, to: &run)
        if r.lingShi > 0 { run.lingShiGained += r.lingShi }
        rebuildSkills()
        applyRunModifiers()
        if r.heal > 0 { world.heal(world.stats.hp * r.heal) }
        saveRngStates()
    }

    func rerollInsight() -> [InsightCard]? {
        guard run.rerollsLeft > 0 else { return nil }
        run.rerollsLeft -= 1
        return rollInsight()
    }

    // MARK: 机缘（9.2）

    func rollEvents() -> [String] {
        var pool = cfg.events.events.filter { e in
            if let m = e.minDemon, run.heartDemon < m { return false }
            return true
        }
        var out: [String] = []
        while out.count < cfg.events.choices, !pool.isEmpty {
            guard let k = eventRng.weightedIndex(pool.map { $0.weight }) else { break }
            out.append(pool.remove(at: k).id)
        }
        return out
    }

    /// 云游商人的价格（9.2）。
    func eventCost(_ e: EventDef) -> Double {
        (e.costPerRealm ?? 0) * Double(1 + min(4, max(0, run.stageIndex - 1) / 3))
    }

    func canAfford(_ e: EventDef) -> Bool { run.lingShiGained >= eventCost(e) }

    /// 选择机缘。返回获得的法宝（商人、祭坛）。
    @discardableResult
    func chooseEvent(_ id: String) -> Item? {
        guard let e = cfg.events.def(id) else { return nil }
        run.pendingEventChoices = nil
        var gained: Item?
        if e.costPerRealm != nil {
            let c = eventCost(e)
            guard run.lingShiGained >= c else { return nil }
            run.lingShiGained -= c
        }
        if e.mods != nil { run.events.append(id) }
        if e.demon != 0 {
            world.heartDemon = run.heartDemon
            world.addHeartDemon(e.demon)
            run.heartDemon = world.heartDemon
        }
        if let n = e.insights { run.pendingInsights += n }
        if let q = e.item {
            var r = eventRng
            let item = ItemForge.make(cfg, quality: ItemForge.rollQuality(cfg, tier: run.tier, magicFind: world.stats.magicFind,
                                                                          minQuality: q, rng: &r),
                                      tier: run.tier, school: run.school, rng: &r)
            eventRng = r
            run.loot.append(item)
            gained = item
        }
        applyRunModifiers()
        if e.healFull == true { world.player.hp = world.stats.hp }
        if let loss = e.hpLoss { world.player.hp = max(1, world.player.hp * (1 - loss)) }
        syncFromWorld()
        saveRngStates()
        return gained
    }

    // MARK: 一世内换装（4.3）

    /// 用本世拾取的法宝替换当前同部位装备。
    func equipFromLoot(_ item: Item) {
        if let k = run.equippedSnapshot.firstIndex(where: { $0.slot == item.slot }) {
            run.equippedSnapshot[k] = item
        } else {
            run.equippedSnapshot.append(item)
        }
        applyRunModifiers()
    }

    func equippedInRun(_ slot: ItemSlot) -> Item? { run.equippedSnapshot.first { $0.slot == slot } }

    /// 单件法宝的战力，用于掉落面板比较（11.5 的公式，只换这一件）。
    func powerWith(_ item: Item) -> Double {
        var items = run.equippedSnapshot.filter { $0.slot != item.slot }
        items.append(item)
        return StatAssembler.power(cfg, save: save, items: items)
    }

    var currentPower: Double { StatAssembler.power(cfg, save: save, items: run.equippedSnapshot) }

    // MARK: 结算数据

    func result() -> RunResult {
        syncFromWorld()
        let done = run.cleared ? 15 : run.stageIndex
        return RunResult(tier: run.tier, school: run.school, lingGen: run.lingGen, stagesDone: done,
                         level: run.level, kills: run.stats.kills, bestHit: run.stats.bestHit, time: run.stats.time,
                         cleared: run.cleared, shadowKilled: run.shadowKilled, usedRevive: run.usedRevive,
                         lingShi: run.lingShiGained, loot: run.loot, heartDemon: run.heartDemon,
                         equippedSnapshotIds: run.equippedSnapshot.map(\.id))
    }
}
