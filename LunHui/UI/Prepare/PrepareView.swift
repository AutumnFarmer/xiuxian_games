#if os(iOS)
import SwiftUI

/// 出发准备（4.1、17.4）。
struct PrepareView: View {
    @Environment(AppState.self) private var app
    @State private var tier = 1
    @State private var lingGenIndex = 0
    @State private var school: School = .sword
    @State private var pills: [String] = []
    @State private var pickSlot: ItemSlot?

    var body: some View {
        let cfg = app.config
        let s = app.save
        let pv = s.nextRunPreview
        VStack(spacing: 0) {
            HStack {
                Button { app.goCave() } label: { Image(systemName: "chevron.left").font(.system(size: 18, weight: .bold)).frame(width: 44, height: 44) }
                Text("出发准备").font(.system(size: 20, weight: .heavy)).foregroundStyle(Color.lhText)
                Spacer()
            }
            .padding(.horizontal, 8)
            ScrollView {
                VStack(spacing: 12) {
                    tierCard(cfg, s)
                    previewCard(cfg, pv)
                    lingGenCard(cfg, pv)
                    schoolCard(cfg, s)
                    gearCard(cfg, s)
                    pillCard(cfg, s)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 90)
            }
            .overlay(alignment: .bottom) {
                let cost = app.pillsCost(pills)
                let ok = s.lingShi >= cost && pv.lingGenChoices.indices.contains(lingGenIndex)
                Button {
                    guard ok else { return }
                    app.startRun(tier: tier, school: school, lingGen: pv.lingGenChoices[lingGenIndex], pills: pills)
                } label: {
                    Text(cost > 0 ? "出 发（丹药 \(NumberText.format(cost)) 灵石）" : "出 发").frame(maxWidth: .infinity)
                }
                .buttonStyle(LHButtonStyle(enabled: ok))
                .font(.system(size: 18, weight: .heavy))
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
                .background(LinearGradient(colors: [.clear, Color.lhBg], startPoint: .top, endPoint: .center).ignoresSafeArea())
            }
        }
        .lhScreen()
        .onAppear {
            tier = min(max(1, s.lastTier), s.maxTierUnlocked)
            school = School(rawValue: s.lastSchool).flatMap { s.unlockedSchools.contains($0.rawValue) ? $0 : nil } ?? .sword
            pills = s.lastPills.filter { app.pillsCost([$0]) <= s.lingShi }
        }
        .sheet(item: $pickSlot) { slot in
            ItemPickerSheet(slot: slot)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: 劫数（11.5）

    private func tierCard(_ cfg: GameConfig, _ s: SaveData) -> some View {
        let power = StatAssembler.power(cfg, save: s, pills: pills)
        let rec = StatAssembler.recommendedPower(cfg, tier: tier)
        return LHCard {
            VStack(spacing: 8) {
                HStack {
                    RepeatButton(symbol: "minus") { tier = max(1, tier - 1) }
                    Spacer()
                    VStack(spacing: 0) {
                        Text("第 \(tier) 劫").font(.system(size: 30, weight: .heavy)).foregroundStyle(Color.lhGold)
                        Text("已解锁到第 \(s.maxTierUnlocked) 劫").font(.caption).foregroundStyle(Color.lhSub)
                    }
                    Spacer()
                    RepeatButton(symbol: "plus") { tier = min(s.maxTierUnlocked, tier + 1) }
                }
                HStack {
                    Text("怪物强度 ×\(scaleText(cfg.balance.enemyScale(tier: tier)))").font(.caption).foregroundStyle(Color.lhSub)
                    Spacer()
                    Text("推荐 \(NumberText.format(rec))").font(.caption.bold()).foregroundStyle(Color.lhSub)
                    Text("当前 \(NumberText.format(power))").font(.caption.bold()).foregroundStyle(power >= rec ? .green : .red)
                }
                if power < rec { Text("此劫凶险").font(.caption.bold()).foregroundStyle(.red) }
            }
        }
    }

    private func scaleText(_ v: Double) -> String {
        v < 100 ? String(format: "%.1f", v) : NumberText.format(v)
    }

    // MARK: 本世信息（9.1、9.3）

    private func previewCard(_ cfg: GameConfig, _ pv: RunPreview) -> some View {
        LHCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("本世秘境").font(.headline).foregroundStyle(Color.lhText)
                HStack(spacing: 6) {
                    ForEach(Array(pv.themeOrder.enumerated()), id: \.offset) { i, id in
                        let t = cfg.themes.def(id)
                        VStack(spacing: 2) {
                            Text(cfg.enemies.realms[i].name).font(.system(size: 10)).foregroundStyle(Color.lhSub)
                            Text(t.name).font(.system(size: 12, weight: .bold)).foregroundStyle(Color.element(t.element))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Color(hex: t.bg), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                HStack {
                    Text("秘境词缀").font(.subheadline.bold()).foregroundStyle(Color.lhText)
                    Spacer()
                    Button("刷新") { app.rerollAffixes() }
                        .font(.caption.bold())
                        .disabled(pv.affixRerollUsed)
                        .foregroundStyle(pv.affixRerollUsed ? Color.lhSub : Color.lhGold)
                }
                let active = cfg.dungeonAffixes.activeCount(tier: tier)
                ForEach(Array(pv.dungeonAffixes.enumerated()), id: \.offset) { i, id in
                    if let a = cfg.dungeonAffixes.def(id) {
                        HStack(alignment: .top) {
                            Text(a.name).font(.system(size: 13, weight: .bold)).foregroundStyle(i < active ? (a.isBuff ? .green : .orange) : Color.lhSub)
                            Text(a.desc).font(.system(size: 12)).foregroundStyle(Color.lhSub)
                            Spacer()
                            if i >= active { Text("第 \(cfg.dungeonAffixes.highTierFrom) 劫起").font(.caption2).foregroundStyle(Color.lhSub) }
                            else if let r = a.reward { Text("收益 +\(Int(r * 100))%").font(.caption2.bold()).foregroundStyle(Color.lhGold) }
                        }
                    }
                }
            }
        }
    }

    // MARK: 灵根（6.5）

    private func lingGenCard(_ cfg: GameConfig, _ pv: RunPreview) -> some View {
        LHCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("灵根").font(.headline).foregroundStyle(Color.lhText)
                    Spacer()
                    Button("刷新") { app.rerollLingGen(); lingGenIndex = 0 }
                        .font(.caption.bold())
                        .disabled(pv.lingGenRerollUsed)
                        .foregroundStyle(pv.lingGenRerollUsed ? Color.lhSub : Color.lhGold)
                }
                HStack(spacing: 8) {
                    ForEach(Array(pv.lingGenChoices.enumerated()), id: \.offset) { i, lg in
                        Button { lingGenIndex = i } label: {
                            VStack(spacing: 4) {
                                HStack(spacing: 2) {
                                    ForEach(lg.elements, id: \.self) { e in Circle().fill(Color.element(e)).frame(width: lg.elements.count > 2 ? 8 : 12) }
                                }
                                Text(lg.displayName(cfg.elements)).font(.system(size: 13, weight: .bold)).foregroundStyle(Color.lhText).lineLimit(1).minimumScaleFactor(0.7)
                                Text(lingGenDesc(cfg, lg)).font(.system(size: 10)).foregroundStyle(Color.lhSub).multilineTextAlignment(.center).lineLimit(3)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, minHeight: 92)
                            .background(Color.white.opacity(lingGenIndex == i ? 0.12 : 0.04), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(lingGenIndex == i ? Color.lhGold : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func lingGenDesc(_ cfg: GameConfig, _ lg: LingGen) -> String {
        guard let t = cfg.linggen.types.first(where: { $0.id == lg.type }) else { return "" }
        switch lg.type {
        case .single, .variant: return "元素伤害 +\(Int(t.elemPct * 100))%\n状态几率 +\(Int(t.statusChance * 100))%"
        case .dual: return lg.isGeneratingPair(cfg.elements) ? "各 +\(Int(t.elemPct * 100))%\n相生 +50%" : "各 +\(Int(t.elemPct * 100))%\n克制 ×1.5"
        case .five: return "相生 +50%\n克制 ×1.5"
        }
    }

    // MARK: 流派（7.1）

    private func schoolCard(_ cfg: GameConfig, _ s: SaveData) -> some View {
        LHCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("流派").font(.headline).foregroundStyle(Color.lhText)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(cfg.schools.schools, id: \.id) { sd in
                            let unlocked = s.unlockedSchools.contains(sd.id.rawValue)
                            Button { if unlocked { school = sd.id } } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(sd.name).font(.system(size: 16, weight: .heavy))
                                        if !unlocked { Image(systemName: "lock.fill").font(.caption) }
                                    }
                                    .foregroundStyle(unlocked ? Color.lhText : Color.lhSub)
                                    Text(unlocked ? sd.desc : sd.unlockText).font(.system(size: 11)).foregroundStyle(Color.lhSub)
                                    Text("绝学：\(sd.ultName)").font(.system(size: 11, weight: .semibold)).foregroundStyle(unlocked ? Color.lhGold : Color.lhSub)
                                }
                                .padding(10)
                                .frame(width: 128, height: 82, alignment: .topLeading)
                                .background(Color.white.opacity(school == sd.id ? 0.12 : 0.04), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(school == sd.id ? Color.lhGold : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: 法宝（12.1、13）

    private func gearCard(_ cfg: GameConfig, _ s: SaveData) -> some View {
        LHCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("法宝").font(.headline).foregroundStyle(Color.lhText)
                HStack(spacing: 10) {
                    ForEach(ItemSlot.allCases, id: \.self) { slot in
                        Button { pickSlot = slot } label: {
                            VStack(spacing: 3) {
                                if let it = s.equippedItem(slot) {
                                    ItemIcon(item: it, cfg: cfg, size: 54)
                                } else {
                                    RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4]))
                                        .frame(width: 54, height: 54)
                                        .overlay(Image(systemName: "plus").foregroundStyle(Color.lhSub))
                                }
                                Text(cfg.items.slot(slot).name).font(.system(size: 10)).foregroundStyle(Color.lhSub)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    VStack(spacing: 3) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10).fill(Color.lhGold.opacity(0.12)).frame(width: 54, height: 54)
                            Image(systemName: BenmingShapeIcon.symbol(s.benming.shape)).foregroundStyle(Color(hex: cfg.benming.color(level: s.benming.level)))
                        }
                        Text("本命 \(s.benming.level)").font(.system(size: 10)).foregroundStyle(Color.lhSub)
                    }
                }
            }
        }
    }

    // MARK: 丹药（14.5）

    private func pillCard(_ cfg: GameConfig, _ s: SaveData) -> some View {
        LHCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("丹药（最多 \(cfg.cave.maxPills) 颗）").font(.headline).foregroundStyle(Color.lhText)
                ForEach(cfg.cave.pills, id: \.id) { p in
                    let price = MetaGame.pillPrice(cfg, s, p.id)
                    let on = pills.contains(p.id)
                    let afford = app.pillsCost(pills + (on ? [] : [p.id])) <= s.lingShi
                    Button {
                        if on { pills.removeAll { $0 == p.id } }
                        else if pills.count < cfg.cave.maxPills, afford { pills.append(p.id) }
                    } label: {
                        HStack {
                            Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Color.lhGold : Color.lhSub)
                            Text(p.name).font(.system(size: 14, weight: .bold)).foregroundStyle(Color.lhText)
                            Text(p.desc).font(.system(size: 12)).foregroundStyle(Color.lhSub)
                            Spacer()
                            Text(NumberText.format(price)).font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(afford || on ? Color(hex: "#FFD54F") : .red)
                        }
                        .opacity(afford || on ? 1 : 0.5)
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 32)
                }
            }
        }
    }
}

extension ItemSlot: Identifiable { var id: String { rawValue } }

/// 长按连续加减（17.4）。
struct RepeatButton: View {
    var symbol: String
    var action: () -> Void
    @State private var timer: Timer?

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .heavy))
            .foregroundStyle(Color.lhGold)
            .frame(width: 52, height: 52)
            .background(Color.white.opacity(0.06), in: Circle())
            .contentShape(Circle())
            .onTapGesture { action() }
            .onLongPressGesture(minimumDuration: 0.35, perform: {}, onPressingChanged: { pressing in
                timer?.invalidate()
                timer = nil
                guard pressing else { return }
                let start = Date()
                timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
                    guard Date().timeIntervalSince(start) > 0.35 else { return }
                    DispatchQueue.main.async { action() }
                }
            })
    }
}

/// 出发准备里选法宝（17.4）：只显示该部位。
struct ItemPickerSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let slot: ItemSlot

    var body: some View {
        let cfg = app.config
        let s = app.save
        let current = StatAssembler.power(cfg, save: s)
        let items = s.items.filter { $0.slot == slot }.sorted { StatAssembler.power(cfg, save: s, items: replaced(s, $0)) > StatAssembler.power(cfg, save: s, items: replaced(s, $1)) }
        NavigationStack {
            List(items) { it in
                Button {
                    var sv = app.save
                    MetaGame.equip(&sv, it)
                    app.save = sv
                    app.persist()
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        ItemIcon(item: it, cfg: cfg, size: 44, equipped: s.isEquipped(it))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(it.name).font(.system(size: 15, weight: .bold)).foregroundStyle(Color.quality(it.qualityIndex(cfg)))
                            Text(it.affixes.prefix(2).map { Item.affixText($0, cfg, withRoll: false) }.joined(separator: "  ")).font(.caption2).foregroundStyle(Color.lhSub).lineLimit(1)
                        }
                        Spacer()
                        PowerDelta(delta: StatAssembler.power(cfg, save: s, items: replaced(s, it)) - current)
                    }
                }
                .listRowBackground(Color.lhCard)
            }
            .scrollContentBackground(.hidden)
            .background(Color.lhBg)
            .navigationTitle(cfg.items.slot(slot).name)
            .navigationBarTitleDisplayMode(.inline)
            .overlay { if items.isEmpty { Text("还没有这个部位的法宝").foregroundStyle(Color.lhSub) } }
        }
        .preferredColorScheme(.dark)
    }

    private func replaced(_ s: SaveData, _ it: Item) -> [Item] {
        s.equippedItems.filter { $0.slot != it.slot } + [it]
    }
}
#endif
