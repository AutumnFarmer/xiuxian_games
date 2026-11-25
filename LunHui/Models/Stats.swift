import Foundation

/// 流派（7.1）。
enum School: String, Codable, CaseIterable {
    case sword, magic, body, beast, demon

    var index: Int { School.allCases.firstIndex(of: self)! }
}

/// 属性 id（5.2、12.4）。词条、心法、丹药、道心、机缘都用这一套。
enum StatKey: String, Codable, CaseIterable {
    case atkFlat, hpFlat, atkPct, hpPct, critRate, critDmg, dmgPct, elemPct, schoolPct, elitePct
    case cdr, area, duration, projSpeed, projCount, moveSpeed, pickup, dmgReduce, regen, lifesteal
    case statusChance, statusPower, magicFind, lingShiPct, expPct, revive
}

/// 一条属性修改：stat + 数值，elemPct / schoolPct 带 param（元素或流派 id）。
struct StatMod: Codable, Equatable {
    var stat: StatKey
    var value: Double
    var param: String?

    init(_ stat: StatKey, _ value: Double, param: String? = nil) {
        self.stat = stat
        self.value = value
        self.param = param
    }
}

/// 属性来源的累加器（5.3）。同一属性的所有来源一律相加。
struct StatBlock: Equatable {
    var v = [Double](repeating: 0, count: StatKey.allCases.count)
    var elem = [Double](repeating: 0, count: 7)
    var school = [Double](repeating: 0, count: 5)

    subscript(_ k: StatKey) -> Double {
        get { v[k.ordinal] }
        set { v[k.ordinal] = newValue }
    }

    mutating func add(_ k: StatKey, _ value: Double, param: String? = nil) {
        switch k {
        case .elemPct:
            if let p = param, let e = Element(rawValue: p) { elem[e.index] += value }
        case .schoolPct:
            if let p = param, let s = School(rawValue: p) { school[s.index] += value }
        default:
            v[k.ordinal] += value
        }
    }

    mutating func add(_ m: StatMod, times: Double = 1) { add(m.stat, m.value * times, param: m.param) }
    mutating func add(_ mods: [StatMod], times: Double = 1) { for m in mods { add(m, times: times) } }

    static func + (a: StatBlock, b: StatBlock) -> StatBlock {
        var r = a
        for i in r.v.indices { r.v[i] += b.v[i] }
        for i in r.elem.indices { r.elem[i] += b.elem[i] }
        for i in r.school.indices { r.school[i] += b.school[i] }
        return r
    }
}

extension StatKey {
    var ordinal: Int { StatKey.allCases.firstIndex(of: self)! }

    /// 是否按百分比显示。
    var isPercent: Bool {
        switch self {
        case .atkFlat, .hpFlat, .projCount, .revive: return false
        default: return true
        }
    }
}

/// 汇总后的最终属性（5.2、5.3）。百分比都是小数。
struct PlayerStats: Equatable {
    var atk = 100.0
    var hp = 1000.0
    var critRate = 0.05
    var critDmg = 1.5
    var dmgPct = 0.0
    var elemPct = [Double](repeating: 0, count: 7)
    var schoolPct = [Double](repeating: 0, count: 5)
    var elitePct = 0.0
    var cdr = 0.0
    var area = 1.0
    var duration = 1.0
    var projCount = 0
    var projSpeed = 1.0
    var moveSpeed = 160.0
    var pickup = 80.0
    var dmgReduce = 0.0
    var regen = 0.0
    var lifesteal = 0.0
    var statusChance = 0.0
    var statusPower = 0.0
    var magicFind = 0.0
    var lingShiPct = 0.0
    var expPct = 0.0
    var revive = 1

    /// 按 5.3 的公式汇总。levelFactor 见 4.6，benmingMult 见 13.3。
    static func finalize(_ b: StatBlock, cfg: StatsConfig, levelFactor: Double, benmingMult: Double) -> PlayerStats {
        var s = PlayerStats()
        let i = cfg.initial, c = cfg.caps
        s.atk = (i.atk + b[.atkFlat]) * levelFactor * (1 + b[.atkPct]) * benmingMult
        s.hp = (i.hp + b[.hpFlat]) * levelFactor * (1 + b[.hpPct]) * benmingMult
        s.critRate = i.critRate + b[.critRate]
        s.critDmg = i.critDmg + b[.critDmg]
        s.dmgPct = b[.dmgPct]
        s.elemPct = b.elem
        s.schoolPct = b.school
        s.elitePct = b[.elitePct]
        s.cdr = min(c.cdr, max(0, b[.cdr]))
        s.area = max(0.1, 1 + b[.area])
        s.duration = max(0.1, 1 + b[.duration])
        s.projCount = Int(b[.projCount].rounded(.down))
        s.projSpeed = max(0.1, 1 + b[.projSpeed])
        s.moveSpeed = min(c.moveSpeed, i.moveSpeed * max(0.1, 1 + b[.moveSpeed]))
        s.pickup = i.pickup * max(0.1, 1 + b[.pickup])
        s.dmgReduce = min(c.dmgReduce, max(0, b[.dmgReduce]))
        s.regen = b[.regen]
        s.lifesteal = b[.lifesteal]
        s.statusChance = b[.statusChance]
        s.statusPower = b[.statusPower]
        s.magicFind = b[.magicFind]
        s.lingShiPct = b[.lingShiPct]
        s.expPct = b[.expPct]
        s.revive = i.revive + Int(b[.revive].rounded(.down))
        return s
    }
}
