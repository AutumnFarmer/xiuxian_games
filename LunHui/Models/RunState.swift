import Foundation

/// 一世里一个功法的状态（18.4）。
struct SkillState: Codable, Equatable {
    var id: String
    var level: Int
    var element: Element
    var evolved: Bool
}

struct RunStats: Codable, Equatable {
    var kills = 0
    var bestHit = 0.0
    var time = 0.0
}

/// 进行中的一世（18.4）。每关开始和过关时保存。
struct RunState: Codable, Equatable {
    static let currentVersion = 1

    var version = RunState.currentVersion
    var seed: UInt64
    /// 随机流：spawn、loot、insight、event（3.4）。
    var rngStates: [String: UInt64]
    var tier: Int
    var school: School
    var lingGen: LingGen
    var themeOrder: [String]
    var dungeonAffixes: [String]
    var pills: [String]
    /// 出发时的 4 件装备，一世内换装后同步更新。
    var equippedSnapshot: [Item]
    /// 即将开始的关卡序号 0 到 14。
    var stageIndex = 0
    var level = 1
    var exp = 0.0
    var hp = 0.0
    var skills: [SkillState] = []
    /// 心法 id → 等级。顺序见 passiveOrder。
    var passives: [String: Int] = [:]
    var passiveOrder: [String] = []
    /// 已选机缘 id，用于重算属性。
    var events: [String] = []
    var heartDemon = 0
    var ultCharge = 0.0
    var revivesLeft = 1
    var usedRevive = false
    var rerollsLeft = 2
    var pendingInsights = 0
    /// 已经完成的顿悟次数（7.2 的保底用）。
    var insightsDone = 0
    /// 过关后待选的机缘卡，选完清空。
    var pendingEventChoices: [String]?
    /// 双灵根、五行灵根：功法第一次出现时定下的元素（6.5）。
    var skillElements: [String: Element] = [:]
    var loot: [Item] = []
    var lingShiGained = 0.0
    var stats = RunStats()
    /// 影子关已击败（第 10 章）。
    var shadowKilled = false
    var finished = false
    var cleared = false

    var realm: Int { min(4, stageIndex / 3) }
}

/// 一世结束时交给结算的数据（第 15 章）。
struct RunResult: Equatable {
    var tier: Int
    var school: School
    var lingGen: LingGen
    var stagesDone: Int
    var level: Int
    var kills: Int
    var bestHit: Double
    var time: Double
    var cleared: Bool
    var shadowKilled: Bool
    var usedRevive: Bool
    var lingShi: Double
    var loot: [Item]
    var heartDemon: Int
    /// 结束时身上的装备 id。一世内换上的新法宝，结算后保持装备。
    var equippedSnapshotIds: [UUID] = []
}
