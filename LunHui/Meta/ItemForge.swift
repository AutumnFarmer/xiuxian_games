import Foundation

/// 法宝生成、分解、洗练、重铸（第 12 章）。
enum ItemForge {
    // MARK: 生成（12.1 到 12.5）

    /// 按权重随机品质（12.3）。minQuality 是保底下限。
    static func rollQuality(_ cfg: GameConfig, tier: Int, magicFind: Double, minQuality: Int, rng: inout SeededRandom) -> Int {
        let qs = cfg.items.qualities
        var w = qs.map { $0.weight }
        for i in w.indices where i >= cfg.items.magicFindFromQuality { w[i] *= (1 + max(0, magicFind)) }
        // 第 30 劫以下不掉混沌品，权重并入神品。
        for i in w.indices where tier < qs[i].minTier {
            if i > 0 { w[i - 1] += w[i] }
            w[i] = 0
        }
        for i in 0..<min(minQuality, w.count) { w[i] = 0 }
        if w.allSatisfy({ $0 <= 0 }) { return min(max(0, minQuality), qs.count - 1) }
        return rng.weightedIndex(w) ?? 0
    }

    static func make(_ cfg: GameConfig, slot: ItemSlot? = nil, quality q: Int, tier: Int, school: School?,
                     rng: inout SeededRandom, now: Date = Date()) -> Item {
        let items = cfg.items
        let qual = items.qualities[max(0, min(q, items.qualities.count - 1))]
        let s = slot ?? ItemSlot.allCases[rng.int(ItemSlot.allCases.count)]
        let sd = items.slot(s)
        let p = cfg.balance.itemScale(tier: tier)
        var affixes: [Affix] = []
        var pool = items.affixes.filter { $0.slots.isEmpty || $0.slots.contains(s) }
        for _ in 0..<qual.affixes {
            guard let k = rng.weightedIndex(pool.map { $0.weight }) else { break }
            let def = pool.remove(at: k)
            affixes.append(rollAffix(cfg, def, quality: qual, tier: tier, rng: &rng))
        }
        var legendary: String?
        if qual.legendary { legendary = rollLegendary(cfg, school: school, rng: &rng) }
        let suffix = rng.pick(sd.suffixes) ?? sd.name
        let prefix = legendary.flatMap { cfg.legendaries.def($0)?.name } ?? (rng.pick(items.prefixes) ?? "")
        return Item(id: UUID(uuid: uuidBytes(&rng)), slot: s, quality: qual.id, level: tier, name: prefix + suffix,
                    mainAtk: sd.mainAtk * qual.factor * p, mainHp: sd.mainHp * qual.factor * p,
                    affixes: affixes, legendary: legendary, locked: false, isNew: true, obtainedAt: now)
    }

    static func rollAffix(_ cfg: GameConfig, _ def: ItemsConfig.AffixDef, quality qual: ItemsConfig.Quality, tier: Int,
                          rng: inout SeededRandom) -> Affix {
        let u = rng.range(qual.rollMin, qual.rollMax)
        var value = def.min + (def.max - def.min) * u
        if def.scales == true { value *= cfg.balance.itemScale(tier: tier) }
        if def.stat == .projCount { value = def.min }
        var param: String?
        if def.param == "element" { param = Element.allCases[rng.int(Element.allCases.count)].rawValue }
        if def.param == "school" { param = School.allCases[rng.int(School.allCases.count)].rawValue }
        return Affix(type: def.id, value: value, roll: u, param: param)
    }

    /// 传说特效（12.5）：70% 从"本流派功法、通用功法、全局"里抽，30% 从全部里抽。
    static func rollLegendary(_ cfg: GameConfig, school: School?, rng: inout SeededRandom) -> String? {
        let all = cfg.legendaries.legendaries
        var pool = all
        if let school, rng.chance(cfg.legendaries.schoolBias) {
            pool = all.filter { l in
                guard let sk = l.skill else { return true }
                let s = cfg.skills.def(sk)?.school
                return s == nil || s == school
            }
        }
        return rng.pick(pool)?.id
    }

    private static func uuidBytes(_ rng: inout SeededRandom) -> uuid_t {
        let a = rng.next(), b = rng.next()
        var t: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &t) { buf in
            for k in 0..<8 { buf[k] = UInt8((a >> (8 * UInt64(k))) & 0xFF) }
            for k in 0..<8 { buf[8 + k] = UInt8((b >> (8 * UInt64(k))) & 0xFF) }
            buf[6] = (buf[6] & 0x0F) | 0x40
            buf[8] = (buf[8] & 0x3F) | 0x80
        }
        return t
    }

    // MARK: 分解与洗练（12.6）

    static func salvageValue(_ cfg: GameConfig, _ item: Item) -> Double {
        let q = cfg.items.qualities[item.qualityIndex(cfg)]
        return (q.salvage * (1 + 0.05 * Double(item.level - 1))).rounded(.down)
    }

    static func reforgeCost(_ cfg: GameConfig, _ item: Item, discountLevel: Int, recast: Bool) -> Double {
        let q = cfg.items.qualities[item.qualityIndex(cfg)]
        let base = q.reforge * (1 + 0.05 * Double(item.level - 1))
        let discount = max(0, 1 - cfg.cave.discountPerLevel * Double(discountLevel))
        return max(1, (base * discount * (recast ? cfg.cave.recastMult : 1)).rounded(.up))
    }

    /// 洗练：重新随机一条词条的数值，类型不变。
    static func reforge(_ cfg: GameConfig, _ item: Item, affix k: Int, rng: inout SeededRandom) -> Affix? {
        guard k >= 0, k < item.affixes.count,
              let def = cfg.items.affixes.first(where: { $0.id == item.affixes[k].type }) else { return nil }
        let qual = cfg.items.qualities[item.qualityIndex(cfg)]
        var a = rollAffix(cfg, def, quality: qual, tier: item.level, rng: &rng)
        a.param = item.affixes[k].param
        return a
    }

    /// 重铸：把一条词条换成另一种随机词条，不能和已有的重复。
    static func recast(_ cfg: GameConfig, _ item: Item, affix k: Int, rng: inout SeededRandom) -> Affix? {
        guard k >= 0, k < item.affixes.count else { return nil }
        let have = Set(item.affixes.map(\.type))
        let pool = cfg.items.affixes.filter { ($0.slots.isEmpty || $0.slots.contains(item.slot)) && !have.contains($0.id) }
        guard let i = rng.weightedIndex(pool.map { $0.weight }) else { return nil }
        let qual = cfg.items.qualities[item.qualityIndex(cfg)]
        return rollAffix(cfg, pool[i], quality: qual, tier: item.level, rng: &rng)
    }
}
