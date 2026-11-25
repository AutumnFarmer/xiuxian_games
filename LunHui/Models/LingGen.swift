import Foundation

enum LingGenType: String, Codable {
    case single, dual, variant, five
}

/// 灵根（6.5）。elements：单灵根和变异灵根 1 个，双灵根 2 个，五行灵根 5 个。
struct LingGen: Codable, Equatable {
    var type: LingGenType
    var elements: [Element]

    /// 双灵根的两个元素是否相生（金水、水木、木火、火土、土金）。
    func isGeneratingPair(_ cfg: ElementsConfig) -> Bool {
        guard type == .dual, elements.count == 2 else { return false }
        let a = elements[0], b = elements[1]
        return cfg.generates(statusElement: a, hit: b) || cfg.generates(statusElement: b, hit: a)
    }

    /// 克制系数（5.4、6.5）。
    func counterMult(_ cfg: GameConfig) -> Double {
        switch type {
        case .five: return cfg.linggen.fiveCounterMult
        case .dual: return isGeneratingPair(cfg.elements) ? cfg.balance.counterMult : cfg.linggen.dualCounterMult
        default: return cfg.balance.counterMult
        }
    }

    /// 相生加成（6.3、6.5）。
    func generateBonus(_ cfg: GameConfig) -> Double {
        switch type {
        case .five: return cfg.linggen.fiveGeneratingBonus
        case .dual: return isGeneratingPair(cfg.elements) ? cfg.linggen.dualGeneratingBonus : cfg.balance.generateBonus
        default: return cfg.balance.generateBonus
        }
    }

    /// 灵根自带的属性加成。
    func statMods(_ cfg: GameConfig) -> [StatMod] {
        guard let t = cfg.linggen.types.first(where: { $0.id == type }) else { return [] }
        var mods: [StatMod] = []
        if t.elemPct > 0 {
            for e in elements { mods.append(StatMod(.elemPct, t.elemPct, param: e.rawValue)) }
        }
        if t.statusChance > 0 { mods.append(StatMod(.statusChance, t.statusChance)) }
        return mods
    }

    /// 学新功法时随机的元素（6.5）。
    func rollSkillElement(_ rng: inout SeededRandom) -> Element {
        rng.pick(elements) ?? .metal
    }

    func displayName(_ cfg: ElementsConfig) -> String {
        switch type {
        case .single: return "\(cfg.name(elements[0]))灵根"
        case .variant: return "\(cfg.name(elements[0]))灵根·变异"
        case .dual: return elements.map { cfg.name($0) }.joined() + "双灵根"
        case .five: return "五行灵根"
        }
    }

    /// 随机生成一个灵根（6.5 的权重）。
    static func roll(_ cfg: GameConfig, _ rng: inout SeededRandom, excluding: [LingGen] = []) -> LingGen {
        for _ in 0..<50 {
            let types = cfg.linggen.types
            let i = rng.weightedIndex(types.map { $0.weight }) ?? 0
            let g: LingGen
            switch types[i].id {
            case .single:
                g = LingGen(type: .single, elements: [rng.pick(Element.fiveElements)!])
            case .variant:
                g = LingGen(type: .variant, elements: [rng.chance(0.5) ? .thunder : .ice])
            case .dual:
                var five = Element.fiveElements
                rng.shuffle(&five)
                g = LingGen(type: .dual, elements: [five[0], five[1]])
            case .five:
                g = LingGen(type: .five, elements: Element.fiveElements)
            }
            if !excluding.contains(where: { $0.sameAs(g) }) { return g }
        }
        return LingGen(type: .single, elements: [.fire])
    }

    /// 双灵根元素顺序不同也算同一个。
    func sameAs(_ o: LingGen) -> Bool {
        type == o.type && Set(elements) == Set(o.elements)
    }
}

/// linggen.json
struct LingGenConfig: Codable {
    struct TypeDef: Codable {
        var id: LingGenType
        var name: String
        var weight: Double
        var elemPct: Double
        var statusChance: Double
    }
    var version: Int
    var types: [TypeDef]
    var dualGeneratingBonus: Double
    var dualCounterMult: Double
    var fiveGeneratingBonus: Double
    var fiveCounterMult: Double
    var choices: Int
    var freeRerolls: Int
}
