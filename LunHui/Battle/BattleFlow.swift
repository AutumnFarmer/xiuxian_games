import Foundation
import Observation

/// 战斗界面的流程（4.3 到 4.6）：关卡开始、顿悟、掉落面板、机缘、暂停、死亡。
/// 纯逻辑，可以在命令行测试；BattleScene 每帧推进逻辑后调用 afterSteps()。
@Observable
final class BattleFlow {
    enum Phase: Equatable {
        case fighting
        case insight([InsightCard])
        case loot([Item])
        case event([String])
        case paused
        case dead
        case finished
    }

    var phase: Phase = .fighting
    /// 刚从机缘获得的法宝（商人、祭坛），显示一次提示。
    var gainedItem: Item?
    let hud = BattleHUDModel()

    @ObservationIgnored let rc: RunController
    @ObservationIgnored weak var app: AppState?
    @ObservationIgnored private var preStage = false
    @ObservationIgnored private var pausedFrom: Phase = .fighting
    @ObservationIgnored private var hudTimer = 0.0
    @ObservationIgnored private var lastDemon = 0
    /// 每关开始时回调（表现层切换音乐）。
    @ObservationIgnored var onStageStart: ((StageKind) -> Void)?

    var world: BattleWorld { rc.world }
    var cfg: GameConfig { rc.cfg }
    var isLogicRunning: Bool { phase == .fighting }

    init(rc: RunController, app: AppState?) {
        self.rc = rc
        self.app = app
        lastDemon = rc.run.heartDemon
    }

    // MARK: 开始

    /// 进入战斗界面时调用一次：续玩时先弹出过关后没选的机缘（4.3）。
    func begin() {
        if let ch = rc.run.pendingEventChoices, !ch.isEmpty {
            phase = .event(ch)
        } else {
            beginStage()
        }
    }

    private func beginStage() {
        // 开局额外顿悟、机缘给的顿悟在关卡开始前弹出（7.2、9.2）
        if rc.run.pendingInsights > 0 {
            rc.run.pendingInsights -= 1
            preStage = true
            phase = .insight(rc.rollInsight())
            return
        }
        preStage = false
        rc.startStage()
        onStageStart?(world.setup.kind)
        app?.saveRunCheckpoint()
        let i = rc.run.stageIndex
        if i > 0, i % 3 == 0 {
            hud.pushBanner("境界突破", sub: rc.realmName, style: .realm, duration: cfg.fx.realmBanner)
        } else {
            hud.pushBanner(rc.stageTitle(), style: .normal, duration: 1.2)
        }
        refreshHUD(force: true)
        phase = .fighting
    }

    // MARK: 每帧

    /// BattleScene 推进了 steps 个逻辑步之后调用。
    func afterSteps(_ steps: Int) {
        guard phase == .fighting else { return }
        rc.run.stats.time += Double(steps) * world.dt
        if world.heartDemon >= cfg.heartDemon.shadowAt, lastDemon < cfg.heartDemon.shadowAt {
            hud.flashScreen(.purple, duration: 1)
            hud.pushBanner("心魔已成", sub: "终劫将见心魔", style: .demon, duration: 2)
        }
        lastDemon = world.heartDemon
        switch world.phase {
        case .dead:
            rc.syncFromWorld()
            phase = .dead
            onDeath?()
        case .cleared:
            rc.finishStage()
            app?.saveRunCheckpoint()
            if rc.run.finished {
                phase = .finished
                app?.endRun()
            } else {
                phase = .loot(rc.stageItems)
            }
        default:
            if world.pendingLevelUps > 0 {
                world.pendingLevelUps -= 1
                phase = .insight(rc.rollInsight())
            }
        }
    }

    /// 每 0.1 秒刷新一次 HUD（3.4）。dt 是真实经过的时间。
    func tickHUD(_ dt: Double) {
        hud.clock += dt
        hudTimer += dt
        if hudTimer >= 0.1 {
            hudTimer = 0
            refreshHUD()
        }
        hud.expire()
    }

    func refreshHUD(force: Bool = false) {
        let w = world, h = hud
        h.set(\.hp, w.player.hp.rounded())
        h.set(\.maxHp, w.stats.hp.rounded())
        h.set(\.shield, w.player.shield.rounded())
        h.set(\.level, w.level)
        h.set(\.expFrac, min(1, w.exp / cfg.balance.expNeed(level: w.level)))
        h.set(\.heartDemon, w.heartDemon)
        let band = cfg.heartDemon.band(w.heartDemon)
        h.set(\.demonBand, band.name)
        h.set(\.demonColor, band.color)
        h.set(\.stageTitle, rc.stageTitle())
        h.set(\.kills, w.kills)
        h.set(\.lingShi, (rc.run.lingShiGained + w.stageLingShi).rounded())
        h.set(\.items, rc.run.loot.count + w.stageItemCount)
        h.set(\.revives, w.revivesLeft)
        switch w.setup.kind {
        case .normal:
            h.set(\.timeLeft, w.phase == .fighting ? w.normalTimeLeft.rounded(.up) : 0)
            h.set(\.bossName, nil)
            h.set(\.isTribulation, false)
        case .boss, .shadow:
            h.set(\.timeLeft, nil)
            h.set(\.isTribulation, false)
            if let b = w.enemies.first(where: { $0.isBossLike && !$0.dead }) {
                h.set(\.bossName, w.setup.kind == .shadow ? "心魔" : w.director.bossName)
                h.set(\.bossFrac, max(0, b.hp / b.maxHp))
                h.set(\.bossEnraged, b.enraged)
            } else if w.director.victory {
                h.set(\.bossFrac, 0)
            } else {
                h.set(\.bossName, nil)
            }
        case .tribulation:
            h.set(\.timeLeft, nil)
            h.set(\.bossName, nil)
            h.set(\.isTribulation, true)
            h.set(\.tribulationWave, min(cfg.bosses.tribulation.waves, w.director.wave + 1))
            h.set(\.tribulationWaves, cfg.bosses.tribulation.waves)
            h.set(\.tribulationProgress, max(0, w.director.progress))
        }
        let skills = w.skills.map {
            SkillHUD(id: $0.slot, name: $0.displayName, level: $0.level, element: $0.element,
                     evolved: $0.evolution != nil, cd: ($0.cooldownProgress(w) * 20).rounded() / 20)
        }
        h.set(\.skills, skills)
        let u = rc.ultimate
        h.set(\.ult, (w.ultCharge / cfg.balance.ult.max * 50).rounded() / 50)
        h.set(\.ultReady, u?.canCast(w) ?? false)
        h.set(\.ultActive, u?.isActive ?? false)
        h.set(\.ultName, cfg.schools.def(rc.run.school).ultName)
        _ = force
    }

    // MARK: 操作

    @ObservationIgnored var onUltimate: (() -> Void)?
    @ObservationIgnored var onDeath: (() -> Void)?

    func castUltimate() {
        guard phase == .fighting, rc.ultimate?.canCast(world) == true else { return }
        rc.ultimate?.cast(world)
        onUltimate?()
        refreshHUD(force: true)
    }

    func chooseInsight(_ card: InsightCard) {
        // 连点时第二次点击可能落在旧卡上，只接受当前这组卡（防止重复获得）
        guard case .insight(let cards) = phase, cards.contains(card) else { return }
        rc.chooseInsight(card)
        if preStage {
            beginStage()
        } else if world.pendingLevelUps > 0 {
            world.pendingLevelUps -= 1
            phase = .insight(rc.rollInsight())
        } else {
            phase = .fighting
        }
        refreshHUD(force: true)
    }

    func rerollInsight() {
        guard case .insight = phase, let cards = rc.rerollInsight() else { return }
        phase = .insight(cards)
    }

    var rerollsLeft: Int { rc.run.rerollsLeft }

    func equipLoot(_ item: Item) {
        rc.equipFromLoot(item)
        if case .loot(let items) = phase { phase = .loot(items) }
    }

    func closeLoot() {
        guard case .loot = phase else { return }
        if let ch = rc.run.pendingEventChoices, !ch.isEmpty {
            phase = .event(ch)
        } else {
            beginStage()
        }
    }

    func chooseEvent(_ id: String) {
        guard case .event(let ids) = phase, ids.contains(id) else { return }
        gainedItem = rc.chooseEvent(id)
        app?.saveRunCheckpoint()
        beginStage()
    }

    func pause() {
        guard phase == .fighting else { return }
        pausedFrom = phase
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        phase = .fighting
    }

    /// 暂停菜单里的"放弃本世"（4.5）。
    func abandon() {
        guard phase == .paused || phase == .dead else { return }
        phase = .finished
        app?.endRun()
    }

    /// 死亡后点"转世"。
    func confirmDeath() {
        guard phase == .dead else { return }
        phase = .finished
        app?.endRun()
    }
}
