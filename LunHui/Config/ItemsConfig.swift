import Foundation

/// 法宝部位（12.1）。
enum ItemSlot: String, Codable, CaseIterable {
    case weapon, robe, pendant, ring
}

/// items.json（12.1 到 12.4）。
struct ItemsConfig: Codable {
    struct Slot: Codable {
        var id: ItemSlot
        var name: String
        var mainAtk: Double
        var mainHp: Double
        var suffixes: [String]
    }
    struct Quality: Codable {
        var id: String
        var name: String
        var color: String
        var factor: Double
        var affixes: Int
        var rollMin: Double
        var rollMax: Double
        var legendary: Bool
        var weight: Double
        /// 从第几劫起掉落（混沌品 30）。
        var minTier: Int
        /// 分解获得洗练石（12.6）。
        var salvage: Double
        /// 洗练基础价（12.6）。
        var reforge: Double
    }
    struct AffixDef: Codable {
        var id: String
        var stat: StatKey
        var name: String
        var min: Double
        var max: Double
        var weight: Double
        var slots: [ItemSlot]
        /// "element" 或 "school"：生成时随机选定参数。
        var param: String?
        /// 固定值类词条，数值再乘 P(法宝等级)。
        var scales: Bool?
    }
    var version: Int
    var slots: [Slot]
    var qualities: [Quality]
    var affixes: [AffixDef]
    var prefixes: [String]
    var drops: DropsConfig
    /// 宝品及以上（品质序号 ≥ 2）的权重 × (1 + magicFind)。
    var magicFindFromQuality: Int

    func slot(_ s: ItemSlot) -> Slot { slots.first { $0.id == s }! }
    func qualityIndex(_ id: String) -> Int { qualities.firstIndex { $0.id == id } ?? 0 }
}
