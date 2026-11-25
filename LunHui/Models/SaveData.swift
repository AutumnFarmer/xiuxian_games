import Foundation

/// 本命法宝（第 13 章、18.3）。
struct Benming: Codable, Equatable {
    /// 为空表示还没选外形，启动时进入 firstLaunch。
    var shape: String?
    var name: String = "本命法宝"
    var level: Int = 1
    /// 已选觉醒。带元素的写成 "bm_elem:fire"。可以重复。
    var awakenings: [String] = []
    /// 待选的觉醒，每组 3 个。
    var pendingAwakenings: [[String]] = []
}

/// 下一世的预览（4.1、18.3）。
struct RunPreview: Codable, Equatable {
    var themeOrder: [String]
    var dungeonAffixes: [String]
    var lingGenChoices: [LingGen]
    var lingGenRerollUsed: Bool
    var affixRerollUsed: Bool
}

/// 纪录（15.2）。
struct Records: Codable, Equatable {
    var bestHit: Double = 0
    var maxTierCleared: Int = 0
    var maxKillsInRun: Int = 0
    var totalRuns: Int = 0
    var totalKills: Int = 0
    var firstClearDone: Bool = false
    var firstShadowKillDone: Bool = false

    init() {}

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        bestHit = try c.decodeIfPresent(Double.self, forKey: .bestHit) ?? 0
        maxTierCleared = try c.decodeIfPresent(Int.self, forKey: .maxTierCleared) ?? 0
        maxKillsInRun = try c.decodeIfPresent(Int.self, forKey: .maxKillsInRun) ?? 0
        totalRuns = try c.decodeIfPresent(Int.self, forKey: .totalRuns) ?? 0
        totalKills = try c.decodeIfPresent(Int.self, forKey: .totalKills) ?? 0
        firstClearDone = try c.decodeIfPresent(Bool.self, forKey: .firstClearDone) ?? false
        firstShadowKillDone = try c.decodeIfPresent(Bool.self, forKey: .firstShadowKillDone) ?? false
    }
}

/// 设置（17.7）。
struct Settings: Codable, Equatable {
    enum DamageText: String, Codable, CaseIterable { case all, crit, off }
    var damageText: DamageText = .all
    var screenShake = true
    var haptics = true
    var sound = true
    /// 结算时自动分解凡品和灵品（12.6）。
    var autoSalvageLow = true

    init() {}

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        damageText = try c.decodeIfPresent(DamageText.self, forKey: .damageText) ?? .all
        screenShake = try c.decodeIfPresent(Bool.self, forKey: .screenShake) ?? true
        haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? true
        sound = try c.decodeIfPresent(Bool.self, forKey: .sound) ?? true
        autoSalvageLow = try c.decodeIfPresent(Bool.self, forKey: .autoSalvageLow) ?? true
    }
}

/// 局外存档（18.3）。新增字段一律给默认值，老存档能直接解码（18.2）。
struct SaveData: Codable, Equatable {
    static let currentVersion = 1

    var version = SaveData.currentVersion
    var createdAt = Date()
    var lingShi = 0.0
    var suHui = 0.0
    var lingSui = 0.0
    var xiLianShi = 0.0
    var maxTierUnlocked = 1
    var unlockedSchools: [String] = ["sword", "magic", "body"]
    var items: [Item] = []
    var equipped: [String: UUID] = [:]
    var benming = Benming()
    var daoXinLevel = 0
    var daoXinPoints: [String: Int] = [:]
    var buildings: [String: Int] = [:]
    var nextRunPreview: RunPreview
    var records = Records()
    var settings = Settings()
    var hasActiveRun = false
    /// 出发准备界面上次的选择，方便下次直接出发。
    var lastTier = 1
    var lastSchool = "sword"
    var lastPills: [String] = []

    init(preview: RunPreview) {
        nextRunPreview = preview
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        lingShi = try c.decodeIfPresent(Double.self, forKey: .lingShi) ?? 0
        suHui = try c.decodeIfPresent(Double.self, forKey: .suHui) ?? 0
        lingSui = try c.decodeIfPresent(Double.self, forKey: .lingSui) ?? 0
        xiLianShi = try c.decodeIfPresent(Double.self, forKey: .xiLianShi) ?? 0
        maxTierUnlocked = try c.decodeIfPresent(Int.self, forKey: .maxTierUnlocked) ?? 1
        unlockedSchools = try c.decodeIfPresent([String].self, forKey: .unlockedSchools) ?? ["sword", "magic", "body"]
        items = try c.decodeIfPresent([Item].self, forKey: .items) ?? []
        equipped = try c.decodeIfPresent([String: UUID].self, forKey: .equipped) ?? [:]
        benming = try c.decodeIfPresent(Benming.self, forKey: .benming) ?? Benming()
        daoXinLevel = try c.decodeIfPresent(Int.self, forKey: .daoXinLevel) ?? 0
        daoXinPoints = try c.decodeIfPresent([String: Int].self, forKey: .daoXinPoints) ?? [:]
        buildings = try c.decodeIfPresent([String: Int].self, forKey: .buildings) ?? [:]
        nextRunPreview = try c.decode(RunPreview.self, forKey: .nextRunPreview)
        records = try c.decodeIfPresent(Records.self, forKey: .records) ?? Records()
        settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
        hasActiveRun = try c.decodeIfPresent(Bool.self, forKey: .hasActiveRun) ?? false
        lastTier = try c.decodeIfPresent(Int.self, forKey: .lastTier) ?? 1
        lastSchool = try c.decodeIfPresent(String.self, forKey: .lastSchool) ?? "sword"
        lastPills = try c.decodeIfPresent([String].self, forKey: .lastPills) ?? []
    }

    func building(_ id: String) -> Int { buildings[id] ?? 0 }

    func equippedItem(_ slot: ItemSlot) -> Item? {
        guard let id = equipped[slot.rawValue] else { return nil }
        return items.first { $0.id == id }
    }

    var equippedItems: [Item] { ItemSlot.allCases.compactMap { equippedItem($0) } }

    func isEquipped(_ item: Item) -> Bool { equipped[item.slot.rawValue] == item.id }

    func capacity(_ cfg: GameConfig) -> Int {
        cfg.cave.baseCapacity + cfg.cave.capacityPerLevel * building("lq_capacity")
    }

    var daoXinUnspent: Int { daoXinLevel - daoXinPoints.values.reduce(0, +) }
}
