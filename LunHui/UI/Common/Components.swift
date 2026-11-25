#if os(iOS)
import SwiftUI

/// 通用界面组件（17.1）。
struct LHCard<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.lhCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct LHButtonStyle: ButtonStyle {
    var color: Color = .lhGold
    var filled = true
    var enabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(filled ? Color.black : color)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(filled ? color : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(color, lineWidth: filled ? 0 : 1.5)
            )
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// 资源数字：图标 + 缩写数字。
struct ResourceChip: View {
    var icon: String
    var value: Double
    var color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 12, weight: .bold)).foregroundStyle(color)
            Text(NumberText.format(value)).font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(Color.lhText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.06), in: Capsule())
    }
}

/// 进度条。
struct Bar: View {
    var frac: Double
    var color: Color
    var height: CGFloat = 8
    var back: Color = .white.opacity(0.12)

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(back)
                Capsule().fill(color).frame(width: CGFloat(max(0, min(1, frac))) * g.size.width)
            }
        }
        .frame(height: height)
    }
}

extension Color {
    static func element(_ e: Element?) -> Color { Color(uiColor: Palette.element(e)) }
    static func quality(_ q: Int) -> Color { Color(uiColor: Palette.quality(q)) }
}

/// 法宝图标：品质边框 + 部位符号。
struct ItemIcon: View {
    var item: Item
    var cfg: GameConfig
    var size: CGFloat = 52
    var equipped = false

    var body: some View {
        let q = item.qualityIndex(cfg)
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.quality(q).opacity(0.18))
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.quality(q), lineWidth: q >= 4 ? 2.5 : 1.5)
            Image(systemName: ItemIcon.symbol(item.slot))
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(Color.quality(q))
            VStack {
                HStack {
                    if item.locked { Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.white) }
                    Spacer()
                    if item.isNew { Circle().fill(Color.red).frame(width: 7, height: 7) }
                }
                Spacer()
                HStack {
                    if equipped { Text("装").font(.system(size: 9, weight: .bold)).foregroundStyle(.black).padding(2).background(Color.lhGold, in: RoundedRectangle(cornerRadius: 3)) }
                    Spacer()
                    Text("\(item.level)").font(.system(size: 10, weight: .bold).monospacedDigit()).foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(4)
        }
        .frame(width: size, height: size)
    }

    static func symbol(_ s: ItemSlot) -> String {
        switch s {
        case .weapon: return "bolt.fill"
        case .robe: return "shield.lefthalf.filled"
        case .pendant: return "seal.fill"
        case .ring: return "circle.circle.fill"
        }
    }
}

/// 战力变化箭头。
struct PowerDelta: View {
    var delta: Double

    var body: some View {
        if abs(delta) < 1 {
            Text("—").font(.caption).foregroundStyle(Color.lhSub)
        } else {
            HStack(spacing: 2) {
                Image(systemName: delta > 0 ? "arrow.up" : "arrow.down").font(.system(size: 10, weight: .bold))
                Text(NumberText.format(abs(delta))).font(.system(size: 12, weight: .semibold).monospacedDigit())
            }
            .foregroundStyle(delta > 0 ? Color.green : Color.red)
        }
    }
}

/// 法宝详情（17.6）：名称、主属性、词条（含百分位）、传说特效。
struct ItemDetailBody: View {
    var item: Item
    var cfg: GameConfig
    var learnedSkills: Set<String>? = nil

    var body: some View {
        let q = item.qualityIndex(cfg)
        let qual = cfg.items.qualities[q]
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ItemIcon(item: item, cfg: cfg, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.system(size: 18, weight: .bold)).foregroundStyle(Color.quality(q))
                    Text("\(qual.name) · \(cfg.items.slot(item.slot).name) · Lv.\(item.level)")
                        .font(.caption).foregroundStyle(Color.lhSub)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                if item.mainAtk > 0 { Text("攻击 +\(NumberText.format(item.mainAtk))").foregroundStyle(Color.lhText) }
                if item.mainHp > 0 { Text("生命 +\(NumberText.format(item.mainHp))").foregroundStyle(Color.lhText) }
            }
            .font(.system(size: 14, weight: .semibold))
            Divider().overlay(Color.white.opacity(0.1))
            ForEach(Array(item.affixes.enumerated()), id: \.offset) { _, a in
                Text(Item.affixText(a, cfg)).font(.system(size: 13)).foregroundStyle(Color(hex: "#90CAF9"))
            }
            if let l = item.legendary, let d = cfg.legendaries.def(l) {
                let need = d.skill.flatMap { cfg.skills.def($0)?.name }
                let active = learnedSkills == nil || d.skill == nil || learnedSkills!.contains(d.skill!)
                VStack(alignment: .leading, spacing: 2) {
                    Text("【\(d.name)】\(d.desc)").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(active ? Color.lhGold : Color.lhSub)
                    if let need { Text("需习得：\(need)").font(.caption2).foregroundStyle(Color.lhSub) }
                }
                .padding(.top, 2)
            }
        }
    }
}

extension View {
    func lhScreen() -> some View {
        self.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.lhBg.ignoresSafeArea())
            .preferredColorScheme(.dark)
    }
}
#endif
