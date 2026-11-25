import Foundation

extension BattleWorld {
    // MARK: 投射物（5.5）

    func updateProjectiles() {
        var i = 0
        while i < projectiles.count {
            if !projectiles[i].dead { stepProjectile(i) }
            i += 1
        }
    }

    private func stepProjectile(_ i: Int) {
        switch projectiles[i].motion {
        case .straight:
            let v = projectiles[i].vel
            projectiles[i].pos += v * dt
            projectiles[i].range -= v.length * dt
            if projectiles[i].range <= 0 {
                expireProjectile(i)
                return
            }
        case .orbit:
            projectiles[i].orbitAngle += projectiles[i].orbitSpeed * dt
            projectiles[i].pos = player.pos + Vec2.fromAngle(projectiles[i].orbitAngle, projectiles[i].orbitRadius)
            if projectiles[i].life.isFinite {
                projectiles[i].life -= dt
                if projectiles[i].life <= 0 {
                    expireProjectile(i)
                    return
                }
            }
        }
        if projectiles[i].team == .enemy {
            let rr = projectiles[i].radius + player.radius
            if projectiles[i].pos.distSq(player.pos) <= rr * rr {
                hurtPlayer(projectiles[i].enemyDamage)
                projectiles[i].dead = true
            }
            return
        }
        collidePlayerProjectile(i)
    }

    private func expireProjectile(_ i: Int) {
        projectiles[i].dead = true
        let s = projectiles[i].skill
        if s >= 0, s < skills.count { skills[s].projectileExpired(self, proj: i) }
    }

    private func collidePlayerProjectile(_ i: Int) {
        let pr = projectiles[i]
        let reach = pr.radius + pr.halfWidth
        var hitList: [Int] = []
        forEachEnemy(inCircle: pr.pos, radius: reach) { e in
            if pr.halfWidth > 0 {
                let d = enemies[e].pos - pr.pos
                let dir = pr.vel.normalized()
                let along = abs(d.dot(dir))
                let perp = abs(d.x * dir.y - d.y * dir.x)
                let er = enemies[e].radius
                if along > pr.radius + er || perp > pr.halfWidth + er { return true }
            }
            hitList.append(e)
            return true
        }
        guard !hitList.isEmpty else { return }
        let orbit = pr.motion == .orbit
        for e in hitList {
            guard !projectiles[i].dead, e < enemies.count, !enemies[e].dead else { continue }
            let eid = enemies[e].id
            if let k = projectiles[i].hits.firstIndex(of: eid) {
                // 环绕类：同一敌人每 0.5 秒最多结算一次（7.5 剑阵）。直线类只结算一次。
                guard orbit, time - projectiles[i].hitTimes[k] >= cfg.balance.areaTick else { continue }
                projectiles[i].hitTimes[k] = time
            } else {
                projectiles[i].hits.append(eid)
                projectiles[i].hitTimes.append(time)
            }
            let s = projectiles[i].skill
            if s >= 0, s < skills.count {
                skills[s].projectileHit(self, proj: i, enemy: e)
            } else {
                damageEnemy(e, projectiles[i].hit, from: projectiles[i].pos)
            }
            if projectiles[i].pierce == 0 {
                projectiles[i].dead = true
                if s >= 0, s < skills.count { skills[s].projectileExpired(self, proj: i) }
                break
            } else if projectiles[i].pierce > 0 {
                projectiles[i].pierce -= 1
            }
        }
        // 直线投射物记录太多已命中目标没有意义，保留最近的 64 个。
        if !orbit, projectiles[i].hits.count > 64 {
            projectiles[i].hits.removeFirst(32)
            projectiles[i].hitTimes.removeFirst(32)
        }
    }

    // MARK: 区域

    func zoneContains(_ z: Zone, point p: Vec2, radius r: Double) -> Bool {
        shapeContains(z.shape, at: z.pos, point: p, radius: r)
    }

    func updateZones() {
        var i = 0
        while i < zones.count {
            if !zones[i].dead { stepZone(i) }
            i += 1
        }
    }

    private func stepZone(_ i: Int) {
        if zones[i].followPlayer { zones[i].pos = player.pos }
        if !zones[i].triggered {
            zones[i].delay -= dt
            guard zones[i].delay <= 0 else { return }
            zones[i].triggered = true
            triggerZone(i)
            if zones[i].dead { return }
            if zones[i].duration <= 0 {
                zones[i].dead = true
                return
            }
            zones[i].tickTimer = zones[i].tick
            return
        }
        if zones[i].duration.isFinite {
            zones[i].duration -= dt
            if zones[i].duration <= 0 {
                zones[i].dead = true
                return
            }
        }
        guard zones[i].team == .player else { return }
        zones[i].tickTimer -= dt
        if zones[i].tickTimer <= 0 {
            zones[i].tickTimer += zones[i].tick
            tickZone(i)
        }
    }

    private func triggerZone(_ i: Int) {
        let z = zones[i]
        if z.team == .enemy {
            if z.enemyDamage > 0, zoneContains(z, point: player.pos, radius: player.radius) {
                hurtPlayer(z.enemyDamage)
                if z.knockback > 0 { knockPlayer(from: z.pos, distance: z.knockback) }
            }
            if z.killsOwner, let o = enemies.firstIndex(where: { $0.id == z.ownerId && !$0.dead }) {
                enemies[o].dead = true
                events.append(.explosion(pos: z.pos, radius: z.radiusForDisplay, element: enemies[o].element))
            }
            if z.moveOwnerHere, let o = enemies.firstIndex(where: { $0.id == z.ownerId && !$0.dead }) {
                enemies[o].pos = z.pos
                events.append(.shake(1))
            }
            if z.visual == .telegraph, z.enemyDamage > 0, !z.killsOwner {
                events.append(.explosion(pos: z.pos, radius: min(z.radiusForDisplay, 160), element: nil))
            }
            return
        }
        tickZone(i)
        let s = z.skill
        if s >= 0, s < skills.count, z.tag < SkillBase.followUpTag { skills[s].zoneTriggered(self, zone: i) }
    }

    private func tickZone(_ i: Int) {
        let z = zones[i]
        guard z.hit.mult > 0 else { return }
        let targets = enemiesIn(z.shape, at: z.pos)
        for t in targets { damageEnemy(t, z.hit, from: z.pos) }
    }

    // MARK: 召唤物

    func updateSummons() {
        for i in summons.indices where !summons[i].dead {
            if summons[i].life > 0 {
                summons[i].life -= dt
                if summons[i].life <= 0 {
                    summons[i].dead = true
                    continue
                }
            }
            // 离玩家超过 500pt 时瞬移回来（7.4）。
            if summons[i].pos.distSq(player.pos) > 500 * 500 {
                summons[i].pos = player.pos + Vec2.fromAngle(summons[i].angle, 40)
            }
        }
    }
}
