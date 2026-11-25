import Foundation

/// 均匀网格（3.3），格子边长默认 64pt。每个逻辑步重建一次。
/// 只按中心点入格，查询时调用方把实体半径算进查询半径。
final class SpatialGrid {
    let cell: Double
    private var buckets: [Int64: [Int32]] = [:]
    private var usedKeys: [Int64] = []

    init(cell: Double = 64) { self.cell = cell }

    @inline(__always)
    private func key(_ cx: Int, _ cy: Int) -> Int64 {
        (Int64(cx) << 32) | Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: cy)))
    }

    @inline(__always)
    private func cellCoord(_ v: Double) -> Int { Int(floor(v / cell)) }

    func clear() {
        for k in usedKeys { buckets[k]?.removeAll(keepingCapacity: true) }
        usedKeys.removeAll(keepingCapacity: true)
    }

    func insert(_ index: Int, at p: Vec2) {
        let k = key(cellCoord(p.x), cellCoord(p.y))
        if buckets[k] == nil { buckets[k] = [] }
        if buckets[k]!.isEmpty { usedKeys.append(k) }
        buckets[k]!.append(Int32(index))
    }

    /// 把中心在 [c - r, c + r] 方框内的所有下标放进 out（先清空 out）。
    /// 结果是候选集，调用方还要自己做精确的圆形判定。
    func query(_ c: Vec2, _ r: Double, into out: inout [Int32]) {
        out.removeAll(keepingCapacity: true)
        let x0 = cellCoord(c.x - r), x1 = cellCoord(c.x + r)
        let y0 = cellCoord(c.y - r), y1 = cellCoord(c.y + r)
        // 查询范围特别大时（比如全屏效果），格子太多，调用方应改为直接遍历。
        for cx in x0...x1 {
            for cy in y0...y1 {
                if let b = buckets[key(cx, cy)], !b.isEmpty { out.append(contentsOf: b) }
            }
        }
    }
}
