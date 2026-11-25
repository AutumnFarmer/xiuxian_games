import Foundation
import Observation

/// HUD 上一个功法图标（17.5）。
struct SkillHUD: Equatable, Identifiable {
    var id: Int
    var name: String
    var level: Int
    var element: Element
    var evolved: Bool
    var cd: Double
}

/// 横幅样式（第 16 章）。
enum BannerStyle: Equatable {
    case normal, levelUp, realm, boss, xian, shen, hundun, demon, victory
}

struct Banner: Identifiable, Equatable {
    let id: Int
    var text: String
    var sub: String = ""
    var style: BannerStyle
    var until: Double
}

/// 屏幕边缘或全屏闪光（16.3、10.4）。
enum ScreenFlash: Equatable {
    case gold, red, purple, white
}

/// 战斗 HUD 的数据（3.4）。BattleScene 每 0.1 秒写一次，SwiftUI 只读这个对象。
@Observable
final class BattleHUDModel {
    var hp = 0.0
    var maxHp = 1.0
    var shield = 0.0
    var level = 1
    var expFrac = 0.0
    var heartDemon = 0
    var demonBand = "清明"
    var demonColor = "#FFFFFF"
    var stageTitle = ""
    var timeLeft: Double?
    var bossName: String?
    var bossFrac = 0.0
    var bossEnraged = false
    var isTribulation = false
    var tribulationWave = 0
    var tribulationWaves = 9
    var tribulationProgress = 1.0
    var kills = 0
    var skills: [SkillHUD] = []
    var ult = 0.0
    var ultReady = false
    var ultName = ""
    var ultActive = false
    var lingShi = 0.0
    var items = 0
    var revives = 0
    var banners: [Banner] = []
    var toasts: [Banner] = []
    var flash: ScreenFlash?
    var flashUntil = 0.0
    var bossIntro: String?
    var bossIntroUntil = 0.0
    var clock = 0.0
    /// 仙品以上掉落相对玩家的方向（屏幕外时显示箭头，16.3）。
    var lootArrows: [LootArrow] = []

    @ObservationIgnored private var nextId = 1

    func set<T: Equatable>(_ kp: ReferenceWritableKeyPath<BattleHUDModel, T>, _ v: T) {
        if self[keyPath: kp] != v { self[keyPath: kp] = v }
    }

    func pushBanner(_ text: String, sub: String = "", style: BannerStyle = .normal, duration: Double) {
        nextId += 1
        // 同时最多 2 条，新的顶掉旧的
        if banners.count >= 2 { banners.removeFirst() }
        banners.append(Banner(id: nextId, text: text, sub: sub, style: style, until: clock + duration))
    }

    func pushToast(_ text: String, style: BannerStyle, duration: Double = 2.5) {
        nextId += 1
        if toasts.count >= 4 { toasts.removeFirst() }
        toasts.append(Banner(id: nextId, text: text, style: style, until: clock + duration))
    }

    func flashScreen(_ f: ScreenFlash, duration: Double) {
        flash = f
        flashUntil = clock + duration
    }

    func showBossIntro(_ name: String, duration: Double) {
        bossIntro = name
        bossIntroUntil = clock + duration
    }

    /// 清理过期的横幅和闪光。
    func expire() {
        if banners.contains(where: { $0.until <= clock }) { banners.removeAll { $0.until <= clock } }
        if toasts.contains(where: { $0.until <= clock }) { toasts.removeAll { $0.until <= clock } }
        if flash != nil, clock >= flashUntil { flash = nil }
        if bossIntro != nil, clock >= bossIntroUntil { bossIntro = nil }
    }
}

struct LootArrow: Equatable, Identifiable {
    var id: Int
    var angle: Double
    var quality: Int
}
