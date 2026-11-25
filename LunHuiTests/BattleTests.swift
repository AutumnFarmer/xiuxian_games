import XCTest
@testable import LunHui

/// 无界面战斗测试：直接推进 BattleWorld。
final class BattleTests: XCTestCase {
    let cfg = TestConfig.shared

    func makeWorld(kind: StageKind = .normal, realm: Int = 0, tier: Int = 1, theme: Element = .wood,
                   lingGen: LingGen = LingGen(type: .single, elements: [.fire]), seed: UInt64 = 1) -> BattleWorld {
        let setup = StageSetup(tier: tier, realm: realm, stageIndex: realm * 3, kind: kind, themeElement: theme)
        let w = BattleWorld(cfg: cfg, setup: setup, lingGen: lingGen, school: .sword, seed: seed)
        w.viewSize = Vec2(430, 932)
        return w
    }

    /// 让玩家绕圈走，模拟一个会走位的玩家。
    func runBot(_ w: BattleWorld, seconds: Double) {
        let steps = Int(seconds * 60)
        for k in 0..<steps {
            let t = Double(k) / 60
            w.player.input = Vec2.fromAngle(t * 0.45)
            w.step()
            w.events.removeAll(keepingCapacity: true)
            if w.phase == .cleared || w.phase == .dead { return }
        }
    }

    // MARK: 伤害公式（5.4）

    func testDamageFormulaBasics() {
        let w = makeWorld()
        var b = StatBlock()
        b.add(.critRate, -0.05)          // 关掉暴击，结果只剩浮动
        b.add(.atkFlat, 100)             // 攻击 200
        b.add(.dmgPct, 0.5)
        b.add(.elemPct, 0.2, param: "fire")
        w.baseBlock = b
        XCTAssertEqual(w.stats.atk, 200, accuracy: 1e-9)
        w.spawnMinion(typeIndex: 0, at: Vec2(50, 0))
        let e = w.enemies[0]  // 木系怪，火不克木
        let hit = Hit(mult: 1.0, element: .fire, school: .sword, statusChance: 0)
        for _ in 0..<200 {
            let (d, crit) = w.computeDamage(hit, on: e)
            XCTAssertFalse(crit)
            // 200 × 1 × (1 + 0.5 + 0.2) = 340，再乘 0.95 到 1.05
            XCTAssertGreaterThanOrEqual(d, 340 * 0.95 - 1e-6)
            XCTAssertLessThanOrEqual(d, 340 * 1.05 + 1e-6)
        }
    }

    func testCounterAndGenerating() {
        let w = makeWorld(theme: .metal)
        var b = StatBlock()
        b.add(.critRate, -0.05)
        w.baseBlock = b
        w.spawnMinion(typeIndex: 0, at: Vec2(50, 0))
        var e = w.enemies[0]
        let fire = Hit(mult: 1, element: .fire, school: nil, statusChance: 0)
        let water = Hit(mult: 1, element: .water, school: nil, statusChance: 0)
        func avg(_ h: Hit, _ e: Enemy) -> Double {
            var s = 0.0
            for _ in 0..<2000 { s += w.computeDamage(h, on: e).0 }
            return s / 2000
        }
        // 火克金：×1.3
        XCTAssertEqual(avg(fire, e) / avg(water, e), 1.3, accuracy: 0.02)
        // 目标带木的标记时，火命中相生 +0.3（易伤系数 1.3）
        e.marks[Element.wood.index] = 1
        let ratio = avg(fire, e) / avg(water, e)
        XCTAssertEqual(ratio, 1.3 * 1.3, accuracy: 0.03)
    }

    func testCritOverflowConvertsToCritDamage() {
        let w = makeWorld()
        var b = StatBlock()
        b.add(.critRate, 1.05)   // 暴击率 110%
        w.baseBlock = b
        w.spawnMinion(typeIndex: 0, at: Vec2(50, 0))
        let hit = Hit(mult: 1, element: nil, school: nil, statusChance: 0)
        let (d, crit) = w.computeDamage(hit, on: w.enemies[0])
        XCTAssertTrue(crit)
        // 暴伤 150% + 10% × 1.5 = 165%
        XCTAssertGreaterThan(d, 100 * 1.65 * 0.95 - 1e-6)
        XCTAssertLessThan(d, 100 * 1.65 * 1.05 + 1e-6)
    }

    func testBurnTicks() {
        let w = makeWorld()
        w.spawnMinion(typeIndex: 2, at: Vec2(500, 0))   // 石傀，血厚
        w.enemies[0].hp = 1e9
        w.enemies[0].maxHp = 1e9
        w.applyStatus(0, .fire, hitDamage: 1000)
        let before = w.enemies[0].hp
        for _ in 0..<(60 * 4) { w.step() }
        // 6 跳 × 1000 × 10% = 600
        XCTAssertEqual(before - w.enemies[0].hp, 600, accuracy: 1e-6)
    }

    // MARK: 整关

    func testNormalStageClears() {
        let w = makeWorld()
        w.baseBlock = schoolBlock(.sword)
        w.skills = [SkillFactory.make(id: "yujian", slot: 0, level: 1, element: .fire, cfg: cfg)!]
        w.startStage(w.setup)
        runBot(w, seconds: 100)
        XCTAssertEqual(w.phase, .cleared, "90 秒后应清场结束")
        XCTAssertGreaterThan(w.kills, 150)
        XCTAssertGreaterThan(w.level, 3)
        XCTAssertGreaterThan(w.stageLingShi, 0)
    }

    func testPlayerWithoutSkillsDiesAndRevivesOnce() {
        let w = makeWorld(realm: 4, tier: 30)
        w.startStage(w.setup)
        var revived = false
        for _ in 0..<(60 * 90) {
            w.player.input = .zero
            w.step()
            if w.events.contains(where: { if case .revive = $0 { return true } else { return false } }) { revived = true }
            w.events.removeAll()
            if w.phase == .dead { break }
        }
        XCTAssertTrue(revived)
        XCTAssertEqual(w.phase, .dead)
        XCTAssertEqual(w.revivesLeft, 0)
    }

    func testThreeHundredEnemiesPerformance() {
        let w = makeWorld(realm: 2)
        w.baseBlock = schoolBlock(.sword)
        w.skills = [SkillFactory.make(id: "yujian", slot: 0, level: 5, element: .fire, cfg: cfg)!]
        w.startStage(w.setup)
        for k in 0..<300 { w.spawnMinion(typeIndex: k % 3, at: Vec2.fromAngle(Double(k), 200 + Double(k % 50) * 6)) }
        for e in w.enemies.indices { w.enemies[e].hp = 1e12; w.enemies[e].maxHp = 1e12 }
        let t0 = Date()
        for _ in 0..<600 { w.step(); w.events.removeAll(keepingCapacity: true) }
        let perStep = Date().timeIntervalSince(t0) / 600
        print("300 只怪每步耗时 \(String(format: "%.3f", perStep * 1000)) ms")
        // Linux 沙盒比 A18 Pro 慢得多，这里只防止明显的性能退化。
        XCTAssertLessThan(perStep, 0.012)
    }

    func schoolBlock(_ s: School) -> StatBlock {
        var b = StatBlock()
        b.add(cfg.schools.def(s).passive)
        return b
    }
}
