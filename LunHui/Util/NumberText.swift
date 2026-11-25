import Foundation

/// 大数字的中文单位缩写（11.2）。
enum NumberText {
    /// 每个单位比上一个大 1 万倍：万 = 1e4，亿 = 1e8，兆 = 1e12 ……
    static let units = ["万", "亿", "兆", "京", "垓", "秭", "穰", "沟", "涧", "正", "载"]

    static func format(_ value: Double) -> String {
        guard value.isFinite else { return value.isNaN ? "0" : "∞" }
        let sign = value < 0 ? "-" : ""
        return sign + formatPositive(abs(value))
    }

    private static func formatPositive(_ a: Double) -> String {
        if a < 9_999.5 { return String(Int(a.rounded())) }
        var scale = 10_000.0
        for unit in units {
            let mantissa = a / scale
            // 四舍五入到 1 位小数后不足 1 万，就用这个单位；否则进位到下一个单位。
            if (mantissa * 10).rounded() / 10 < 10_000 {
                return String(format: "%.1f", mantissa) + unit
            }
            scale *= 10_000
        }
        return scientific(a)
    }

    /// 超过最大单位后改用科学计数，例如 3.2e52。
    static func scientific(_ a: Double) -> String {
        var exp = Int(floor(log10(a)))
        var mantissa = a / pow(10, Double(exp))
        if (mantissa * 10).rounded() / 10 >= 10 {
            mantissa /= 10
            exp += 1
        }
        return String(format: "%.1f", mantissa) + "e\(exp)"
    }

    /// 百分比，保留 1 位小数（12.4）。value 是小数，0.052 显示为 5.2%。
    static func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }
}
