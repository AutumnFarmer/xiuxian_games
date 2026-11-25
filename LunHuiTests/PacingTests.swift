import XCTest
@testable import LunHui

/// 节奏模拟（21 章）：机器人一世接一世地玩，每世结算后装最好的法宝、祭炼、升道心，然后挑能打的最高劫数。
/// 默认不跑（很慢），设置环境变量 LH_PACING=世数 才运行，比如 LH_PACING=30。
final class PacingTests: XCTestCase {
    func testPacing() throws {
        guard let n = ProcessInfo.processInfo.environment["LH_PACING"].flatMap(Int.init), n > 0 else {
            throw XCTSkip("设置 LH_PACING=世数 才运行")
        }
        let cfg = TestConfig.shared
        var rng = SeededRandom(seed: 2026)
        var save = MetaGame.newSave(cfg, rng: &rng)
        var tier = 1
        var totalSeconds = 0.0
        let schools: [School] = [.sword, .magic, .body]
        var lastFail = false
        for life in 1...n {
            let unlocked = schools + (save.unlockedSchools.contains("beast") ? [.beast] : []) + (save.unlockedSchools.contains("demon") ? [.demon] : [])
            let school = unlocked[life % unlocked.count]
            let lg = save.nextRunPreview.lingGenChoices[0]
            let startPower = StatAssembler.power(cfg, save: save)
            var sim = RunSimulator(cfg: cfg, save: save)
            sim.maxSecondsPerStage = 200
            let rep = sim.run(tier: tier, school: school, lingGen: lg, seed: UInt64(1000 + life))
            totalSeconds += rep.seconds
            let report = MetaGame.settle(cfg, save: &save, result: rep.result!, rng: &rng)
            // 装最好的法宝
            for slot in ItemSlot.allCases {
                let cands = save.items.filter { $0.slot == slot }
                if let best = cands.max(by: { power(cfg, save, $0) < power(cfg, save, $1) }) { MetaGame.equip(&save, best) }
            }
            _ = MetaGame.refineAll(cfg, &save, rng: &rng)
            while let g = save.benming.pendingAwakenings.first { MetaGame.chooseAwakening(&save, g[0]) }
            _ = MetaGame.levelDaoXinAll(cfg, &save)
            MetaGame.allocate(&save, save.daoXinPoints.count % 2 == 0 ? "dx_atk" : "dx_hp", save.daoXinUnspent)
            // 藏经阁按顺序升
            for id in ["cj_revive", "cj_cards", "cj_skill", "cj_start", "cj_reroll", "lq_capacity"] {
                while MetaGame.upgrade(cfg, &save, id) {}
            }
            let pw = StatAssembler.power(cfg, save: save)
            let rec = StatAssembler.recommendedPower(cfg, tier: tier)
            print(String(format: "第%2d世 劫%3d %@ %@ 关%2d 级%2d 用时%4.0f分 | 战力%@ 推荐%@ 比%.2f | 本命%3d 道心%3d 法宝%3d 神%d 混%d | 最高劫%d",
                         life, tier, cfg.schools.def(school).name, rep.cleared ? "通关" : "死亡", rep.stagesDone, rep.level,
                         totalSeconds / 60, NumberText.format(pw), NumberText.format(rec), pw / rec,
                         save.benming.level, save.daoXinLevel, save.items.count,
                         save.items.filter { $0.quality == "shen" }.count, save.items.filter { $0.quality == "hundun" }.count,
                         save.maxTierUnlocked))
            _ = report
            print("CSV,\(life),\(tier),\(rep.cleared ? 1 : 0),\(rep.stagesDone),\(startPower),\(StatAssembler.recommendedPower(cfg, tier: tier)),\(rep.usedReviveFlag ? 1 : 0),\(rep.result?.heartDemon ?? 0),\(rep.result?.shadowKilled == true ? 1 : 0),\(rep.timedOut ? 1 : 0),\(Int(rep.finalStageSeconds)),\(rep.bossTimes.map { String(Int($0)) }.joined(separator: "/"))")
            // 下一世：通关就往上推，死了就退一劫
            if rep.cleared {
                tier = save.maxTierUnlocked
                lastFail = false
            } else {
                tier = max(1, tier - (lastFail ? 2 : 1))
                lastFail = true
            }
        }
    }

    private func power(_ cfg: GameConfig, _ s: SaveData, _ it: Item) -> Double {
        StatAssembler.power(cfg, save: s, items: s.equippedItems.filter { $0.slot != it.slot } + [it])
    }
}
