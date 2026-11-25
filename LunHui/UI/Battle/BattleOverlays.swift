#if os(iOS)
import SwiftUI

/// 战斗中的弹窗：顿悟、掉落面板、机缘、暂停、死亡（4.3、7.2、9.2、17.5）。
struct BattleOverlays: View {
    let flow: BattleFlow

    var body: some View {
        Group {
            switch flow.phase {
            case .insight(let cards): InsightOverlay(flow: flow, cards: cards)
            case .loot(let items): LootOverlay(flow: flow, items: items)
            case .event(let ids): EventOverlay(flow: flow, ids: ids)
            case .paused: PauseOverlay(flow: flow)
            case .dead: DeathOverlay(flow: flow)
            case .fighting, .finished: EmptyView()
            }
        }
        .animation(.easeOut(duration: 0.2), value: flow.phase)
    }
}

private struct Dim<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            content
        }
        .transition(.opacity)
    }
}

// MARK: 顿悟（7.2、16.5）

struct InsightOverlay: View {
    let flow: BattleFlow
    let cards: [InsightCard]
    @State private var appeared = false

    var body: some View {
        Dim {
            VStack(spacing: 14) {
                Text("顿 悟").font(.system(size: 30, weight: .heavy)).foregroundStyle(Color.lhGold)
                Text("Lv.\(flow.world.level)").font(.caption.bold()).foregroundStyle(Color.lhSub)
                ForEach(Array(cards.enumerated()), id: \.element.key) { i, c in
                    let t = InsightGen.text(flow.cfg, c, run: flow.rc.run)
                    Button { flow.chooseInsight(c) } label: { InsightCardView(t: t) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("insight-card-\(i)")
                        .offset(y: appeared ? 0 : 80)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(duration: 0.35).delay(Double(i) * 0.06), value: appeared)
                }
                Button {
                    flow.rerollInsight()
                } label: {
                    Label("刷新（剩 \(flow.rerollsLeft) 次）", systemImage: "arrow.clockwise")
                }
                .buttonStyle(LHButtonStyle(color: .lhSub, filled: false, enabled: flow.rerollsLeft > 0))
                .disabled(flow.rerollsLeft <= 0)
            }
            .padding(.horizontal, 22)
        }
        .onAppear { appeared = true }
    }
}

struct InsightCardView: View {
    let t: InsightCardText

    var body: some View {
        let c = t.isEvolution ? Color.lhGold : (t.element.map { Color.element($0) } ?? Color(hex: "#90CAF9"))
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(c.opacity(0.2))
                Text(String(t.title.prefix(1))).font(.system(size: 22, weight: .heavy)).foregroundStyle(c)
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(t.title).font(.system(size: 18, weight: .heavy)).foregroundStyle(Color.lhText)
                    if t.isNew { Text("新").font(.system(size: 11, weight: .heavy)).foregroundStyle(.black).padding(.horizontal, 5).background(Color.green, in: Capsule()) }
                }
                Text(t.subtitle).font(.system(size: 12, weight: .semibold)).foregroundStyle(c)
                Text(t.detail).font(.system(size: 13)).foregroundStyle(Color.lhSub).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(t.isEvolution
                      ? AnyShapeStyle(LinearGradient(colors: [Color(hex: "#3E2F00"), Color(hex: "#1A1D24")], startPoint: .topLeading, endPoint: .bottomTrailing))
                      : AnyShapeStyle(Color.lhCard))
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(c.opacity(t.isEvolution ? 1 : 0.5), lineWidth: t.isEvolution ? 2.5 : 1))
        .shadow(color: t.isEvolution ? Color.lhGold.opacity(0.5) : .clear, radius: 12)
    }
}

// MARK: 掉落面板（4.3）

struct LootOverlay: View {
    let flow: BattleFlow
    let items: [Item]
    @State private var selected: Item?

    var body: some View {
        let cfg = flow.cfg
        let sorted = items.sorted { $0.qualityIndex(cfg) > $1.qualityIndex(cfg) }
        Dim {
            VStack(spacing: 12) {
                Text("本关所得").font(.system(size: 24, weight: .heavy)).foregroundStyle(Color.lhGold)
                Text("灵石 +\(NumberText.format(flow.world.stageLingShi))").font(.subheadline.bold()).foregroundStyle(Color(hex: "#FFD54F"))
                if sorted.isEmpty {
                    Text("本关没有拾取法宝").foregroundStyle(Color.lhSub).padding(.vertical, 30)
                } else {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                            ForEach(sorted) { it in
                                let delta = flow.rc.powerWith(it) - flow.rc.currentPower
                                let equipped = flow.rc.equippedInRun(it.slot)?.id == it.id
                                Button { selected = it } label: {
                                    VStack(spacing: 2) {
                                        ItemIcon(item: it, cfg: cfg, size: 56, equipped: equipped)
                                        if !equipped, delta >= 1 { PowerDelta(delta: delta) } else { Text(" ").font(.caption2) }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                }
                if let it = selected {
                    LHCard {
                        VStack(alignment: .leading, spacing: 10) {
                            ItemDetailBody(item: it, cfg: cfg, learnedSkills: Set(flow.rc.run.skills.map(\.id)))
                            let equipped = flow.rc.equippedInRun(it.slot)?.id == it.id
                            HStack {
                                PowerDelta(delta: flow.rc.powerWith(it) - flow.rc.currentPower)
                                Spacer()
                                Button(equipped ? "已装备" : "装备") { flow.equipLoot(it); selected = nil }
                                    .buttonStyle(LHButtonStyle(enabled: !equipped))
                                    .disabled(equipped)
                            }
                        }
                    }
                }
                Button("继续") { flow.closeLoot() }.buttonStyle(LHButtonStyle()).padding(.top, 4)
                    .accessibilityIdentifier("loot-continue")
            }
            .padding(.horizontal, 18)
        }
    }
}

// MARK: 机缘（9.2）

struct EventOverlay: View {
    let flow: BattleFlow
    let ids: [String]

    var body: some View {
        let cfg = flow.cfg
        Dim {
            VStack(spacing: 14) {
                Text("机 缘").font(.system(size: 30, weight: .heavy)).foregroundStyle(Color.lhGold)
                Text("心魔 \(flow.rc.run.heartDemon)").font(.caption.bold()).foregroundStyle(Color(hex: "#B388FF"))
                ForEach(Array(ids.enumerated()), id: \.element) { idx, id in
                    if let e = cfg.events.def(id) {
                        let afford = e.costPerRealm == nil || flow.rc.canAfford(e)
                        Button { if afford { flow.chooseEvent(id) } } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(e.name).font(.system(size: 19, weight: .heavy)).foregroundStyle(Color.lhText)
                                    Text(e.desc).font(.system(size: 13)).foregroundStyle(Color.lhSub)
                                    if e.costPerRealm != nil {
                                        Text("花费 \(NumberText.format(flow.rc.eventCost(e))) 灵石（本世已得 \(NumberText.format(flow.rc.run.lingShiGained))）")
                                            .font(.caption).foregroundStyle(afford ? Color(hex: "#FFD54F") : .red)
                                    }
                                }
                                Spacer()
                                if e.demon != 0 {
                                    Text(e.demon > 0 ? "心魔 +\(e.demon)" : "心魔 \(e.demon)")
                                        .font(.system(size: 13, weight: .heavy))
                                        .foregroundStyle(e.demon > 0 ? Color(hex: "#B388FF") : Color(hex: "#64B5F6"))
                                }
                            }
                            .padding(14)
                            .background(Color.lhCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(e.demon > 0 ? Color(hex: "#7E57C2") : (e.demon < 0 ? Color(hex: "#42A5F5") : Color.white.opacity(0.15)), lineWidth: 1.5))
                            .opacity(afford ? 1 : 0.45)
                        }
                        .buttonStyle(.plain)
                        .disabled(!afford)
                        .accessibilityIdentifier("event-\(idx)")
                    }
                }
            }
            .padding(.horizontal, 22)
        }
    }
}

// MARK: 暂停（17.5）

struct PauseOverlay: View {
    let flow: BattleFlow
    @State private var confirmAbandon = false

    var body: some View {
        let cfg = flow.cfg
        let run = flow.rc.run
        let s = flow.world.stats
        Dim {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("暂停").font(.system(size: 28, weight: .heavy)).foregroundStyle(Color.lhGold).frame(maxWidth: .infinity)
                    LHCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("第 \(run.tier) 劫 · \(run.lingGen.displayName(cfg.elements)) · \(cfg.schools.def(run.school).name)").font(.headline).foregroundStyle(Color.lhText)
                            Text("功法").font(.caption.bold()).foregroundStyle(Color.lhSub)
                            ForEach(run.skills, id: \.id) { sk in
                                let name = sk.evolved ? (cfg.evolutions.forSkill(sk.id)?.name ?? sk.id) : (cfg.skills.def(sk.id)?.name ?? sk.id)
                                Text("\(name) \(sk.evolved ? "（神通）" : "Lv.\(sk.level)") · \(cfg.elements.name(sk.element))").font(.subheadline).foregroundStyle(Color.element(sk.element))
                            }
                            if !run.passiveOrder.isEmpty {
                                Text("心法").font(.caption.bold()).foregroundStyle(Color.lhSub)
                                Text(run.passiveOrder.map { "\(cfg.passives.def($0)?.name ?? $0) Lv.\(run.passives[$0] ?? 0)" }.joined(separator: "、"))
                                    .font(.subheadline).foregroundStyle(Color.lhText)
                            }
                            if !run.events.isEmpty {
                                Text("机缘").font(.caption.bold()).foregroundStyle(Color.lhSub)
                                Text(run.events.compactMap { cfg.events.def($0)?.name }.joined(separator: "、")).font(.subheadline).foregroundStyle(Color.lhText)
                            }
                            Text("秘境词缀").font(.caption.bold()).foregroundStyle(Color.lhSub)
                            ForEach(StatAssembler.activeAffixes(cfg, run: run), id: \.self) { id in
                                if let a = cfg.dungeonAffixes.def(id) {
                                    Text("\(a.name)：\(a.desc)").font(.subheadline).foregroundStyle(a.isBuff ? Color.green : Color.orange)
                                }
                            }
                        }
                    }
                    LHCard {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("属性").font(.caption.bold()).foregroundStyle(Color.lhSub)
                            statRow("攻击", NumberText.format(s.atk))
                            statRow("生命", NumberText.format(s.hp))
                            statRow("暴击率 / 暴击伤害", "\(NumberText.percent(s.critRate)) / \(NumberText.percent(s.critDmg))")
                            statRow("全伤害", NumberText.percent(s.dmgPct))
                            statRow("冷却缩减", NumberText.percent(s.cdr))
                            statRow("范围", NumberText.percent(s.area))
                            statRow("减伤", NumberText.percent(s.dmgReduce))
                            statRow("寻宝", NumberText.percent(s.magicFind + flow.world.magicFindBonus))
                        }
                    }
                    HStack {
                        Button("放弃本世") { confirmAbandon = true }.buttonStyle(LHButtonStyle(color: .red, filled: false))
                        Spacer()
                        Button("继续") { flow.resume() }.buttonStyle(LHButtonStyle())
                            .accessibilityIdentifier("pause-resume")
                    }
                }
                .padding(20)
            }
        }
        .confirmationDialog("放弃本世会按死亡结算，收获全部保留", isPresented: $confirmAbandon, titleVisibility: .visible) {
            Button("放弃并结算", role: .destructive) { flow.abandon() }
        }
    }

    private func statRow(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(Color.lhSub); Spacer(); Text(v).foregroundStyle(Color.lhText).monospacedDigit() }.font(.subheadline)
    }
}

// MARK: 死亡（4.4）

struct DeathOverlay: View {
    let flow: BattleFlow

    var body: some View {
        Dim {
            VStack(spacing: 16) {
                Text("兵 解").font(.system(size: 40, weight: .heavy)).foregroundStyle(Color(hex: "#B0BEC5"))
                Text("身死道消，宿慧不灭").foregroundStyle(Color.lhSub)
                Text("止步 \(flow.rc.stageTitle())").font(.headline).foregroundStyle(Color.lhText)
                Button("转世") { flow.confirmDeath() }.buttonStyle(LHButtonStyle()).padding(.top, 10)
                    .accessibilityIdentifier("death-confirm")
            }
        }
    }
}
#endif
