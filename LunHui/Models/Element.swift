import Foundation

/// 七种元素（6.1）。雷、冰是变异元素，本体分别是木、水。
enum Element: String, Codable, CaseIterable {
    case metal, wood, water, fire, earth, thunder, ice

    static let fiveElements: [Element] = [.metal, .wood, .water, .fire, .earth]

    /// 变异元素的本体；五行元素返回自己。
    var base: Element {
        switch self {
        case .thunder: return .wood
        case .ice: return .water
        default: return self
        }
    }

    var isVariant: Bool { self == .thunder || self == .ice }
}

/// 元素状态（6.4）。
enum StatusKind: String, Codable, CaseIterable {
    case flaw, entangle, slow, burn, stun, shock, freeze

    var element: Element {
        switch self {
        case .flaw: return .metal
        case .entangle: return .wood
        case .slow: return .water
        case .burn: return .fire
        case .stun: return .earth
        case .shock: return .thunder
        case .freeze: return .ice
        }
    }

    static func of(_ e: Element) -> StatusKind {
        switch e {
        case .metal: return .flaw
        case .wood: return .entangle
        case .water: return .slow
        case .fire: return .burn
        case .earth: return .stun
        case .thunder: return .shock
        case .ice: return .freeze
        }
    }
}

/// 敌我阵营。玩家阵营的攻击打敌人，敌人阵营（含心魔影子）的攻击打玩家。
enum Team: String, Codable {
    case player, enemy
}
