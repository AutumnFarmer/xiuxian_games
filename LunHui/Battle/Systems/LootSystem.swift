import Foundation

/// 掉落参数（12.3），在 items.json 的 drops 里。
struct DropsConfig: Codable {
    var minionItemChance: Double
    var eliteItems: Double
    var bossItems: Double
    var bossMinQuality: Int
    var finalItems: Double
    var finalMinQuality: Int
    var minionLingShiChance: Double
    var minionLingShi: Double
    var eliteLingShi: Double
    var bossLingShi: Double
    var finalLingShi: Double
    var lingShiTierBonus: Double
}

extension BattleWorld {
    var drops_: DropsConfig { cfg.items.drops }

    // MARK: 生成掉落

    func dropExp(_ amount: Double, at p: Vec2) {
        if drops.count >= cfg.balance.caps.drops {
            // 超过上限时合并（3.3）。
            if let k = drops.lastIndex(where: { $0.kind == .exp && !$0.dead }) {
                drops[k].amount += amount
                return
            }
        }
        drops.append(Drop(id: makeId(), kind: .exp, amount: amount, pos: p, vel: popVelocity(60)))
    }

    func dropLingShi(_ base: Double, at p: Vec2) {
        let amount = base * (1 + stats.lingShiPct + lingShiBonus) * (1 + drops_.lingShiTierBonus * Double(tier - 1))
        guard amount > 0 else { return }
        if drops.count >= cfg.balance.caps.drops,
           let k = drops.lastIndex(where: { $0.kind == .lingShi && !$0.dead }) {
            drops[k].amount += amount
            return
        }
        drops.append(Drop(id: makeId(), kind: .lingShi, amount: amount, pos: p, vel: popVelocity(90)))
    }

    /// 掉 n 件法宝（12.3）。期望数量的整数部分必掉，小数部分按概率再掉 1 件。
    /// minQuality：第一件的品质下限（保底）。
    func dropItems(expected: Double, source: ItemDropSource, minQuality: Int, at p: Vec2) {
        guard let roll = rollItem else { return }
        let x = expected * (1 + dropBonus) * dropFactor
        var n = Int(x.rounded(.down))
        if lootRng.chance(x - Double(n)) { n += 1 }
        for k in 0..<n {
            guard let info = roll(&lootRng, source, k == 0 ? minQuality : 0) else { continue }
            var d = Drop(id: makeId(), kind: .item, amount: 1, pos: p, vel: popVelocity(info.quality >= 3 ? 160 : 110))
            d.itemIndex = info.index
            d.quality = info.quality
            drops.append(d)
            events.append(.itemDropped(quality: info.quality, pos: p))
        }
    }

    func dropLoot(for e: Enemy) {
        let r = Double(1 + realm)
        switch e.role {
        case .minion:
            if lootRng.chance(drops_.minionLingShiChance) { dropLingShi(drops_.minionLingShi * r, at: e.pos) }
            dropItems(expected: drops_.minionItemChance, source: .minion, minQuality: 0, at: e.pos)
        case .elite:
            dropLingShi(drops_.eliteLingShi * r, at: e.pos)
            dropItems(expected: drops_.eliteItems, source: .elite, minQuality: 0, at: e.pos)
        case .boss:
            dropLingShi(drops_.bossLingShi * r, at: e.pos)
            dropItems(expected: drops_.bossItems, source: .boss, minQuality: drops_.bossMinQuality, at: e.pos)
        case .shadow, .spirit:
            break
        }
    }

    /// 天劫、心魔影子的掉落（12.3），在最终关胜利时调用。
    func dropFinalLoot(at p: Vec2) {
        dropLingShi(drops_.finalLingShi, at: p)
        dropItems(expected: drops_.finalItems, source: .final, minQuality: drops_.finalMinQuality, at: p)
    }

    private func popVelocity(_ speed: Double) -> Vec2 {
        Vec2.fromAngle(rng.range(0, 2 * .pi), rng.range(speed * 0.5, speed))
    }

    // MARK: 拾取

    func updateDrops() {
        let collectAll = phase == .collecting || phase == .clearing
        let pick2 = stats.pickup * stats.pickup
        let fly = cfg.balance.pickupFlySpeed * (collectAll ? 2 : 1)
        let reach = player.radius + 8
        for i in drops.indices where !drops[i].dead {
            if !drops[i].flying {
                if drops[i].vel.lengthSq > 1 {
                    drops[i].pos += drops[i].vel * dt
                    drops[i].vel = drops[i].vel * 0.88
                }
                if collectAll || drops[i].pos.distSq(player.pos) <= pick2 { drops[i].flying = true }
                continue
            }
            let d = player.pos - drops[i].pos
            let l = d.length
            if l <= reach + fly * dt {
                collect(i)
            } else {
                drops[i].pos += d / l * fly * dt
            }
        }
    }

    func collect(_ i: Int) {
        drops[i].dead = true
        let d = drops[i]
        switch d.kind {
        case .exp:
            gainExp(d.amount)
        case .lingShi:
            stageLingShi += d.amount
        case .item:
            stageItemCount += 1
            onItemPicked?(d.itemIndex)
        }
    }
}
