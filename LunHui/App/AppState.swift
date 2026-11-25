import Foundation
import Observation

/// 顶层界面路由（17.2）。
enum Route: Equatable {
    case loading
    case firstLaunch
    case cave
    case prepare
    case battle
    case settlement
    /// 存档损坏（18.1）。
    case corrupted(backupAvailable: Bool)
    case fatal(String)
}

/// 全局状态：配置、存档、当前一世、路由。界面只通过这里修改存档。
@Observable
final class AppState {
    var route: Route = .loading
    /// 局外存档。任何修改都要调用 persist()。
    var save: SaveData
    /// 进行中的一世。
    @ObservationIgnored private(set) var runController: RunController?
    /// 战斗界面的流程，进入战斗时创建（BattleView 持有它的观察）。
    @ObservationIgnored private(set) var battleFlow: BattleFlow?
    /// 每次开始或继续一世时加 1，让战斗界面重新创建场景。
    private(set) var battleToken = 0
    private(set) var lastReport: SettlementReport?

    /// Debug 菜单的测试开局（20 章 M7）：下一世从第几关开始、开局心魔值、额外顿悟次数。只在 Debug 版生效。
    var debugStartStage = 0
    var debugStartDemon = 0
    var debugExtraInsights = 0
    /// Debug：战斗中显示帧率和节点数。
    var debugShowFPS = false

    @ObservationIgnored private(set) var cfg: GameConfig!
    @ObservationIgnored let saveManager: SaveManager
    @ObservationIgnored var metaRng = SeededRandom.fromClock()

    init(saveManager: SaveManager = SaveManager()) {
        self.saveManager = saveManager
        save = SaveData(preview: RunPreview(themeOrder: [], dungeonAffixes: [], lingGenChoices: [],
                                            lingGenRerollUsed: false, affixRerollUsed: false))
    }

    var config: GameConfig { cfg }

    // MARK: 启动

    func boot(config: GameConfig? = nil) {
        do {
            cfg = try config ?? GameConfig.loadBundled()
        } catch {
            route = .fatal("\(error)")
            return
        }
        switch saveManager.load() {
        case .ok(let s):
            save = s
            enterAfterLoad()
        case .missing:
            save = MetaGame.newSave(cfg, rng: &metaRng)
            persist()
            enterAfterLoad()
        case .corrupted(let backup):
            route = .corrupted(backupAvailable: backup)
        }
    }

    private func enterAfterLoad() {
        if save.hasActiveRun, saveManager.loadRun() == nil {
            save.hasActiveRun = false
            persist()
        }
        route = save.benming.shape == nil ? .firstLaunch : .cave
    }

    func restoreBackup() {
        guard let s = saveManager.loadBackup() else { return }
        save = s
        persist()
        enterAfterLoad()
    }

    func startFresh() {
        saveManager.resetAll()
        save = MetaGame.newSave(cfg, rng: &metaRng)
        persist()
        enterAfterLoad()
    }

    @discardableResult
    func persist() -> Bool { saveManager.save(save) }

    // MARK: 第一次进入（13.1）

    func chooseBenmingShape(_ shape: String) {
        save.benming.shape = shape
        persist()
        route = .cave
    }

    // MARK: 出发（4.1）

    func goPrepare() { route = .prepare }
    func goCave() { route = .cave }

    func rerollLingGen() {
        guard !save.nextRunPreview.lingGenRerollUsed else { return }
        save.nextRunPreview.lingGenChoices = PreviewGen.rollLingGen(cfg, rng: &metaRng)
        save.nextRunPreview.lingGenRerollUsed = true
        persist()
    }

    func rerollAffixes() {
        guard !save.nextRunPreview.affixRerollUsed else { return }
        save.nextRunPreview.dungeonAffixes = PreviewGen.rollAffixes(cfg, rng: &metaRng)
        save.nextRunPreview.affixRerollUsed = true
        persist()
    }

    func pillsCost(_ pills: [String]) -> Double {
        pills.reduce(0) { $0 + MetaGame.pillPrice(cfg, save, $1) }
    }

    /// 出发：扣丹药灵石，生成 RunState 并写进 run.json。
    func startRun(tier: Int, school: School, lingGen: LingGen, pills: [String]) {
        let cost = pillsCost(pills)
        guard save.lingShi >= cost else { return }
        save.lingShi -= cost
        save.lastTier = tier
        save.lastSchool = school.rawValue
        save.lastPills = pills
        let seed = metaRng.next()
        var run = RunController.newRun(cfg, save: save, tier: tier, school: school, lingGen: lingGen, pills: pills, seed: seed)
        #if DEBUG
        applyDebugStart(&run)
        #endif
        save.hasActiveRun = true
        saveManager.saveRun(run)
        persist()
        runController = RunController(cfg: cfg, save: save, run: run)
        makeFlow()
        route = .battle
    }

    private func makeFlow() {
        guard let rc = runController else { return }
        let f = BattleFlow(rc: rc, app: self)
        battleFlow = f
        battleToken += 1
        f.begin()
    }

    #if DEBUG
    private func applyDebugStart(_ run: inout RunState) {
        if debugStartStage > 0 {
            run.stageIndex = min(14, debugStartStage)
            run.level = 1 + 4 * run.stageIndex
        }
        if debugStartDemon > 0 { run.heartDemon = min(cfg.heartDemon.max, debugStartDemon) }
        run.pendingInsights += debugExtraInsights
    }
    #endif

    /// 继续本世（4.5）。
    func continueRun() {
        guard let run = saveManager.loadRun() else {
            save.hasActiveRun = false
            persist()
            return
        }
        runController = RunController(cfg: cfg, save: save, run: run)
        makeFlow()
        route = .battle
    }

    /// 在洞府里放弃本世：按死亡处理，正常结算（4.5）。
    func abandonFromCave() {
        guard let run = saveManager.loadRun() else {
            save.hasActiveRun = false
            persist()
            return
        }
        let rc = RunController(cfg: cfg, save: save, run: run)
        rc.endRun()
        finish(rc)
    }

    // MARK: 战斗中的存档点（4.3）

    /// 每关开始、过关时调用。
    func saveRunCheckpoint() {
        guard let rc = runController else { return }
        saveManager.saveRun(rc.run)
    }

    /// 一世结束：结算、删除 run.json、进入结算界面（第 15 章）。
    func endRun() {
        guard let rc = runController else { return }
        if !rc.run.finished { rc.endRun() }
        finish(rc)
    }

    private func finish(_ rc: RunController) {
        let report = MetaGame.settle(cfg, save: &save, result: rc.result(), rng: &metaRng)
        saveManager.deleteRun()
        persist()
        lastReport = report
        runController = nil
        battleFlow = nil
        route = .settlement
    }

    func leaveSettlement() {
        lastReport = nil
        route = .cave
    }

    // MARK: 设置（17.7）

    func resetEverything() {
        startFresh()
    }
}
