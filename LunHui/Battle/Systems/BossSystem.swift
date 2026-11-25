import Foundation

extension BattleWorld {
    // MARK: 境界 Boss（8.6）

    func bossAct(_ i: Int, _ rate: Double) {
        let common = cfg.bosses.common
        let def = cfg.bosses.realmBosses[enemies[i].typeIndex]
        if !enemies[i].enraged, enemies[i].hp <= enemies[i].maxHp * common.enrageAt {
            enemies[i].enraged = true
            events.append(.banner(text: "\(def.name)狂暴了！", duration: 1.2))
            events.append(.shake(2))
        }
        // 正在进行的连续招式（扑击的冲刺、连爪）
        if enemies[i].seqLeft > 0 {
            enemies[i].seqTimer -= dt * rate
            if enemies[i].seqTimer <= 0 { continueSequence(i, def) }
            return
        }
        enemies[i].timerA -= dt * rate
        guard enemies[i].timerA <= 0 else { return }
        let move = def.moves[enemies[i].moveIndex % def.moves.count]
        enemies[i].moveIndex += 1
        castBossMove(i, move)
        enemies[i].timerA = enemies[i].enraged ? common.enragedInterval : common.moveInterval
    }

    /// 狂暴时投射物数量 ×1.5，向上取整（8.6）。
    private func bossCount(_ i: Int, _ n: Double) -> Int {
        let c = enemies[i].enraged ? (n * cfg.bosses.common.enrageProjMult).rounded(.up) : n
        return max(1, Int(c))
    }

    private func castBossMove(_ i: Int, _ m: BossMove) {
        let b = enemies[i]
        let atk = b.atk
        let toP = (player.pos - b.pos).normalized(or: .up)
        switch m.kind {
        case "dash":
            let len = m.v("length", 300)
            zones.append(enemyZone(.rect(m.v("width", 60) / 2, len, toP), at: b.pos, telegraph: m.v("telegraph", 0.6),
                                   damage: atk * m.v("mult", 3), ownerId: b.id))
            enemies[i].seqLeft = 1
            enemies[i].seqKind = 0
            enemies[i].seqTimer = max(0.6, m.v("telegraph", 0.6))
            enemies[i].dashVel = toP * (len / max(0.05, m.v("dashTime", 0.3)))
        case "summon":
            let minions = cfg.enemies.minionTypes
            let id = minions[min(Int(m.v("typeIndex")), minions.count - 1)].id
            let ti = cfg.enemies.types.firstIndex { $0.id == id } ?? 0
            let n = Int(m.v("count", 6))
            for k in 0..<n {
                spawnMinion(typeIndex: ti, at: b.pos + Vec2.fromAngle(Double(k) * 2 * .pi / Double(n), b.radius + 30))
            }
            events.append(.banner(text: m.name, duration: 0.8))
        case "swipes":
            enemies[i].seqLeft = Int(m.v("count", 3))
            enemies[i].seqKind = 1
            enemies[i].seqTimer = 0
            continueSequence(i, cfg.bosses.realmBosses[b.typeIndex], move: m)
        case "webs":
            for _ in 0..<bossCount(i, m.v("count", 3)) {
                let p = player.pos + Vec2.fromAngle(rng.range(0, 2 * .pi), rng.range(0, m.v("spread", 120)))
                var z = enemyZone(.circle(m.v("radius", 70)), at: p, telegraph: m.v("flightTime", 0.6), damage: 0,
                                  ownerId: b.id, visual: .web)
                z.duration = m.v("duration", 5)
                z.slowPlayer = m.v("slow", 0.5)
                zones.append(z)
            }
        case "rain":
            let spread = m.v("spread", 220)
            for _ in 0..<bossCount(i, m.v("count", 6)) {
                let p = spread > 0
                    ? player.pos + Vec2.fromAngle(rng.range(0, 2 * .pi), rng.range(0, spread))
                    : randomPointInView(around: player.pos)
                zones.append(enemyZone(.circle(m.v("radius", 60)), at: p, telegraph: m.v("telegraph", 0.8),
                                       damage: atk * m.v("mult", 2), ownerId: b.id))
            }
        case "rings":
            let w = m.v("width", 70)
            for k in 0..<Int(m.v("count", 3)) {
                let inner = Double(k) * w, outer = Double(k + 1) * w + b.radius
                let shape: ZoneShape = k == 0 ? .circle(outer) : .ring(inner + b.radius, outer)
                zones.append(enemyZone(shape, at: b.pos, telegraph: m.v("telegraph", 0.6) + Double(k) * m.v("interval", 0.35),
                                       damage: atk * m.v("mult", 3), ownerId: b.id))
            }
        case "shots":
            let n = bossCount(i, m.v("count", 3))
            let step = m.v("spreadDeg", 15).degToRad
            for k in 0..<n {
                let a = (Double(k) - Double(n - 1) / 2) * step
                shootEnemyProjectile(from: b.pos, dir: toP.rotated(a), speed: m.v("speed", 300), radius: m.v("radius", 25),
                                     damage: atk * m.v("mult", 2.5), visual: .fireball, element: b.element)
            }
        case "leap":
            var z = enemyZone(.circle(m.v("radius", 150)), at: player.pos, telegraph: m.v("telegraph", 0.8),
                              damage: atk * m.v("mult", 4), ownerId: b.id)
            z.moveOwnerHere = true
            zones.append(z)
        case "lines":
            let n = bossCount(i, m.v("count", 8))
            for k in 0..<n {
                let d = toP.rotated(Double(k) * 2 * .pi / Double(n))
                zones.append(enemyZone(.rect(m.v("width", 20) / 2, m.v("length", 500), d), at: b.pos,
                                       telegraph: m.v("telegraph", 0.8), damage: atk * m.v("mult", 3), ownerId: b.id))
            }
        case "blink":
            let behind = player.pos - player.facing.normalized() * m.v("distance", 150)
            enemies[i].pos = behind
            events.append(.explosion(pos: behind, radius: 40, element: b.element))
            zones.append(enemyZone(.circle(m.v("radius", 130)), at: behind, telegraph: m.v("telegraph", 0.6),
                                   damage: atk * m.v("mult", 3.5), ownerId: b.id))
        case "cone":
            zones.append(enemyZone(.cone(m.v("radius", 400), m.v("angle", 60).degToRad / 2, toP), at: b.pos,
                                   telegraph: m.v("telegraph", 1.0), damage: atk * m.v("mult", 4), ownerId: b.id))
        case "nova":
            zones.append(enemyZone(.circle(m.v("radius", 200)), at: b.pos, telegraph: m.v("telegraph", 0.8),
                                   damage: atk * m.v("mult", 3), ownerId: b.id, knockback: m.v("knockback", 150)))
        default:
            break
        }
    }

    private func continueSequence(_ i: Int, _ def: BossesConfig.RealmBoss, move: BossMove? = nil) {
        switch enemies[i].seqKind {
        case 0:
            // 扑击：预警结束，开始冲刺
            enemies[i].seqLeft = 0
            let t = enemies[i].dashVel.length > 0 ? 0.3 : 0
            enemies[i].dashLeft = t
        default:
            // 连爪：每次朝玩家方向一记扇形
            let m = move ?? def.moves.first { $0.kind == "swipes" }!
            let b = enemies[i]
            let dir = (player.pos - b.pos).normalized(or: .up)
            zones.append(enemyZone(.cone(m.v("radius", 120) + b.radius, m.v("angle", 90).degToRad / 2, dir), at: b.pos,
                                   telegraph: m.v("telegraph", 0.6), damage: b.atk * m.v("mult", 2), ownerId: b.id))
            enemies[i].seqLeft -= 1
            enemies[i].seqTimer = max(0.6, m.v("telegraph", 0.6))
        }
    }

    // MARK: 心魔影子（8.8），M6 实现

    func shadowAct(_ i: Int, _ rate: Double) {
        shadowController?.act(self, i, rate)
    }
}

/// 心魔影子的行为。M6 之前为空。
protocol ShadowControlling: AnyObject {
    func act(_ w: BattleWorld, _ i: Int, _ rate: Double)
}
