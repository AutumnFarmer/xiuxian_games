#if os(iOS) && DEBUG
import SwiftUI

/// Debug 菜单（20 章 M7，只在 Debug 版出现）：加资源、给指定法宝、改劫数。
struct DebugView: View {
    @Environment(AppState.self) private var app
    @State private var quality = 4
    @State private var legendary = ""
    @State private var tier = 1

    var body: some View {
        let cfg = app.config
        List {
            Section("资源") {
                Button("灵石 +10 万") { app.mutate { $0.lingShi += 100_000 } }
                Button("宿慧 +1 万") { app.mutate { $0.suHui += 10_000 } }
                Button("灵髓 +1 万") { app.mutate { $0.lingSui += 10_000 } }
                Button("洗练石 +1000") { app.mutate { $0.xiLianShi += 1000 } }
            }
            Section("劫数") {
                Stepper("解锁到第 \(tier) 劫", value: $tier, in: 1...500)
                Button("应用") { app.mutate { $0.maxTierUnlocked = max(1, tier) } }
            }
            Section("给法宝") {
                Picker("品质", selection: $quality) {
                    ForEach(0..<cfg.items.qualities.count, id: \.self) { Text(cfg.items.qualities[$0].name).tag($0) }
                }
                Picker("传说特效", selection: $legendary) {
                    Text("随机").tag("")
                    ForEach(cfg.legendaries.legendaries, id: \.id) { Text("\($0.name)（\($0.skill.flatMap { cfg.skills.def($0)?.name } ?? "全局")）").tag($0.id) }
                }
                Button("每个部位各给 1 件") {
                    var rng = app.metaRng
                    app.mutate { s in
                        for slot in ItemSlot.allCases {
                            var it = ItemForge.make(cfg, slot: slot, quality: quality, tier: s.maxTierUnlocked,
                                                    school: School(rawValue: s.lastSchool), rng: &rng)
                            if !legendary.isEmpty, quality >= 4 {
                                it.legendary = legendary
                                it.name = (cfg.legendaries.def(legendary)?.name ?? "") + cfg.items.slot(slot).suffixes[0]
                            }
                            s.items.append(it)
                        }
                    }
                    app.metaRng = rng
                }
            }
            Section("流派") {
                Button("解锁全部流派") { app.mutate { $0.unlockedSchools = School.allCases.map(\.rawValue) } }
            }
            Section("测试开局（下一世生效）") {
                Stepper("从 \(stageName(app.debugStartStage)) 开始",
                        value: Binding(get: { app.debugStartStage }, set: { app.debugStartStage = $0 }), in: 0...14)
                Stepper("开局心魔 \(app.debugStartDemon)",
                        value: Binding(get: { app.debugStartDemon }, set: { app.debugStartDemon = $0 }), in: 0...100, step: 10)
                Stepper("开局额外顿悟 \(app.debugExtraInsights) 次",
                        value: Binding(get: { app.debugExtraInsights }, set: { app.debugExtraInsights = $0 }), in: 0...60, step: 5)
                Text("心魔值 ≥ 70 时最终关打心魔影子，否则打天劫。跳到后面的关时记得加顿悟次数，不然功法太少。")
                    .font(.caption).foregroundStyle(Color.lhSub)
            }
            Section("显示") {
                Toggle("战斗中显示帧率和节点数", isOn: Binding(get: { app.debugShowFPS }, set: { app.debugShowFPS = $0 }))
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Debug")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .lhScreen()
        .onAppear { tier = app.save.maxTierUnlocked }
    }

    private func stageName(_ i: Int) -> String {
        let realm = app.config.enemies.realms[min(4, i / 3)].name
        if i == 14 { return "\(realm)·最终关" }
        if i == 13 || (i < 12 && i % 3 == 2) { return "\(realm)·劫关" }
        return "\(realm)·第 \(i % 3 + 1) 关"
    }
}
#endif
