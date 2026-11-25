import Foundation

extension BattleWorld {
    // MARK: 生成敌人（8.1 到 8.4）

    /// 敌人数值的共同系数：劫数和秘境词缀。
    var enemyHpScale: Double { cfg.balance.enemyScale(tier: tier) * setup.enemyHpMult }
    var enemyAtkScale: Double { cfg.balance.enemyScale(tier: tier) * setup.enemyAtkMult }

    @discardableResult
    func spawnMinion(typeIndex ti: Int, at p: Vec2) -> Int? {
        guard aliveEnemies < cfg.balance.caps.enemies else { return nil }
        let t = cfg.enemies.types[ti]
        let r = cfg.enemies.realms[realm]
        let e = Enemy(id: makeId(), role: .minion, typeIndex: ti, pos: p, radius: t.radius,
                      speed: t.speed * setup.enemySpeedMult,
                      hp: r.hp * t.hpMult * enemyHpScale, maxHp: r.hp * t.hpMult * enemyHpScale,
                      atk: r.atk * t.atkMult * enemyAtkScale, element: setup.themeElement)
        enemies.append(e)
        aliveEnemies += 1
        return enemies.count - 1
    }

    @discardableResult
    func spawnElite(at p: Vec2) -> Int? {
        let ec = cfg.enemies.elite
        let r = cfg.enemies.realms[realm]
        let baseIndex = cfg.enemies.types.firstIndex { $0.id == ec.base } ?? 0
        var e = Enemy(id: makeId(), role: .elite, typeIndex: baseIndex, pos: p, radius: ec.radius,
                      speed: ec.speed * setup.enemySpeedMult,
                      hp: r.hp * ec.hpMult * enemyHpScale, maxHp: r.hp * ec.hpMult * enemyHpScale,
                      atk: r.atk * ec.atkMult * enemyAtkScale, element: setup.themeElement)
        var pool = EliteAffix.allCases
        rng.shuffle(&pool)
        e.affixA = pool[0]
        if tier >= ec.twoAffixesFromTier { e.affixB = pool[1] }
        for a in [e.affixA, e.affixB].compactMap({ $0 }) {
            let pr = eliteAffixParams(a)
            switch a {
            case .swift: e.speed *= pr["speedMult"] ?? 1.6
            case .armored:
                e.hp *= pr["hpMult"] ?? 1.8
                e.maxHp = e.hp
                e.radius *= pr["sizeMult"] ?? 1.3
            case .summoner: e.timerA = pr["interval"] ?? 6
            case .thunder: e.timerB = pr["interval"] ?? 4
            case .split: break
            }
        }
        enemies.append(e)
        aliveEnemies += 1
        return enemies.count - 1
    }

    func eliteAffixParams(_ a: EliteAffix) -> [String: Double] {
        cfg.enemies.eliteAffixes.first { $0.id == a.rawValue }?.params ?? [:]
    }

    /// 天劫的雷灵（8.7）。
    @discardableResult
    func spawnSpirit(at p: Vec2) -> Int? {
        let tc = cfg.bosses.tribulation
        let r = cfg.enemies.realms[4]
        let ti = cfg.enemies.types.firstIndex { $0.id == "spirit" } ?? 0
        let e = Enemy(id: makeId(), role: .spirit, typeIndex: ti, pos: p, radius: tc.spiritRadius,
                      speed: tc.spiritSpeed * setup.enemySpeedMult,
                      hp: r.hp * tc.spiritHpMult * enemyHpScale, maxHp: r.hp * tc.spiritHpMult * enemyHpScale,
                      atk: r.atk * tc.spiritAtkMult * enemyAtkScale, element: .thunder)
        enemies.append(e)
        aliveEnemies += 1
        return enemies.count - 1
    }

    @discardableResult
    func spawnBoss(index bi: Int, at p: Vec2) -> Int {
        let b = cfg.bosses.realmBosses[bi]
        let r = cfg.enemies.realms[realm]
        var e = Enemy(id: makeId(), role: .boss, typeIndex: bi, pos: p, radius: b.radius,
                      speed: cfg.bosses.common.chaseSpeed * setup.enemySpeedMult,
                      hp: r.bossHp * enemyHpScale, maxHp: r.bossHp * enemyHpScale,
                      atk: r.atk * enemyAtkScale, element: setup.themeElement)
        e.timerA = cfg.bosses.common.moveInterval
        enemies.append(e)
        aliveEnemies += 1
        return enemies.count - 1
    }

    /// 刷一只按境界权重随机类型的小怪（8.3）。
    func spawnRandomMinion(at p: Vec2) {
        let w = cfg.enemies.realmWeights[min(realm, cfg.enemies.realmWeights.count - 1)].weights
        let k = rng.weightedIndex(w) ?? 0
        let minionTypes = cfg.enemies.minionTypes
        let id = minionTypes[min(k, minionTypes.count - 1)].id
        let ti = cfg.enemies.types.firstIndex { $0.id == id } ?? 0
        spawnMinion(typeIndex: ti, at: p)
    }

    // MARK: 更新敌人

    func updateEnemies() {
        let st = cfg.elements.status
        var alive = 0
        let n = enemies.count
        for i in 0..<n where !enemies[i].dead {
            alive += 1
            // 状态计时
            if enemies[i].flawTime > 0 {
                enemies[i].flawTime -= dt
                if enemies[i].flawTime <= 0 { enemies[i].flawStacks = 0 }
            }
            if enemies[i].rootTime > 0 { enemies[i].rootTime -= dt }
            if enemies[i].slowTime > 0 { enemies[i].slowTime -= dt }
            if enemies[i].stunTime > 0 { enemies[i].stunTime -= dt }
            if enemies[i].freezeTime > 0 { enemies[i].freezeTime -= dt }
            if enemies[i].vulnTime > 0 {
                enemies[i].vulnTime -= dt
                if enemies[i].vulnTime <= 0 { enemies[i].vulnAmount = 0 }
            }
            for k in 0..<7 where enemies[i].marks[k] > 0 { enemies[i].marks[k] -= dt }
            if enemies[i].burnTicks > 0 {
                enemies[i].burnTimer -= dt
                if enemies[i].burnTimer <= 0 {
                    enemies[i].burnTimer += st.burn.interval
                    enemies[i].burnTicks -= 1
                    damageFixed(i, enemies[i].burnTick, element: .fire)
                    if enemies[i].dead { continue }
                }
            }
            // 清场爆碎（4.2）
            if enemies[i].clearAt >= 0 {
                if time >= enemies[i].clearAt { killEnemy(i, cleared: true) }
                continue
            }
            if director.introTime > 0 { continue }
            moveEnemy(i)
            if enemies[i].dead { continue }
            actEnemy(i)
        }
        aliveEnemies = alive
        separateEnemies()
    }

    private func moveEnemy(_ i: Int) {
        if enemies[i].knockTime > 0 {
            let f = enemies[i].knockTime / cfg.balance.knockbackTime
            enemies[i].pos += enemies[i].knock * f * dt
            enemies[i].knockTime -= dt
            return
        }
        guard enemies[i].canMove else { return }
        if enemies[i].role == .boss, enemies[i].dashLeft > 0 {
            enemies[i].dashLeft -= dt
            enemies[i].pos += enemies[i].dashVel * dt
            return
        }
        if enemies[i].role == .boss, enemies[i].seqLeft > 0 { return }
        let toP = player.pos - enemies[i].pos
        let dist = toP.length
        // 离玩家太远：瞬移到前方屏幕外（8.1）。Boss 不瞬移。
        if dist > cfg.balance.enemyRespawnDistance, !enemies[i].isBossLike {
            enemies[i].pos = offscreenPointAhead()
            return
        }
        var dir = toP.normalized(or: .up)
        let t = cfg.enemies.types[enemies[i].typeIndex]
        if enemies[i].role == .minion, t.id == "archer" {
            let keep = t.params?["keepDistance"] ?? 300
            if dist < keep - 20 { dir = -dir } else if dist < keep + 20 { dir = .zero }
        }
        if enemies[i].role == .minion, t.id == "bomber", enemies[i].phase == 1 { return }
        let speed = enemies[i].speed * enemies[i].slowFactor
        enemies[i].pos += dir * speed * dt
    }

    private func actEnemy(_ i: Int) {
        guard enemies[i].canAct else { return }
        let e = enemies[i]
        // 接触伤害（8.1）
        let rr = e.radius + player.radius
        if e.pos.distSq(player.pos) <= rr * rr, enemies[i].role != .shadow {
            hurtPlayer(e.atk)
        }
        let actRate = e.slowFactor
        switch e.role {
        case .minion:
            let t = cfg.enemies.types[e.typeIndex]
            if t.id == "archer" { archerAct(i, t, actRate) }
            if t.id == "bomber" { bomberAct(i, t) }
        case .elite:
            eliteAct(i, actRate)
        case .boss:
            bossAct(i, actRate)
        case .shadow:
            shadowAct(i, actRate)
        case .spirit:
            break
        }
    }

    private func archerAct(_ i: Int, _ t: EnemiesConfig.TypeDef, _ rate: Double) {
        let p = t.params ?? [:]
        enemies[i].timerA += dt * rate
        let interval = p["interval"] ?? 2.5
        guard enemies[i].timerA >= interval else { return }
        enemies[i].timerA = 0
        let dir = (player.pos - enemies[i].pos).normalized(or: .up)
        shootEnemyProjectile(from: enemies[i].pos, dir: dir, speed: p["projSpeed"] ?? 220,
                             radius: p["projRadius"] ?? 8, damage: enemies[i].atk, visual: .arrow, element: enemies[i].element)
    }

    private func bomberAct(_ i: Int, _ t: EnemiesConfig.TypeDef) {
        let p = t.params ?? [:]
        if enemies[i].phase == 0 {
            let trig = p["trigger"] ?? 50
            if enemies[i].pos.dist(player.pos) <= trig + enemies[i].radius + player.radius {
                enemies[i].phase = 1
                var z = enemyZone(.circle(p["radius"] ?? 80), at: enemies[i].pos, telegraph: p["fuse"] ?? 0.8,
                                  damage: enemies[i].atk, ownerId: enemies[i].id)
                z.killsOwner = true
                zones.append(z)
            }
        }
    }

    func shootEnemyProjectile(from p: Vec2, dir: Vec2, speed: Double, radius: Double, damage: Double,
                              visual: ProjVisual, element: Element?, range: Double = 900) {
        guard projectiles.count < cfg.balance.caps.projectiles else { return }
        projectiles.append(Projectile(id: makeId(), team: .enemy, motion: .straight, visual: visual, pos: p,
                                      vel: dir * speed, radius: radius, range: range, pierce: 0,
                                      hit: Hit(mult: 0, element: nil, school: nil, statusChance: -1),
                                      enemyDamage: damage, element: element))
    }

    /// 敌人阵营的预警区域（8.1：至少 0.6 秒）。
    func enemyZone(_ shape: ZoneShape, at p: Vec2, telegraph: Double, damage: Double, ownerId: Int = -1,
                   knockback: Double = 0, visual: ZoneVisual = .telegraph) -> Zone {
        var z = Zone(id: makeId(), team: .enemy, shape: shape, pos: p, visual: visual, element: nil,
                     delay: max(0.6, telegraph), delayTotal: max(0.6, telegraph), duration: 0,
                     hit: Hit(mult: 0, element: nil, school: nil, statusChance: -1), enemyDamage: damage)
        z.ownerId = ownerId
        z.knockback = knockback
        return z
    }

    private func eliteAct(_ i: Int, _ rate: Double) {
        if enemies[i].has(.summoner) {
            enemies[i].timerA -= dt * rate
            if enemies[i].timerA <= 0 {
                let pr = eliteAffixParams(.summoner)
                enemies[i].timerA = pr["interval"] ?? 6
                let c = enemies[i].pos
                for k in 0..<Int(pr["count"] ?? 4) {
                    spawnMinion(typeIndex: 0, at: c + Vec2.fromAngle(Double(k) * .pi / 2, 40))
                }
            }
        }
        if enemies[i].has(.thunder) {
            enemies[i].timerB -= dt * rate
            if enemies[i].timerB <= 0 {
                let pr = eliteAffixParams(.thunder)
                enemies[i].timerB = pr["interval"] ?? 4
                zones.append(enemyZone(.circle(pr["radius"] ?? 70), at: player.pos, telegraph: pr["telegraph"] ?? 0.8,
                                       damage: enemies[i].atk * (pr["mult"] ?? 3), ownerId: enemies[i].id))
            }
        }
    }

    // MARK: 推开（8.1）

    private func separateEnemies() {
        let k = cfg.balance.enemyNeighborCheck
        for i in enemies.indices where !enemies[i].dead && !enemies[i].isBossLike {
            let p = enemies[i].pos
            let r = enemies[i].radius
            grid.query(p, r * 2 + 4, into: &gridScratch)
            var checked = 0
            var push = Vec2.zero
            for kk in gridScratch {
                let j = Int(kk)
                if j == i || j >= enemies.count || enemies[j].dead { continue }
                checked += 1
                if checked > k { break }
                let d = p - enemies[j].pos
                let minD = r + enemies[j].radius
                let l2 = d.lengthSq
                if l2 < minD * minD, l2 > 1e-6 {
                    let l = l2.squareRoot()
                    push += d / l * ((minD - l) * 0.5)
                }
            }
            if push.lengthSq > 0 { enemies[i].pos += push * 0.5 }
        }
    }

    // MARK: 死亡

    /// 敌人死亡：掉落、真元、修为、分裂、碎裂等。cleared 表示清场爆碎。
    func killEnemy(_ i: Int, cleared: Bool = false, by hit: Hit? = nil) {
        guard !enemies[i].dead else { return }
        enemies[i].dead = true
        enemies[i].hp = min(0, enemies[i].hp)
        let e = enemies[i]
        kills += 1
        events.append(.enemyDied(id: e.id, pos: e.pos, element: e.element, role: e.role, radius: e.radius))
        // 冰封中被击杀时碎裂（6.4）
        if e.freezeTime > 0, !cleared { shatter(at: e.pos) }
        // 真元（7.3）
        switch e.role {
        case .minion, .spirit: addUltCharge(cfg.balance.ult.perKill)
        case .elite: addUltCharge(cfg.balance.ult.perElite)
        default: break
        }
        // 修为（4.6）
        let minionExp = 1 + Double(realm)
        switch e.role {
        case .minion, .spirit: dropExp(minionExp, at: e.pos)
        case .elite: dropExp(minionExp * cfg.enemies.elite.expMult, at: e.pos)
        case .boss, .shadow: dropExp(minionExp * cfg.enemies.bossExpMult, at: e.pos)
        }
        // 掉落（12.3），雷灵不掉
        if e.role != .spirit { dropLoot(for: e) }
        // 分裂（8.4）
        if e.role == .elite, e.has(.split) {
            let n = Int(eliteAffixParams(.split)["count"] ?? 5)
            let runner = cfg.enemies.types.firstIndex { $0.id == "runner" } ?? 0
            for k in 0..<n { spawnMinion(typeIndex: runner, at: e.pos + Vec2.fromAngle(Double(k) * 2 * .pi / Double(n), 30)) }
        }
        if e.role == .elite { events.append(.hitStop(0.05)); events.append(.shake(1)) }
        // 尸爆词缀（9.3）
        if setup.minionExplode, e.role == .minion, !cleared {
            zones.append(enemyZone(.circle(50), at: e.pos, telegraph: 0.6, damage: e.atk))
        }
        for sk in skills { sk.enemyKilled(self, e) }
        for h in hooks { h.enemyKilled(self, e) }
        if let hit, case .skill(let s) = hit.source, s >= 0, s < skills.count { skills[s].killedEnemy(self, e, hit: hit) }
        director.enemyKilled(self, e)
        // 发出者死亡后，它没触发的预警一起消失。爆灵被打死就不会爆。
        for z in zones.indices where zones[z].ownerId == e.id && !zones[z].triggered && zones[z].team == .enemy {
            if e.role == .minion || e.role == .elite { zones[z].dead = true }
        }
    }
}
