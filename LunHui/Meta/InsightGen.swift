import Foundation

/// 一张顿悟卡（7.2）。
enum InsightCard: Equatable {
    case evolution(skill: String, evo: String)
    case skillUp(String)
    case newSkill(String, Element)
    case passiveUp(String)
    case newPassive(String)
    case lingShi(Double)
    case heal(Double)

    var key: String {
        switch self {
        case .evolution(let s, _): return "ev:" + s
        case .skillUp(let s): return "su:" + s
        case .newSkill(let s, _): return "ns:" + s
        case .passiveUp(let p): return "pu:" + p
        case .newPassive(let p): return "np:" + p
        case .lingShi: return "ls"
        case .heal: return "heal"
        }
    }
}

/// 卡面显示用的文字。
struct InsightCardText {
    var title: String
    var subtitle: String
    var detail: String
    var isNew: Bool
    var isEvolution: Bool
    var element: Element?
}

enum InsightGen {
    /// 生成一次顿悟的卡（7.2）。
    static func cards(_ cfg: GameConfig, run: RunState, cardCount: Int, rng: inout SeededRandom) -> [InsightCard] {
        let maxLv = cfg.skills.maxLevel
        var out: [InsightCard] = []
        if let ev = availableEvolution(cfg, run: run) { out.append(ev) }

        let pool = cfg.skills.pool(for: run.school)
        let learned = Set(run.skills.map(\.id))
        let upgradable = run.skills.filter { !$0.evolved && $0.level < maxLv }.map(\.id)
        let unlearned = pool.map(\.id).filter { !learned.contains($0) }
        let passUp = run.passiveOrder.filter { (run.passives[$0] ?? 0) < maxLv }
        let passNew = cfg.passives.passives.map(\.id).filter { run.passives[$0] == nil }
        let skillSlotsFree = run.skills.count < cfg.skills.maxSkills
        let passiveSlotsFree = run.passives.count < cfg.skills.maxPassives

        func element(for id: String) -> Element {
            if let e = run.skillElements[id] { return e }
            var r = rng
            let e = run.lingGen.rollSkillElement(&r)
            rng = r
            return e
        }

        // 保底：每世前 2 次顿悟，至少 2 张新功法。
        if run.insightsDone < cfg.insight.guaranteeFirst, skillSlotsFree {
            var candidates = unlearned
            rng.shuffle(&candidates)
            for id in candidates.prefix(cfg.insight.guaranteeNewSkills) where out.count < cardCount {
                out.append(.newSkill(id, element(for: id)))
            }
        }

        let w = cfg.insight.weights
        var attempts = 0
        while out.count < cardCount, attempts < 60 {
            attempts += 1
            var kinds: [(Double, Int)] = []
            if !upgradable.isEmpty { kinds.append((w.skillUp, 0)) }
            if skillSlotsFree, !unlearned.isEmpty { kinds.append((w.newSkill, 1)) }
            if !passUp.isEmpty { kinds.append((w.passiveUp, 2)) }
            if passiveSlotsFree, !passNew.isEmpty { kinds.append((w.newPassive, 3)) }
            guard let k = rng.weightedIndex(kinds.map { $0.0 }) else { break }
            let card: InsightCard?
            switch kinds[k].1 {
            case 0: card = rng.pick(upgradable).map { .skillUp($0) }
            case 1: card = rng.pick(unlearned).map { .newSkill($0, element(for: $0)) }
            case 2: card = rng.pick(passUp).map { .passiveUp($0) }
            default: card = rng.pick(passNew).map { .newPassive($0) }
            }
            if let c = card, !out.contains(where: { $0.key == c.key }) { out.append(c) }
        }
        // 补位（7.2）
        if out.count < cardCount {
            let realm = Double(run.realm)
            for c in [InsightCard.lingShi(cfg.insight.fallbackLingShi * (1 + realm)), .heal(cfg.insight.fallbackHeal)]
                where out.count < cardCount && !out.contains(where: { $0.key == c.key }) {
                out.append(c)
            }
        }
        return out
    }

    /// 满 5 级的功法且学了对应心法（7.8）。按功法栏顺序，每次只出一个。
    static func availableEvolution(_ cfg: GameConfig, run: RunState) -> InsightCard? {
        for s in run.skills where !s.evolved && s.level >= cfg.skills.maxLevel {
            if let ev = cfg.evolutions.forSkill(s.id), run.passives[ev.passive] != nil {
                return .evolution(skill: s.id, evo: ev.id)
            }
        }
        return nil
    }

    /// 把选中的卡应用到 RunState。返回需要立即发放的灵石或回血比例。
    static func apply(_ card: InsightCard, to run: inout RunState) -> (lingShi: Double, heal: Double) {
        run.insightsDone += 1
        switch card {
        case .evolution(let s, _):
            if let i = run.skills.firstIndex(where: { $0.id == s }) { run.skills[i].evolved = true }
        case .skillUp(let s):
            if let i = run.skills.firstIndex(where: { $0.id == s }) { run.skills[i].level += 1 }
        case .newSkill(let s, let e):
            run.skillElements[s] = e
            run.skills.append(SkillState(id: s, level: 1, element: e, evolved: false))
        case .passiveUp(let p):
            run.passives[p, default: 0] += 1
        case .newPassive(let p):
            run.passives[p] = 1
            run.passiveOrder.append(p)
        case .lingShi(let v):
            return (v, 0)
        case .heal(let h):
            return (0, h)
        }
        return (0, 0)
    }

    static func text(_ cfg: GameConfig, _ card: InsightCard, run: RunState) -> InsightCardText {
        switch card {
        case .evolution(let s, let evId):
            let ev = cfg.evolutions.evolutions.first { $0.id == evId }
            let name = cfg.skills.def(s)?.name ?? s
            return InsightCardText(title: ev?.name ?? "神通", subtitle: "神通·\(name)", detail: ev?.desc ?? "",
                                   isNew: false, isEvolution: true, element: run.skills.first { $0.id == s }?.element)
        case .skillUp(let s):
            let d = cfg.skills.def(s)
            let lv = run.skills.first { $0.id == s }?.level ?? 1
            return InsightCardText(title: d?.name ?? s, subtitle: "Lv.\(lv) → Lv.\(lv + 1)",
                                   detail: d?.levelDesc[safe: lv] ?? "", isNew: false, isEvolution: false,
                                   element: run.skills.first { $0.id == s }?.element)
        case .newSkill(let s, let e):
            let d = cfg.skills.def(s)
            let school = d?.school.map { cfg.schools.def($0).name } ?? "通用"
            return InsightCardText(title: d?.name ?? s, subtitle: "新功法 · \(school) · \(cfg.elements.name(e))",
                                   detail: d?.desc ?? "", isNew: true, isEvolution: false, element: e)
        case .passiveUp(let p):
            let d = cfg.passives.def(p)
            let lv = run.passives[p] ?? 1
            return InsightCardText(title: d?.name ?? p, subtitle: "心法 Lv.\(lv) → Lv.\(lv + 1)",
                                   detail: modsText(cfg, d?.stepMods(level: lv + 1) ?? []), isNew: false, isEvolution: false, element: nil)
        case .newPassive(let p):
            let d = cfg.passives.def(p)
            return InsightCardText(title: d?.name ?? p, subtitle: "新心法",
                                   detail: modsText(cfg, d?.stepMods(level: 1) ?? []), isNew: true, isEvolution: false, element: nil)
        case .lingShi(let v):
            return InsightCardText(title: "灵石袋", subtitle: "补位", detail: "获得 \(NumberText.format(v)) 灵石",
                                   isNew: false, isEvolution: false, element: nil)
        case .heal(let h):
            return InsightCardText(title: "回春", subtitle: "补位", detail: "回复 \(Int(h * 100))% 最大生命",
                                   isNew: false, isEvolution: false, element: nil)
        }
    }

    static func modsText(_ cfg: GameConfig, _ mods: [StatMod]) -> String {
        mods.map { StatText.mod(cfg, $0) }.joined(separator: "，")
    }
}

/// 属性名和数值的显示。
enum StatText {
    static let names: [StatKey: String] = [
        .atkFlat: "攻击", .hpFlat: "生命", .atkPct: "攻击", .hpPct: "生命", .critRate: "暴击率", .critDmg: "暴击伤害",
        .dmgPct: "全伤害", .elemPct: "系伤害", .schoolPct: "伤害", .elitePct: "精英与 Boss 伤害", .cdr: "冷却缩减",
        .area: "范围", .duration: "持续时间", .projSpeed: "弹速", .projCount: "额外投射物", .moveSpeed: "移速",
        .pickup: "拾取范围", .dmgReduce: "减伤", .regen: "生命回复", .lifesteal: "吸血", .statusChance: "状态几率",
        .statusPower: "状态效果", .magicFind: "寻宝", .lingShiPct: "灵石获取", .expPct: "修为获取", .revive: "复活次数",
    ]

    static func mod(_ cfg: GameConfig, _ m: StatMod) -> String {
        var name = names[m.stat] ?? m.stat.rawValue
        if m.stat == .elemPct, let p = m.param, let e = Element(rawValue: p) { name = cfg.elements.name(e) + name }
        if m.stat == .schoolPct, let p = m.param, let s = School(rawValue: p) { name = cfg.schools.def(s).name + name }
        let v = m.stat.isPercent ? NumberText.percent(m.value) : NumberText.format(m.value)
        return "\(name) +\(v)"
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { i >= 0 && i < count ? self[i] : nil }
}
