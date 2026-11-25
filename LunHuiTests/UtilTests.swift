import XCTest
@testable import LunHui

final class UtilTests: XCTestCase {
    func testNumberText() {
        XCTAssertEqual(NumberText.format(0), "0")
        XCTAssertEqual(NumberText.format(9527), "9527")
        XCTAssertEqual(NumberText.format(9999.4), "9999")
        XCTAssertEqual(NumberText.format(9999.6), "1.0万")
        XCTAssertEqual(NumberText.format(123_456), "12.3万")
        XCTAssertEqual(NumberText.format(99_990_000), "9999.0万")
        XCTAssertEqual(NumberText.format(99_999_600), "1.0亿")
        XCTAssertEqual(NumberText.format(450_000_000), "4.5亿")
        XCTAssertEqual(NumberText.format(6.7e12), "6.7兆")
        XCTAssertEqual(NumberText.format(8.9e16), "8.9京")
        XCTAssertEqual(NumberText.format(1.2e20), "1.2垓")
        XCTAssertEqual(NumberText.format(5e44), "5.0载")
        XCTAssertEqual(NumberText.format(3.2e52), "3.2e52")
        XCTAssertEqual(NumberText.format(-12_345), "-1.2万")
        XCTAssertEqual(NumberText.percent(0.052), "5.2%")
    }

    func testSeededRandomIsDeterministic() {
        var a = SeededRandom(seed: 42)
        var b = SeededRandom(seed: 42)
        for _ in 0..<1000 { XCTAssertEqual(a.next(), b.next()) }
        var c = SeededRandom(seed: 7)
        var sum = 0.0
        for _ in 0..<10_000 {
            let d = c.nextDouble()
            XCTAssertTrue(d >= 0 && d < 1)
            sum += d
        }
        XCTAssertEqual(sum / 10_000, 0.5, accuracy: 0.02)
    }

    func testWeightedIndex() {
        var r = SeededRandom(seed: 1)
        var counts = [0, 0, 0]
        for _ in 0..<30_000 { counts[r.weightedIndex([1, 0, 2])!] += 1 }
        XCTAssertEqual(counts[1], 0)
        XCTAssertEqual(Double(counts[2]) / Double(counts[0]), 2, accuracy: 0.1)
        XCTAssertNil(r.weightedIndex([0, 0]))
    }

    func testSpatialGridFindsNeighbours() {
        let g = SpatialGrid(cell: 64)
        let pts = [Vec2(0, 0), Vec2(70, 0), Vec2(-200, 300), Vec2(10, -10)]
        for (i, p) in pts.enumerated() { g.insert(i, at: p) }
        var out: [Int32] = []
        g.query(Vec2(0, 0), 20, into: &out)
        XCTAssertTrue(out.contains(0))
        XCTAssertTrue(out.contains(3))
        XCTAssertFalse(out.contains(2))
        g.clear()
        g.query(Vec2(0, 0), 500, into: &out)
        XCTAssertTrue(out.isEmpty)
    }

    func testConfigLoads() {
        let cfg = TestConfig.shared
        XCTAssertEqual(cfg.balance.enemyScale(tier: 1), 1)
        XCTAssertEqual(cfg.balance.enemyScale(tier: 11), pow(cfg.balance.tierEnemyBase, 10), accuracy: 1e-9)
        // 11.1：法宝强度涨得比怪物慢，形成软上限
        XCTAssertGreaterThan(cfg.balance.tierEnemyBase, cfg.balance.tierItemBase)
        XCTAssertEqual(cfg.balance.expNeed(level: 1), 10)
        XCTAssertEqual(cfg.balance.expNeed(level: 2), 26)
        XCTAssertEqual(cfg.skills.pool(for: .sword).count, 8)
        XCTAssertTrue(cfg.elements.counters(.fire, .metal))
        XCTAssertTrue(cfg.elements.counters(.thunder, .water))
        XCTAssertFalse(cfg.elements.counters(.metal, .fire))
        XCTAssertTrue(cfg.elements.generates(statusElement: .wood, hit: .fire))
        XCTAssertTrue(cfg.elements.generates(statusElement: .thunder, hit: .fire))
        XCTAssertTrue(cfg.elements.generates(statusElement: .water, hit: .thunder))
    }
}
