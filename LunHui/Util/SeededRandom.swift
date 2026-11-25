import Foundation

/// SplitMix64 随机数（3.4）。所有随机都走这里，状态可以存档。
struct SeededRandom: Codable, Equatable {
    private(set) var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// [0, 1)
    mutating func nextDouble() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * nextDouble() }

    /// [0, n)
    mutating func int(_ n: Int) -> Int {
        precondition(n > 0, "int(n) 需要 n > 0")
        return Int(next() % UInt64(n))
    }

    mutating func chance(_ p: Double) -> Bool {
        if p >= 1 { return true }
        if p <= 0 { return false }
        return nextDouble() < p
    }

    /// 按权重返回下标；全部权重 ≤ 0 时返回 nil。
    mutating func weightedIndex(_ weights: [Double]) -> Int? {
        let total = weights.reduce(0) { $0 + max(0, $1) }
        guard total > 0 else { return nil }
        var r = nextDouble() * total
        for (i, w) in weights.enumerated() where w > 0 {
            if r < w { return i }
            r -= w
        }
        return weights.lastIndex(where: { $0 > 0 })
    }

    mutating func pick<T>(_ a: [T]) -> T? { a.isEmpty ? nil : a[int(a.count)] }

    mutating func shuffle<T>(_ a: inout [T]) {
        guard a.count > 1 else { return }
        for i in stride(from: a.count - 1, to: 0, by: -1) { a.swapAt(i, int(i + 1)) }
    }

    /// 派生一条独立的随机流。
    mutating func split() -> SeededRandom { SeededRandom(seed: next()) }

    /// 以系统时间为种子（局外的洗练等操作用，3.4）。
    static func fromClock() -> SeededRandom {
        let t = UInt64(Date().timeIntervalSince1970 * 1_000_000)
        var r = SeededRandom(seed: t ^ 0xA5A5_5A5A_DEAD_BEEF)
        _ = r.next()
        return r
    }
}
