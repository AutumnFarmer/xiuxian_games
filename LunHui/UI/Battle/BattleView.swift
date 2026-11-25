#if os(iOS)
import SpriteKit
import SwiftUI

/// 战斗界面：SpriteView + HUD + 弹窗（17.5）。
struct BattleView: View {
    @Environment(AppState.self) private var app
    @State private var scene: BattleScene?

    var body: some View {
        GeometryReader { g in
            ZStack {
                if let scene {
                    SpriteView(scene: scene, preferredFramesPerSecond: 60, options: [.ignoresSiblingOrder],
                               debugOptions: app.debugShowFPS ? [.showsFPS, .showsNodeCount, .showsDrawCount] : [])
                        .ignoresSafeArea()
                }
                if let flow = app.battleFlow {
                    BattleHUD(flow: flow)
                    BattleOverlays(flow: flow)
                }
            }
            .onAppear {
                guard scene == nil, let flow = app.battleFlow else { return }
                let size = CGSize(width: g.size.width + g.safeAreaInsets.leading + g.safeAreaInsets.trailing,
                                  height: g.size.height + g.safeAreaInsets.top + g.safeAreaInsets.bottom)
                scene = BattleScene(flow: flow, size: size, settings: app.save.settings)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

// MARK: HUD

struct BattleHUD: View {
    let flow: BattleFlow
    private var hud: BattleHUDModel { flow.hud }

    var body: some View {
        ZStack {
            VStack(spacing: 6) {
                topRow
                if let name = hud.bossName { bossBar(name).allowsHitTesting(false) }
                if hud.isTribulation { tribulationBar.allowsHitTesting(false) }
                Spacer()
                bottomRow
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 10)
            banners
            flashOverlay
            lootArrows
            if let intro = hud.bossIntro { bossIntro(intro) }
        }
    }

    private var topRow: some View {
        HStack(alignment: .top) {
            leftInfo.allowsHitTesting(false).layoutPriority(1)
            Spacer()
            centerInfo.allowsHitTesting(false)
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Button { flow.pause() } label: {
                    Image(systemName: "pause.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 44, height: 44).background(.black.opacity(0.35), in: Circle())
                }
                .accessibilityIdentifier("battle-pause")
                rightInfo.allowsHitTesting(false)
            }
        }
    }

    private var leftInfo: some View {
            VStack(alignment: .leading, spacing: 4) {
                ZStack(alignment: .leading) {
                    Bar(frac: hud.hp / max(1, hud.maxHp), color: hud.hp / max(1, hud.maxHp) < 0.3 ? .red : Color(hex: "#E53935"), height: 14)
                    if hud.shield > 0 {
                        Bar(frac: min(1, hud.shield / max(1, hud.maxHp)), color: Color(hex: "#80DEEA").opacity(0.8), height: 14, back: .clear)
                    }
                    Text("\(NumberText.format(hud.hp)) / \(NumberText.format(hud.maxHp))")
                        .font(.system(size: 10, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                        .padding(.leading, 6)
                }
                .frame(width: 170)
                HStack(spacing: 6) {
                    Text("Lv.\(hud.level)").font(.system(size: 12, weight: .heavy).monospacedDigit()).foregroundStyle(Color.lhGold)
                        .lineLimit(1).fixedSize()
                    Bar(frac: hud.expFrac, color: Color(hex: "#64FFDA"), height: 6).frame(width: 110)
                }
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill").font(.system(size: 10))
                    Text("心魔 \(hud.heartDemon) · \(hud.demonBand)").font(.system(size: 11, weight: .bold))
                        .lineLimit(1).fixedSize()
                }
                .foregroundStyle(Color(hex: hud.demonColor))
                if hud.revives > 0 {
                    Text("复活 ×\(hud.revives)").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.lhSub)
                }
            }
    }

    private var centerInfo: some View {
            VStack(spacing: 2) {
                Text(hud.stageTitle).font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                if let t = hud.timeLeft {
                    Text("\(Int(t))").font(.system(size: 22, weight: .heavy).monospacedDigit())
                        .foregroundStyle(t <= 10 ? Color.lhGold : .white)
                }
            }
            .shadow(color: .black, radius: 3)
    }

    private var rightInfo: some View {
            VStack(alignment: .trailing, spacing: 6) {
                Text("斩 \(hud.kills)").font(.system(size: 11, weight: .bold).monospacedDigit()).foregroundStyle(.white.opacity(0.85))
                HStack(spacing: 3) {
                    Image(systemName: "diamond.fill").font(.system(size: 9)).foregroundStyle(Color(hex: "#FFD54F"))
                    Text(NumberText.format(hud.lingShi)).font(.system(size: 11, weight: .semibold).monospacedDigit())
                }
                .foregroundStyle(.white.opacity(0.85))
                HStack(spacing: 3) {
                    Image(systemName: "shippingbox.fill").font(.system(size: 9)).foregroundStyle(Color.quality(3))
                    Text("\(hud.items)").font(.system(size: 11, weight: .semibold).monospacedDigit())
                }
                .foregroundStyle(.white.opacity(0.85))
            }
    }

    private func bossBar(_ name: String) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(name).font(.system(size: 13, weight: .heavy)).foregroundStyle(hud.bossEnraged ? .red : .white)
                Spacer()
                Text("\(Int((hud.bossFrac * 100).rounded(.up)))%").font(.system(size: 12, weight: .bold).monospacedDigit()).foregroundStyle(.white)
            }
            Bar(frac: hud.bossFrac, color: hud.bossEnraged ? .red : Color(hex: "#FF7043"), height: 10)
        }
        .padding(.horizontal, 20)
    }

    private var tribulationBar: some View {
        VStack(spacing: 2) {
            HStack {
                Text("第 \(hud.tribulationWave) / \(hud.tribulationWaves) 道雷劫").font(.system(size: 13, weight: .heavy)).foregroundStyle(Color(hex: "#B388FF"))
                Spacer()
                Text("劫云 \(Int((hud.tribulationProgress * 100).rounded()))%").font(.system(size: 12, weight: .bold).monospacedDigit()).foregroundStyle(.white)
            }
            Bar(frac: hud.tribulationProgress, color: Color(hex: "#7C4DFF"), height: 10)
        }
        .padding(.horizontal, 20)
    }

    private var bottomRow: some View {
        HStack(alignment: .bottom) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(42), spacing: 6), count: 3), alignment: .leading, spacing: 6) {
                ForEach(hud.skills) { s in SkillIcon(s: s) }
            }
            .frame(width: 140, alignment: .leading)
            .allowsHitTesting(false)
            Spacer()
            Button { flow.castUltimate() } label: {
                ZStack {
                    Circle().fill(.black.opacity(0.45))
                    Circle().trim(from: 0, to: hud.ult).stroke(Color.lhGold, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(hud.ultName).font(.system(size: 12, weight: .heavy)).minimumScaleFactor(0.6).lineLimit(1)
                        Text(hud.ultActive ? "施展中" : (hud.ultReady ? "就绪" : "\(Int(hud.ult * 100))")).font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(hud.ultReady ? Color.lhGold : .white.opacity(0.7))
                    .padding(6)
                }
                .frame(width: 72, height: 72)
                .shadow(color: hud.ultReady ? Color.lhGold.opacity(0.9) : .clear, radius: hud.ultReady ? 12 : 0)
            }
            .disabled(!hud.ultReady)
            .accessibilityIdentifier("battle-ult")
        }
    }

    private var banners: some View {
        VStack(spacing: 8) {
            Spacer().frame(height: 150)
            ForEach(hud.banners) { b in BannerView(b: b) }
            Spacer()
            VStack(spacing: 4) {
                ForEach(hud.toasts) { t in
                    Text(t.text).font(.system(size: 13, weight: .bold)).foregroundStyle(Color.quality(3))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(.black.opacity(0.55), in: Capsule())
                }
            }
            .padding(.bottom, 120)
        }
        .allowsHitTesting(false)
        .animation(.spring(duration: 0.25), value: hud.banners)
    }

    private func flashColor(_ f: ScreenFlash) -> Color {
        switch f {
        case .gold: return .lhGold
        case .red: return Color(hex: "#FF1744")
        case .purple: return Color(hex: "#7E57C2")
        case .white: return .white
        }
    }

    @ViewBuilder private var flashOverlay: some View {
        if let f = hud.flash {
            let c = flashColor(f)
            Rectangle().strokeBorder(c.opacity(0.85), lineWidth: 26).blur(radius: 18).ignoresSafeArea().allowsHitTesting(false)
            if f == .white || f == .red { c.opacity(0.18).ignoresSafeArea().allowsHitTesting(false) }
        }
    }

    private var lootArrows: some View {
        GeometryReader { g in
            ForEach(hud.lootArrows) { a in
                let cx = g.size.width / 2, cy = g.size.height / 2
                let dx = CGFloat(cos(a.angle)), dy = CGFloat(-sin(a.angle))
                let k = min((cx - 26) / max(0.01, abs(dx)), (cy - 60) / max(0.01, abs(dy)))
                Image(systemName: "arrowtriangle.right.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.quality(a.quality))
                    .rotationEffect(.radians(-a.angle))
                    .position(x: cx + dx * k, y: cy + dy * k)
                    .shadow(color: Color.quality(a.quality), radius: 6)
            }
        }
        .allowsHitTesting(false)
    }

    private func bossIntro(_ name: String) -> some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 6) {
                Text("劫 至").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.lhSub)
                Text(name).font(.system(size: 40, weight: .heavy)).foregroundStyle(Color(hex: "#FF7043"))
                    .shadow(color: .red, radius: 12)
            }
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

struct SkillIcon: View {
    let s: SkillHUD

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.45))
            RoundedRectangle(cornerRadius: 8).fill(Color.element(s.element).opacity(0.35))
                .mask(alignment: .bottom) { Rectangle().frame(height: CGFloat(42 * s.cd)) }
            RoundedRectangle(cornerRadius: 8).stroke(s.evolved ? Color.lhGold : Color.element(s.element), lineWidth: s.evolved ? 2 : 1)
            Text(String(s.name.prefix(2))).font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
            Text(s.evolved ? "神" : "\(s.level)").font(.system(size: 9, weight: .heavy)).foregroundStyle(s.evolved ? Color.lhGold : .white)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(3)
        }
        .frame(width: 42, height: 42)
    }
}

struct BannerView: View {
    let b: Banner

    private var style: (Color, CGFloat) {
        switch b.style {
        case .shen: return (.lhGold, 30)
        case .hundun: return (Color(hex: "#FF1744"), 32)
        case .xian: return (Color.quality(3), 22)
        case .realm: return (.lhGold, 34)
        case .levelUp: return (Color(hex: "#64FFDA"), 24)
        case .demon: return (Color(hex: "#B388FF"), 26)
        case .victory: return (.lhGold, 30)
        case .boss: return (Color(hex: "#FF7043"), 28)
        case .normal: return (.white, 22)
        }
    }

    var body: some View {
        let c = style.0, size = style.1
        VStack(spacing: 2) {
            Text(b.text).font(.system(size: size, weight: .heavy)).foregroundStyle(c)
            if !b.sub.isEmpty { Text(b.sub).font(.system(size: 15, weight: .bold)).foregroundStyle(.white) }
        }
        .shadow(color: c.opacity(0.8), radius: 10)
        .shadow(color: .black, radius: 2)
        .transition(.scale(scale: 1.4).combined(with: .opacity))
    }
}
#endif
