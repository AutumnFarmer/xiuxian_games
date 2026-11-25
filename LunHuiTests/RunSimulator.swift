import Foundation
@testable import LunHui

/// 无界面整世模拟：一个会绕圈走位、按简单优先级选顿悟和机缘的机器人。
/// 用于验收（20 章）和对照节奏目标（21 章）。
struct RunSimulator {
    struct Report {
        var stagesDone = 0
        var cleared = false
        var died = false
        var level = 1
        var kills = 0
        var seconds = 0.0
        var items = 0
        var qualityCounts = [Int](repeating: 0, count: 6)
        var insights = 0
        var bossTimes: [Double] = []
        var deathStage = -1
        var result: RunResult?
    }

    let cfg: GameConfig
    var save: SaveData
    var maxSecondsPerStage = 240.0
    var trace = false

    init(cfg: GameConfig, save: SaveData) {
        self.cfg = cfg
        self.save = save
    }

    func run(tier: Int, school: School, lingGen: LingGen, seed: UInt64, pills: [String] = []) -> Report {
        var rep = Report()
        let state = RunController.newRun(cfg, save: save, tier: tier, school: school, lingGen: lingGen, pills: pills, seed: seed)
        let rc = RunController(cfg: cfg, save: save, run: state)
        let w = rc.world
        w.viewSize = Vec2(430, 932)
        var botT = 0.0
        while rc.run.stageIndex < 15 {
            // 开局额外顿悟和机缘给的顿悟（7.2、9.2）
            while rc.run.pendingInsights > 0 {
                rc.run.pendingInsights -= 1
                pickInsight(rc, &rep)
            }
            if trace { print("trace stage \(rc.run.stageIndex) skills \(rc.run.skills.map { "\($0.id)\($0.level)\($0.evolved ? "*" : "")" })"); fflush(stdout) }
            rc.startStage()
            let kind = w.setup.kind
            var t = 0.0
            var bossStart = -1.0
            while w.phase != .cleared && w.phase != .dead && t < maxSecondsPerStage {
                botT += w.dt
                t += w.dt
                w.player.input = botInput(w, botT)
                w.step()
                if w.director.bossSpawned, bossStart < 0 { bossStart = t }
                if rc.ultimate?.canCast(w) == true, w.enemies.count > 25 || w.enemies.contains(where: { $0.isBossLike }) {
                    rc.ultimate?.cast(w)
                }
                w.events.removeAll(keepingCapacity: true)
                while w.pendingLevelUps > 0 {
                    w.pendingLevelUps -= 1
                    pickInsight(rc, &rep)
                }
            }
            rep.seconds += t
            if kind == .boss, bossStart >= 0, w.phase == .cleared { rep.bossTimes.append(t - bossStart) }
            if w.phase != .cleared {
                rep.died = true
                rep.deathStage = rc.run.stageIndex
                rc.endRun()
                break
            }
            rc.finishStage()
            if let choices = rc.run.pendingEventChoices { pickEvent(rc, choices) }
        }
        rc.run.stats.time = rep.seconds
        let r = rc.result()
        rep.result = r
        rep.stagesDone = r.stagesDone
        rep.cleared = r.cleared
        rep.level = r.level
        rep.kills = r.kills
        rep.items = r.loot.count
        for it in r.loot { rep.qualityCounts[it.qualityIndex(cfg)] += 1 }
        return rep
    }

    /// 绕着一个缓慢移动的圆心走，避开最近的敌人。
    private func botInput(_ w: BattleWorld, _ t: Double) -> Vec2 {
        var dir = Vec2.fromAngle(t * 0.5)
        if let i = w.nearestEnemy(to: w.player.pos, within: 90) {
            let away = (w.player.pos - w.enemies[i].pos).normalized()
            dir = (dir + away * 1.5).normalized()
        }
        // 躲开敌人的预警区域
        for z in w.zones where z.team == .enemy && !z.triggered && z.enemyDamage > 0 {
            if w.zoneContains(z, point: w.player.pos, radius: w.player.radius + 10) {
                dir = (w.player.pos - z.pos).normalized(or: dir.rotated(.pi / 2))
                break
            }
        }
        return dir
    }

    private func pickInsight(_ rc: RunController, _ rep: inout Report) {
        let cards = rc.rollInsight()
        rep.insights += 1
        func score(_ c: InsightCard) -> Int {
            switch c {
            case .evolution: return 100
            case .newSkill: return rc.run.skills.count < 4 ? 80 : 40
            case .skillUp: return 60
            case .newPassive(let p): return ["p_atk", "p_crit", "p_critdmg", "p_cdr", "p_area"].contains(p) ? 50 : 30
            case .passiveUp: return 45
            case .heal: return 10
            case .lingShi: return 5
            }
        }
        if let best = cards.max(by: { score($0) < score($1) }) { rc.chooseInsight(best) }
    }

    private func pickEvent(_ rc: RunController, _ choices: [String]) {
        let prefer = ["e_ghost", "e_cave", "e_demonpill", "e_shrine", "e_blood", "e_altar", "e_herb", "e_spring", "e_merchant", "e_calm"]
        let sorted = choices.sorted { (prefer.firstIndex(of: $0) ?? 99) < (prefer.firstIndex(of: $1) ?? 99) }
        for id in sorted {
            if let e = cfg.events.def(id), e.costPerRealm != nil, !rc.canAfford(e) { continue }
            rc.chooseEvent(id)
            return
        }
    }
}
