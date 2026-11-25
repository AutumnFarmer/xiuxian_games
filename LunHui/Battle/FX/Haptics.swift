#if os(iOS)
import CoreHaptics
import UIKit

/// 震动（16.4）：轻、中、强三档，加一档"连续 3 次"给混沌品。
/// 设备不支持 Core Haptics 时退回 UIImpactFeedbackGenerator。同一档 0.1 秒内最多触发一次。
final class Haptics {
    static let shared = Haptics()

    var enabled = true
    private var engine: CHHapticEngine?
    private var last = [Double](repeating: 0, count: 5)
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)

    private init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let e = try CHHapticEngine()
            e.isAutoShutdownEnabled = true
            e.resetHandler = { [weak e] in try? e?.start() }
            try e.start()
            engine = e
        } catch {
            engine = nil
        }
    }

    /// level：1 轻，2 中，3 强，4 混沌（连续 3 次强）。
    func play(_ level: Int, minInterval: Double = 0.1) {
        guard enabled, level > 0 else { return }
        let l = min(level, 4)
        let now = CACurrentMediaTime()
        guard now - last[l] >= minInterval else { return }
        last[l] = now
        if let engine {
            do {
                let pattern = try CHHapticPattern(events: events(l), parameters: [])
                try engine.makePlayer(with: pattern).start(atTime: 0)
                return
            } catch {
                // 走下面的退回方案
            }
        }
        switch l {
        case 1: light.impactOccurred()
        case 2: medium.impactOccurred()
        default: heavy.impactOccurred()
        }
    }

    private func events(_ l: Int) -> [CHHapticEvent] {
        func tap(_ t: Double, _ intensity: Float, _ sharp: Float) -> CHHapticEvent {
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharp),
            ], relativeTime: t)
        }
        switch l {
        case 1: return [tap(0, 0.45, 0.5)]
        case 2: return [tap(0, 0.75, 0.6)]
        case 3: return [tap(0, 1.0, 0.8), CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3),
        ], relativeTime: 0.02, duration: 0.18)]
        default: return [tap(0, 1, 1), tap(0.12, 1, 0.9), tap(0.24, 1, 1)]
        }
    }
}
#endif
