import XCTest
@testable import LunHui

/// 整世、局外循环和存档测试（20 章 M2、M4、M5 的验收）。
final class RunTests: XCTestCase {
    let cfg = TestConfig.shared

    func freshSave(seed: UInt64 = 1) -> SaveData {
        var r = SeededRandom(seed: seed)
        return MetaGame.newSave(cfg, rng: &r)
    }

    // M2：用剑修从练气第 1 关打到通关
    func testSwordRunTierOne() {
        let sim = RunSimulator(cfg: cfg, save: freshSave())
        let rep = sim.run(tier: 1, school: .sword, lingGen: LingGen(type: .single, elements: [.fire]), seed: 11)
        print("剑修第 1 劫：关数 \(rep.stagesDone)，等级 \(rep.level)，击杀 \(rep.kills)，用时 \(Int(rep.seconds)) 秒，法宝 \(rep.items)，品质 \(rep.qualityCounts)，Boss 用时 \(rep.bossTimes.map { Int($0) })")
        XCTAssertGreaterThanOrEqual(rep.stagesDone, 9, "新手第一世至少应该打到元婴")
        XCTAssertGreaterThan(rep.level, 20)
        XCTAssertGreaterThan(rep.items, 10)
    }

    /// 每个流派都能跑完一世而不出错（M6 的验收前提）。
    func testEverySchoolRuns() {
        var save = freshSave()
        save.unlockedSchools = School.allCases.map(\.rawValue)
        for (k, s) in School.allCases.enumerated() {
            let sim = RunSimulator(cfg: cfg, save: save)
            let rep = sim.run(tier: 1, school: s, lingGen: LingGen(type: .dual, elements: [.wood, .fire]), seed: UInt64(100 + k))
            print("\(cfg.schools.def(s).name)：关数 \(rep.stagesDone)，等级 \(rep.level)，击杀 \(rep.kills)，用时 \(Int(rep.seconds)) 秒")
            XCTAssertGreaterThanOrEqual(rep.stagesDone, 6, "\(s) 第 1 劫至少打到金丹")
        }
    }

    // M4：连续 3 世，资源和法宝正确保存
    func testThreeRunsAndSettlement() {
        var save = freshSave()
        var rng = SeededRandom(seed: 5)
        for k in 0..<3 {
            let sim = RunSimulator(cfg: cfg, save: save)
            let rep = sim.run(tier: save.maxTierUnlocked, school: .magic, lingGen: LingGen(type: .single, elements: [.water]),
                              seed: UInt64(20 + k))
            let before = save.items.count
            let report = MetaGame.settle(cfg, save: &save, result: rep.result!, rng: &rng)
            XCTAssertGreaterThanOrEqual(report.lingSui, cfg.settlement.lingSuiMin)
            XCTAssertEqual(save.items.count, before + report.keptItems.count)
            // 装上最好的法宝
            for slot in ItemSlot.allCases {
                if let best = save.items.filter({ $0.slot == slot }).max(by: {
                    StatAssembler.power(cfg, save: save, items: [$0]) < StatAssembler.power(cfg, save: save, items: [$1])
                }) { MetaGame.equip(&save, best) }
            }
            _ = MetaGame.refineAll(cfg, &save, rng: &rng)
            _ = MetaGame.levelDaoXinAll(cfg, &save)
            MetaGame.allocate(&save, "dx_atk", save.daoXinUnspent)
            print("第 \(k + 1) 世：\(report.title)，关数 \(rep.stagesDone)，灵石 \(Int(save.lingShi))，宿慧 \(Int(save.suHui))，本命 Lv.\(save.benming.level)，道心 \(save.daoXinLevel)，法宝 \(save.items.count)，战力 \(Int(StatAssembler.power(cfg, save: save)))，最高劫 \(save.maxTierUnlocked)")
        }
        XCTAssertEqual(save.records.totalRuns, 3)
        XCTAssertGreaterThan(save.benming.level, 1)
        XCTAssertGreaterThan(StatAssembler.power(cfg, save: save), 0)
    }

    // M4：存档和读档，包括中途存的 RunState
    func testSaveRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lh-\(UUID().uuidString)")
        let sm = SaveManager(directory: dir)
        var save = freshSave()
        var rng = SeededRandom(seed: 9)
        save.items.append(ItemForge.make(cfg, quality: 4, tier: 3, school: .sword, rng: &rng))
        save.lingShi = 12345
        XCTAssertTrue(sm.save(save))
        guard case .ok(let loaded) = sm.load() else { return XCTFail("读档失败") }
        XCTAssertEqual(loaded.items.count, 1)
        XCTAssertEqual(loaded.lingShi, 12345)
        XCTAssertEqual(loaded.items[0].legendary, save.items[0].legendary)
        // 第二次保存后有备份
        save.lingShi = 1
        XCTAssertTrue(sm.save(save))
        XCTAssertNotNil(sm.loadBackup())
        // 损坏主存档时能识别，并能从备份恢复
        try Data("{坏的".utf8).write(to: sm.saveURL)
        guard case .corrupted(let ok) = sm.load() else { return XCTFail("应识别为损坏") }
        XCTAssertTrue(ok)
        // RunState
        let run = RunController.newRun(cfg, save: save, tier: 1, school: .sword, lingGen: LingGen(type: .single, elements: [.fire]), pills: [], seed: 3)
        XCTAssertTrue(sm.saveRun(run))
        XCTAssertEqual(sm.loadRun(), run)
        // 老存档缺字段也能解码（18.2）
        let minimal = #"{"nextRunPreview":{"themeOrder":["forest","volcano","lake","desert","canyon"],"dungeonAffixes":["a_fire"],"lingGenChoices":[],"lingGenRerollUsed":false,"affixRerollUsed":false}}"#
        try Data(minimal.utf8).write(to: sm.saveURL)
        guard case .ok(let old) = sm.load() else { return XCTFail("老存档应能解码") }
        XCTAssertEqual(old.maxTierUnlocked, 1)
        XCTAssertEqual(old.unlockedSchools, ["sword", "magic", "body"])
        try? FileManager.default.removeItem(at: dir)
    }

    // M4：掉落统计和 12.3 的估算一致（模拟 1000 世的掉落）
    func testDropDistributionMatchesDesign() {
        var rng = SeededRandom(seed: 77)
        func simulate(tier: Int, mf: Double, bonus: Double, lives: Int) -> (items: Double, xian: Double, shen: Double, hundun: Double) {
            var c = [Double](repeating: 0, count: 6)
            var n = 0.0
            let d = cfg.items.drops
            for _ in 0..<lives {
                func drop(_ expected: Double, _ minQ: Int) {
                    let x = expected * (1 + bonus)
                    var k = Int(x)
                    if rng.chance(x - Double(k)) { k += 1 }
                    for j in 0..<k {
                        let q = ItemForge.rollQuality(cfg, tier: tier, magicFind: mf, minQuality: j == 0 ? minQ : 0, rng: &rng)
                        c[q] += 1
                        n += 1
                    }
                }
                for _ in 0..<5500 { drop(d.minionItemChance, 0) }
                for _ in 0..<23 { drop(d.eliteItems, 0) }
                for _ in 0..<4 { drop(d.bossItems, d.bossMinQuality) }
                drop(d.finalItems, d.finalMinQuality)
            }
            let L = Double(lives)
            return (n / L, c[3] / L, c[4] / L, c[5] / L)
        }
        let t1 = simulate(tier: 1, mf: 0, bonus: 0, lives: 1000)
        print("第 1 劫每世：法宝 \(t1.items)，仙品 \(t1.xian)，神品 \(t1.shen)")
        XCTAssertEqual(t1.items, 55, accuracy: 6)
        XCTAssertEqual(t1.xian, 5, accuracy: 1.2)
        XCTAssertEqual(t1.shen, 1.6, accuracy: 0.5)
        XCTAssertEqual(t1.hundun, 0)
        let t30 = simulate(tier: 30, mf: 1.0, bonus: 0.3, lives: 1000)
        print("第 30 劫每世：法宝 \(t30.items)，神品 \(t30.shen)，混沌 \(t30.hundun)")
        XCTAssertEqual(t30.items, 70, accuracy: 8)
        XCTAssertEqual(1 / t30.hundun, 3, accuracy: 1.2)
    }

    // 顿悟：保底和神通
    func testInsightGuaranteeAndEvolution() {
        let save = freshSave()
        var run = RunController.newRun(cfg, save: save, tier: 1, school: .sword, lingGen: LingGen(type: .single, elements: [.metal]), pills: [], seed: 4)
        var rng = SeededRandom(seed: 8)
        let first = InsightGen.cards(cfg, run: run, cardCount: 3, rng: &rng)
        XCTAssertEqual(first.count, 3)
        XCTAssertGreaterThanOrEqual(first.filter { if case .newSkill = $0 { return true } else { return false } }.count, 2)
        run.insightsDone = 5
        run.skills[0].level = 5
        run.passives["p_proj"] = 1
        run.passiveOrder = ["p_proj"]
        let cards = InsightGen.cards(cfg, run: run, cardCount: 3, rng: &rng)
        guard case .evolution(let s, _) = cards[0] else { return XCTFail("第一张应是神通") }
        XCTAssertEqual(s, "yujian")
        _ = InsightGen.apply(cards[0], to: &run)
        XCTAssertTrue(run.skills[0].evolved)
    }

    /// 心魔影子关能生成并被击败（8.8）。
    func testShadowStage() {
        let save = freshSave()
        var state = RunController.newRun(cfg, save: save, tier: 1, school: .demon, lingGen: LingGen(type: .single, elements: [.fire]), pills: [], seed: 31)
        state.stageIndex = 14
        state.heartDemon = 80
        state.level = 40
        state.skills = [SkillState(id: "shihun", level: 5, element: .fire, evolved: true),
                        SkillState(id: "mohuo", level: 5, element: .fire, evolved: false),
                        SkillState(id: "xinmozhan", level: 5, element: .fire, evolved: false)]
        let rc = RunController(cfg: cfg, save: save, run: state)
        rc.world.viewSize = Vec2(430, 932)
        rc.startStage()
        XCTAssertEqual(rc.world.setup.kind, .shadow)
        XCTAssertTrue(rc.world.enemies.contains { $0.role == .shadow })
        // 把影子血量调低，确认能打死并触发胜利
        for i in rc.world.enemies.indices where rc.world.enemies[i].role == .shadow { rc.world.enemies[i].hp = 1000 }
        for k in 0..<(60 * 60) {
            rc.world.player.input = Vec2.fromAngle(Double(k) / 60)
            rc.world.step()
            rc.world.events.removeAll()
            if rc.world.phase == .cleared || rc.world.phase == .dead { break }
        }
        XCTAssertEqual(rc.world.phase, .cleared)
        rc.finishStage()
        XCTAssertTrue(rc.run.shadowKilled)
        XCTAssertTrue(rc.run.cleared)
    }
}

#if os(iOS)
/// iOS 上配置表必须打包进 App（19.1）。
final class BundleTests: XCTestCase {
    func testBundledConfigLoads() throws {
        let cfg = try GameConfig.loadBundled()
        XCTAssertEqual(cfg.skills.skills.count, 24)
        XCTAssertEqual(cfg.legendaries.legendaries.count, 30)
    }
}
#endif

/// BattleFlow 的流程测试：关卡开始、顿悟、掉落面板、机缘、续玩（4.3、4.5）。
final class FlowTests: XCTestCase {
    let cfg = TestConfig.shared

    func testFlowThroughTwoStagesAndResume() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lh-flow-\(UUID().uuidString)")
        let app = AppState(saveManager: SaveManager(directory: dir))
        app.boot(config: cfg)
        XCTAssertEqual(app.route, .firstLaunch)
        app.chooseBenmingShape("sword")
        XCTAssertEqual(app.route, .cave)
        let lg = app.save.nextRunPreview.lingGenChoices[0]
        app.startRun(tier: 1, school: .sword, lingGen: lg, pills: [])
        XCTAssertEqual(app.route, .battle)
        let flow = app.battleFlow!
        flow.world.viewSize = Vec2(440, 956)
        var stagesCleared = 0
        var insights = 0
        var sawLoot = false
        var sawEvent = false
        var k = 0
        while stagesCleared < 2, k < 60 * 400 {
            k += 1
            switch flow.phase {
            case .fighting:
                flow.world.player.input = Vec2.fromAngle(Double(k) / 100)
                flow.world.step()
                flow.world.events.removeAll()
                flow.afterSteps(1)
                flow.tickHUD(flow.world.dt)
            case .insight(let cards):
                insights += 1
                flow.chooseInsight(cards[0])
            case .loot:
                sawLoot = true
                stagesCleared += 1
                if stagesCleared == 2 { break }
                flow.closeLoot()
            case .event(let ch):
                sawEvent = true
                flow.chooseEvent(ch[0])
            default:
                XCTFail("意外的阶段 \(flow.phase)")
                return
            }
        }
        XCTAssertTrue(sawLoot)
        XCTAssertTrue(sawEvent)
        XCTAssertGreaterThan(insights, 2)
        XCTAssertGreaterThan(flow.hud.kills, 50)
        // 第 2 关打完后杀掉 App：续玩时应先弹出机缘，再开始第 3 关（4.3）
        XCTAssertEqual(app.runController?.run.stageIndex, 2)
        let app2 = AppState(saveManager: SaveManager(directory: dir))
        app2.boot(config: cfg)
        XCTAssertTrue(app2.save.hasActiveRun)
        app2.continueRun()
        let flow2 = app2.battleFlow!
        guard case .event(let ch) = flow2.phase else { return XCTFail("续玩应先弹出机缘") }
        flow2.chooseEvent(ch[0])
        // 机缘可能给顿悟（古修洞府、古魔残魂），顿悟在关卡开始前弹出
        while case .insight(let cards) = flow2.phase { flow2.chooseInsight(cards[0]) }
        XCTAssertEqual(flow2.phase, .fighting)
        XCTAssertEqual(flow2.world.setup.kind, .boss)
        // 放弃本世，进入结算
        flow2.pause()
        flow2.abandon()
        XCTAssertEqual(app2.route, .settlement)
        XCTAssertNotNil(app2.lastReport)
        XCTAssertFalse(app2.save.hasActiveRun)
        XCTAssertNil(app2.saveManager.loadRun())
        try? FileManager.default.removeItem(at: dir)
    }
}
