import Foundation

/// 一关的流程状态（4.2、8.5、8.7）。
struct StageDirector {
    var spawnAccum = 0.0
    var nextSecond = 1.0
    /// 敌人超过上限时排队的数量（3.3）。
    var backlog = 0
    var elitesSpawned = 0
    var hordeDone = false
    var bossSpawned = false
    var bossName = ""
    /// Boss 登场演出剩余时间（8.5）。
    var introTime = 0.0
    var victory = false
    var collectTimer = 0.0
    // 天劫（8.7）
    var wave = 0
    var waveTime = 0.0
    var boltAccum = 0.0
    var aimedAccum = 0.0
    /// 劫云进度条，从 1 降到 0。
    var progress = 1.0
    var revivedThisWave = false

    mutating func enemyKilled(_ w: BattleWorld, _ e: Enemy) {
        switch e.role {
        case .boss, .shadow:
            if w.setup.kind == .boss || w.setup.kind == .shadow {
                victory = true
                w.events.append(.slowMo(duration: 0.3, scale: 0.2))
                w.events.append(.shake(3))
                w.events.append(.haptic(3))
                if e.role == .shadow {
                    w.dropFinalLoot(at: e.pos)
                    w.events.append(.banner(text: "心魔已斩", duration: 2))
                }
            }
        case .spirit:
            progress -= w.cfg.bosses.tribulation.progressPerSpirit
        default:
            break
        }
    }
}

extension BattleWorld {
    // MARK: 流程

    func updateDirector() {
        if director.introTime > 0 {
            director.introTime -= dt
            return
        }
        switch setup.kind {
        case .normal: updateNormalStage()
        case .boss: updateBossStage()
        case .tribulation, .shadow: updateTribulation()
        }
    }

    /// 普通关剩余时间（HUD 用）。
    var normalTimeLeft: Double { max(0, cfg.balance.stage.normalDuration - time) }

    private func updateNormalStage() {
        let n = cfg.spawn.normal
        let r = Double(realm)
        let dur = cfg.balance.stage.normalDuration
        let f = min(1, time / dur)
        let start = n.startRateBase + n.startRatePerRealm * r
        let end = n.endRateBase + n.endRatePerRealm * r
        director.spawnAccum += (start + (end - start) * f) * setup.spawnMult * dt
        settleSpawns()
        // 精英（8.5）
        if director.elitesSpawned < n.eliteTimes.count, time >= n.eliteTimes[director.elitesSpawned] {
            director.elitesSpawned += 1
            for _ in 0..<Int(setup.eliteMult.rounded()) { spawnElite(at: offscreenPoint()) }
        }
        // 兽潮（8.5）
        if !director.hordeDone, time >= n.hordeTime {
            director.hordeDone = true
            for k in 0..<n.hordeCount {
                let a = Double(k) * 2 * .pi / Double(n.hordeCount)
                spawnMinion(typeIndex: 0, at: player.pos + Vec2.fromAngle(a, n.hordeRadius))
            }
            events.append(.banner(text: "兽潮来袭", duration: 1.5))
            events.append(.haptic(1))
        }
        if time >= dur { director.victory = true }
    }

    private func updateBossStage() {
        let b = cfg.spawn.boss
        let prelude = cfg.balance.stage.bossPrelude
        if !director.bossSpawned {
            director.spawnAccum += (b.preludeRateBase + b.preludeRatePerRealm * Double(realm)) * setup.spawnMult * dt
            settleSpawns()
            if director.elitesSpawned == 0, time >= b.eliteTime {
                director.elitesSpawned = 1
                for _ in 0..<Int(setup.eliteMult.rounded()) { spawnElite(at: offscreenPoint()) }
            }
            if time >= prelude {
                director.bossSpawned = true
                let bi = min(realm, cfg.bosses.realmBosses.count - 1)
                let def = cfg.bosses.realmBosses[bi]
                spawnBoss(index: bi, at: player.pos + Vec2(0, viewSize.y * 0.3))
                director.bossName = def.name
                director.introTime = cfg.balance.stage.bossIntro
                events.append(.bossIntro(name: def.name))
                events.append(.shake(2))
                events.append(.haptic(2))
            }
        } else {
            director.spawnAccum += b.afterRate * setup.spawnMult * dt
            settleSpawns()
        }
    }

    /// 每秒结算一次刷怪，小数部分累积到下一秒（8.5）。
    private func settleSpawns() {
        guard time >= director.nextSecond else { return }
        director.nextSecond += 1
        var n = Int(director.spawnAccum.rounded(.down)) + director.backlog
        director.spawnAccum -= Double(Int(director.spawnAccum.rounded(.down)))
        director.backlog = 0
        guard n > 0 else { return }
        let sp = cfg.spawn
        let groups = min(n, sp.groupMin + rng.int(max(1, sp.groupMax - sp.groupMin + 1)))
        for g in 0..<groups {
            let size = g == groups - 1 ? n : n / groups
            n -= size
            let c = offscreenPoint()
            for _ in 0..<size {
                if aliveEnemies + 1 > cfg.balance.caps.enemies {
                    director.backlog += 1
                    continue
                }
                let p = c + Vec2.fromAngle(rng.range(0, 2 * .pi), rng.range(0, sp.groupSpread))
                spawnRandomMinion(at: p)
                aliveEnemies += 0
            }
        }
    }

    // MARK: 天劫（8.7）

    private func updateTribulation() {
        let tc = cfg.bosses.tribulation
        if director.waveTime == 0 { startWave() }
        director.waveTime += dt
        let w = min(director.wave, tc.boltsPerSecond.count - 1)
        director.boltAccum += tc.boltsPerSecond[w] * dt
        let realmAtk = cfg.enemies.realms[4].atk * enemyAtkScale
        let boltDamage = realmAtk * tc.boltMult
        let lastWave = director.wave == tc.waves - 1
        while director.boltAccum >= 1 {
            director.boltAccum -= 1
            var p = player.pos + Vec2.fromAngle(rng.range(0, 2 * .pi), rng.range(40, 320))
            if lastWave, tc.aimedOnLastWave {
                director.aimedAccum += 1
                if director.aimedAccum >= Double(max(1, Int(tc.boltsPerSecond[w]))) {
                    director.aimedAccum = 0
                    p = player.pos
                }
            }
            var z = enemyZone(.circle(tc.boltRadius), at: p, telegraph: tc.boltTelegraph, damage: boltDamage)
            z.visual = .strikeMark
            zones.append(z)
        }
        if director.progress <= 0 {
            tribulationWon()
            return
        }
        if director.waveTime >= tc.waveDuration {
            // 这道雷劫结束：没杀死的雷灵消散，扛过时进度 −8%。
            for i in enemies.indices where enemies[i].role == .spirit && !enemies[i].dead {
                enemies[i].dead = true
                events.append(.enemyDied(id: enemies[i].id, pos: enemies[i].pos, element: .thunder, role: .spirit, radius: enemies[i].radius))
            }
            if !director.revivedThisWave { director.progress -= tc.progressPerWave }
            director.wave += 1
            director.waveTime = 0
            if director.wave >= tc.waves || director.progress <= 0 { tribulationWon() }
        }
    }

    private func startWave() {
        let tc = cfg.bosses.tribulation
        director.revivedThisWave = false
        director.waveTime = dt
        for _ in 0..<tc.spiritsPerWave { spawnSpirit(at: offscreenPoint()) }
        events.append(.banner(text: "第 \(director.wave + 1) / \(tc.waves) 道雷劫", duration: 1.0))
        events.append(.shake(1))
    }

    private func tribulationWon() {
        guard !director.victory else { return }
        director.victory = true
        for i in zones.indices where zones[i].team == .enemy { zones[i].dead = true }
        dropFinalLoot(at: player.pos + Vec2(0, 120))
        events.append(.banner(text: "渡劫成功", duration: 2))
        events.append(.shake(3))
        events.append(.haptic(3))
    }

    // MARK: 关卡阶段

    func updatePhase() {
        switch phase {
        case .fighting:
            if director.victory { beginClear() }
        case .clearing:
            if !enemies.contains(where: { !$0.dead }) {
                phase = .collecting
                director.collectTimer = 0
            }
        case .collecting:
            director.collectTimer += dt
            if drops.isEmpty || director.collectTimer > 3 {
                for i in drops.indices where !drops[i].dead { collect(i) }
                phase = .cleared
            }
        case .cleared, .dead:
            break
        }
    }

    /// 清场爆碎（4.2）：所有敌人按离玩家由近到远的顺序在 0.5 秒内依次爆开。
    /// 自定：Boss 被击败和渡劫成功时，剩下的小怪也一起爆开，这样关卡能干净地结束。
    private func beginClear() {
        phase = .clearing
        for i in projectiles.indices where projectiles[i].team == .enemy { projectiles[i].dead = true }
        for i in zones.indices where zones[i].team == .enemy { zones[i].dead = true }
        let alive = enemies.indices.filter { !enemies[$0].dead }
            .sorted { enemies[$0].pos.distSq(player.pos) < enemies[$1].pos.distSq(player.pos) }
        let dur = cfg.balance.stage.clearDuration
        for (k, i) in alive.enumerated() {
            enemies[i].clearAt = time + dur * Double(k) / Double(max(1, alive.count))
        }
        if setup.kind == .normal { events.append(.shake(2)) }
    }
}
