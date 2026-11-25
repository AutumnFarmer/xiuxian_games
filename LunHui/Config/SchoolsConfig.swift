import Foundation

/// 流派解锁条件（7.1）。
enum SchoolUnlock: String, Codable {
    case initial, firstClear, firstShadowKill
}

/// schools.json 里的一个流派（7.1、7.3）。
struct SchoolDef: Codable {
    var id: School
    var name: String
    var desc: String
    var passive: [StatMod]
    var startSkill: String
    var ultName: String
    var ultDesc: String
    var unlock: SchoolUnlock
    var unlockText: String
    /// 御兽：每个召唤类功法的召唤物数量加成。
    var summonCountBonus: Int?
    /// 御兽：召唤物攻击间隔变化（−0.15 表示 −15%）。
    var summonIntervalPct: Double?
    /// 魔修：心魔值获取系数。
    var heartDemonGain: Double?
    /// 魔修：每 10 点心魔值的全伤害加成。
    var dmgPctPer10Demon: Double?
}

struct SchoolsConfig: Codable {
    var version: Int
    var schools: [SchoolDef]

    func def(_ s: School) -> SchoolDef { schools.first { $0.id == s }! }
}

/// insight.json：顿悟三选一（7.2）。
struct InsightConfig: Codable {
    struct Weights: Codable {
        var skillUp: Double
        var newSkill: Double
        var passiveUp: Double
        var newPassive: Double
    }
    var version: Int
    var cards: Int
    var weights: Weights
    /// 每世前 N 次顿悟保底。
    var guaranteeFirst: Int
    /// 保底时至少几张新功法。
    var guaranteeNewSkills: Int
    var freeRerolls: Int
    /// 补位："灵石袋"每境界序号的灵石，基数 × (1 + 境界序号)。
    var fallbackLingShi: Double
    /// 补位："回春"回复最大生命比例。
    var fallbackHeal: Double
}
