import Foundation

/// settlement.json（第 15 章）。
struct SettlementConfig: Codable {
    var version: Int
    var suHuiPerStage: Double
    var suHuiPerLevel: Double
    var suHuiClear: Double
    var suHuiTierBonus: Double
    var lingSuiBase: Double
    var lingSuiPerStage: Double
    var lingSuiTierBonus: Double
    var lingSuiClearMult: Double
    var lingSuiMin: Double
    var tierUnlockClear: Int
    var tierUnlockNoRevive: Int
    var autoSalvageQualities: [String]
}

/// cave.json（第 14 章）。
struct CaveConfig: Codable {
    struct DaoXinPoint: Codable {
        var id: String
        var name: String
        var stat: StatKey
        var value: Double
        var scales: Bool?
    }
    struct DaoXin: Codable {
        var costBase: Double
        var costGrowth: Double
        var points: [DaoXinPoint]
    }
    struct Upgrade: Codable {
        var id: String
        var building: String
        var name: String
        var desc: String
        /// 0 表示没有上限。
        var max: Int
        var costBase: Double
        /// 花费 = costBase × N^costPow，N 是要升到的等级。
        var costPow: Double

        func cost(toLevel n: Int) -> Double { costBase * pow(Double(n), costPow) }
    }
    struct Pill: Codable {
        var id: String
        var name: String
        var desc: String
        var price: Double
        var mods: [StatMod]?
        var demon: Int?
    }
    var version: Int
    var daoxin: DaoXin
    var upgrades: [Upgrade]
    var pills: [Pill]
    var pillPriceTierBonus: Double
    var maxPills: Int
    var baseCapacity: Int
    var capacityPerLevel: Int
    var discountPerLevel: Double
    var recastMult: Double

    func upgrade(_ id: String) -> Upgrade? { upgrades.first { $0.id == id } }
    func pill(_ id: String) -> Pill? { pills.first { $0.id == id } }

    /// 道心升到下一级所需宿慧（14.2）。
    func daoXinCost(level d: Int) -> Double { (daoxin.costBase * pow(daoxin.costGrowth, Double(d))).rounded(.down) }
}

/// events.json（9.2）。
struct EventDef: Codable {
    var id: String
    var name: String
    var weight: Double
    var desc: String
    var demon: Int
    var healFull: Bool?
    var mods: [StatMod]?
    var insights: Int?
    var costPerRealm: Double?
    /// 获得 1 件法宝，品质下限（品质序号）。
    var item: Int?
    var hpLoss: Double?
    var minDemon: Int?
}

struct EventsConfig: Codable {
    var version: Int
    var choices: Int
    var events: [EventDef]

    func def(_ id: String) -> EventDef? { events.first { $0.id == id } }
}

/// benming.json（第 13 章）。
struct BenmingConfig: Codable {
    struct Shape: Codable { var id: String; var name: String }
    struct Awakening: Codable {
        var id: String
        var name: String
        var desc: String
        var mods: [StatMod]?
        var randomElement: Bool?
        var strikeCdr: Double?
        var strikeDmg: Double?
    }
    struct ColorStep: Codable { var from: Int; var color: String }
    var version: Int
    var costBase: Double
    var costPerLevel: Double
    var multPerLevel: Double
    var strikeBase: Double
    var strikePerLevel: Double
    var strikeInterval: Double
    var strikeRadius: Double
    var strikeRange: Double
    var strikeMinInterval: Double
    var strikeStatusChance: Double
    var awakenEvery: Int
    var awakenChoices: Int
    var nameMaxLength: Int
    var shapes: [Shape]
    var awakenings: [Awakening]
    var colors: [ColorStep]

    /// 升到下一级所需灵髓（13.2）。
    func cost(level l: Int) -> Double { costBase + costPerLevel * Double(l) }
    /// 本命倍率（13.3）。
    func mult(level l: Int) -> Double { 1 + multPerLevel * Double(l - 1) }
    func strikeMult(level l: Int) -> Double { strikeBase + strikePerLevel * Double(l - 1) }
    func awakening(_ id: String) -> Awakening? { awakenings.first { $0.id == id } }
    func color(level l: Int) -> String { colors.last { l >= $0.from }?.color ?? "#E0E0E0" }
}

/// heartDemon.json（第 10 章）。
struct HeartDemonConfig: Codable {
    struct Band: Codable {
        var from: Int
        var name: String
        var exp: Double
        var drop: Double
        var mf: Double
        var ls: Double
        var color: String
    }
    var version: Int
    var max: Int
    var shadowAt: Int
    var bands: [Band]
    var shadowStrengthPer: Double
    var shadowHpMult: Double
    var shadowSkillDmg: Double
    var shadowTelegraph: Double
    var shadowUltInterval: Double
    var shadowSummonPenalty: Double
    var shadowRewardMult: Double
    var shadowExtraItemQuality: Int
    var shadowHundunChance: Double
    var shadowOrbit: Double
    var shadowSpeedFactor: Double
    var shadowMinionRate: Double

    func band(_ v: Int) -> Band { bands.last { v >= $0.from } ?? bands[0] }
    /// 心魔强度系数（10.3）。
    func shadowStrength(_ v: Int) -> Double { 1 + Double(Swift.max(0, v - shadowAt)) * shadowStrengthPer }
}

/// dungeonAffixes.json（9.3）。
struct DungeonAffixDef: Codable {
    var id: String
    var name: String
    var kind: String
    var desc: String
    var elemMult: [String: Double]?
    var shockMult: Double?
    var shatterMult: Double?
    var mods: [StatMod]?
    var dropFactor: Double?
    var minionExplode: Bool?
    var eliteMult: Double?
    var spawnMult: Double?
    var hpMult: Double?
    var atkMult: Double?
    var speedMult: Double?
    var reward: Double?
    var rewardExp: Double?

    var isBuff: Bool { kind == "buff" }
}

struct DungeonAffixesConfig: Codable {
    var version: Int
    var previewCount: Int
    var lowTierCount: Int
    var highTierCount: Int
    var highTierFrom: Int
    var freeRerolls: Int
    var affixes: [DungeonAffixDef]

    func def(_ id: String) -> DungeonAffixDef? { affixes.first { $0.id == id } }
    func activeCount(tier: Int) -> Int { tier >= highTierFrom ? highTierCount : lowTierCount }
}

/// legendaries.json（12.5）。
struct LegendaryDef: Codable {
    var id: String
    var name: String
    var skill: String?
    var desc: String
    var params: [String: Double]
}

struct LegendariesConfig: Codable {
    var version: Int
    var schoolBias: Double
    var legendaries: [LegendaryDef]

    func def(_ id: String) -> LegendaryDef? { legendaries.first { $0.id == id } }
}

/// fx.json（第 16 章）。
struct FXConfig: Codable {
    struct DamageText: Codable {
        var rise: Double
        var life: Double
        var normalSize: Double
        var critSize: Double
        var dotSize: Double
        var critPop: Double
        var mergeWindow: Double
        var max: Int
    }
    struct Shake: Codable { var amp: Double; var time: Double }
    struct Haptic: Codable { var minInterval: Double }
    struct DropFX: Codable {
        var pillar: Double
        var ring: Bool
        var hitStop: Double
        var banner: String
        var haptic: Int
    }
    struct Pieces: Codable { var minion: Int; var elite: Int; var boss: Int; var maxFullPerFrame: Int }
    var version: Int
    var damageText: DamageText
    var shake: [Shake]
    var haptic: Haptic
    var drops: [DropFX]
    var deathPieces: Pieces
    var levelBanner: Double
    var realmBanner: Double
}
