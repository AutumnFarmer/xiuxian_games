#if os(iOS)
import SwiftUI

/// 洞府（17.3）：资源、建筑、出发。
struct CaveView: View {
    @Environment(AppState.self) private var app
    @State private var path = NavigationPath()
    @State private var confirmAbandon = false

    enum Dest: Hashable { case fabaoge, lianqi, liandan, cangjing, benming, daoxin, settings }

    var body: some View {
        let cfg = app.config
        let s = app.save
        NavigationStack(path: $path) {
            VStack(spacing: 14) {
                header(s)
                benmingShowcase(s)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    building("法宝阁", "\(s.items.count) / \(s.capacity(cfg))", "shippingbox.fill", .fabaoge, dot: s.items.contains { $0.isNew })
                    building("炼器室", "洗练石 \(NumberText.format(s.xiLianShi))", "hammer.fill", .lianqi)
                    building("炼丹房", "\(cfg.cave.pills.count) 种丹药", "flask.fill", .liandan)
                    building("藏经阁", cangjingStatus(s), "books.vertical.fill", .cangjing,
                             dot: cfg.cave.upgrades.contains { $0.building == "cangjing" && (MetaGame.upgradeCost(cfg, s, $0.id).map { s.lingShi >= $0 } ?? false) })
                    building("本命殿", "Lv.\(s.benming.level)", "sparkles", .benming,
                             dot: !s.benming.pendingAwakenings.isEmpty || s.lingSui >= cfg.benming.cost(level: s.benming.level))
                    building("道心台", s.daoXinUnspent > 0 ? "可分配 \(s.daoXinUnspent) 点" : "Lv.\(s.daoXinLevel)", "brain.head.profile", .daoxin,
                             dot: s.daoXinUnspent > 0 || s.suHui >= cfg.cave.daoXinCost(level: s.daoXinLevel))
                }
                Spacer(minLength: 0)
                bottom(s)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .lhScreen()
            .navigationDestination(for: Dest.self) { d in
                switch d {
                case .fabaoge: FabaogeView()
                case .lianqi: LianqiView()
                case .liandan: LiandanView()
                case .cangjing: UpgradeListView(building: "cangjing", title: "藏经阁")
                case .benming: BenmingView()
                case .daoxin: DaoXinView()
                case .settings: SettingsView()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(.lhGold)
        .confirmationDialog("放弃本世会按死亡结算，收获全部保留", isPresented: $confirmAbandon, titleVisibility: .visible) {
            Button("放弃并结算", role: .destructive) { app.abandonFromCave() }
        }
    }

    private func cangjingStatus(_ s: SaveData) -> String {
        let n = app.config.cave.upgrades.filter { $0.building == "cangjing" }.reduce(0) { $0 + s.building($1.id) }
        return "已修 \(n) 层"
    }

    private func header(_ s: SaveData) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("洞府").font(.system(size: 26, weight: .heavy)).foregroundStyle(Color.lhGold)
                Spacer()
                Button { path.append(Dest.settings) } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 18)).foregroundStyle(Color.lhSub).frame(width: 44, height: 44)
                }
            }
            HStack(spacing: 6) {
                ResourceChip(icon: "diamond.fill", value: s.lingShi, color: Color(hex: "#FFD54F"))
                ResourceChip(icon: "moon.stars.fill", value: s.suHui, color: Color(hex: "#B39DDB"))
                ResourceChip(icon: "drop.fill", value: s.lingSui, color: Color(hex: "#4DD0E1"))
                ResourceChip(icon: "cube.fill", value: s.xiLianShi, color: Color(hex: "#90CAF9"))
            }
            HStack {
                Text("战力 \(NumberText.format(StatAssembler.power(app.config, save: s)))").font(.system(size: 15, weight: .heavy)).foregroundStyle(Color.lhText)
                Spacer()
                Text("最高 第 \(s.maxTierUnlocked) 劫").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.lhSub)
            }
        }
    }

    private func benmingShowcase(_ s: SaveData) -> some View {
        TimelineView(.animation) { t in
            let a = t.date.timeIntervalSinceReferenceDate * 1.4
            ZStack {
                Circle().fill(Color.white.opacity(0.04)).frame(width: 150, height: 150)
                Circle().fill(Color.white).frame(width: 34, height: 34).shadow(color: .white.opacity(0.5), radius: 10)
                Image(systemName: BenmingShapeIcon.symbol(s.benming.shape))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(hex: app.config.benming.color(level: s.benming.level)))
                    .shadow(color: Color(hex: app.config.benming.color(level: s.benming.level)), radius: 8)
                    .offset(x: cos(a) * 60, y: sin(a) * 60)
            }
            .frame(height: 150)
        }
        .overlay(alignment: .bottom) {
            Text("\(s.benming.name) · Lv.\(s.benming.level)").font(.caption.bold()).foregroundStyle(Color.lhSub)
        }
    }

    private func building(_ name: String, _ status: String, _ icon: String, _ d: Dest, dot: Bool = false) -> some View {
        Button { path.append(d) } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Color.lhGold).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 16, weight: .bold)).foregroundStyle(Color.lhText)
                    Text(status).font(.system(size: 12)).foregroundStyle(Color.lhSub).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(Color.lhCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if dot { Circle().fill(Color.red).frame(width: 9, height: 9).padding(8) }
            }
        }
        .buttonStyle(.plain)
    }

    private func bottom(_ s: SaveData) -> some View {
        HStack(spacing: 10) {
            if s.hasActiveRun {
                Button("放弃") { confirmAbandon = true }.buttonStyle(LHButtonStyle(color: .red, filled: false))
                Button { app.continueRun() } label: { Text("继续本世").frame(maxWidth: .infinity) }.buttonStyle(LHButtonStyle())
            } else {
                Button { app.goPrepare() } label: { Text("出 发").frame(maxWidth: .infinity) }.buttonStyle(LHButtonStyle())
            }
        }
        .font(.system(size: 18, weight: .heavy))
    }
}
#endif
