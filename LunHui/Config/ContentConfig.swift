import Foundation

/// enemies.json（8.2 到 8.4）。
struct EnemiesConfig: Codable {
    struct Realm: Codable {
        var id: String
        var name: String
        var hp: Double
        var atk: Double
        var bossHp: Double
    }
    struct TypeDef: Codable {
        var id: String
        var name: String
        var hpMult: Double
        var atkMult: Double
        var speed: Double
        var radius: Double
        /// 是否参与普通刷怪（realmWeights 按这些类型的顺序）。
        var minion: Bool
        var shape: String
        var params: [String: Double]?
    }
    struct RealmWeights: Codable { var weights: [Double] }
    struct Elite: Codable {
        var base: String
        var hpMult: Double
        var atkMult: Double
        var speed: Double
        var radius: Double
        var expMult: Double
        var twoAffixesFromTier: Int
    }
    struct EliteAffix: Codable {
        var id: String
        var name: String
        var params: [String: Double]
    }

    var version: Int
    var realms: [Realm]
    var types: [TypeDef]
    var realmWeights: [RealmWeights]
    var elite: Elite
    var eliteAffixes: [EliteAffix]
    var bossExpMult: Double

    var minionTypes: [TypeDef] { types.filter { $0.minion } }
    func type(_ id: String) -> TypeDef { types.first { $0.id == id }! }
}

/// spawn.json（8.5）。
struct SpawnConfig: Codable {
    struct Normal: Codable {
        var startRateBase: Double
        var startRatePerRealm: Double
        var endRateBase: Double
        var endRatePerRealm: Double
        var eliteTimes: [Double]
        var hordeTime: Double
        var hordeCount: Int
        var hordeRadius: Double
    }
    struct Boss: Codable {
        var preludeRateBase: Double
        var preludeRatePerRealm: Double
        var eliteTime: Double
        var afterRate: Double
    }
    var version: Int
    var normal: Normal
    var boss: Boss
    var groupMin: Int
    var groupMax: Int
    var groupSpread: Double
    var offscreenMargin: Double
}

/// bosses.json（8.6 到 8.8）。
struct BossMove: Codable {
    var kind: String
    var name: String
    var p: [String: Double]

    func v(_ k: String, _ d: Double = 0) -> Double { p[k] ?? d }
}

struct BossesConfig: Codable {
    struct RealmBoss: Codable {
        var id: String
        var name: String
        var radius: Double
        var moves: [BossMove]
    }
    struct Common: Codable {
        var moveInterval: Double
        var enragedInterval: Double
        var enrageAt: Double
        var enrageProjMult: Double
        var chaseSpeed: Double
    }
    struct Tribulation: Codable {
        var waves: Int
        var waveDuration: Double
        var boltsPerSecond: [Double]
        var aimedOnLastWave: Bool
        var boltRadius: Double
        var boltTelegraph: Double
        var boltMult: Double
        var spiritsPerWave: Int
        var spiritHpMult: Double
        var spiritAtkMult: Double
        var spiritSpeed: Double
        var spiritRadius: Double
        var progressPerSpirit: Double
        var progressPerWave: Double
    }
    var version: Int
    var common: Common
    var realmBosses: [RealmBoss]
    var tribulation: Tribulation
}

/// themes.json（9.1）。
struct ThemeDef: Codable {
    var id: String
    var name: String
    var element: Element
    var bg: String
    var deco: String
}

struct ThemesConfig: Codable {
    var version: Int
    var themes: [ThemeDef]

    func def(_ id: String) -> ThemeDef { themes.first { $0.id == id } ?? themes[0] }
}
