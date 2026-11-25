#if os(iOS)
import SwiftUI

/// 修改存档的小工具：复制一份、修改、写回并保存。
extension AppState {
    func mutate(_ body: (inout SaveData) -> Void) {
        var s = save
        body(&s)
        save = s
        persist()
    }
}

// MARK: 法宝阁（12.6、17.6）

struct FabaogeView: View {
    @Environment(AppState.self) private var app
    @State private var filter: ItemSlot?
    @State private var sort = 0
    @State private var selected: Item?
    @State private var showSalvage = false

    var body: some View {
        let cfg = app.config
        let s = app.save
        let current = StatAssembler.power(cfg, save: s)
        var items = s.items.filter { filter == nil || $0.slot == filter }
        var power: [UUID: Double] = [:]
        for it in items { power[it.id] = powerOf(it) }
        switch sort {
        case 0: items.sort { ($0.qualityIndex(cfg), $0.level) > ($1.qualityIndex(cfg), $1.level) }
        case 1: items.sort { $0.level > $1.level }
        case 2: items.sort { (power[$0.id] ?? 0) > (power[$1.id] ?? 0) }
        default: items.sort { $0.obtainedAt > $1.obtainedAt }
        }
        return VStack(spacing: 8) {
            Picker("部位", selection: $filter) {
                Text("全部").tag(ItemSlot?.none)
                ForEach(ItemSlot.allCases, id: \.self) { Text(cfg.items.slot($0).name).tag(ItemSlot?.some($0)) }
            }
            .pickerStyle(.segmented)
            Picker("排序", selection: $sort) {
                Text("品质").tag(0); Text("等级").tag(1); Text("战力").tag(2); Text("获得").tag(3)
            }
            .pickerStyle(.segmented)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                    ForEach(items) { it in
                        Button {
                            selected = it
                            if it.isNew { app.mutate { MetaGame.markSeen(&$0, it.id) } }
                        } label: {
                            VStack(spacing: 1) {
                                ItemIcon(item: it, cfg: cfg, size: 60, equipped: s.isEquipped(it))
                                if !s.isEquipped(it) { PowerDelta(delta: (power[it.id] ?? 0) - current) }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            Button { showSalvage = true } label: { Label("一键分解", systemImage: "trash").frame(maxWidth: .infinity) }
                .buttonStyle(LHButtonStyle(color: .lhSub, filled: false))
        }
        .padding(.horizontal, 12)
        .navigationTitle("法宝阁 \(s.items.count)/\(s.capacity(cfg))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .lhScreen()
        .sheet(item: $selected) { it in
            NavigationStack { ItemDetailSheet(itemId: it.id) }
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSalvage) { SalvageSheet().presentationDetents([.medium]) }
    }

    private func powerOf(_ it: Item) -> Double {
        let s = app.save
        return StatAssembler.power(app.config, save: s, items: s.equippedItems.filter { $0.slot != it.slot } + [it])
    }
}

struct ItemDetailSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let itemId: UUID
    @State private var confirmSalvage = false

    var body: some View {
        let cfg = app.config
        let s = app.save
        if let it = s.items.first(where: { $0.id == itemId }) {
            let equipped = s.isEquipped(it)
            let delta = StatAssembler.power(cfg, save: s, items: s.equippedItems.filter { $0.slot != it.slot } + [it]) - StatAssembler.power(cfg, save: s)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ItemDetailBody(item: it, cfg: cfg)
                    if let cur = s.equippedItem(it.slot), cur.id != it.id {
                        HStack { Text("对比当前装备").font(.caption).foregroundStyle(Color.lhSub); Spacer(); PowerDelta(delta: delta) }
                    }
                    HStack(spacing: 8) {
                        Button(equipped ? "已装备" : "装备") { app.mutate { MetaGame.equip(&$0, it) } }
                            .buttonStyle(LHButtonStyle(enabled: !equipped)).disabled(equipped)
                        Button(it.locked ? "解锁" : "加锁") { app.mutate { MetaGame.toggleLock(&$0, it.id) } }
                            .buttonStyle(LHButtonStyle(color: .lhSub, filled: false))
                        Button("分解 +\(NumberText.format(ItemForge.salvageValue(cfg, it)))") { confirmSalvage = true }
                            .buttonStyle(LHButtonStyle(color: .red, filled: false, enabled: !it.locked && !equipped))
                            .disabled(it.locked || equipped)
                    }
                    NavigationLink("去洗练") { ForgeDetailView(itemId: it.id) }
                        .buttonStyle(LHButtonStyle(color: Color(hex: "#90CAF9"), filled: false))
                }
                .padding(20)
            }
            .background(Color.lhBg)
            .preferredColorScheme(.dark)
            .confirmationDialog("分解这件法宝？", isPresented: $confirmSalvage, titleVisibility: .visible) {
                Button("分解", role: .destructive) {
                    app.mutate { MetaGame.salvage(cfg, &$0, ids: [it.id]) }
                    dismiss()
                }
            }
        } else {
            Text("法宝已不存在").foregroundStyle(Color.lhSub).lhScreen()
        }
    }
}

struct SalvageSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var picks: Set<String> = ["fan", "ling", "bao"]

    var body: some View {
        let cfg = app.config
        let cands = MetaGame.salvageCandidates(cfg, app.save, qualities: picks)
        let stones = cands.reduce(0) { $0 + ItemForge.salvageValue(cfg, $1) }
        VStack(alignment: .leading, spacing: 14) {
            Text("一键分解").font(.title3.bold()).foregroundStyle(Color.lhText)
            Text("加锁和装备中的法宝不会被分解").font(.caption).foregroundStyle(Color.lhSub)
            ForEach(cfg.items.qualities, id: \.id) { q in
                Toggle(isOn: Binding(get: { picks.contains(q.id) }, set: { on in if on { picks.insert(q.id) } else { picks.remove(q.id) } })) {
                    Text(q.name).foregroundStyle(Color(hex: q.color)).font(.headline)
                }
            }
            Button("分解 \(cands.count) 件，获得 \(NumberText.format(stones)) 洗练石") {
                app.mutate { MetaGame.salvage(cfg, &$0, ids: Set(cands.map(\.id))) }
                dismiss()
            }
            .buttonStyle(LHButtonStyle(color: .red, enabled: !cands.isEmpty))
            .disabled(cands.isEmpty)
        }
        .padding(20)
        .background(Color.lhBg)
        .preferredColorScheme(.dark)
    }
}

// MARK: 炼器室（12.6、14.4）

struct LianqiView: View {
    @Environment(AppState.self) private var app
    @State private var tab = 0

    var body: some View {
        let cfg = app.config
        let s = app.save
        VStack(spacing: 10) {
            Picker("", selection: $tab) { Text("洗练").tag(0); Text("升级").tag(1) }.pickerStyle(.segmented)
            if tab == 0 {
                Text("洗练石 \(NumberText.format(s.xiLianShi))").font(.subheadline.bold()).foregroundStyle(Color(hex: "#90CAF9"))
                List {
                    ForEach(s.items.sorted { $0.qualityIndex(cfg) > $1.qualityIndex(cfg) }) { it in
                        NavigationLink { ForgeDetailView(itemId: it.id) } label: {
                            HStack {
                                ItemIcon(item: it, cfg: cfg, size: 40, equipped: s.isEquipped(it))
                                Text(it.name).foregroundStyle(Color.quality(it.qualityIndex(cfg)))
                            }
                        }
                        .listRowBackground(Color.lhCard)
                    }
                }
                .scrollContentBackground(.hidden)
            } else {
                UpgradeListView(building: "lianqi", title: nil)
            }
        }
        .padding(.horizontal, 12)
        .navigationTitle("炼器室")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .lhScreen()
    }
}

struct ForgeDetailView: View {
    @Environment(AppState.self) private var app
    let itemId: UUID
    @State private var pending: (index: Int, affix: Affix)?

    var body: some View {
        let cfg = app.config
        let s = app.save
        ScrollView {
            if let it = s.items.first(where: { $0.id == itemId }) {
                VStack(alignment: .leading, spacing: 14) {
                    ItemDetailBody(item: it, cfg: cfg)
                    Text("洗练石 \(NumberText.format(s.xiLianShi))").font(.subheadline.bold()).foregroundStyle(Color(hex: "#90CAF9"))
                    ForEach(Array(it.affixes.enumerated()), id: \.offset) { k, a in
                        LHCard(padding: 10) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(Item.affixText(a, cfg)).font(.subheadline.bold()).foregroundStyle(Color.lhText)
                                HStack {
                                    let c1 = MetaGame.reforgeCost(cfg, s, it, recast: false)
                                    let c2 = MetaGame.reforgeCost(cfg, s, it, recast: true)
                                    Button("洗练 \(NumberText.format(c1))") { roll(k, recast: false) }
                                        .buttonStyle(LHButtonStyle(color: Color(hex: "#90CAF9"), filled: false, enabled: s.xiLianShi >= c1))
                                        .disabled(s.xiLianShi < c1)
                                    Button("重铸 \(NumberText.format(c2))") { roll(k, recast: true) }
                                        .buttonStyle(LHButtonStyle(color: .orange, filled: false, enabled: s.xiLianShi >= c2))
                                        .disabled(s.xiLianShi < c2)
                                }
                            }
                        }
                    }
                    if it.legendary != nil { Text("传说特效不能洗练，也不能重铸").font(.caption).foregroundStyle(Color.lhSub) }
                }
                .padding(16)
            }
        }
        .navigationTitle("洗练")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .lhScreen()
        .alert("洗练结果", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("保留新值") {
                if let p = pending { app.mutate { MetaGame.applyAffix(&$0, itemId, affix: p.index, p.affix) } }
                pending = nil
            }
            Button("保留旧值", role: .cancel) { pending = nil }
        } message: {
            if let p = pending, let it = s.items.first(where: { $0.id == itemId }), p.index < it.affixes.count {
                Text("旧：\(Item.affixText(it.affixes[p.index], cfg))\n新：\(Item.affixText(p.affix, cfg))")
            }
        }
    }

    private func roll(_ k: Int, recast: Bool) {
        var rng = app.metaRng
        var result: Affix?
        app.mutate { result = MetaGame.rollAffix(app.config, &$0, itemId, affix: k, recast: recast, rng: &rng) }
        app.metaRng = rng
        if let result { pending = (k, result) }
    }
}

// MARK: 炼丹房（14.5）

struct LiandanView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let cfg = app.config
        List {
            Section { Text("丹药在出发准备里服用，每世最多 \(cfg.cave.maxPills) 颗，效果持续一世。").font(.caption).foregroundStyle(Color.lhSub) }
                .listRowBackground(Color.clear)
            ForEach(cfg.cave.pills, id: \.id) { p in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.headline).foregroundStyle(Color.lhText)
                        Text(p.desc).font(.caption).foregroundStyle(Color.lhSub)
                    }
                    Spacer()
                    Text("\(NumberText.format(MetaGame.pillPrice(cfg, app.save, p.id))) 灵石").font(.subheadline.monospacedDigit()).foregroundStyle(Color(hex: "#FFD54F"))
                }
                .listRowBackground(Color.lhCard)
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("炼丹房")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .lhScreen()
    }
}

// MARK: 藏经阁、炼器室升级（14.3、14.4）

struct UpgradeListView: View {
    @Environment(AppState.self) private var app
    let building: String
    let title: String?

    var body: some View {
        let cfg = app.config
        let s = app.save
        let list = List {
            Section { ResourceChip(icon: "diamond.fill", value: s.lingShi, color: Color(hex: "#FFD54F")) }.listRowBackground(Color.clear)
            ForEach(cfg.cave.upgrades.filter { $0.building == building }, id: \.id) { u in
                let lv = s.building(u.id)
                let cost = MetaGame.upgradeCost(cfg, s, u.id)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(u.name)  Lv.\(lv)\(u.max > 0 ? "/\(u.max)" : "")").font(.headline).foregroundStyle(Color.lhText)
                        Text(u.desc).font(.caption).foregroundStyle(Color.lhSub)
                    }
                    Spacer()
                    if let cost {
                        Button(NumberText.format(cost)) { app.mutate { MetaGame.upgrade(cfg, &$0, u.id) } }
                            .buttonStyle(LHButtonStyle(enabled: s.lingShi >= cost))
                            .disabled(s.lingShi < cost)
                    } else {
                        Text("已满").foregroundStyle(Color.lhGold).font(.subheadline.bold())
                    }
                }
                .listRowBackground(Color.lhCard)
            }
        }
        .scrollContentBackground(.hidden)
        if let title {
            list.navigationTitle(title).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar).lhScreen()
        } else {
            list
        }
    }
}

// MARK: 本命殿（第 13 章）

struct BenmingView: View {
    @Environment(AppState.self) private var app
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        let cfg = app.config
        let s = app.save
        let bm = s.benming
        let cost = cfg.benming.cost(level: bm.level)
        ScrollView {
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color(hex: cfg.benming.color(level: bm.level)).opacity(0.15)).frame(width: 130, height: 130)
                    Image(systemName: BenmingShapeIcon.symbol(bm.shape)).font(.system(size: 52, weight: .bold))
                        .foregroundStyle(Color(hex: cfg.benming.color(level: bm.level)))
                        .shadow(color: Color(hex: cfg.benming.color(level: bm.level)), radius: bm.level >= 300 ? 18 : 8)
                }
                Button { newName = bm.name; renaming = true } label: {
                    HStack { Text(bm.name).font(.title2.bold()); Image(systemName: "pencil").font(.caption) }.foregroundStyle(Color.lhText)
                }
                Text("Lv.\(bm.level)").font(.system(size: 28, weight: .heavy).monospacedDigit()).foregroundStyle(Color.lhGold)
                LHCard {
                    VStack(alignment: .leading, spacing: 6) {
                        row("本命倍率", "×\(String(format: "%.2f", cfg.benming.mult(level: bm.level)))")
                        row("本命一击", NumberText.percent(cfg.benming.strikeMult(level: bm.level)))
                        row("下一级", "\(NumberText.format(cost)) 灵髓（现有 \(NumberText.format(s.lingSui))）")
                        row("下次觉醒", "Lv.\((bm.level / cfg.benming.awakenEvery + 1) * cfg.benming.awakenEvery)")
                    }
                }
                HStack {
                    Button("祭炼 1 次") { refine(all: false) }.buttonStyle(LHButtonStyle(enabled: s.lingSui >= cost)).disabled(s.lingSui < cost)
                    Button("祭炼到灵髓用完") { refine(all: true) }.buttonStyle(LHButtonStyle(filled: false, enabled: s.lingSui >= cost)).disabled(s.lingSui < cost)
                }
                if !bm.awakenings.isEmpty {
                    LHCard {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("已觉醒").font(.caption.bold()).foregroundStyle(Color.lhSub)
                            let grouped = Dictionary(grouping: bm.awakenings, by: { $0 })
                            ForEach(grouped.keys.sorted(), id: \.self) { k in
                                let t = MetaGame.awakeningText(cfg, k)
                                Text("\(t.name) ×\(grouped[k]!.count)：\(t.desc)").font(.subheadline).foregroundStyle(Color.lhText)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("本命殿")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .lhScreen()
        .sheet(isPresented: Binding(get: { !app.save.benming.pendingAwakenings.isEmpty }, set: { _ in })) {
            AwakeningSheet().interactiveDismissDisabled().presentationDetents([.medium])
        }
        .alert("改名", isPresented: $renaming) {
            TextField("本命法宝", text: $newName)
            Button("确定") {
                let n = String(newName.trimmingCharacters(in: .whitespaces).prefix(cfg.benming.nameMaxLength))
                if !n.isEmpty { app.mutate { $0.benming.name = n } }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func refine(all: Bool) {
        var rng = app.metaRng
        app.mutate { s in
            if all { _ = MetaGame.refineAll(app.config, &s, rng: &rng) } else { MetaGame.refineBenming(app.config, &s, rng: &rng) }
        }
        app.metaRng = rng
        Haptics.shared.play(all ? 3 : 1)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(Color.lhSub); Spacer(); Text(v).foregroundStyle(Color.lhText).monospacedDigit() }.font(.subheadline)
    }
}

struct AwakeningSheet: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let cfg = app.config
        VStack(spacing: 14) {
            Text("本命觉醒").font(.title.bold()).foregroundStyle(Color.lhGold)
            if let group = app.save.benming.pendingAwakenings.first {
                Text("还有 \(app.save.benming.pendingAwakenings.count) 次觉醒待选").font(.caption).foregroundStyle(Color.lhSub)
                ForEach(group, id: \.self) { raw in
                    let t = MetaGame.awakeningText(cfg, raw)
                    Button { app.mutate { MetaGame.chooseAwakening(&$0, raw) } } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t.name).font(.headline).foregroundStyle(Color.lhText)
                            Text(t.desc).font(.subheadline).foregroundStyle(Color.lhSub)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color.lhCard, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.lhGold.opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .frame(maxHeight: .infinity)
        .background(Color.lhBg)
        .preferredColorScheme(.dark)
    }
}

// MARK: 道心台（14.2）

struct DaoXinView: View {
    @Environment(AppState.self) private var app
    @State private var confirmReset = false

    var body: some View {
        let cfg = app.config
        let s = app.save
        let cost = cfg.cave.daoXinCost(level: s.daoXinLevel)
        List {
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("道心 Lv.\(s.daoXinLevel)").font(.title3.bold()).foregroundStyle(Color.lhGold)
                        Text("宿慧 \(NumberText.format(s.suHui)) · 下一级 \(NumberText.format(cost))").font(.caption).foregroundStyle(Color.lhSub)
                    }
                    Spacer()
                    Button("全部升级") { app.mutate { _ = MetaGame.levelDaoXinAll(cfg, &$0) } }
                        .buttonStyle(LHButtonStyle(enabled: s.suHui >= cost)).disabled(s.suHui < cost)
                }
                Text("可分配 \(s.daoXinUnspent) 点").font(.headline).foregroundStyle(s.daoXinUnspent > 0 ? Color.green : Color.lhSub)
            }
            .listRowBackground(Color.lhCard)
            Section {
                ForEach(cfg.cave.daoxin.points, id: \.id) { pt in
                    let n = s.daoXinPoints[pt.id] ?? 0
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(pt.name)  \(n) 点").font(.headline).foregroundStyle(Color.lhText)
                            Text(pointDesc(cfg, s, pt)).font(.caption).foregroundStyle(Color.lhSub)
                        }
                        Spacer()
                        Button("+1") { app.mutate { MetaGame.allocate(&$0, pt.id, 1) } }
                            .buttonStyle(LHButtonStyle(filled: false, enabled: s.daoXinUnspent > 0)).disabled(s.daoXinUnspent <= 0)
                        Button("+全部") { app.mutate { s in let n = s.daoXinUnspent; MetaGame.allocate(&s, pt.id, n) } }
                            .buttonStyle(LHButtonStyle(enabled: s.daoXinUnspent > 0)).disabled(s.daoXinUnspent <= 0)
                    }
                }
            }
            .listRowBackground(Color.lhCard)
            Button("重置属性点（免费）") { confirmReset = true }.foregroundStyle(.red).listRowBackground(Color.lhCard)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("道心台")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .lhScreen()
        .confirmationDialog("重置所有属性点？", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("重置", role: .destructive) { app.mutate { MetaGame.resetDaoXin(&$0) } }
        }
    }

    private func pointDesc(_ cfg: GameConfig, _ s: SaveData, _ pt: CaveConfig.DaoXinPoint) -> String {
        let v = pt.value * (pt.scales == true ? cfg.balance.itemScale(tier: s.maxTierUnlocked) : 1)
        let text = pt.stat.isPercent ? NumberText.percent(v) : NumberText.format(v)
        return "每点 \(StatText.names[pt.stat] ?? "") +\(text)\(pt.scales == true ? "（随最高劫数成长）" : "")"
    }
}

// MARK: 设置（17.7）

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @State private var resetText = ""
    @State private var showReset = false

    var body: some View {
        let s = app.save.settings
        List {
            Section("战斗") {
                Picker("伤害数字", selection: Binding(get: { s.damageText }, set: { v in app.mutate { $0.settings.damageText = v } })) {
                    Text("全部显示").tag(Settings.DamageText.all)
                    Text("只显示暴击").tag(Settings.DamageText.crit)
                    Text("关闭").tag(Settings.DamageText.off)
                }
                Toggle("震屏", isOn: Binding(get: { s.screenShake }, set: { v in app.mutate { $0.settings.screenShake = v } }))
                Toggle("震动", isOn: Binding(get: { s.haptics }, set: { v in app.mutate { $0.settings.haptics = v } }))
                Toggle("音效", isOn: Binding(get: { s.sound }, set: { v in app.mutate { $0.settings.sound = v } }))
            }
            .listRowBackground(Color.lhCard)
            Section("法宝") {
                Toggle("结算时自动分解凡品和灵品", isOn: Binding(get: { s.autoSalvageLow }, set: { v in app.mutate { $0.settings.autoSalvageLow = v } }))
                Text("法宝阁满时，自动分解品质最低、等级最低的未锁定法宝。").font(.caption).foregroundStyle(Color.lhSub)
            }
            .listRowBackground(Color.lhCard)
            Section("纪录") {
                let r = app.save.records
                LabeledContent("总世数", value: "\(r.totalRuns)")
                LabeledContent("总击杀", value: NumberText.format(Double(r.totalKills)))
                LabeledContent("最高一击", value: NumberText.format(r.bestHit))
                LabeledContent("最高通关劫数", value: "\(r.maxTierCleared)")
            }
            .listRowBackground(Color.lhCard)
            Section {
                Button("重置存档") { showReset = true }.foregroundStyle(.red)
            }
            .listRowBackground(Color.lhCard)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .lhScreen()
        .alert("输入「重置」二字确认", isPresented: $showReset) {
            TextField("重置", text: $resetText)
            Button("确认重置", role: .destructive) {
                if resetText == "重置" { app.resetEverything() }
                resetText = ""
            }
            Button("取消", role: .cancel) { resetText = "" }
        } message: { Text("会清空全部进度，不能恢复。") }
    }
}

// MARK: 转世结算（15.3）

struct SettlementView: View {
    @Environment(AppState.self) private var app
    @State private var shown = 0.0

    var body: some View {
        let cfg = app.config
        if let rep = app.lastReport {
            let r = rep.result
            ScrollView {
                VStack(spacing: 14) {
                    Text(rep.title).font(.system(size: 38, weight: .heavy))
                        .foregroundStyle(r.cleared ? Color.lhGold : Color(hex: "#B0BEC5"))
                        .padding(.top, 30)
                    LHCard {
                        VStack(alignment: .leading, spacing: 5) {
                            row("劫数", "第 \(r.tier) 劫")
                            row("灵根 / 流派", "\(r.lingGen.displayName(cfg.elements)) · \(cfg.schools.def(r.school).name)")
                            row("关数", "\(r.stagesDone) / 15")
                            row("等级", "\(r.level)")
                            row("击杀", NumberText.format(Double(r.kills)))
                            row("最高一击", NumberText.format(r.bestHit))
                            row("用时", "\(Int(r.time) / 60) 分 \(Int(r.time) % 60) 秒")
                        }
                    }
                    LHCard {
                        VStack(alignment: .leading, spacing: 6) {
                            res("灵石", rep.lingShi, "#FFD54F")
                            res("宿慧", rep.suHui, "#B39DDB")
                            res("灵髓", rep.lingSui, "#4DD0E1")
                            if rep.xiLianShiFromSalvage > 0 { res("洗练石（自动分解 \(rep.salvagedCount) 件）", rep.xiLianShiFromSalvage, "#90CAF9") }
                        }
                    }
                    if !rep.keptItems.isEmpty {
                        LHCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("入阁法宝 \(rep.keptItems.count) 件").font(.headline).foregroundStyle(Color.lhText)
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                                    ForEach(rep.keptItems.prefix(36)) { it in
                                        ItemIcon(item: it, cfg: cfg, size: 48)
                                            .shadow(color: it.qualityIndex(cfg) >= 4 ? Color.quality(it.qualityIndex(cfg)) : .clear, radius: 8)
                                    }
                                }
                            }
                        }
                    }
                    if rep.newMaxTier != nil || !rep.unlockedSchools.isEmpty || !rep.newRecords.isEmpty {
                        LHCard {
                            VStack(alignment: .leading, spacing: 4) {
                                if let t = rep.newMaxTier { Text("解锁至第 \(t) 劫").font(.headline).foregroundStyle(Color.lhGold) }
                                ForEach(rep.unlockedSchools, id: \.self) { Text("解锁流派：\($0)").font(.headline).foregroundStyle(Color.green) }
                                ForEach(rep.newRecords, id: \.self) { Text("新纪录：\($0)").font(.subheadline.bold()).foregroundStyle(Color.orange) }
                            }
                        }
                    }
                    Button { app.leaveSettlement() } label: { Text("回到洞府").frame(maxWidth: .infinity) }
                        .buttonStyle(LHButtonStyle())
                        .padding(.vertical, 10)
                }
                .padding(.horizontal, 16)
            }
            .lhScreen()
            .onAppear {
                withAnimation(.easeOut(duration: 1)) { shown = 1 }
                Audio.shared.play(r.cleared ? "victory" : "click")
            }
        } else {
            Color.lhBg.onAppear { app.leaveSettlement() }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(Color.lhSub); Spacer(); Text(v).foregroundStyle(Color.lhText).monospacedDigit() }.font(.subheadline)
    }

    private func res(_ k: String, _ v: Double, _ c: String) -> some View {
        HStack {
            Text(k).foregroundStyle(Color.lhSub)
            Spacer()
            RollingNumber(value: v * shown).foregroundStyle(Color(hex: c))
        }
        .font(.headline)
    }
}

/// 数字从 0 滚动到最终值（15.3）。
struct RollingNumber: View, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var body: some View { Text("+\(NumberText.format(value))").monospacedDigit() }
}
#endif
