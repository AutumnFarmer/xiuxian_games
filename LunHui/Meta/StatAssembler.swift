import Foundation

/// 把各个来源的属性加在一起（5.3）。
enum StatAssembler {
    /// 局外来源：装备、本命觉醒、道心（11.5 的战力也只算这些和丹药）。
    static func metaBlock(_ cfg: GameConfig, save: SaveData, items: [Item]? = nil) -> StatBlock {
        var b = StatBlock()
        for it in items ?? save.equippedItems { b.add(it.statMods(cfg)) }
        b.add(awakeningMods(cfg, save.benming))
        let p = cfg.balance.itemScale(tier: save.maxTierUnlocked)
        for pt in cfg.cave.daoxin.points {
            let n = Double(save.daoXinPoints[pt.id] ?? 0)
            guard n > 0 else { continue }
            b.add(pt.stat, pt.value * n * (pt.scales == true ? p : 1))
        }
        return b
    }

    /// 本命觉醒的属性（13.4）。带元素的写成 "bm_elem:fire"。
    static func awakeningMods(_ cfg: GameConfig, _ bm: Benming) -> [StatMod] {
        var mods: [StatMod] = []
        for raw in bm.awakenings {
            let parts = raw.split(separator: ":").map(String.init)
            guard let a = cfg.benming.awakening(parts[0]) else { continue }
            for m in a.mods ?? [] {
                var mm = m
                if a.randomElement == true, parts.count > 1 { mm.param = parts[1] }
                mods.append(mm)
            }
        }
        return mods
    }

    /// 本命一击的冷却缩减和伤害加成（13.4 的"本命通神"）。
    static func strikeBonus(_ cfg: GameConfig, _ bm: Benming) -> (cdr: Double, dmg: Double) {
        var c = 0.0, d = 0.0
        for raw in bm.awakenings {
            let id = String(raw.split(separator: ":")[0])
            guard let a = cfg.benming.awakening(id) else { continue }
            c += a.strikeCdr ?? 0
            d += a.strikeDmg ?? 0
        }
        return (c, d)
    }

    static func pillMods(_ cfg: GameConfig, _ pills: [String]) -> [StatMod] {
        pills.compactMap { cfg.cave.pill($0) }.flatMap { $0.mods ?? [] }
    }

    /// 一世内的全部来源：局外 + 丹药 + 灵根 + 流派被动 + 心法 + 机缘 + 秘境词缀。功法自带属性另外加（BattleWorld）。
    static func runBlock(_ cfg: GameConfig, save: SaveData, run: RunState) -> StatBlock {
        var b = metaBlock(cfg, save: save, items: run.equippedSnapshot)
        b.add(pillMods(cfg, run.pills))
        b.add(run.lingGen.statMods(cfg))
        b.add(cfg.schools.def(run.school).passive)
        for (id, lv) in run.passives {
            if let d = cfg.passives.def(id) { b.add(d.mods(level: lv)) }
        }
        for id in run.events {
            if let e = cfg.events.def(id) { b.add(e.mods ?? []) }
        }
        for id in activeAffixes(cfg, run: run) {
            if let a = cfg.dungeonAffixes.def(id) { b.add(a.mods ?? []) }
        }
        // 藏经阁"复活"（14.3）
        b.add(.revive, Double(save.building("cj_revive")))
        // 传说"不死"（12.5）
        if run.equippedSnapshot.contains(where: { $0.legendary == "L_busi" }) { b.add(.revive, 1) }
        return b
    }

    /// 本世生效的秘境词缀（9.3）：第 10 劫以下只取前 2 条。
    static func activeAffixes(_ cfg: GameConfig, run: RunState) -> [String] {
        Array(run.dungeonAffixes.prefix(cfg.dungeonAffixes.activeCount(tier: run.tier)))
    }

    // MARK: 战力（11.5）

    static func power(_ cfg: GameConfig, save: SaveData, items: [Item]? = nil, pills: [String] = []) -> Double {
        var b = metaBlock(cfg, save: save, items: items)
        b.add(pillMods(cfg, pills))
        let s = PlayerStats.finalize(b, cfg: cfg.stats, levelFactor: 1, benmingMult: cfg.benming.mult(level: save.benming.level))
        let crit = min(1, s.critRate)
        let out = s.atk * (1 + crit * (s.critDmg - 1)) * (1 + s.dmgPct)
        let surv = s.hp / max(0.25, 1 - s.dmgReduce)
        return (out.squareRoot() * surv.squareRoot() * 10).rounded()
    }

    static func recommendedPower(_ cfg: GameConfig, tier: Int) -> Double {
        cfg.balance.recommendPowerBase * cfg.balance.enemyScale(tier: tier)
    }
}
