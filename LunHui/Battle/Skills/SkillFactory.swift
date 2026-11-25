import Foundation

/// 按 id 创建功法行为。新功法在这里注册。
enum SkillFactory {
    static let types: [String: SkillBase.Type] = [
        "yujian": YuJianSkill.self,
    ]

    static func make(id: String, slot: Int, level: Int, element: Element, cfg: GameConfig) -> SkillBase? {
        guard let def = cfg.skills.def(id) else { return nil }
        let t = types[id] ?? PlaceholderSkill.self
        return t.init(def: def, slot: slot, level: level, element: element, cfg: cfg)
    }
}

/// 还没实现的功法：什么都不做。
final class PlaceholderSkill: SkillBase {}
