import Foundation

/// 法宝上的一条词条（12.4、18.3）。
struct Affix: Codable, Equatable {
    /// 词条 id（items.json 的 affixes）。
    var type: String
    /// 生成时算好的数值。
    var value: Double
    /// 0 到 1，在范围里的位置，用于显示百分位。
    var roll: Double
    /// 元素 id 或流派 id。
    var param: String?
}

/// 一件法宝（12.1、18.3）。
struct Item: Codable, Equatable, Identifiable {
    var id: UUID
    var slot: ItemSlot
    /// 品质 id：fan、ling、bao、xian、shen、hundun。
    var quality: String
    /// 法宝等级，等于掉落时的劫数。
    var level: Int
    var name: String
    var mainAtk: Double
    var mainHp: Double
    var affixes: [Affix]
    var legendary: String?
    var locked: Bool
    var isNew: Bool
    var obtainedAt: Date
}

extension Item {
    /// 品质序号 0 到 5。
    func qualityIndex(_ cfg: GameConfig) -> Int { cfg.items.qualityIndex(quality) }

    /// 这件法宝提供的全部属性（主属性 + 词条）。
    func statMods(_ cfg: GameConfig) -> [StatMod] {
        var mods: [StatMod] = []
        if mainAtk > 0 { mods.append(StatMod(.atkFlat, mainAtk)) }
        if mainHp > 0 { mods.append(StatMod(.hpFlat, mainHp)) }
        for a in affixes {
            guard let def = cfg.items.affixes.first(where: { $0.id == a.type }) else { continue }
            mods.append(StatMod(def.stat, a.value, param: a.param))
        }
        return mods
    }

    /// 词条显示文字，比如"暴击率 +5.5%（88%）"或"火系伤害 +18.0%"。
    static func affixText(_ a: Affix, _ cfg: GameConfig, withRoll: Bool = true) -> String {
        guard let def = cfg.items.affixes.first(where: { $0.id == a.type }) else { return a.type }
        var name = def.name
        if def.param == "element", let p = a.param, let e = Element(rawValue: p) {
            name = cfg.elements.name(e) + def.name
        } else if def.param == "school", let p = a.param, let s = School(rawValue: p) {
            name = cfg.schools.def(s).name + def.name
        }
        let valueText = def.stat.isPercent ? NumberText.percent(a.value) : NumberText.format(a.value)
        let rollText = withRoll ? "（\(Int((a.roll * 100).rounded()))%）" : ""
        return "\(name) +\(valueText)\(rollText)"
    }
}
