import Foundation

/// balance.json：全局系数（第 4、5、6、11 章）。
struct BalanceConfig: Codable {
    struct Revive: Codable { var radius: Double; var invuln: Double }
    struct LevelWave: Codable { var radius: Double; var mult: Double; var knockback: Double }
    struct Stage: Codable {
        var normalDuration: Double
        var bossPrelude: Double
        var normalHeal: Double
        var clearDuration: Double
        var bossIntro: Double
    }
    struct Caps: Codable {
        var enemies: Int
        var projectiles: Int
        var damageTexts: Int
        var drops: Int
        /// 自定：区域数量上限（文档没写），防止残留区、血河等堆积过多。
        var zones: Int
    }
    struct Ult: Codable { var perKill: Double; var perElite: Double; var perBossPct: Double; var max: Double }
    struct Joystick: Codable { var deadZone: Double; var radius: Double }

    var version: Int
    var tierEnemyBase: Double
    var tierItemBase: Double
    var expNeedBase: Double
    var expNeedPerLevel: Double
    var levelStatPerLevel: Double
    var counterMult: Double
    var counterMultStrong: Double
    var generateBonus: Double
    var generateBonusStrong: Double
    var critOverflowToCritDmg: Double
    var dmgFloatMin: Double
    var dmgFloatMax: Double
    var hitInvuln: Double
    var knockbackTime: Double
    var eliteKnockbackFactor: Double
    var areaTick: Double
    var pickupFlySpeed: Double
    var lifestealCapPerSec: Double
    var targetRange: Double
    var meleeRange: Double
    var enemyNeighborCheck: Int
    var enemyRespawnDistance: Double
    var recommendPowerBase: Double
    var revive: Revive
    var levelWave: LevelWave
    var stage: Stage
    var caps: Caps
    var ult: Ult
    var joystick: Joystick

    /// E(T)，11.1
    func enemyScale(tier: Int) -> Double { pow(tierEnemyBase, Double(max(1, tier) - 1)) }
    /// P(T)，11.1
    func itemScale(tier: Int) -> Double { pow(tierItemBase, Double(max(1, tier) - 1)) }
    /// 4.6
    func expNeed(level: Int) -> Double { expNeedBase + expNeedPerLevel * Double(level - 1) }
    /// 4.6
    func levelFactor(level: Int) -> Double { 1 + levelStatPerLevel * Double(level - 1) }
}

/// stats.json：玩家属性初始值和上限（5.2）。
struct StatsConfig: Codable {
    struct Initial: Codable {
        var atk: Double
        var hp: Double
        var critRate: Double
        var critDmg: Double
        var moveSpeed: Double
        var pickup: Double
        var revive: Int
    }
    struct Caps: Codable {
        var critRate: Double
        var cdr: Double
        var moveSpeed: Double
        var dmgReduce: Double
    }
    var version: Int
    var initial: Initial
    var caps: Caps
}
