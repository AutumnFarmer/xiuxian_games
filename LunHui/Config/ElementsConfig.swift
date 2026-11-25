import Foundation

/// elements.json（6.1 到 6.4）。
struct ElementsConfig: Codable {
    struct Def: Codable {
        var id: Element
        var name: String
        var color: String
        var statusName: String
    }
    struct Flaw: Codable { var vulnPerStack: Double; var maxStacks: Int; var duration: Double }
    struct Entangle: Codable { var duration: Double; var eliteDuration: Double; var bossSlow: Double; var bossSlowDuration: Double }
    struct Slow: Codable { var amount: Double; var maxAmount: Double; var duration: Double }
    struct Burn: Codable { var tickPct: Double; var ticks: Int; var interval: Double }
    struct Stun: Codable { var duration: Double; var eliteDuration: Double; var bossVuln: Double; var bossVulnDuration: Double }
    struct Shock: Codable { var pct: Double; var targets: Int; var radius: Double; var markDuration: Double }
    struct Freeze: Codable { var duration: Double; var eliteDuration: Double; var shatterRadius: Double; var shatterMult: Double }
    struct Status: Codable {
        var flaw: Flaw
        var entangle: Entangle
        var slow: Slow
        var burn: Burn
        var stun: Stun
        var shock: Shock
        var freeze: Freeze
    }

    var version: Int
    var elements: [Def]
    var counters: [String: [Element]]
    var generates: [String: Element]
    var status: Status

    // 运行时查表，启动时由 GameConfig 调 prepare() 生成。
    private(set) var counterMatrix: [[Bool]] = []
    private(set) var generatesOf: [Element?] = []

    enum CodingKeys: String, CodingKey { case version, elements, counters, generates, status }

    mutating func prepare() {
        counterMatrix = Array(repeating: Array(repeating: false, count: 7), count: 7)
        for (k, list) in counters {
            guard let a = Element(rawValue: k) else { continue }
            for t in list { counterMatrix[a.index][t.index] = true }
        }
        generatesOf = Array(repeating: nil, count: 7)
        for (k, v) in generates {
            if let a = Element(rawValue: k) { generatesOf[a.index] = v }
        }
    }

    /// 攻击元素 a 是否克制目标元素 t（6.2）。
    func counters(_ a: Element, _ t: Element) -> Bool { counterMatrix[a.index][t.index] }

    /// 带着元素 s 状态的目标，被元素 h 命中时是否触发相生（6.3）。都按本体算。
    func generates(statusElement s: Element, hit h: Element) -> Bool {
        generatesOf[s.base.index] == h.base
    }

    func def(_ e: Element) -> Def { elements.first { $0.id == e }! }
    func name(_ e: Element) -> String { def(e).name }
    func color(_ e: Element) -> String { def(e).color }
}

extension Element {
    var index: Int {
        switch self {
        case .metal: return 0
        case .wood: return 1
        case .water: return 2
        case .fire: return 3
        case .earth: return 4
        case .thunder: return 5
        case .ice: return 6
        }
    }

    static func fromIndex(_ i: Int) -> Element { allCases[i] }
}
