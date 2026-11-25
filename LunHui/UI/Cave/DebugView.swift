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
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Debug")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .lhScreen()
        .onAppear { tier = app.save.maxTierUnlocked }
    }
}
#endif
