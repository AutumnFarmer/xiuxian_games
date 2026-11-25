#if os(iOS)
import SpriteKit
import SwiftUI
import UIKit

/// 颜色（17.1、6.1、12.2）。
enum Palette {
    static let bg = UIColor(hex: "#0F1115")
    static let card = UIColor(hex: "#1A1D24")
    static let text = UIColor(hex: "#EDEDED")
    static let subtext = UIColor(hex: "#9AA0A6")
    static let gold = UIColor(hex: "#FFC107")
    static let danger = UIColor(hex: "#FF5252")
    static let telegraph = UIColor(red: 1, green: 0.15, blue: 0.1, alpha: 1)

    static let elementHex: [Element: String] = [
        .metal: "#E8C547", .wood: "#4CAF50", .water: "#2196F3", .fire: "#F4511E",
        .earth: "#8D6E63", .thunder: "#B388FF", .ice: "#80DEEA",
    ]
    static let qualityHex = ["#9E9E9E", "#4CAF50", "#2196F3", "#9C27B0", "#FFC107", "#FF1744"]

    static func element(_ e: Element?) -> UIColor {
        guard let e else { return .white }
        return UIColor(hex: elementHex[e] ?? "#FFFFFF")
    }

    static func quality(_ q: Int) -> UIColor { UIColor(hex: qualityHex[max(0, min(5, q))]) }
}

extension UIColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = CGFloat((v >> 16) & 0xFF) / 255
        let g = CGFloat((v >> 8) & 0xFF) / 255
        let b = CGFloat(v & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

extension Color {
    init(hex: String) { self.init(uiColor: UIColor(hex: hex)) }
    static let lhBg = Color(uiColor: Palette.bg)
    static let lhCard = Color(uiColor: Palette.card)
    static let lhText = Color(uiColor: Palette.text)
    static let lhSub = Color(uiColor: Palette.subtext)
    static let lhGold = Color(uiColor: Palette.gold)
}

extension Vec2 {
    var cg: CGPoint { CGPoint(x: x, y: y) }
}

extension CGPoint {
    var vec: Vec2 { Vec2(Double(x), Double(y)) }
}
#endif
