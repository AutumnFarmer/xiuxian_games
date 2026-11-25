import Foundation

/// 功法标签（7.4）。target = 索敌，melee = 近战。
enum SkillTag: String, Codable {
    case projectile, target, melee, area, aura, summon
}

/// skills.json 里的一个功法（7.5、7.6）。
struct SkillDef: Codable {
    var id: String
    var name: String
    var school: School?
    var tags: [SkillTag]
    /// 0 表示"—"：一学会就常驻。
    var cooldown: Double
    var baseMult: Double
    var statusChance: Double
    var params: [String: Double]
    /// 第 N 项是升到 N + 1 级时增加的参数，第 1 项为空（19.3）。
    var levels: [[String: Double]]
    var desc: String
    /// 第 N 项是第 N + 1 级的说明，用于顿悟卡面。
    var levelDesc: [String]

    func has(_ t: SkillTag) -> Bool { tags.contains(t) }

    /// 第 level 级的参数：基础参数 + 各级增量累加。
    func params(level: Int) -> [String: Double] {
        var p = params
        for i in 0..<min(max(level, 0), levels.count) {
            for (k, v) in levels[i] { p[k, default: 0] += v }
        }
        return p
    }
}

/// skills.json
struct SkillsConfig: Codable {
    var version: Int
    var growthPerLevel: Double
    var maxLevel: Int
    var maxSkills: Int
    var maxPassives: Int
    var skills: [SkillDef]

    private(set) var index: [String: Int] = [:]
    enum CodingKeys: String, CodingKey { case version, growthPerLevel, maxLevel, maxSkills, maxPassives, skills }

    mutating func prepare() {
        index = [:]
        for (i, s) in skills.enumerated() { index[s.id] = i }
    }

    func def(_ id: String) -> SkillDef? { index[id].map { skills[$0] } }

    /// 7.4：倍率(L) = 1 级倍率 × (1 + 0.25 × (L − 1))
    func mult(_ d: SkillDef, level: Int) -> Double {
        d.baseMult * (1 + growthPerLevel * Double(level - 1))
    }

    /// 本流派 4 个功法 + 通用功法（7.1）。
    func pool(for school: School) -> [SkillDef] {
        skills.filter { $0.school == school || $0.school == nil }
    }
}

/// evolutions.json 里的一个神通（7.8）。
struct EvolutionDef: Codable {
    var id: String
    var name: String
    var skill: String
    var passive: String
    var params: [String: Double]
    var desc: String
}

struct EvolutionsConfig: Codable {
    var version: Int
    var multFactor: Double
    var evolutions: [EvolutionDef]

    func forSkill(_ id: String) -> EvolutionDef? { evolutions.first { $0.skill == id } }
}

/// passives.json 里的一个心法（7.7）。
struct PassiveDef: Codable {
    var id: String
    var name: String
    /// 每级加成。和 levels 二选一。
    var perLevel: [StatMod]?
    /// 每一级单独的加成（比如分光术 2、4 级加投射物），有就优先用。
    var levels: [[StatMod]]?
    var desc: String

    /// 学到第 level 级时的累计加成。
    func mods(level: Int) -> [StatMod] {
        if let levels {
            return levels.prefix(level).flatMap { $0 }
        }
        guard let perLevel else { return [] }
        return perLevel.map { StatMod($0.stat, $0.value * Double(level), param: $0.param) }
    }

    /// 第 level 级这一级本身加了什么（卡面用）。
    func stepMods(level: Int) -> [StatMod] {
        if let levels, level >= 1, level <= levels.count { return levels[level - 1] }
        return perLevel ?? []
    }
}

struct PassivesConfig: Codable {
    var version: Int
    var passives: [PassiveDef]

    func def(_ id: String) -> PassiveDef? { passives.first { $0.id == id } }
}
