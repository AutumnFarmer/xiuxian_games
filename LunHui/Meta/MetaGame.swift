import Foundation

/// 结算的结果（15.1、15.2），给结算界面显示。
struct SettlementReport: Equatable {
    var title: String
    var result: RunResult
    var lingShi: Double
    var suHui: Double
    var lingSui: Double
    var xiLianShiFromSalvage: Double
    var keptItems: [Item]
    var salvagedCount: Int
    var newMaxTier: Int?
    var unlockedSchools: [String]
    var newRecords: [String]
}

/// 局外逻辑（第 12 到 15 章）：结算、法宝阁、洗练、本命、道心、洞府升级、丹药。
/// 所有操作都直接修改传入的 SaveData，调用方负责存档。
enum MetaGame {
    // MARK: 新存档

    static func newSave(_ cfg: GameConfig, rng: inout SeededRandom) -> SaveData {
        SaveData(preview: PreviewGen.make(cfg, rng: &rng))
    }

    // MARK: 结算（第 15 章）

    static func settle(_ cfg: GameConfig, save: inout SaveData, result r: RunResult, rng: inout SeededRandom) -> SettlementReport {
        let sc = cfg.settlement
        let t = Double(r.tier - 1)
        let s = Double(r.stagesDone)
        var suHui = (sc.suHuiPerStage * s + Double(r.level) * sc.suHuiPerLevel) * (1 + sc.suHuiTierBonus * t)
        if r.cleared { suHui += sc.suHuiClear * (1 + sc.suHuiTierBonus * t) }
        var lingSui = (sc.lingSuiBase + sc.lingSuiPerStage * s) * (1 + sc.lingSuiTierBonus * t)
        if r.cleared { lingSui *= sc.lingSuiClearMult }
        var lingShi = r.lingShi
        if r.shadowKilled {
            let m = cfg.heartDemon.shadowRewardMult
            suHui *= m
            lingSui *= m
            lingShi *= m
        }
        lingSui = max(sc.lingSuiMin, lingSui)
        suHui = suHui.rounded(.down)
        lingSui = lingSui.rounded(.down)
        lingShi = lingShi.rounded(.down)
        save.lingShi += lingShi
        save.suHui += suHui
        save.lingSui += lingSui

        // 法宝入阁，按自动分解设置处理（12.6）
        var kept: [Item] = []
        var salvaged = 0
        var stones = 0.0
        let auto = Set(save.settings.autoSalvageLow ? sc.autoSalvageQualities : [])
        for it in r.loot {
            if auto.contains(it.quality), !r.equippedIds.contains(it.id) {
                stones += ItemForge.salvageValue(cfg, it)
                salvaged += 1
            } else {
                kept.append(it)
            }
        }
        save.items.append(contentsOf: kept)
        // 一世内换上的装备，结算后也装在身上
        for it in r.loot where r.equippedIds.contains(it.id) {
            save.equipped[it.slot.rawValue] = it.id
        }
        // 法宝阁满了：分解品质最低、等级最低的未锁定法宝
        let cap = save.capacity(cfg)
        if save.items.count > cap {
            let protected = Set(save.equipped.values)
            let order = save.items.indices
                .filter { !save.items[$0].locked && !protected.contains(save.items[$0].id) }
                .sorted {
                    let a = save.items[$0], b = save.items[$1]
                    let qa = a.qualityIndex(cfg), qb = b.qualityIndex(cfg)
                    return qa != qb ? qa < qb : a.level < b.level
                }
            let excess = save.items.count - cap
            let remove = Set(order.prefix(excess))
            for i in remove { stones += ItemForge.salvageValue(cfg, save.items[i]) }
            salvaged += remove.count
            save.items = save.items.enumerated().filter { !remove.contains($0.offset) }.map { $0.element }
        }
        save.xiLianShi += stones

        // 解锁（15.2）
        var newMax: Int?
        if r.cleared {
            let up = r.tier + (r.usedRevive ? sc.tierUnlockClear : sc.tierUnlockNoRevive)
            if up > save.maxTierUnlocked {
                save.maxTierUnlocked = up
                newMax = up
            }
        }
        var schools: [String] = []
        if r.cleared, !save.records.firstClearDone {
            save.records.firstClearDone = true
            for sd in cfg.schools.schools where sd.unlock == .firstClear && !save.unlockedSchools.contains(sd.id.rawValue) {
                save.unlockedSchools.append(sd.id.rawValue)
                schools.append(sd.name)
            }
        }
        if r.shadowKilled, !save.records.firstShadowKillDone {
            save.records.firstShadowKillDone = true
            for sd in cfg.schools.schools where sd.unlock == .firstShadowKill && !save.unlockedSchools.contains(sd.id.rawValue) {
                save.unlockedSchools.append(sd.id.rawValue)
                schools.append(sd.name)
            }
        }
        var records: [String] = []
        if r.bestHit > save.records.bestHit {
            if save.records.bestHit > 0 { records.append("最高一击") }
            save.records.bestHit = r.bestHit
        }
        if r.cleared, r.tier > save.records.maxTierCleared {
            if save.records.maxTierCleared > 0 { records.append("最高劫数") }
            save.records.maxTierCleared = r.tier
        }
        if r.kills > save.records.maxKillsInRun {
            if save.records.maxKillsInRun > 0 { records.append("单世击杀") }
            save.records.maxKillsInRun = r.kills
        }
        save.records.totalRuns += 1
        save.records.totalKills += r.kills
        save.lastTier = r.tier
        save.hasActiveRun = false
        save.nextRunPreview = PreviewGen.make(cfg, rng: &rng)

        let title = r.shadowKilled ? "心魔已斩" : (r.cleared ? "渡劫成功" : "兵解转世")
        let sorted = kept.sorted { $0.qualityIndex(cfg) > $1.qualityIndex(cfg) }
        return SettlementReport(title: title, result: r, lingShi: lingShi, suHui: suHui, lingSui: lingSui,
                                xiLianShiFromSalvage: stones, keptItems: sorted, salvagedCount: salvaged,
                                newMaxTier: newMax, unlockedSchools: schools, newRecords: records)
    }

    // MARK: 法宝阁（12.6）

    static func equip(_ save: inout SaveData, _ item: Item) {
        save.equipped[item.slot.rawValue] = item.id
        markSeen(&save, item.id)
    }

    static func markSeen(_ save: inout SaveData, _ id: UUID) {
        if let i = save.items.firstIndex(where: { $0.id == id }) { save.items[i].isNew = false }
    }

    static func toggleLock(_ save: inout SaveData, _ id: UUID) {
        if let i = save.items.firstIndex(where: { $0.id == id }) { save.items[i].locked.toggle() }
    }

    /// 分解：加锁和装备中的不能分解。返回获得的洗练石。
    @discardableResult
    static func salvage(_ cfg: GameConfig, _ save: inout SaveData, ids: Set<UUID>) -> Double {
        let protected = Set(save.equipped.values)
        var stones = 0.0
        save.items.removeAll { it in
            guard ids.contains(it.id), !it.locked, !protected.contains(it.id) else { return false }
            stones += ItemForge.salvageValue(cfg, it)
            return true
        }
        save.xiLianShi += stones
        return stones
    }

    /// 一键分解的候选（按品质勾选）。
    static func salvageCandidates(_ cfg: GameConfig, _ save: SaveData, qualities: Set<String>) -> [Item] {
        let protected = Set(save.equipped.values)
        return save.items.filter { qualities.contains($0.quality) && !$0.locked && !protected.contains($0.id) }
    }

    // MARK: 洗练与重铸（12.6）

    static func reforgeCost(_ cfg: GameConfig, _ save: SaveData, _ item: Item, recast: Bool) -> Double {
        ItemForge.reforgeCost(cfg, item, discountLevel: save.building("lq_discount"), recast: recast)
    }

    /// 洗练或重铸一条词条，扣洗练石，返回新词条（还没应用，玩家选择后调用 applyAffix）。
    static func rollAffix(_ cfg: GameConfig, _ save: inout SaveData, _ id: UUID, affix k: Int, recast: Bool,
                          rng: inout SeededRandom) -> Affix? {
        guard let i = save.items.firstIndex(where: { $0.id == id }) else { return nil }
        let cost = reforgeCost(cfg, save, save.items[i], recast: recast)
        guard save.xiLianShi >= cost else { return nil }
        let a = recast ? ItemForge.recast(cfg, save.items[i], affix: k, rng: &rng)
                       : ItemForge.reforge(cfg, save.items[i], affix: k, rng: &rng)
        guard let a else { return nil }
        save.xiLianShi -= cost
        return a
    }

    static func applyAffix(_ save: inout SaveData, _ id: UUID, affix k: Int, _ a: Affix) {
        guard let i = save.items.firstIndex(where: { $0.id == id }), k < save.items[i].affixes.count else { return }
        save.items[i].affixes[k] = a
    }

    // MARK: 本命法宝（第 13 章）

    /// 祭炼一次。到 10 的倍数级时生成一组待选觉醒。
    @discardableResult
    static func refineBenming(_ cfg: GameConfig, _ save: inout SaveData, rng: inout SeededRandom) -> Bool {
        let cost = cfg.benming.cost(level: save.benming.level)
        guard save.lingSui >= cost else { return false }
        save.lingSui -= cost
        save.benming.level += 1
        if save.benming.level % cfg.benming.awakenEvery == 0 {
            save.benming.pendingAwakenings.append(rollAwakenings(cfg, rng: &rng))
        }
        return true
    }

    /// 祭炼到灵髓用完，返回升了几级。
    static func refineAll(_ cfg: GameConfig, _ save: inout SaveData, rng: inout SeededRandom) -> Int {
        var n = 0
        while n < 100_000, refineBenming(cfg, &save, rng: &rng) { n += 1 }
        return n
    }

    static func rollAwakenings(_ cfg: GameConfig, rng: inout SeededRandom) -> [String] {
        var pool = cfg.benming.awakenings
        rng.shuffle(&pool)
        return pool.prefix(cfg.benming.awakenChoices).map { a in
            a.randomElement == true ? "\(a.id):\(Element.allCases[rng.int(7)].rawValue)" : a.id
        }
    }

    static func chooseAwakening(_ save: inout SaveData, _ choice: String) {
        guard !save.benming.pendingAwakenings.isEmpty else { return }
        save.benming.pendingAwakenings.removeFirst()
        save.benming.awakenings.append(choice)
    }

    static func awakeningText(_ cfg: GameConfig, _ raw: String) -> (name: String, desc: String) {
        let parts = raw.split(separator: ":").map(String.init)
        guard let a = cfg.benming.awakening(parts[0]) else { return (raw, "") }
        if a.randomElement == true, parts.count > 1, let e = Element(rawValue: parts[1]) {
            return (a.name, cfg.elements.name(e) + a.desc)
        }
        return (a.name, a.desc)
    }

    // MARK: 道心（14.2）

    @discardableResult
    static func levelDaoXin(_ cfg: GameConfig, _ save: inout SaveData) -> Bool {
        let cost = cfg.cave.daoXinCost(level: save.daoXinLevel)
        guard save.suHui >= cost else { return false }
        save.suHui -= cost
        save.daoXinLevel += 1
        return true
    }

    static func levelDaoXinAll(_ cfg: GameConfig, _ save: inout SaveData) -> Int {
        var n = 0
        while n < 100_000, levelDaoXin(cfg, &save) { n += 1 }
        return n
    }

    static func allocate(_ save: inout SaveData, _ id: String, _ n: Int = 1) {
        let k = min(n, save.daoXinUnspent)
        guard k > 0 else { return }
        save.daoXinPoints[id, default: 0] += k
    }

    static func resetDaoXin(_ save: inout SaveData) { save.daoXinPoints = [:] }

    // MARK: 洞府升级（14.3、14.4）

    static func upgradeCost(_ cfg: GameConfig, _ save: SaveData, _ id: String) -> Double? {
        guard let u = cfg.cave.upgrade(id) else { return nil }
        let lv = save.building(id)
        if u.max > 0, lv >= u.max { return nil }
        return u.cost(toLevel: lv + 1)
    }

    @discardableResult
    static func upgrade(_ cfg: GameConfig, _ save: inout SaveData, _ id: String) -> Bool {
        guard let c = upgradeCost(cfg, save, id), save.lingShi >= c else { return false }
        save.lingShi -= c
        save.buildings[id, default: 0] += 1
        return true
    }

    // MARK: 丹药（14.5）

    static func pillPrice(_ cfg: GameConfig, _ save: SaveData, _ id: String) -> Double {
        guard let p = cfg.cave.pill(id) else { return 0 }
        return (p.price * (1 + cfg.cave.pillPriceTierBonus * Double(save.maxTierUnlocked - 1))).rounded(.down)
    }
}

extension RunResult {
    /// 一世内换上的法宝 id（结算后保持装备）。
    var equippedIds: Set<UUID> { Set(equippedSnapshotIds) }
}
